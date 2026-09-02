// Subsight — criação de documento com slots dinâmicos por tipo.

const areaLogin = document.getElementById('area-login');
const areaCriar = document.getElementById('area-criar');
const formLogin = document.getElementById('form-login');
const msgLogin = document.getElementById('msg-login');
const seletorTipo = document.getElementById('tipo');
const slotsDinamicos = document.getElementById('slots-dinamicos');

let slotsPorTipo = {};

async function carregarCatalogo() {
  const { data: tipos } = await sb.from('tipos_documento').select('tipo, descricao').order('tipo');
  const { data: slots } = await sb.from('slots_tipo').select('tipo, slot, exige_papel, exige_vinculo');

  slotsPorTipo = {};
  for (const s of slots || []) {
    (slotsPorTipo[s.tipo] ||= []).push(s);
  }

  seletorTipo.innerHTML = (tipos || [])
    .map((t) => `<option value="${t.tipo}">${t.descricao}</option>`)
    .join('');

  renderSlots();
}

// Um tipo é "livre" quando não tem nenhum slot fixo no catálogo: aí a
// quantidade de assinaturas e quem assina cada uma vêm de quem cria.
function tipoEhLivre(tipo) {
  return !(slotsPorTipo[tipo] || []).length;
}

function renderSlots() {
  if (tipoEhLivre(seletorTipo.value)) {
    renderSlotsLivres();
    return;
  }

  const slots = slotsPorTipo[seletorTipo.value] || [];
  slotsDinamicos.innerHTML = slots
    .map((s) => {
      const pedeCedulaPessoa = s.exige_vinculo === 'pessoa_exata';
      const rotulo = pedeCedulaPessoa ? 'Cédula da pessoa (PP-...)' : 'Cédula da empresa (EP-...)';
      const requisito = [
        s.exige_papel ? `papel: ${s.exige_papel}` : null,
        s.exige_vinculo ? `vínculo: ${s.exige_vinculo}` : null,
      ]
        .filter(Boolean)
        .join(' · ');
      return `
        <div class="campo-slot-dinamico" data-slot="${s.slot}" data-tipo-vinculo="${pedeCedulaPessoa ? 'pessoa' : 'empresa'}">
          <label>Slot "${s.slot}" ${requisito ? `<span style="color:#A9A9A9;font-weight:400">(${requisito})</span>` : ''}</label>
          <input class="valor-slot" placeholder="${rotulo}" required />
        </div>`;
    })
    .join('');
}

function renderSlotsLivres() {
  slotsDinamicos.innerHTML = `
    <label for="qtd-assinaturas">Quantas assinaturas este documento precisa?</label>
    <input id="qtd-assinaturas" type="number" min="1" max="10" value="2" />
    <div id="assinantes-livres"></div>`;

  const campoQtd = document.getElementById('qtd-assinaturas');
  campoQtd.addEventListener('input', renderAssinantesLivres);
  renderAssinantesLivres();
}

function renderAssinantesLivres() {
  const campoQtd = document.getElementById('qtd-assinaturas');
  const alvo = document.getElementById('assinantes-livres');
  let qtd = parseInt(campoQtd.value, 10);
  if (!Number.isFinite(qtd)) return;
  qtd = Math.min(Math.max(qtd, 1), 10);

  // preserva o que já foi digitado ao mudar a quantidade
  const anteriores = Array.from(alvo.querySelectorAll('.campo-slot-dinamico')).map((b) => ({
    vinculo: b.dataset.tipoVinculo,
    valor: b.querySelector('.valor-slot').value,
  }));

  alvo.innerHTML = Array.from({ length: qtd }, (_, i) => {
    const anterior = anteriores[i] || { vinculo: 'pessoa', valor: '' };
    const ehPessoa = anterior.vinculo === 'pessoa';
    return `
      <div class="campo-slot-dinamico" data-slot="assinante_${i + 1}" data-tipo-vinculo="${anterior.vinculo}">
        <label>Assinatura ${i + 1} — quem assina?</label>
        <select class="tipo-vinculo-livre">
          <option value="pessoa" ${ehPessoa ? 'selected' : ''}>Uma pessoa (cédula PP-...)</option>
          <option value="empresa" ${ehPessoa ? '' : 'selected'}>Alguém de uma empresa (cédula EP-...)</option>
        </select>
        <input class="valor-slot" placeholder="${ehPessoa ? 'PP-2026-00001' : 'EP-2026-00001'}"
               value="${anterior.valor.replace(/"/g, '&quot;')}" required />
      </div>`;
  }).join('');

  alvo.querySelectorAll('.tipo-vinculo-livre').forEach((sel) => {
    sel.addEventListener('change', () => {
      const bloco = sel.closest('.campo-slot-dinamico');
      bloco.dataset.tipoVinculo = sel.value;
      bloco.querySelector('.valor-slot').placeholder =
        sel.value === 'pessoa' ? 'PP-2026-00001' : 'EP-2026-00001';
    });
  });
}

