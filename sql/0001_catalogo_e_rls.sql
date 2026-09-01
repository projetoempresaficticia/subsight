-- pp-assinatura (Subsight): seed do catálogo de tipos de documento + RLS.
-- O schema (tipos_documento, slots_tipo, documentos, documento_slots) e a
-- função ass_verificar já existiam de uma sessão anterior; o catálogo tinha
-- sido esvaziado na limpeza de teste dessa sessão e é recriado aqui como
-- dado permanente (não de teste).
-- Aplicada ao Supabase do projeto (moxxbehwylcjaqjacmyh) em 2026-09-01.

insert into public.tipos_documento (tipo, descricao, orgao_destino) values
  ('contrato_trabalho', 'Contrato de trabalho entre empresa e funcionário', null),
  ('contrato_b2b', 'Contrato entre duas empresas', null),
  ('declaracao', 'Declaração simples de uma empresa', null)
on conflict (tipo) do nothing;

insert into public.slots_tipo (tipo, slot, exige_papel, exige_vinculo) values
  ('contrato_trabalho', 'empregador', 'gerente', 'empresa_parametro'),
  ('contrato_trabalho', 'empregado', null, 'pessoa_exata'),
  ('contrato_b2b', 'parte_A', 'gerente', 'empresa_parametro'),
  ('contrato_b2b', 'parte_B', 'gerente', 'empresa_parametro'),
  ('declaracao', 'declarante', null, 'empresa_parametro')
on conflict (tipo, slot) do nothing;

alter table public.tipos_documento enable row level security;
alter table public.slots_tipo enable row level security;
alter table public.documentos enable row level security;
alter table public.documento_slots enable row level security;

create policy "catalogo tipos leitura publica"
  on public.tipos_documento for select using (true);
create policy "catalogo slots leitura publica"
  on public.slots_tipo for select using (true);
create policy "catalogo tipos escrita professor"
  on public.tipos_documento for all
  using (public.fn_e_professor()) with check (public.fn_e_professor());
create policy "catalogo slots escrita professor"
  on public.slots_tipo for all
  using (public.fn_e_professor()) with check (public.fn_e_professor());

-- documentos.criado_por é text (guarda o uid como texto).
create policy "criador ve seus documentos"
  on public.documentos for select
  using (criado_por = auth.uid()::text);
create policy "professor ve todos os documentos"
  on public.documentos for select
  using (public.fn_e_professor());
create policy "esperado no slot ve o documento"
  on public.documentos for select
  using (
    exists (
      select 1 from public.documento_slots ds
      where ds.documento_id = documentos.id
        and (
          ds.pessoa_esperada = (select cedula from public.pessoas where id = auth.uid())
          or ds.empresa_esperada = (
            select e.cedula from public.pessoas p
            join public.empresas e on e.id = p.empresa_id
            where p.id = auth.uid()
          )
        )
    )
  );

create policy "ve slots dos documentos que pode ver"
  on public.documento_slots for select
  using (
    exists (
      select 1 from public.documentos d
      where d.id = documento_slots.documento_id
        and (d.criado_por = auth.uid()::text or public.fn_e_professor())
    )
    or pessoa_esperada = (select cedula from public.pessoas where id = auth.uid())
    or empresa_esperada = (
      select e.cedula from public.pessoas p
      join public.empresas e on e.id = p.empresa_id
      where p.id = auth.uid()
    )
  );
