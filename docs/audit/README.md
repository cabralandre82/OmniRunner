# Auditoria Omni Runner — Documentação & Rastreabilidade

> **Atualizado:** 2026-04-17
> **Status:** Em execução — Onda 0
> **Escopo:** Portal Next.js + App Flutter + Supabase (DB, Edge Functions, pg_cron) + CI/CD + Compliance

Esta pasta é a **fonte única da verdade** para a auditoria de 360° do Omni Runner realizada em 2026-04-17. Todos os achados, status de correção, runbooks derivados e relatórios de progresso ficam aqui.

---

## Como ler esta pasta

| Arquivo / pasta | O que é |
|---|---|
| [`README.md`](./README.md) | Este arquivo — índice e guia |
| [`METHODOLOGY.md`](./METHODOLOGY.md) | As 23 lentes, critérios de severidade, processo |
| [`FINDINGS.md`](./FINDINGS.md) *(gerado)* | Tabela-índice de todos os 310 findings (ordenável, filtrável) |
| [`SCORECARD.md`](./SCORECARD.md) *(gerado)* | Burn-down, % críticos fechados, por onda/lente |
| [`ROADMAP.md`](./ROADMAP.md) | Ondas 0 → 3 com milestones |
| [`registry.json`](./registry.json) *(gerado)* | Registry legível por máquina (CI, dashboards, scripts) |
| [`findings/`](./findings/) | 1 arquivo Markdown por finding — **fonte autoral** |
| [`findings/_template.md`](./findings/_template.md) | Template para criar/editar findings manualmente |
| [`parts/`](./parts/) | Os 8 relatórios originais da auditoria completa (narrativa) |
| [`runbooks/`](./runbooks/) | Runbooks operacionais derivados de findings específicos |

**Arquivos marcados "gerado"** são produzidos por `tools/audit/*.ts` a partir dos `findings/*.md`. **Não editar manualmente** — fonte = arquivos individuais de finding.

---

## Fluxo de trabalho por finding

```
┌──────────────┐   ┌──────────────┐   ┌──────────────┐   ┌──────────────┐
│  findings/   │ → │ GitHub Issue │ → │  Branch + PR │ → │ status=fixed │
│  L02-01.md   │   │  (wave ≤ 1)  │   │  Closes #N   │   │ + teste regr.│
└──────────────┘   └──────────────┘   └──────────────┘   └──────────────┘
       ▲                                                        │
       └────── CI rebuilds FINDINGS.md + SCORECARD.md ◄─────────┘
```

1. **Finding nasce** em `findings/LXX-YY-slug.md` com `status: fix-pending`.
2. **Issue** (opcional em findings médios): rodar `npx tsx tools/audit/generate-issues.ts --wave 0`.
3. **Correção**: dev cria branch `audit/LXX-YY-slug`, abre PR com título `[LXX-YY] fix: <descrição>`, referencia `Fixes audit/LXX-YY` no body.
4. **Atualização**: PR inclui mudança em `findings/LXX-YY-slug.md` → `status: fixed` + `linked_prs: [#NNN]` + referência ao teste de regressão.
5. **CI valida**: `tools/audit/verify.ts` confirma que `status: fixed` tem teste associado que passa.
6. **Scorecard atualiza** automaticamente após merge em master.

---

## Estados possíveis de um finding

| `status`        | Significado                                                          |
|-----------------|----------------------------------------------------------------------|
| `fix-pending`   | Não iniciado                                                          |
| `in-progress`   | PR aberto, em desenvolvimento/review                                  |
| `fixed`         | PR merged, teste de regressão presente e verde                        |
| `wont-fix`      | Decisão consciente de não corrigir (exige justificativa em `note`)   |
| `deferred`      | Adiado para onda posterior (exige `deferred_to_wave`)                |
| `duplicate`     | Duplicado de outro finding (exige `duplicate_of`)                     |
| `not-reproducible` | Não reproduzível na auditoria atual (exige `note`)                |

---

## Severidades

| Rótulo       | Critério | SLA para correção |
|--------------|----------|--------------------|
| 🔴 `critical` | Perda financeira direta, exposição de dados pessoais sensíveis, risco legal/regulatório grave, compromisso de autenticação/autorização | Onda 0 ou 1 |
| 🟠 `high`     | Degradação severa de UX/confiabilidade, vulnerabilidade exploitável mas mitigada parcialmente, violação LGPD baixa gravidade | Onda 1 ou 2 |
| 🟡 `medium`   | Débito técnico, falta de defesa em profundidade, inconsistência arquitetural | Onda 2 ou 3 |
| 🟢 `safe`     | Item auditado e considerado correto — mantido no registry para rastreabilidade | — |
| ⚪ `na`        | Fora do escopo ou não auditado | — |

---

## Como adicionar um novo finding

1. Copiar `findings/_template.md` para `findings/LXX-YY-slug.md` (usar próximo ID disponível na lente).
2. Preencher frontmatter YAML e corpo.
3. Commitar isoladamente ou junto com PR de correção.
4. `tools/audit/build-registry.ts` regenera `registry.json` + `FINDINGS.md`.

---

## Histórico

- **2026-04-17** — Auditoria inicial de 23 lentes × 310 findings (pt-BR).
- **2026-04-17** — Estrutura `docs/audit/` criada.