seletorTipo.addEventListener('change', renderSlots);

async function verificarSessao() {
  const { data } = await sb.auth.getSession();
  if (data.session) {
    areaLogin.hidden = true;
    areaCriar.hidden = false;
    carregarCatalogo();
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

async function calcularHashSHA256(arquivo) {
  const buffer = await arquivo.arrayBuffer();
  const digest = await crypto.subtle.digest('SHA-256', buffer);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

document.getElementById('form-criar').addEventListener('submit', async (ev) => {
  ev.preventDefault();
  const msg = document.getElementById('msg-criar');
  const btn = document.getElementById('btn-criar');
  const arquivo = document.getElementById('arquivo').files[0];

  if (!arquivo || arquivo.type !== 'application/pdf') {
    msg.textContent = 'Escolha um ficheiro PDF.';
    msg.className = 'msg erro';
    return;
  }
  if (arquivo.size > 15 * 1024 * 1024) {
    msg.textContent = 'Ficheiro grande demais (máx. 15 MB).';
    msg.className = 'msg erro';
    return;
  }

  const blocos = slotsDinamicos.querySelectorAll('.campo-slot-dinamico');
  const slotsJson = Array.from(blocos).map((b) => {
    const cedula = b.querySelector('.valor-slot').value.trim();
    const ehPessoa = b.dataset.tipoVinculo === 'pessoa';
    return {
      slot: b.dataset.slot,
      pessoa_esperada: ehPessoa ? cedula : null,
      empresa_esperada: ehPessoa ? null : cedula,
    };
  });

  btn.disabled = true;
  msg.textContent = 'A criar o documento…';
  msg.className = 'msg';

  const rCriar = await api('ass_criar_documento', { p_tipo: seletorTipo.value, p_slots: slotsJson });
  if (!rCriar.ok) {
    msg.textContent = 'Erro: ' + rCriar.erro;
    msg.className = 'msg erro';
    btn.disabled = false;
    return;
  }
  const documentoId = rCriar.dados.documento_id;

  msg.textContent = 'A enviar o PDF…';
  const caminho = `${documentoId}/${arquivo.name}`;
  const { error: erroUpload } = await sb.storage.from('documentos').upload(caminho, arquivo, {
    contentType: 'application/pdf',
  });
  if (erroUpload) {
    msg.textContent = 'Documento criado, mas falhou o envio do PDF: ' + erroUpload.message;
    msg.className = 'msg erro';
    btn.disabled = false;
    return;
  }

  msg.textContent = 'A calcular a assinatura de integridade…';
  const hash = await calcularHashSHA256(arquivo);

  const rAnexar = await api('ass_anexar_arquivo', {
    p_documento_id: documentoId,
    p_arquivo_url: caminho,
    p_nome_arquivo: arquivo.name,
    p_hash_conteudo: hash,
  });
  if (!rAnexar.ok) {
    msg.textContent = 'Erro ao finalizar: ' + rAnexar.erro;
    msg.className = 'msg erro';
    btn.disabled = false;
    return;
  }

  mostrarConclusao(documentoId, slotsJson);
});

function mostrarConclusao(documentoId, slotsJson) {
  document.getElementById('form-criar').hidden = true;

  const listaEsperados = slotsJson
    .map((s) => `<li><strong>${s.slot}</strong> — esperado: ${s.pessoa_esperada || s.empresa_esperada}</li>`)
    .join('');

  const painel = document.createElement('div');
  painel.className = 'painel selo selo-ok';
  painel.innerHTML = `
    <div class="selo-icone"><img class="icone" src="web/icons/check-01.svg" alt="" /></div>
    <div class="selo-titulo">Documento criado e enviado</div>
    <div class="selo-subtitulo">O PDF foi enviado com sucesso. Falta assinatura de:</div>
    <ul style="text-align:left; max-width:320px; margin:1rem auto 0; font-size:0.9rem">${listaEsperados}</ul>
    <a href="documento.html?id=${documentoId}" class="botao destaque" style="margin-top:1.5rem">Ver documento →</a>
  `;
  document.getElementById('area-criar').appendChild(painel);
}

verificarSessao();
