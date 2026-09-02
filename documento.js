// Subsight — ver documento (com preview do PDF), escolher onde fica a
// assinatura, assinar slots, anular.

pdfjsLib.GlobalWorkerOptions.workerSrc =
  'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js';

const areaLogin = document.getElementById('area-login');
const areaDocumento = document.getElementById('area-documento');
const areaNaoEncontrado = document.getElementById('area-nao-encontrado');
const formLogin = document.getElementById('form-login');
const msgLogin = document.getElementById('msg-login');
const visualizador = document.getElementById('visualizador-pdf');
const canvas = document.getElementById('d-canvas');
const marcadoresEl = document.getElementById('d-marcadores');
const dicaPosicionar = document.getElementById('dica-posicionar');
const btnConfirmarPosicao = document.getElementById('btn-confirmar-posicao');

const documentoId = new URLSearchParams(window.location.search).get('id');

let slotEscolhendo = null; // slot que está aguardando clique de posição
let posicaoEscolhida = null; // {x, y} em frações 0–1

function badgeEstado(estado) {
  const rotulos = { pendente: 'Pendente', completo: 'Completo', anulado: 'Anulado' };
  return `<span class="badge badge-${estado}">${rotulos[estado] || estado}</span>`;
}

function mostrarMsg(texto, ok) {
  const el = document.getElementById('msg-acao');
  el.textContent = texto;
  el.className = 'msg ' + (ok ? 'sucesso' : 'erro');
}

function desenharMarcadores(slotsAssinados) {
  marcadoresEl.innerHTML = slotsAssinados
    .filter((s) => s.pos_x != null && s.pos_y != null)
    .map(
      (s) => `
      <div class="marcador-assinatura" style="left:${s.pos_x * 100}%; top:${s.pos_y * 100}%">
        <div class="ponto"></div>
        <div class="etiqueta">${s.slot}</div>
      </div>`
    )
    .join('');
}

async function renderizarPdf(urlAssinada) {
  const pdf = await pdfjsLib.getDocument(urlAssinada).promise;
  const pagina = await pdf.getPage(1);
  const escala = 480 / pagina.getViewport({ scale: 1 }).width;
  const viewport = pagina.getViewport({ scale: escala });
  canvas.width = viewport.width;
  canvas.height = viewport.height;
  await pagina.render({ canvasContext: canvas.getContext('2d'), viewport }).promise;
}

visualizador.addEventListener('click', (ev) => {
  if (!slotEscolhendo) return;
  const retangulo = canvas.getBoundingClientRect();
  const x = (ev.clientX - retangulo.left) / retangulo.width;
  const y = (ev.clientY - retangulo.top) / retangulo.height;
  posicaoEscolhida = { x, y };

  const antigo = marcadoresEl.querySelector('.marcador-provisorio');
  if (antigo) antigo.remove();
  const marcador = document.createElement('div');
  marcador.className = 'marcador-assinatura marcador-provisorio';
  marcador.style.left = x * 100 + '%';
  marcador.style.top = y * 100 + '%';
  marcador.innerHTML = `<div class="ponto"></div><div class="etiqueta">${slotEscolhendo}</div>`;
  marcadoresEl.appendChild(marcador);

  btnConfirmarPosicao.hidden = false;
});

function iniciarEscolhaDePosicao(slot) {
  slotEscolhendo = slot;
  posicaoEscolhida = null;
  visualizador.classList.add('escolhendo');
  dicaPosicionar.hidden = false;
  btnConfirmarPosicao.hidden = true;
}

function cancelarEscolhaDePosicao() {
  slotEscolhendo = null;
  posicaoEscolhida = null;
  visualizador.classList.remove('escolhendo');
  dicaPosicionar.hidden = true;
  btnConfirmarPosicao.hidden = true;
  const provisorio = marcadoresEl.querySelector('.marcador-provisorio');
  if (provisorio) provisorio.remove();
}

btnConfirmarPosicao.addEventListener('click', async () => {
  if (!slotEscolhendo || !posicaoEscolhida) return;
  const slot = slotEscolhendo;
  const r = await api('ass_assinar', {
    p_documento_id: documentoId,
    p_slot: slot,
    p_pagina: 1,
    p_pos_x: posicaoEscolhida.x,
    p_pos_y: posicaoEscolhida.y,
  });
  cancelarEscolhaDePosicao();
  if (r.ok) {
    mostrarMsg(`Assinado! Código ${r.dados.codigo}.`, true);
    carregarDocumento();
  } else {
    mostrarMsg('Erro ao assinar: ' + r.erro, false);
  }
});

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
    .select('slot, empresa_esperada, pessoa_esperada, preenchido_por, codigo, assinado_em, pos_x, pos_y')
    .eq('documento_id', documentoId)
    .order('slot');

  document.getElementById('d-titulo').textContent = tipoInfo ? tipoInfo.descricao : doc.tipo;
  document.getElementById('d-estado').innerHTML = badgeEstado(doc.estado);
  document.getElementById('d-hash').textContent = doc.hash_conteudo || '(sem ficheiro anexado)';
  document.getElementById('d-link-verificar').href = `verificar.html?id=${doc.id}`;

  const linkPdf = document.getElementById('d-link-pdf');
  if (doc.arquivo_url) {
    const { data: assinada } = await sb.storage.from('documentos').createSignedUrl(doc.arquivo_url, 300);
    if (assinada) {
      linkPdf.href = assinada.signedUrl;
      linkPdf.hidden = false;
      try {
        await renderizarPdf(assinada.signedUrl);
        visualizador.hidden = false;
      } catch (e) {
        visualizador.hidden = true;
      }
      desenharMarcadores(slots || []);
    }
  } else {
    linkPdf.hidden = true;
    visualizador.hidden = true;
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
          <button type="button" class="destaque" style="margin:0" data-escolher="${s.slot}">
            <img class="icone" src="web/icons/pen-tool-01.svg" alt="" />
            Assinar
          </button>
        </div>`;
    })
    .join('') || '<p class="vazio">Sem slots.</p>';

  listaSlots.querySelectorAll('[data-escolher]').forEach((btn) => {
    btn.addEventListener('click', () => {
      if (!doc.arquivo_url) {
        mostrarMsg('Este documento ainda não tem ficheiro anexado.', false);
        return;
      }
      iniciarEscolhaDePosicao(btn.dataset.escolher);
    });
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
