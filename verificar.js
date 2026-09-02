// Subsight — verificação pública (sem login). ass_verificar não exige sessão.

const painelCarregando = document.getElementById('carregando');
const painelResultado = document.getElementById('resultado');
const painelNaoEncontrado = document.getElementById('nao-encontrado');

function mostrarPainel(painel) {
  painelCarregando.hidden = true;
  painelResultado.hidden = true;
  painelNaoEncontrado.hidden = true;
  painel.hidden = false;
}

async function verificar() {
  const id = new URLSearchParams(window.location.search).get('id');
  if (!id) {
    mostrarPainel(painelNaoEncontrado);
    return;
  }

  const r = await api('ass_verificar', { p_documento_id: id });
  if (!r.ok) {
    mostrarPainel(painelNaoEncontrado);
    return;
  }

  const d = r.dados;
  const selo = document.getElementById('resultado');
  selo.classList.remove('selo-ok', 'selo-aviso', 'selo-erro');

  if (d.valido) {
    selo.classList.add('selo-ok');
    document.getElementById('v-titulo').textContent = 'Documento válido';
    document.getElementById('v-subtitulo').textContent = 'Todas as assinaturas exigidas foram feitas e o ficheiro tem a integridade travada pelo Storage.';
  } else if (!d.integro) {
    selo.classList.add('selo-erro');
    document.getElementById('v-titulo').textContent = 'Sem ficheiro confirmado';
    document.getElementById('v-subtitulo').textContent = 'Este documento ainda não tem um PDF anexado — não pode ser assinado nem verificado.';
  } else {
    selo.classList.add('selo-aviso');
    document.getElementById('v-titulo').textContent = 'Assinaturas pendentes';
    document.getElementById('v-subtitulo').textContent = 'Ainda faltam assinaturas para este documento ser válido.';
  }

  document.getElementById('v-estado').textContent = d.estado;
  document.getElementById('v-assinaturas').textContent = `${d.assinaturas} / ${d.exigidas}`;
  document.getElementById('v-integro').textContent = d.integro ? 'Sim' : 'Não';
  document.getElementById('v-valido').textContent = d.valido ? 'Sim' : 'Não';

  mostrarPainel(painelResultado);
}

verificar();
