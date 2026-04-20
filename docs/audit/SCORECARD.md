# SCORECARD — Progresso da Auditoria

> **Gerado automaticamente** por `tools/audit/build-registry.ts`. **Não editar à mão.**
> Atualizado em 2026-04-20 00:35:50 UTC.

## Visão Geral

| Métrica | Valor | Progresso |
|---|---|---|
| **Total de findings** | 348 | — |
| **✅ Corrigidos** | 93 / 348 (26.7%) | `█████░░░░░░░░░░░░░░░` |
| **🚧 Em progresso** | 1 | — |
| **⏳ Pendentes** | 254 | — |
| **⏭️ Adiados** | 0 | — |
| **🚫 Won't fix** | 0 | — |

## Por Severidade

| Severidade | Total | Corrigidos | % | Progresso |
|---|---|---|---|---|
| 🔴 Critical | 69 | 39 | 56.5% | `███████████░░░░░░░░░` |
| 🟠 High | 123 | 35 | 28.5% | `██████░░░░░░░░░░░░░░` |
| 🟡 Medium | 127 | 2 | 1.6% | `░░░░░░░░░░░░░░░░░░░░` |

## Por Onda

| Onda | Total | Corrigidos | % | Progresso |
|---|---|---|---|---|
| Onda 0 | 15 | 15 | 100.0% | `████████████████████` |
| Onda 1 | 179 | 61 | 34.1% | `███████░░░░░░░░░░░░░` |
| Onda 2 | 125 | 0 | 0.0% | `░░░░░░░░░░░░░░░░░░░░` |
| Onda 3 | 29 | 17 | 58.6% | `████████████░░░░░░░░` |

## Por Lente

| # | Lente | Total | Corrig. | Críticos | Crít. corrig. | Progresso |
|---|---|---|---|---|---|---|
| 1 | CISO | 50 | 25 | 4 | 4 | `█████░░░░░` |
| 2 | CTO | 15 | 8 | 3 | 3 | `█████░░░░░` |
| 3 | CFO | 20 | 7 | 3 | 1 | `████░░░░░░` |
| 4 | CLO | 15 | 4 | 4 | 4 | `███░░░░░░░` |
| 5 | CPO | 20 | 3 | 3 | 2 | `██░░░░░░░░` |
| 6 | COO | 13 | 4 | 2 | 1 | `███░░░░░░░` |
| 7 | CXO | 13 | 0 | 2 | 0 | `░░░░░░░░░░` |
| 8 | CDO | 12 | 0 | 2 | 0 | `░░░░░░░░░░` |
| 9 | CRO | 12 | 1 | 5 | 1 | `█░░░░░░░░░` |
| 10 | CSO | 14 | 1 | 3 | 0 | `█░░░░░░░░░` |
| 11 | Supply Chain | 14 | 5 | 3 | 3 | `████░░░░░░` |
| 12 | Cron/Scheduler | 12 | 3 | 3 | 3 | `███░░░░░░░` |
| 13 | Middleware | 9 | 7 | 3 | 3 | `████████░░` |
| 14 | Contracts | 9 | 6 | 3 | 3 | `███████░░░` |
| 15 | CMO | 8 | 0 | 0 | 0 | `░░░░░░░░░░` |
| 16 | CAO | 10 | 0 | 1 | 0 | `░░░░░░░░░░` |
| 17 | VP Eng | 9 | 2 | 2 | 1 | `██░░░░░░░░` |
| 18 | Principal Eng | 10 | 6 | 4 | 3 | `██████░░░░` |
| 19 | DBA | 10 | 4 | 4 | 4 | `████░░░░░░` |
| 20 | SRE | 13 | 7 | 3 | 3 | `█████░░░░░` |
| 21 | Atleta Pro | 20 | 0 | 5 | 0 | `░░░░░░░░░░` |
| 22 | Atleta Amador | 20 | 0 | 3 | 0 | `░░░░░░░░░░` |
| 23 | Treinador | 20 | 0 | 4 | 0 | `░░░░░░░░░░` |

---

## Meta da Onda 0 (2026-04-24)

- ✅ 100% dos **critical** da Onda 0 corrigidos
- ✅ CI com `tools/audit/verify.ts` bloqueando PRs que marcam `status: fixed` sem teste de regressão
- ✅ Runbooks gerados para findings com `runbook` populado
