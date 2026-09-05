// Subsight — login e dashboard de documentos.

const areaLogin = document.getElementById('area-login');
const areaDashboard = document.getElementById('area-dashboard');
const navLogado = document.getElementById('nav-logado');
const formLogin = document.getElementById('form-login');
const msgLogin = document.getElementById('msg-login');

function badgeEstado(estado) {
  const rotulos = { pendente: 'Pendente', completo: 'Completo', anulado: 'Anulado' };
  return `<span class="badge badge-${estado}">${rotulos[estado] || estado}</span>`;
}

async function carregarDocumentos() {
  const corpo = document.getElementById('corpo-documentos');

  const { data: tipos } = await sb.from('tipos_documento').select('tipo, descricao');
  const descricaoPorTipo = Object.fromEntries((tipos || []).map((t) => [t.tipo, t.descricao]));

  const { data: docs, error } = await sb
    .from('documentos')
    .select('id, tipo, estado, criado_em')
    .order('criado_em', { ascending: false });

  if (error) {
    corpo.innerHTML = `<tr><td colspan="4" class="vazio">Erro ao carregar: ${error.message}</td></tr>`;
    return;
  }
  if (!docs.length) {
    corpo.innerHTML = '<tr><td colspan="4" class="vazio">Nenhum documento ainda. Crie o primeiro.</td></tr>';
    return;
  }

  corpo.innerHTML = docs
    .map(
      (d) => `
    <tr>
      <td>${descricaoPorTipo[d.tipo] || d.tipo}</td>
      <td>${badgeEstado(d.estado)}</td>
      <td>${new Date(d.criado_em).toLocaleDateString('pt-BR')}</td>
      <td><a href="documento.html?id=${d.id}">Ver →</a></td>
    </tr>`
    )
    .join('');
}

// A entrada tem de caber num ecrã sem rolar, e as telas de trabalho não
// têm essa restrição. A classe no <body> é o que diz ao CSS em qual dos
// dois casos estamos.
function modoEntrada(ligado) {
  document.body.classList.toggle('ss-modo-entrada', ligado);
}

async function verificarSessao() {
  const { data } = await sb.auth.getSession();
  if (data.session) {
    areaLogin.hidden = true;
    areaDashboard.hidden = false;
    navLogado.hidden = false;
    modoEntrada(false);
    carregarDocumentos();
  } else {
    modoEntrada(true);
  }
}

formLogin.addEventListener('submit', async (ev) => {
  ev.preventDefault();
  msgLogin.textContent = '';
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

document.getElementById('btn-sair').addEventListener('click', async () => {
  await sb.auth.signOut();
  areaDashboard.hidden = true;
  navLogado.hidden = true;
  areaLogin.hidden = false;
  modoEntrada(true);
});

verificarSessao();
