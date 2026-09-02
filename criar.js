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

function renderSlots() {
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

  window.location.href = `documento.html?id=${documentoId}`;
});

verificarSessao();
