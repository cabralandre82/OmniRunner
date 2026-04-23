# SCORECARD — Progresso da Auditoria

> **Gerado automaticamente** por `tools/audit/build-registry.ts`. **Não editar à mão.**
> Atualizado em 2026-04-23 17:32:45 UTC.

## Visão Geral

| Métrica | Valor | Progresso |
|---|---|---|
| **Total de findings** | 348 | — |
| **✅ Corrigidos** | 148 / 348 (42.5%) | `█████████░░░░░░░░░░░` |
| **🚧 Em progresso** | 1 | — |
| **⏳ Pendentes** | 192 | — |
| **⏭️ Adiados** | 0 | — |
| **🚫 Won't fix** | 7 | — |

## Por Severidade

| Severidade | Total | Corrigidos | % | Progresso |
|---|---|---|---|---|
| 🔴 Critical | 69 | 47 | 68.1% | `██████████████░░░░░░` |
| 🟠 High | 123 | 81 | 65.9% | `█████████████░░░░░░░` |
| 🟡 Medium | 127 | 3 | 2.4% | `░░░░░░░░░░░░░░░░░░░░` |

## Por Onda

| Onda | Total | Corrigidos | % | Progresso |
|---|---|---|---|---|
| Onda 0 | 15 | 15 | 100.0% | `████████████████████` |
| Onda 1 | 179 | 115 | 64.2% | `█████████████░░░░░░░` |
| Onda 2 | 125 | 1 | 0.8% | `░░░░░░░░░░░░░░░░░░░░` |
| Onda 3 | 29 | 17 | 58.6% | `████████████░░░░░░░░` |

## Por Lente

| # | Lente | Total | Corrig. | Críticos | Crít. corrig. | Progresso |
|---|---|---|---|---|---|---|
| 1 | CISO | 50 | 26 | 4 | 4 | `█████░░░░░` |
| 2 | CTO | 15 | 9 | 3 | 3 | `██████░░░░` |
| 3 | CFO | 20 | 11 | 3 | 3 | `██████░░░░` |
| 4 | CLO | 15 | 5 | 4 | 4 | `███░░░░░░░` |
| 5 | CPO | 20 | 6 | 3 | 3 | `███░░░░░░░` |
| 6 | COO | 13 | 8 | 2 | 2 | `██████░░░░` |
| 7 | CXO | 13 | 2 | 2 | 0 | `██░░░░░░░░` |
| 8 | CDO | 12 | 6 | 2 | 2 | `█████░░░░░` |
| 9 | CRO | 12 | 2 | 5 | 1 | `██░░░░░░░░` |
| 10 | CSO | 14 | 4 | 3 | 0 | `███░░░░░░░` |
| 11 | Supply Chain | 14 | 9 | 3 | 3 | `██████░░░░` |
| 12 | Cron/Scheduler | 12 | 9 | 3 | 3 | `████████░░` |
| 13 | Middleware | 9 | 7 | 3 | 3 | `████████░░` |
| 14 | Contracts | 9 | 6 | 3 | 3 | `███████░░░` |
| 15 | CMO | 8 | 1 | 0 | 0 | `█░░░░░░░░░` |
| 16 | CAO | 10 | 0 | 1 | 0 | `░░░░░░░░░░` |
| 17 | VP Eng | 9 | 5 | 2 | 1 | `██████░░░░` |
| 18 | Principal Eng | 10 | 6 | 4 | 3 | `██████░░░░` |
| 19 | DBA | 10 | 7 | 4 | 4 | `███████░░░` |
| 20 | SRE | 13 | 8 | 3 | 3 | `██████░░░░` |
| 21 | Atleta Pro | 20 | 2 | 5 | 2 | `█░░░░░░░░░` |
| 22 | Atleta Amador | 20 | 3 | 3 | 0 | `██░░░░░░░░` |
| 23 | Treinador | 20 | 6 | 4 | 0 | `███░░░░░░░` |

---

## Meta da Onda 0 (2026-04-24)

- ✅ 100% dos **critical** da Onda 0 corrigidos
- ✅ CI com `tools/audit/verify.ts` bloqueando PRs que marcam `status: fixed` sem teste de regressão
- ✅ Runbooks gerados para findings com `runbook` populado
