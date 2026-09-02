-- Subsight: tipo de documento "livre" — o criador escolhe quantas
-- assinaturas o documento precisa, e quem assina cada uma.
--
-- Os três tipos anteriores (contrato_trabalho, contrato_b2b, declaracao)
-- têm slots FIXOS em slots_tipo: o catálogo diz exatamente quais slots
-- existem e o que cada um exige. O tipo livre é o contrário — não tem
-- nenhuma linha em slots_tipo, e por isso a quantidade e os requisitos
-- de cada slot vêm do que o criador preencheu no momento da criação.
--
-- Regra que substitui o catálogo, para o tipo livre: cada slot tem de
-- nomear quem assina (cédula de pessoa OU de empresa). Sem isso qualquer
-- pessoa com Carteirinha poderia assinar qualquer slot — que é
-- exatamente o buraco que a checagem de slots_tipo fecha nos outros
-- tipos.
-- Aplicada ao Supabase do projeto (moxxbehwylcjaqjacmyh) em 2026-09-02.

insert into public.tipos_documento (tipo, descricao, orgao_destino) values
  ('documento_livre', 'Documento livre (você escolhe quantas assinaturas)', null)
on conflict (tipo) do nothing;

-- Sem insert em slots_tipo de propósito: é a ausência de regra fixa que
-- marca o tipo como livre.

-- ---------------------------------------------------------------------
-- ass_criar_documento: aceita slots livres quando o tipo não tem catálogo
-- ---------------------------------------------------------------------
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
  v_tem_catalogo boolean;
  v_qtd int;
  v_nomes text[];
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'erro', 'Sem sessão.');
  end if;
  if not exists (select 1 from public.tipos_documento where tipo = p_tipo) then
    return jsonb_build_object('ok', false, 'erro', 'Tipo de documento desconhecido.');
  end if;

  v_tem_catalogo := exists (select 1 from public.slots_tipo where tipo = p_tipo);

  if v_tem_catalogo then
    -- tipo com slots fixos: continua exigindo bater exatamente com o catálogo
    select array_agg(slot order by slot) into v_exigidos
      from public.slots_tipo where tipo = p_tipo;
    select array_agg((s->>'slot') order by (s->>'slot'))
      into v_dados from jsonb_array_elements(coalesce(p_slots, '[]'::jsonb)) s;

    if v_exigidos is distinct from v_dados then
      return jsonb_build_object('ok', false, 'erro', 'Os slots enviados não batem com os exigidos pelo tipo.');
    end if;
  else
    -- tipo livre: a quantidade vem de quem cria, mas com limites e com
    -- cada slot obrigado a nomear quem assina
    select count(*) into v_qtd from jsonb_array_elements(coalesce(p_slots, '[]'::jsonb));
    if v_qtd < 1 then
      return jsonb_build_object('ok', false, 'erro', 'Escolha pelo menos uma assinatura.');
    end if;
    if v_qtd > 10 then
      return jsonb_build_object('ok', false, 'erro', 'Máximo de 10 assinaturas por documento.');
    end if;

    select array_agg(s->>'slot') into v_nomes
      from jsonb_array_elements(p_slots) s;
    if exists (select 1 from unnest(v_nomes) n where n is null or btrim(n) = '') then
      return jsonb_build_object('ok', false, 'erro', 'Todo slot precisa de um nome.');
    end if;
    if (select count(distinct n) from unnest(v_nomes) n) <> v_qtd then
      return jsonb_build_object('ok', false, 'erro', 'Os nomes dos slots precisam ser diferentes entre si.');
    end if;

    if exists (
      select 1 from jsonb_array_elements(p_slots) s
      where coalesce(nullif(btrim(s->>'pessoa_esperada'), ''), nullif(btrim(s->>'empresa_esperada'), '')) is null
    ) then
      return jsonb_build_object('ok', false, 'erro',
        'Cada assinatura precisa dizer quem assina (cédula de pessoa ou de empresa).');
    end if;
  end if;

  v_doc_id := gen_random_uuid();

  insert into public.documentos(id, tipo, criado_por, estado)
  values (v_doc_id, p_tipo, v_uid::text, 'pendente');

  for v_slot in select * from jsonb_array_elements(p_slots) loop
    insert into public.documento_slots(documento_id, slot, empresa_esperada, pessoa_esperada)
    values (
      v_doc_id,
      btrim(v_slot->>'slot'),
      nullif(btrim(v_slot->>'empresa_esperada'), ''),
      nullif(btrim(v_slot->>'pessoa_esperada'), '')
    );
  end loop;

  return jsonb_build_object('ok', true, 'dados', jsonb_build_object('documento_id', v_doc_id, 'tipo', p_tipo, 'estado', 'pendente'));
exception when others then
  return jsonb_build_object('ok', false, 'erro', 'Falha ao criar documento: ' || sqlerrm);
end;
$$;

-- ---------------------------------------------------------------------
-- ass_assinar: quando não há regra em slots_tipo, o requisito vem do
-- próprio slot (pessoa_esperada / empresa_esperada gravadas na criação).
-- Sem isso, um tipo livre aceitaria assinatura de qualquer pessoa com
-- Carteirinha — v_regra viria toda NULL e as checagens seriam puladas.
-- ---------------------------------------------------------------------
create or replace function public.ass_assinar(
  p_documento_id uuid,
  p_slot text,
  p_pagina int default null,
  p_pos_x real default null,
  p_pos_y real default null
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
  v_tem_regra boolean;
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
  v_tem_regra := found;

  if v_tem_regra then
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
  else
    -- tipo livre: o requisito é quem o criador nomeou neste slot
    if v_ds.pessoa_esperada is not null then
      if v_pessoa.cedula <> v_ds.pessoa_esperada then
        return jsonb_build_object('ok', false, 'erro', 'Este slot só pode ser assinado pela pessoa exata esperada.');
      end if;
    elsif v_ds.empresa_esperada is not null then
      if v_empresa_cedula is null or v_empresa_cedula <> v_ds.empresa_esperada then
        return jsonb_build_object('ok', false, 'erro', 'Este slot só pode ser assinado por alguém vinculado à empresa esperada.');
      end if;
    else
      return jsonb_build_object('ok', false, 'erro', 'Slot sem assinante definido — documento inválido.');
    end if;
  end if;

  v_hash_ass := encode(digest(
    p_documento_id::text || '|' || p_slot || '|' || v_pessoa.cedula || '|' || now()::text,
    'sha256'), 'hex');
  v_codigo := 'ASS-' || replace(v_pessoa.cedula, '-', '') || '-' || upper(left(v_hash_ass, 4));

  update public.documento_slots
    set preenchido_por = v_pessoa.cedula, codigo = v_codigo, assinado_em = now(),
        pagina_assinatura = p_pagina, pos_x = p_pos_x, pos_y = p_pos_y
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
