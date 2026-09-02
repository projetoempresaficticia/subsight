-- Subsight: guarda onde na página o assinante posicionou a assinatura
-- (clique sobre o preview do PDF, renderizado com PDF.js), para mostrar um
-- carimbo na posição certa depois. Página 1 por agora (documentos de uma
-- página); pos_x/pos_y são frações 0–1 relativas ao tamanho da página, não
-- pixels, para não depender do zoom/tamanho de tela usado ao assinar.
-- Aplicada ao Supabase do projeto (moxxbehwylcjaqjacmyh) em 2026-09-02.

alter table public.documento_slots add column if not exists pagina_assinatura int;
alter table public.documento_slots add column if not exists pos_x real;
alter table public.documento_slots add column if not exists pos_y real;

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
