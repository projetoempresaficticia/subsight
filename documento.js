// Subsight — ver documento, assinar slots, anular.

const areaLogin = document.getElementById('area-login');
const areaDocumento = document.getElementById('area-documento');
const areaNaoEncontrado = document.getElementById('area-nao-encontrado');
const formLogin = document.getElementById('form-login');
const msgLogin = document.getElementById('msg-login');

const documentoId = new URLSearchParams(window.location.search).get('id');

function badgeEstado(estado) {
  const rotulos = { pendente: 'Pendente', completo: 'Completo', anulado: 'Anulado' };
  return `<span class="badge badge-${estado}">${rotulos[estado] || estado}</span>`;
}

function mostrarMsg(texto, ok) {
  const el = document.getElementById('msg-acao');
  el.textContent = texto;
  el.className = 'msg ' + (ok ? 'sucesso' : 'erro');
}

async function assinarSlot(slot) {
  const r = await api('ass_assinar', { p_documento_id: documentoId, p_slot: slot });
  if (r.ok) {
    mostrarMsg(`Assinado! Código ${r.dados.codigo}.`, true);
    carregarDocumento();
  } else {
    mostrarMsg('Erro ao assinar: ' + r.erro, false);
  }
}

async function anular() {
  if (!confirm('Anular este documento? Esta ação não pode ser desfeita.')) return;
  const r = await api('ass_anular', { p_documento_id: documentoId });
  if (r.ok) {
    mostrarMsg('Documento anulado.', true);
    carregarDocumento();
  } else {
    mostrarMsg('Erro ao anular: ' + r.erro, false);
  }
}

async function carregarDocumento() {
  if (!documentoId) {
    areaDocumento.hidden = true;
    areaNaoEncontrado.hidden = false;
    return;
  }

  const { data: doc, error } = await sb
    .from('documentos')
    .select('id, tipo, estado, arquivo_url, nome_arquivo, hash_conteudo, criado_em')
    .eq('id', documentoId)
    .single();

  if (error || !doc) {
    areaDocumento.hidden = true;
    areaNaoEncontrado.hidden = false;
    return;
  }

  const { data: tipoInfo } = await sb
    .from('tipos_documento')
    .select('descricao')
    .eq('tipo', doc.tipo)
    .single();

  const { data: slots } = await sb
    .from('documento_slots')
    .select('slot, empresa_esperada, pessoa_esperada, preenchido_por, codigo, assinado_em')
    .eq('documento_id', documentoId)
    .order('slot');

  document.getElementById('d-titulo').textContent = tipoInfo ? tipoInfo.descricao : doc.tipo;
  document.getElementById('d-estado').innerHTML = badgeEstado(doc.estado);
  document.getElementById('d-hash').textContent = doc.hash_conteudo || '(sem ficheiro anexado)';
  document.getElementById('d-link-verificar').href = `verificar.html?id=${doc.id}`;

  const linkPdf = document.getElementById('d-link-pdf');
  if (doc.arquivo_url) {
    document.getElementById('d-nome-arquivo').textContent = doc.nome_arquivo || 'Ver PDF';
    const { data: assinada } = await sb.storage.from('documentos').createSignedUrl(doc.arquivo_url, 300);
    linkPdf.href = assinada ? assinada.signedUrl : '#';
    linkPdf.hidden = false;
  } else {
    linkPdf.hidden = true;
  }

  const listaSlots = document.getElementById('d-slots');
  listaSlots.innerHTML = (slots || [])
    .map((s) => {
      const esperado = s.pessoa_esperada || s.empresa_esperada || '—';
      if (s.preenchido_por) {
        return `
          <div class="slot-linha">
            <div>
              <div class="slot-nome">${s.slot}</div>
              <div class="slot-requisito">esperado: ${esperado}</div>
            </div>
            <div style="text-align:right">
              <div class="slot-assinado">✓ assinado por ${s.preenchido_por}</div>
              <div class="slot-codigo">${s.codigo}</div>
            </div>
          </div>`;
      }
      return `
        <div class="slot-linha">
          <div>
            <div class="slot-nome">${s.slot}</div>
            <div class="slot-requisito">esperado: ${esperado}</div>
          </div>
          <button type="button" class="destaque" style="margin:0" data-assinar="${s.slot}">
            <img class="icone" src="web/icons/pen-tool-01.svg" alt="" />
            Assinar
          </button>
        </div>`;
    })
    .join('') || '<p class="vazio">Sem slots.</p>';

  listaSlots.querySelectorAll('[data-assinar]').forEach((btn) => {
    btn.addEventListener('click', () => assinarSlot(btn.dataset.assinar));
  });

  const btnAnular = document.getElementById('btn-anular');
  btnAnular.hidden = doc.estado === 'anulado';

  areaNaoEncontrado.hidden = true;
  areaDocumento.hidden = false;
}

async function verificarSessao() {
  const { data } = await sb.auth.getSession();
  if (data.session) {
    areaLogin.hidden = true;
    carregarDocumento();
  }
}

formLogin.addEventListener('submit', async (ev) => {
  ev.preventDefault();
  const email = document.getElementById('email').value;
  const senha = document.getElementById('senha').value;
  const { error } = await sb.auth.signInWithPassword({ email, password: senha });
  if (error) {
    msgLogin.textContent = 'Login inválido.';
    msgLogin.className = 'msg erro';
    return;
  }
  await verificarSessao();
});

document.getElementById('btn-anular').addEventListener('click', anular);

verificarSessao();
