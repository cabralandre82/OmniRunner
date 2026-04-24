# SCORECARD — Progresso da Auditoria

> **Gerado automaticamente** por `tools/audit/build-registry.ts`. **Não editar à mão.**
> Atualizado em 2026-04-24 00:20:32 UTC.

## Visão Geral

| Métrica | Valor | Progresso |
|---|---|---|
| **Total de findings** | 348 | — |
| **✅ Corrigidos** | 233 / 348 (67.0%) | `█████████████░░░░░░░` |
| **🚧 Em progresso** | 1 | — |
| **⏳ Pendentes** | 106 | — |
| **⏭️ Adiados** | 0 | — |
| **🚫 Won't fix** | 7 | — |

## Por Severidade

| Severidade | Total | Corrigidos | % | Progresso |
|---|---|---|---|---|
| 🔴 Critical | 69 | 64 | 92.8% | `███████████████████░` |
| 🟠 High | 123 | 116 | 94.3% | `███████████████████░` |
| 🟡 Medium | 127 | 36 | 28.3% | `██████░░░░░░░░░░░░░░` |

## Por Onda

| Onda | Total | Corrigidos | % | Progresso |
|---|---|---|---|---|
| Onda 0 | 15 | 15 | 100.0% | `████████████████████` |
| Onda 1 | 179 | 167 | 93.3% | `███████████████████░` |
| Onda 2 | 125 | 34 | 27.2% | `█████░░░░░░░░░░░░░░░` |
| Onda 3 | 29 | 17 | 58.6% | `████████████░░░░░░░░` |

## Por Lente

| # | Lente | Total | Corrig. | Críticos | Crít. corrig. | Progresso |
|---|---|---|---|---|---|---|
| 1 | CISO | 50 | 34 | 4 | 4 | `███████░░░` |
| 2 | CTO | 15 | 11 | 3 | 3 | `███████░░░` |
| 3 | CFO | 20 | 14 | 3 | 3 | `███████░░░` |
| 4 | CLO | 15 | 11 | 4 | 4 | `███████░░░` |
| 5 | CPO | 20 | 14 | 3 | 3 | `███████░░░` |
| 6 | COO | 13 | 10 | 2 | 2 | `████████░░` |
| 7 | CXO | 13 | 6 | 2 | 2 | `█████░░░░░` |
| 8 | CDO | 12 | 8 | 2 | 2 | `███████░░░` |
| 9 | CRO | 12 | 9 | 5 | 3 | `████████░░` |
| 10 | CSO | 14 | 9 | 3 | 3 | `██████░░░░` |
| 11 | Supply Chain | 14 | 11 | 3 | 3 | `████████░░` |
| 12 | Cron/Scheduler | 12 | 10 | 3 | 3 | `████████░░` |
| 13 | Middleware | 9 | 9 | 3 | 3 | `██████████` |
| 14 | Contracts | 9 | 6 | 3 | 3 | `███████░░░` |
| 15 | CMO | 8 | 4 | 0 | 0 | `█████░░░░░` |
| 16 | CAO | 10 | 5 | 1 | 0 | `█████░░░░░` |
| 17 | VP Eng | 9 | 7 | 2 | 2 | `████████░░` |
| 18 | Principal Eng | 10 | 9 | 4 | 4 | `█████████░` |
| 19 | DBA | 10 | 10 | 4 | 4 | `██████████` |
| 20 | SRE | 13 | 10 | 3 | 3 | `████████░░` |
| 21 | Atleta Pro | 20 | 6 | 5 | 4 | `███░░░░░░░` |
| 22 | Atleta Amador | 20 | 6 | 3 | 2 | `███░░░░░░░` |
| 23 | Treinador | 20 | 14 | 4 | 4 | `███████░░░` |

---

## Meta da Onda 0 (2026-04-24)

- ✅ 100% dos **critical** da Onda 0 corrigidos
- ✅ CI com `tools/audit/verify.ts` bloqueando PRs que marcam `status: fixed` sem teste de regressão
- ✅ Runbooks gerados para findings com `runbook` populado
