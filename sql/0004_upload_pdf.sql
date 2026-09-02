-- Subsight: documento passa a ser um ficheiro (PDF) enviado ao Storage, em
-- vez de texto digitado. Hash calculado no navegador (SubtleCrypto) no
-- momento do envio; imutabilidade garantida pelo Storage (sem policy de
-- update, e delete restrito ao professor para manutenção/testes).
-- Aplicada ao Supabase do projeto (moxxbehwylcjaqjacmyh) em 2026-09-02.

insert into storage.buckets (id, name, public)
values ('documentos', 'documentos', false)
on conflict (id) do nothing;

alter table public.documentos add column if not exists arquivo_url text;
alter table public.documentos add column if not exists nome_arquivo text;
alter table public.documentos alter column conteudo drop not null;

-- Só o criador pode enviar o ficheiro, e só uma vez (enquanto hash_conteudo
-- ainda é nulo). Path esperado: documentos/{documento_id}/{nome}.
create policy "criador anexa arquivo uma vez"
  on storage.objects for insert
  with check (
    bucket_id = 'documentos'
    and exists (
      select 1 from public.documentos d
      where d.id::text = (storage.foldername(name))[1]
        and d.criado_por = auth.uid()::text
        and d.hash_conteudo is null
    )
  );

-- Quem pode ver o documento (mesma regra de fn_documento_visivel) pode
-- baixar o ficheiro. Sem policy de update: ninguém pode substituir depois
-- de enviado.
create policy "quem ve o documento baixa o arquivo"
  on storage.objects for select
  using (
    bucket_id = 'documentos'
    and public.fn_documento_visivel(((storage.foldername(name))[1])::uuid)
  );

-- ass_criar_documento agora só monta o "envelope" (tipo + slots); o
-- ficheiro é anexado depois via ass_anexar_arquivo.
create or replace function public.ass_criar_documento(
  p_tipo text,
  p_slots jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_doc_id uuid;
  v_slot jsonb;
  v_exigidos text[];
  v_dados text[];
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'erro', 'Sem sessão.');
  end if;
  if not exists (select 1 from public.tipos_documento where tipo = p_tipo) then
    return jsonb_build_object('ok', false, 'erro', 'Tipo de documento desconhecido.');
  end if;

  select array_agg(slot order by slot) into v_exigidos
    from public.slots_tipo where tipo = p_tipo;
  select array_agg((s->>'slot') order by (s->>'slot'))
    into v_dados from jsonb_array_elements(coalesce(p_slots, '[]'::jsonb)) s;

  if v_exigidos is distinct from v_dados then
    return jsonb_build_object('ok', false, 'erro', 'Os slots enviados não batem com os exigidos pelo tipo.');
  end if;

  v_doc_id := gen_random_uuid();

  insert into public.documentos(id, tipo, criado_por, estado)
  values (v_doc_id, p_tipo, v_uid::text, 'pendente');

  for v_slot in select * from jsonb_array_elements(p_slots) loop
    insert into public.documento_slots(documento_id, slot, empresa_esperada, pessoa_esperada)
    values (
      v_doc_id,
      v_slot->>'slot',
      nullif(v_slot->>'empresa_esperada', ''),
      nullif(v_slot->>'pessoa_esperada', '')
    );
  end loop;

  return jsonb_build_object('ok', true, 'dados', jsonb_build_object('documento_id', v_doc_id, 'tipo', p_tipo, 'estado', 'pendente'));
exception when others then
  return jsonb_build_object('ok', false, 'erro', 'Falha ao criar documento: ' || sqlerrm);
end;
$$;

-- ass_anexar_arquivo: liga o PDF já enviado ao Storage ao documento,
-- travando o hash. Só o criador, só uma vez.
create or replace function public.ass_anexar_arquivo(
  p_documento_id uuid,
  p_arquivo_url text,
  p_nome_arquivo text,
  p_hash_conteudo text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_doc record;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'erro', 'Sem sessão.');
  end if;

  select * into v_doc from public.documentos where id = p_documento_id;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'Documento não encontrado.');
  end if;
  if v_doc.criado_por <> v_uid::text then
    return jsonb_build_object('ok', false, 'erro', 'Só o criador pode anexar o ficheiro.');
  end if;
  if v_doc.hash_conteudo is not null then
    return jsonb_build_object('ok', false, 'erro', 'Este documento já tem um ficheiro anexado.');
  end if;
  if coalesce(p_arquivo_url,'') = '' or coalesce(p_hash_conteudo,'') = '' then
    return jsonb_build_object('ok', false, 'erro', 'Dados do ficheiro em falta.');
  end if;

  update public.documentos
    set arquivo_url = p_arquivo_url, nome_arquivo = p_nome_arquivo, hash_conteudo = p_hash_conteudo
    where id = p_documento_id;

  return jsonb_build_object('ok', true, 'dados', jsonb_build_object('documento_id', p_documento_id, 'hash_conteudo', p_hash_conteudo));
