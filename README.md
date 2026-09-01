# pp-assinatura

**Subsight** — assinatura digital com slots parte+papel+vínculo (Prepara Portugal)

**Status:** backend construído e testado de ponta a ponta via SQL real
(criação de documento, assinatura com checagem de legitimidade, conclusão
automática, verificação, anulação). Frontend ainda por fazer.
**Depende de:** [pp-base](https://github.com/projetoempresaficticia/pp-base),
[classcard](https://github.com/projetoempresaficticia/classcard) (pp-identidade)

Documentação completa (PRDs e decisões) em
[prepara-portugal-docs](https://github.com/projetoempresaficticia/prepara-portugal-docs).

## Identidade visual (decidida)

- Nome do produto: **Subsight**
- Fundo `#FFFFFF` · Texto `#000000` · Secundário `#A9A9A9` · Destaque `#EEC1A0`
- Ícones: kit único do Figma "Icones" (estilo Untitled UI, outline 24px) —
  ver `.claude/skills/figma-icons/cache/`
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

## A "regra de ouro"

Um gerente da Empresa A não pode preencher um slot que espera a Empresa B —
`ass_assinar` cruza a empresa vinculada ao assinante (`pessoas.empresa_id`)
com `documento_slots.empresa_esperada`, e o papel do assinante com
`slots_tipo.exige_papel`. Testado explicitamente: gerente da empresa errada
e papel errado são ambos rejeitados; a assinatura correta completa o
documento automaticamente quando é o último slot.

## Testes

Testado via SQL real contra o Supabase do projeto: contrato de trabalho
entre duas empresas fictícias e um funcionário — rejeição por
empresa/vínculo errado, rejeição por papel errado, assinatura válida,
idempotência (assinar o mesmo slot duas vezes falha na segunda), conclusão
automática do documento, `ass_verificar` (íntegro + válido), `ass_anular`
(pendente por criador, completo só por professor). Dados de teste limpos no
fim; o catálogo semeado ficou.

## Advisory de segurança (esperado)

`ass_criar_documento`, `ass_assinar` e `ass_anular` aparecem no security
advisor como `SECURITY DEFINER` chamáveis por `anon`/`authenticated` — é
intencional (porta única), mesmo padrão do `pp-identidade`.

## Convenções

- Regras técnicas completas na skill `pp-assinatura` dentro de
  `.claude/skills/` (não versionada neste repositório).
- Commits seguem a convenção Angular (`feat`, `fix`, `docs`, `chore`, ...).
