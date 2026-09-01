-- pp-assinatura (Subsight): RPCs ass_criar_documento, ass_assinar, ass_anular.
-- ass_verificar já existia (sessão anterior) e não foi alterada.
-- Aplicada ao Supabase do projeto (moxxbehwylcjaqjacmyh) em 2026-09-01.
-- Testada via SQL real: contrato de trabalho entre duas empresas fictícias,
-- confirmando a "regra de ouro" (gerente de uma empresa não consegue
-- preencher o slot de outra), rejeição por papel errado, idempotência
-- (assinar o mesmo slot duas vezes falha na segunda), conclusão automática
-- do documento ao preencher o último slot, ass_verificar (íntegro/válido),
-- e ass_anular (pendente por criador, completo só por professor).

-- ass_criar_documento: qualquer autenticado pode criar (é quem redige o
-- contrato/declaração); os slots concretos (empresa/pessoa esperada) vêm do
-- chamador e têm de bater exatamente com os slots exigidos pelo tipo.
create or replace function public.ass_criar_documento(
  p_tipo text,
  p_conteudo text,
  p_slots jsonb  -- [{"slot":"empregador","empresa_esperada":"EP-...","pessoa_esperada":null}, ...]
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_doc_id uuid;
  v_hash text;
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
  if coalesce(p_conteudo,'') = '' then
    return jsonb_build_object('ok', false, 'erro', 'Conteúdo é obrigatório.');
  end if;

  select array_agg(slot order by slot) into v_exigidos
    from public.slots_tipo where tipo = p_tipo;
  select array_agg((s->>'slot') order by (s->>'slot'))
    into v_dados from jsonb_array_elements(coalesce(p_slots, '[]'::jsonb)) s;

  if v_exigidos is distinct from v_dados then
    return jsonb_build_object('ok', false, 'erro', 'Os slots enviados não batem com os exigidos pelo tipo.');
  end if;

  v_hash := encode(digest(p_conteudo, 'sha256'), 'hex');
  v_doc_id := gen_random_uuid();

  insert into public.documentos(id, tipo, conteudo, hash_conteudo, criado_por, estado)
  values (v_doc_id, p_tipo, p_conteudo, v_hash, v_uid::text, 'pendente');

  for v_slot in select * from jsonb_array_elements(p_slots) loop
    insert into public.documento_slots(documento_id, slot, empresa_esperada, pessoa_esperada)
    values (
      v_doc_id,
      v_slot->>'slot',
      nullif(v_slot->>'empresa_esperada', ''),
      nullif(v_slot->>'pessoa_esperada', '')
    );
  end loop;

  return jsonb_build_object('ok', true, 'dados', jsonb_build_object(
    'documento_id', v_doc_id, 'tipo', p_tipo, 'hash_conteudo', v_hash, 'estado', 'pendente'
  ));
exception when others then
  return jsonb_build_object('ok', false, 'erro', 'Falha ao criar documento: ' || sqlerrm);
end;
$$;

-- ass_assinar: a cédula que assina vem sempre de auth.uid(), nunca de parâmetro.
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

-- ass_anular: pendente -> anulado (criador ou professor); completo -> anulado (só professor).
create or replace function public.ass_anular(p_documento_id uuid)
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

  if v_doc.estado = 'anulado' then
    return jsonb_build_object('ok', false, 'erro', 'Documento já está anulado.');
  end if;

  if v_doc.estado = 'completo' and not public.fn_e_professor() then
    return jsonb_build_object('ok', false, 'erro', 'Só o professor/admin pode anular um documento completo.');
  end if;

  if v_doc.estado = 'pendente' and v_doc.criado_por <> v_uid::text and not public.fn_e_professor() then
    return jsonb_build_object('ok', false, 'erro', 'Só o criador ou o professor/admin pode anular.');
  end if;

  update public.documentos set estado = 'anulado' where id = p_documento_id;

  return jsonb_build_object('ok', true, 'dados', jsonb_build_object('documento_id', p_documento_id, 'estado', 'anulado'));
exception when others then
  return jsonb_build_object('ok', false, 'erro', 'Falha ao anular: ' || sqlerrm);
end;
$$;