exception when others then
  return jsonb_build_object('ok', false, 'erro', 'Falha ao anexar ficheiro: ' || sqlerrm);
end;
$$;

-- ass_assinar: não deixa assinar um documento sem ficheiro anexado.
create or replace function public.ass_assinar(
  p_documento_id uuid,
  p_slot text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_pessoa record;
  v_empresa_cedula text;
  v_doc record;
  v_regra record;
  v_ds record;
  v_hash_ass text;
  v_codigo text;
  v_restantes int;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'erro', 'Sem sessão.');
  end if;

  select p.cedula, p.papel, p.empresa_id into v_pessoa from public.pessoas p where p.id = v_uid;
  if v_pessoa.cedula is null then
    return jsonb_build_object('ok', false, 'erro', 'Sem ficha na Carteirinha.');
  end if;
  select e.cedula into v_empresa_cedula from public.empresas e where e.id = v_pessoa.empresa_id;

  select * into v_doc from public.documentos where id = p_documento_id;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'Documento não encontrado.');
  end if;
  if v_doc.estado <> 'pendente' then
    return jsonb_build_object('ok', false, 'erro', 'Documento não está pendente de assinatura.');
  end if;
  if v_doc.hash_conteudo is null then
    return jsonb_build_object('ok', false, 'erro', 'Este documento ainda não tem ficheiro anexado.');
  end if;

  select * into v_ds from public.documento_slots
    where documento_id = p_documento_id and slot = p_slot;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'Slot não existe neste documento.');
  end if;
  if v_ds.preenchido_por is not null then
    return jsonb_build_object('ok', false, 'erro', 'Slot já foi preenchido.');
  end if;

  select * into v_regra from public.slots_tipo
    where tipo = v_doc.tipo and slot = p_slot;

  if v_regra.exige_papel is not null and v_pessoa.papel <> v_regra.exige_papel then
    return jsonb_build_object('ok', false, 'erro',
      format('Este slot exige papel "%s".', v_regra.exige_papel));
  end if;

  if v_regra.exige_vinculo = 'pessoa_exata' and v_pessoa.cedula <> v_ds.pessoa_esperada then
    return jsonb_build_object('ok', false, 'erro', 'Este slot só pode ser assinado pela pessoa exata esperada.');
  end if;

  if v_regra.exige_vinculo = 'empresa_parametro'
     and (v_empresa_cedula is null or v_empresa_cedula <> v_ds.empresa_esperada) then
    return jsonb_build_object('ok', false, 'erro', 'Este slot só pode ser assinado por alguém vinculado à empresa esperada.');
  end if;

  v_hash_ass := encode(digest(
    p_documento_id::text || '|' || p_slot || '|' || v_pessoa.cedula || '|' || now()::text,
    'sha256'), 'hex');
  v_codigo := 'ASS-' || replace(v_pessoa.cedula, '-', '') || '-' || upper(left(v_hash_ass, 4));

  update public.documento_slots
    set preenchido_por = v_pessoa.cedula, codigo = v_codigo, assinado_em = now()
    where documento_id = p_documento_id and slot = p_slot;

  select count(*) into v_restantes from public.documento_slots
    where documento_id = p_documento_id and preenchido_por is null;
  if v_restantes = 0 then
    update public.documentos set estado = 'completo' where id = p_documento_id;
  end if;

  return jsonb_build_object('ok', true, 'dados', jsonb_build_object(
    'codigo', v_codigo,
    'documento_estado', case when v_restantes = 0 then 'completo' else 'pendente' end
  ));
exception when others then
  return jsonb_build_object('ok', false, 'erro', 'Falha ao assinar: ' || sqlerrm);
end;
$$;

-- ass_verificar: já não recalcula hash a partir de texto (não é possível
-- reconferir o ficheiro a partir do SQL) — "íntegro" passa a significar
-- "tem hash travado", garantido pela imutabilidade do Storage.
create or replace function public.ass_verificar(p_documento_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_doc record; v_falta int; v_total int;
begin
  select * into v_doc from public.documentos where id = p_documento_id;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'Documento não encontrado.');
  end if;
  select count(*) filter (where preenchido_por is null), count(*)
    into v_falta, v_total from public.documento_slots where documento_id = p_documento_id;
  return jsonb_build_object('ok', true, 'dados', jsonb_build_object(
    'estado', v_doc.estado,
    'assinaturas', v_total - v_falta,
    'exigidas', v_total,
    'completo', (v_falta = 0),
    'integro', (v_doc.hash_conteudo is not null),
    'valido', (v_falta = 0 and v_doc.hash_conteudo is not null)
  ));
end; $$;

-- Sem policy de delete, nem o dono consegue apagar um PDF já enviado — bom
-- para imutabilidade do ponto de vista de negócio, mas sem via nenhuma de
-- manutenção/limpeza de teste. Adiciona só para o professor/admin.
create policy "professor remove arquivo (manutencao)"
  on storage.objects for delete
  using (bucket_id = 'documentos' and public.fn_e_professor());
