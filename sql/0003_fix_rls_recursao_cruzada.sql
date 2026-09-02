-- Fix: "infinite recursion detected in policy for relation documentos".
-- A policy de select em documentos consultava documento_slots, e a de
-- documento_slots consultava documentos de volta — recursão cruzada entre
-- as duas tabelas (mesma classe de bug do pp-identidade/classcard, sql
-- 0003 daquele repo, mas ali era uma tabela consultando a si mesma; aqui
-- são duas tabelas se consultando uma à outra). Só apareceu testando pela
-- UI real com RLS ativo — os testes anteriores via SQL rodavam como
-- service role, que bypassa RLS, escondendo o bug.
-- Corrige com uma função security definer que decide a visibilidade do
-- documento uma vez só (bypassando RLS na checagem interna), e as duas
-- tabelas passam a usar essa mesma função em vez de se consultar.
-- Aplicada ao Supabase do projeto (moxxbehwylcjaqjacmyh) em 2026-09-02.

create or replace function public.fn_documento_visivel(p_documento_id uuid)
returns boolean
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_cedula text;
  v_empresa_cedula text;
begin
  if v_uid is null then
    return false;
  end if;
  if public.fn_e_professor() then
    return true;
  end if;
  if exists (select 1 from public.documentos d where d.id = p_documento_id and d.criado_por = v_uid::text) then
    return true;
  end if;

  select p.cedula into v_cedula from public.pessoas p where p.id = v_uid;
  select e.cedula into v_empresa_cedula
    from public.pessoas p join public.empresas e on e.id = p.empresa_id
    where p.id = v_uid;

  return exists (
    select 1 from public.documento_slots ds
    where ds.documento_id = p_documento_id
      and (ds.pessoa_esperada = v_cedula or ds.empresa_esperada = v_empresa_cedula)
  );
end;
$$;
revoke execute on function public.fn_documento_visivel(uuid) from anon;
grant execute on function public.fn_documento_visivel(uuid) to authenticated;

drop policy if exists "criador ve seus documentos" on public.documentos;
drop policy if exists "professor ve todos os documentos" on public.documentos;
drop policy if exists "esperado no slot ve o documento" on public.documentos;
create policy "documento visivel"
  on public.documentos for select
  using (public.fn_documento_visivel(id));

drop policy if exists "ve slots dos documentos que pode ver" on public.documento_slots;
create policy "slots do documento visivel"
  on public.documento_slots for select
  using (public.fn_documento_visivel(documento_id));
