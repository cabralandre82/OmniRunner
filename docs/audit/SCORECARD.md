# SCORECARD — Progresso da Auditoria

> **Gerado automaticamente** por `tools/audit/build-registry.ts`. **Não editar à mão.**
> Atualizado em 2026-04-18 03:20:38 UTC.

## Visão Geral

| Métrica | Valor | Progresso |
|---|---|---|
| **Total de findings** | 348 | — |
| **✅ Corrigidos** | 17 / 348 (4.9%) | `█░░░░░░░░░░░░░░░░░░░` |
| **🚧 Em progresso** | 8 | — |
| **⏳ Pendentes** | 323 | — |
| **⏭️ Adiados** | 0 | — |
| **🚫 Won't fix** | 0 | — |

## Por Severidade

| Severidade | Total | Corrigidos | % | Progresso |
|---|---|---|---|---|
| 🔴 Critical | 69 | 0 | 0.0% | `░░░░░░░░░░░░░░░░░░░░` |
| 🟠 High | 123 | 0 | 0.0% | `░░░░░░░░░░░░░░░░░░░░` |
| 🟡 Medium | 127 | 0 | 0.0% | `░░░░░░░░░░░░░░░░░░░░` |

## Por Onda

| Onda | Total | Corrigidos | % | Progresso |
|---|---|---|---|---|
| Onda 0 | 15 | 0 | 0.0% | `░░░░░░░░░░░░░░░░░░░░` |
| Onda 1 | 177 | 0 | 0.0% | `░░░░░░░░░░░░░░░░░░░░` |
| Onda 2 | 127 | 0 | 0.0% | `░░░░░░░░░░░░░░░░░░░░` |
| Onda 3 | 29 | 17 | 58.6% | `████████████░░░░░░░░` |

## Por Lente

| # | Lente | Total | Corrig. | Críticos | Crít. corrig. | Progresso |
|---|---|---|---|---|---|---|
| 1 | CISO | 50 | 10 | 4 | 0 | `██░░░░░░░░` |
| 2 | CTO | 15 | 2 | 3 | 0 | `█░░░░░░░░░` |
| 3 | CFO | 20 | 4 | 3 | 0 | `██░░░░░░░░` |
| 4 | CLO | 15 | 0 | 4 | 0 | `░░░░░░░░░░` |
| 5 | CPO | 20 | 1 | 3 | 0 | `█░░░░░░░░░` |
| 6 | COO | 13 | 0 | 2 | 0 | `░░░░░░░░░░` |
| 7 | CXO | 13 | 0 | 2 | 0 | `░░░░░░░░░░` |
| 8 | CDO | 12 | 0 | 2 | 0 | `░░░░░░░░░░` |
| 9 | CRO | 12 | 0 | 5 | 0 | `░░░░░░░░░░` |
| 10 | CSO | 14 | 0 | 3 | 0 | `░░░░░░░░░░` |
| 11 | Supply Chain | 14 | 0 | 3 | 0 | `░░░░░░░░░░` |
| 12 | Cron/Scheduler | 12 | 0 | 3 | 0 | `░░░░░░░░░░` |
| 13 | Middleware | 9 | 0 | 3 | 0 | `░░░░░░░░░░` |
| 14 | Contracts | 9 | 0 | 3 | 0 | `░░░░░░░░░░` |
| 15 | CMO | 8 | 0 | 0 | 0 | `░░░░░░░░░░` |
| 16 | CAO | 10 | 0 | 1 | 0 | `░░░░░░░░░░` |
| 17 | VP Eng | 9 | 0 | 2 | 0 | `░░░░░░░░░░` |
| 18 | Principal Eng | 10 | 0 | 4 | 0 | `░░░░░░░░░░` |
| 19 | DBA | 10 | 0 | 4 | 0 | `░░░░░░░░░░` |
| 20 | SRE | 13 | 0 | 3 | 0 | `░░░░░░░░░░` |
| 21 | Atleta Pro | 20 | 0 | 5 | 0 | `░░░░░░░░░░` |
| 22 | Atleta Amador | 20 | 0 | 3 | 0 | `░░░░░░░░░░` |
| 23 | Treinador | 20 | 0 | 4 | 0 | `░░░░░░░░░░` |

---

## Meta da Onda 0 (2026-04-24)

- ✅ 100% dos **critical** da Onda 0 corrigidos
- ✅ CI com `tools/audit/verify.ts` bloqueando PRs que marcam `status: fixed` sem teste de regressão
- ✅ Runbooks gerados para findings com `runbook` populado
