# SCORECARD — Progresso da Auditoria

> **Gerado automaticamente** por `tools/audit/build-registry.ts`. **Não editar à mão.**
> Atualizado em 2026-04-23 23:11:53 UTC.

## Visão Geral

| Métrica | Valor | Progresso |
|---|---|---|
| **Total de findings** | 348 | — |
| **✅ Corrigidos** | 194 / 348 (55.7%) | `███████████░░░░░░░░░` |
| **🚧 Em progresso** | 1 | — |
| **⏳ Pendentes** | 145 | — |
| **⏭️ Adiados** | 0 | — |
| **🚫 Won't fix** | 7 | — |

## Por Severidade

| Severidade | Total | Corrigidos | % | Progresso |
|---|---|---|---|---|
| 🔴 Critical | 69 | 60 | 87.0% | `█████████████████░░░` |
| 🟠 High | 123 | 114 | 92.7% | `███████████████████░` |
| 🟡 Medium | 127 | 3 | 2.4% | `░░░░░░░░░░░░░░░░░░░░` |

## Por Onda

| Onda | Total | Corrigidos | % | Progresso |
|---|---|---|---|---|
| Onda 0 | 15 | 15 | 100.0% | `████████████████████` |
| Onda 1 | 179 | 161 | 89.9% | `██████████████████░░` |
| Onda 2 | 125 | 1 | 0.8% | `░░░░░░░░░░░░░░░░░░░░` |
| Onda 3 | 29 | 17 | 58.6% | `████████████░░░░░░░░` |

## Por Lente

| # | Lente | Total | Corrig. | Críticos | Crít. corrig. | Progresso |
|---|---|---|---|---|---|---|
| 1 | CISO | 50 | 26 | 4 | 4 | `█████░░░░░` |
| 2 | CTO | 15 | 9 | 3 | 3 | `██████░░░░` |
| 3 | CFO | 20 | 11 | 3 | 3 | `██████░░░░` |
| 4 | CLO | 15 | 10 | 4 | 4 | `███████░░░` |
| 5 | CPO | 20 | 8 | 3 | 3 | `████░░░░░░` |
| 6 | COO | 13 | 8 | 2 | 2 | `██████░░░░` |
| 7 | CXO | 13 | 6 | 2 | 2 | `█████░░░░░` |
| 8 | CDO | 12 | 8 | 2 | 2 | `███████░░░` |
| 9 | CRO | 12 | 7 | 5 | 3 | `██████░░░░` |
| 10 | CSO | 14 | 9 | 3 | 3 | `██████░░░░` |
| 11 | Supply Chain | 14 | 9 | 3 | 3 | `██████░░░░` |
| 12 | Cron/Scheduler | 12 | 9 | 3 | 3 | `████████░░` |
| 13 | Middleware | 9 | 7 | 3 | 3 | `████████░░` |
| 14 | Contracts | 9 | 6 | 3 | 3 | `███████░░░` |
| 15 | CMO | 8 | 4 | 0 | 0 | `█████░░░░░` |
| 16 | CAO | 10 | 5 | 1 | 0 | `█████░░░░░` |
| 17 | VP Eng | 9 | 6 | 2 | 2 | `███████░░░` |
| 18 | Principal Eng | 10 | 8 | 4 | 4 | `████████░░` |
| 19 | DBA | 10 | 8 | 4 | 4 | `████████░░` |
| 20 | SRE | 13 | 8 | 3 | 3 | `██████░░░░` |
| 21 | Atleta Pro | 20 | 4 | 5 | 2 | `██░░░░░░░░` |
| 22 | Atleta Amador | 20 | 5 | 3 | 1 | `███░░░░░░░` |
| 23 | Treinador | 20 | 13 | 4 | 3 | `███████░░░` |

---

## Meta da Onda 0 (2026-04-24)

- ✅ 100% dos **critical** da Onda 0 corrigidos
- ✅ CI com `tools/audit/verify.ts` bloqueando PRs que marcam `status: fixed` sem teste de regressão
- ✅ Runbooks gerados para findings com `runbook` populado
