# SCORECARD — Progresso da Auditoria

> **Gerado automaticamente** por `tools/audit/build-registry.ts`. **Não editar à mão.**
> Atualizado em 2026-04-24 01:47:03 UTC.

## Visão Geral

| Métrica | Valor | Progresso |
|---|---|---|
| **Total de findings** | 348 | — |
| **✅ Corrigidos** | 296 / 348 (85.1%) | `█████████████████░░░` |
| **🚧 Em progresso** | 0 | — |
| **⏳ Pendentes** | 40 | — |
| **⏭️ Adiados** | 0 | — |
| **🚫 Won't fix** | 8 | — |

## Por Severidade

| Severidade | Total | Corrigidos | % | Progresso |
|---|---|---|---|---|
| 🔴 Critical | 69 | 64 | 92.8% | `███████████████████░` |
| 🟠 High | 123 | 116 | 94.3% | `███████████████████░` |
| 🟡 Medium | 127 | 99 | 78.0% | `████████████████░░░░` |

## Por Onda

| Onda | Total | Corrigidos | % | Progresso |
|---|---|---|---|---|
| Onda 0 | 15 | 15 | 100.0% | `████████████████████` |
| Onda 1 | 179 | 167 | 93.3% | `███████████████████░` |
| Onda 2 | 125 | 97 | 77.6% | `████████████████░░░░` |
| Onda 3 | 29 | 17 | 58.6% | `████████████░░░░░░░░` |

## Por Lente

| # | Lente | Total | Corrig. | Críticos | Crít. corrig. | Progresso |
|---|---|---|---|---|---|---|
| 1 | CISO | 50 | 43 | 4 | 4 | `█████████░` |
| 2 | CTO | 15 | 13 | 3 | 3 | `█████████░` |
| 3 | CFO | 20 | 14 | 3 | 3 | `███████░░░` |
| 4 | CLO | 15 | 15 | 4 | 4 | `██████████` |
| 5 | CPO | 20 | 19 | 3 | 3 | `██████████` |
| 6 | COO | 13 | 13 | 2 | 2 | `██████████` |
| 7 | CXO | 13 | 13 | 2 | 2 | `██████████` |
| 8 | CDO | 12 | 12 | 2 | 2 | `██████████` |
| 9 | CRO | 12 | 10 | 5 | 3 | `████████░░` |
| 10 | CSO | 14 | 14 | 3 | 3 | `██████████` |
| 11 | Supply Chain | 14 | 14 | 3 | 3 | `██████████` |
| 12 | Cron/Scheduler | 12 | 12 | 3 | 3 | `██████████` |
| 13 | Middleware | 9 | 9 | 3 | 3 | `██████████` |
| 14 | Contracts | 9 | 8 | 3 | 3 | `█████████░` |
| 15 | CMO | 8 | 8 | 0 | 0 | `██████████` |
| 16 | CAO | 10 | 9 | 1 | 0 | `█████████░` |
| 17 | VP Eng | 9 | 9 | 2 | 2 | `██████████` |
| 18 | Principal Eng | 10 | 10 | 4 | 4 | `██████████` |
| 19 | DBA | 10 | 10 | 4 | 4 | `██████████` |
| 20 | SRE | 13 | 13 | 3 | 3 | `██████████` |
| 21 | Atleta Pro | 20 | 8 | 5 | 4 | `████░░░░░░` |
| 22 | Atleta Amador | 20 | 6 | 3 | 2 | `███░░░░░░░` |
| 23 | Treinador | 20 | 14 | 4 | 4 | `███████░░░` |

---

## Meta da Onda 0 (2026-04-24)

- ✅ 100% dos **critical** da Onda 0 corrigidos
- ✅ CI com `tools/audit/verify.ts` bloqueando PRs que marcam `status: fixed` sem teste de regressão
- ✅ Runbooks gerados para findings com `runbook` populado
