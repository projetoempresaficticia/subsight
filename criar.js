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

document.getElementById('form-criar').addEventListener('submit', async (ev) => {
  ev.preventDefault();
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

  const r = await api('ass_criar_documento', {
    p_tipo: seletorTipo.value,
    p_conteudo: document.getElementById('conteudo').value,
    p_slots: slotsJson,
  });

  const msg = document.getElementById('msg-criar');
  if (r.ok) {
    window.location.href = `documento.html?id=${r.dados.documento_id}`;
  } else {
    msg.textContent = 'Erro: ' + r.erro;
    msg.className = 'msg erro';
  }
});

verificarSessao();
