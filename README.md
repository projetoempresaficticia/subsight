# subsight

Assinatura digital com slots parte+papel+vínculo (Prepara Portugal)

**Status:** backend e frontend construídos e testados de ponta a ponta pela
UI real (criação de documento, assinatura com checagem de legitimidade,
conclusão automática, verificação pública, anulação).
**Depende de:** [pp-base](https://github.com/projetoempresaficticia/pp-base),
[classcard](https://github.com/projetoempresaficticia/classcard) (pp-identidade)

Documentação completa (PRDs e decisões) em
[prepara-portugal-docs](https://github.com/projetoempresaficticia/prepara-portugal-docs).

Site: https://projetoempresaficticia.github.io/subsight/

## Identidade visual (decidida)

- Nome do produto: **Subsight**
- Fundo `#FFFFFF` · Texto `#000000` · Secundário `#A9A9A9` · Destaque `#EEC1A0`
- Ícones: kit único do Figma "Icone" (estilo Untitled UI, outline 24px) — 10
  ícones já baixados e otimizados em `web/icons/` (pen-tool, file-check,
  lock, shield-check, check, upload, download, mail, clock, user-profile);
  mais entram conforme a cota do Figma permitir — ver
  `.claude/skills/figma-icons/cache/`
- Identidade visual **Bauhaus** (pedido do Germano): a marca é a própria
  **grade 3×3 de ladrilhos que se encaixam** (quartos/meios-círculo via
  `clipPath` + `circle` posicionado no canto/aresta da célula, triângulo,
  quadrados sólidos) — sem cores novas, só a paleta já fixada. Passou por
  três versões até acertar:
  1. Formas soltas flutuando (círculo, quadrado, triângulo, linha) —
     rejeitada ("esquisito"), não parecia Bauhaus de verdade.
  2. A grade 3×3 certa, mas como marca-d'água flutuante (`position: fixed`)
     num canto da tela, com um logotipo separado e pequeno (28px) no
     cabeçalho — rejeitada por dois motivos: a marca-d'água invadia o
     cartão de login em telas estreitas (por isso ganhou um
     `@media (max-width:900px){display:none}` que a escondia por completo
     no mobile), e o logotipo do cabeçalho ficou "muito pequeno e
     desproporcional" comparado ao estilo de referência (duas imagens de
     app mobile mandadas pelo Germano: cartão preto arredondado com o
     padrão geométrico como arte de fundo/ícone).
  3. O ícone de app quadrado arredondado (`.icone-app`, 48×48px) no
     cabeçalho, mesmo tamanho em toda página, sem posição fixa — resolveu a
     sobreposição, mas deixou o resto da página "completamente branca"
     (queixa do Germano); a grade só aparecia em miniatura, nunca com
     presença de verdade.
  4. A página de login ganhou um hero de verdade (grade grande dentro de
     um cartão preto ao lado do formulário) — resolveu a vitrine, mas o
     Germano apontou que ainda sobrava "espaço em branco" ao lado do
     cartão de login, e que o fundo continuava liso depois de entrar no
     app (lista de documentos, documento, etc.) — ele mandou 6
     referências de novo para deixar claro: páginas tipo Todoist, "SOLID",
     "Branding X" e uma landing chamada literalmente "Bauhaus" — o padrão
     comum entre elas não é só "tenha um bloco geométrico grande", é
     **o app inteiro vive dentro de uma moldura colorida** (a referência
     "Bauhaus" é a mais literal: moldura amarela cheia + cartão branco
     arredondado por dentro, com o bloco geométrico como um painel dentro
     desse cartão).
  5. **Versão atual:** todas as páginas (login, lista, criar, documento,
     verificar) ficam dentro de um `.app-shell` — um cartão branco
     arredondado, com margem, sobre um fundo preto (`--ss-texto`, já
     aprovada, nenhuma cor nova) que cobre a tela inteira. Isso resolve os
     dois pontos de uma vez: o "espaço em branco" do login virou moldura
     preta de propósito (não sobra mais vazio ao lado do cartão), e todo
     o resto do app — inclusive depois de logar — passa a viver dentro
     dessa moldura, não mais num fundo branco liso de ponta a ponta.
     `.app-shell` encolhe até a borda da tela em mobile (sem moldura) para
     não desperdiçar espaço numa tela já pequena.
- UI kit: avaliação em andamento (cota do plano Figma Starter é mensal, só
  20 chamadas) — Krinet visto parcialmente (botões, ótima cobertura de
  estados) como referência provisória; ver
  `.claude/skills/figma-ui-kits/cache/kits-avaliados.md`

## O que este repositório fornece

- `sql/0001_catalogo_e_rls.sql` — semeia o catálogo de tipos de documento
  (`contrato_trabalho`, `contrato_b2b`, `declaracao`) com os slots exigidos
  por cada um, e aplica RLS (catálogo público para leitura, escrita só
  professor; documentos visíveis para quem criou, quem é esperado num slot,
  e o professor). O schema e a função `ass_verificar` já existiam de uma
  sessão anterior; o catálogo tinha sido apagado na limpeza de teste dessa
  sessão e foi recriado aqui como dado permanente.
- `sql/0002_rpc_criar_assinar_anular.sql` — RPCs `ass_criar_documento`,
  `ass_assinar`, `ass_anular` (porta única, `{ok}` sempre). `ass_assinar`
  nunca aceita a cédula do assinante como parâmetro — deriva sempre de
  `auth.uid()`, para impedir assinar em nome de outro.
- `sql/0003_fix_rls_recursao_cruzada.sql` — corrige "infinite recursion
  detected in policy for relation documentos": a policy de `documentos`
  consultava `documento_slots`, e a de `documento_slots` consultava
  `documentos` de volta — recursão cruzada entre as duas tabelas. Só
  apareceu testando pela UI real (RLS ativo); os testes anteriores via SQL
  corriam como service role e não pegavam o bug. Corrigido com
  `fn_documento_visivel()` (security definer), a mesma classe de solução
  do `fn_e_professor()` no classcard — regra para as próximas skills:
  cuidado também com **duas tabelas se consultando uma à outra**, não só
  uma tabela a si mesma.
- `sql/0004_upload_pdf.sql` — o documento passou a ser um **PDF enviado**,
  não texto digitado (pedido do Germano — um app de assinatura de verdade
  assina um ficheiro, não uma caixa de texto). Bucket `documentos` privado
  no Storage; `ass_criar_documento` monta só o "envelope" (tipo + slots),
  `ass_anexar_arquivo` liga o PDF já enviado e trava `hash_conteudo` — só o
  criador, só uma vez (a policy de insert exige `hash_conteudo is null`).
  Sem policy de update no bucket → o ficheiro não pode ser substituído
  depois de anexado (imutabilidade real, testada: uma tentativa de
  sobrescrever é rejeitada por RLS). `ass_assinar` recusa assinar um
  documento sem ficheiro. O hash é calculado no **navegador**
  (`crypto.subtle.digest('SHA-256', ...)`) no momento do envio — o Postgres
  não tem como rebaixar/reconferir um ficheiro do Storage sozinho, por isso
  "íntegro" em `ass_verificar` passa a significar "tem hash travado",
  garantido pela imutabilidade do Storage em vez de recálculo ativo.
  Delete no bucket é restrito ao professor (manutenção/testes) — sem isso,
  nem o próprio dono conseguiria limpar um envio de teste.
- `sql/0005_posicao_assinatura.sql` — `documento_slots` ganha
  `pagina_assinatura`/`pos_x`/`pos_y` (frações 0–1 da página, não pixels —
  independe do zoom/tamanho de ecrã usado ao assinar); `ass_assinar` aceita
  esses três parâmetros opcionais e grava onde o assinante posicionou a
  assinatura.
- `index.html`/`app.js` — login + lista "Meus documentos".
- `criar.html`/`criar.js` — escolher tipo, enviar o PDF, preencher os
  campos de slot dinâmicos (muda conforme o tipo: pede cédula de pessoa ou
  de empresa); ao terminar, mostra um **painel de conclusão** explícito
  ("Documento criado e enviado", lista de quem falta assinar, botão "Ver
  documento →") em vez de redirecionar direto sem explicação.
- `documento.html`/`documento.js` — **preview do PDF** renderizado num
  `<canvas>` via [PDF.js](https://mozilla.github.io/pdf.js/) (não um
  `<iframe>` — precisa ser canvas para capturar clique e converter em
  posição na página); clicar no preview enquanto um slot está "assinando"
  marca onde fica a assinatura, um botão "Confirmar assinatura nesta
  posição" chama `ass_assinar` com essa posição. O carimbo mostra o
  **nome do assinante e a cédula abaixo do nome** (não o nome do slot) —
  enquanto a posição ainda não foi confirmada, mostra o nome/cédula da
  própria pessoa logada (é ela quem vai assinar); depois de confirmado,
  busca o nome em `pessoas` a partir da cédula gravada em
  `preenchido_por`, inclusive após recarregar a página. Botão de baixar
  com ícone (`download-01.svg`) em vez do nome cru do ficheiro.
- `verificar.html`/`verificar.js` — verificação pública (sem login) por
  `ass_verificar`, que já era pública por design.

## A "regra de ouro"

Um gerente da Empresa A não pode preencher um slot que espera a Empresa B —
`ass_assinar` cruza a empresa vinculada ao assinante (`pessoas.empresa_id`)
com `documento_slots.empresa_esperada`, e o papel do assinante com
`slots_tipo.exige_papel`. Testado explicitamente: gerente da empresa errada
e papel errado são ambos rejeitados; a assinatura correta completa o
documento automaticamente quando é o último slot.

## Testes

Testado primeiro via SQL real (backend isolado) e depois pela UI real com
agent-browser (login como gerente e como funcionário de verdade): contrato
de trabalho entre duas empresas fictícias e um funcionário — rejeição por
empresa/vínculo errado, rejeição por papel errado, assinatura válida,
idempotência (assinar o mesmo slot duas vezes falha na segunda), conclusão
automática do documento, painel do documento mostrando os dois códigos de
assinatura, página pública de verificação (`verificar.html`) confirmando
"Documento válido". Foi o teste pela UI real (RLS ativo, não service role)
que pegou o bug de recursão cruzada do `sql/0003`.

Depois, o fluxo de PDF (`sql/0004`) foi testado à parte, também pela UI
real: enviar um PDF de verdade, baixá-lo de volta pela URL assinada e
confirmar que é **byte a byte idêntico** ao original (`diff` limpo),
assinar, conferir "Documento válido" na verificação pública, e confirmar
que uma tentativa de **sobrescrever** o PDF já enviado é rejeitada por RLS
(imutabilidade real, não só documentada). Dados de teste limpos no fim
(incluindo os logins de Auth e o ficheiro no Storage); o catálogo semeado
ficou.

Depois, o preview de PDF + posicionamento (`sql/0005`) foi testado à parte
com um PDF gerado programaticamente (o PDF mínimo sintético usado antes não
tinha um content stream válido — o PDF.js recusava; um PDF com stream real
foi necessário para o teste). O teste pegou um bug real antes de publicar:
`renderizarPdf` calculava a variável `escala` mas passava `scale` (nome
errado) para `getViewport`, um `ReferenceError` silencioso que deixava o
preview simplesmente escondido. Corrigido, testado clicando de fato no
canvas, confirmando a posição capturada, assinando, e confirmando que o
carimbo aparece na posição certa mesmo depois de recarregar a página.

Depois, a grade Bauhaus v2 e o carimbo nome+cédula foram testados juntos,
pela UI real servida localmente (login como professor real via
`agent-browser`): grade decorativa conferida por screenshot nas 4 páginas,
documento de teste criado com um PDF sintético válido, marcador provisório
conferido mostrando nome+cédula da própria pessoa logada ao clicar no
preview, e o carimbo já-assinado conferido mostrando nome+cédula buscados
de `pessoas` pela cédula gravada. A assinatura de fato não pôde ser
confirmada nesse teste porque o professor de bootstrap não tem
`empresa_id` (o slot `declarante` exige vínculo de empresa) — comportamento
esperado do `ass_assinar`, não um bug; o carimbo já-assinado foi conferido
chamando `desenharMarcadores` diretamente com um slot sintético, o que
ainda exercita a consulta real a `pessoas`. Documento de teste anulado no
fim (não existe policy de delete em `documentos`/`documento_slots` — só
anular; o ficheiro no Storage foi removido à parte, que tem policy de
delete restrita ao professor).

## Advisory de segurança (esperado)

`ass_criar_documento`, `ass_assinar` e `ass_anular` aparecem no security
advisor como `SECURITY DEFINER` chamáveis por `anon`/`authenticated` — é
intencional (porta única), mesmo padrão do `pp-identidade`.

## Convenções

- Regras técnicas completas na skill `pp-assinatura` dentro de
  `.claude/skills/` (não versionada neste repositório).
- Commits seguem a convenção Angular (`feat`, `fix`, `docs`, `chore`, ...).
