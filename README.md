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
- Ícones: kit único do Figma "Icone" (estilo Untitled UI, outline 24px) — 9
  ícones já baixados e otimizados em `web/icons/` (pen-tool, file-check,
  lock, shield-check, check, upload, mail, clock, user-profile); mais
  entram conforme a cota do Figma permitir — ver
  `.claude/skills/figma-icons/cache/`
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
- `index.html`/`app.js` — login + lista "Meus documentos".
- `criar.html`/`criar.js` — escolher tipo, enviar o PDF, preencher os
  campos de slot dinâmicos (muda conforme o tipo: pede cédula de pessoa ou
  de empresa).
- `documento.html`/`documento.js` — link para o PDF (URL assinada do
  Storage, o bucket é privado), hash, slots (quem assinou, código), assinar
  um slot vago, anular.
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

## Advisory de segurança (esperado)

`ass_criar_documento`, `ass_assinar` e `ass_anular` aparecem no security
advisor como `SECURITY DEFINER` chamáveis por `anon`/`authenticated` — é
intencional (porta única), mesmo padrão do `pp-identidade`.

## Convenções

- Regras técnicas completas na skill `pp-assinatura` dentro de
  `.claude/skills/` (não versionada neste repositório).
- Commits seguem a convenção Angular (`feat`, `fix`, `docs`, `chore`, ...).
