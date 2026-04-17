---
id: LXX-YY                  # obrigatório — ex: L02-01 (zero-padded, LXX = lente, YY = seq)
audit_ref: "X.Y"            # obrigatório — ex: "2.1" (string, entre aspas)
lens: X                     # obrigatório — 1..23
title: "Título curto e acionável"  # obrigatório
severity: critical          # critical | high | medium | safe | na
status: fix-pending         # fix-pending | in-progress | fixed | wont-fix | deferred | duplicate | not-reproducible
wave: 0                     # 0 | 1 | 2 | 3
discovered_at: 2026-04-17   # ISO date

# ---- Opcionais (recomendados) ----
tags: []                    # ex: [lgpd, finance, anti-cheat, mobile, portal]
files:                      # paths afetados
  - supabase/functions/foo/index.ts
  - omni_runner/lib/bar.dart
correction_type: code       # code | config | migration | docs | process | test
test_required: true
tests: []                   # paths de testes de regressão (obrigatório se test_required=true e status=fixed)
linked_issues: []           # ex: [123, 456]
linked_prs: []              # ex: [789]
owner: unassigned           # GitHub handle ou 'unassigned'
runbook: null               # path para runbook derivado, se existir
effort_points: 3            # estimativa 1/3/5/8/13
blocked_by: []              # ids de outros findings que bloqueiam este
# ---- Estados terminais ----
duplicate_of: null          # id do finding mestre se status=duplicate
deferred_to_wave: null      # wave alvo se status=deferred
note: null                  # justificativa livre (obrigatório para wont-fix, deferred, not-reproducible)
---

# [LXX-YY] Título do achado

> **Lente:** X — Nome da Lente · **Severidade:** 🔴/🟠/🟡 · **Onda:** 0/1/2/3 · **Status:** fix-pending

## Contexto

Descreva o componente, fluxo ou subsistema envolvido. 2–4 linhas.

## Evidência

Cite arquivo e linhas específicas. Use code references para trechos relevantes:

```L1:L5:path/to/file.ts
// código evidenciando o problema
```

## Impacto

Quem é afetado e como? Seja concreto — idealmente quantificável ou cite persona (ex: "atletas com FCmax > 220 BPM" — Lente 21).

## Correção proposta

Passos concretos. Idealmente:

1. Alteração em `arquivo:linha`.
2. Migration `supabase/migrations/YYYYMMDDHHMMSS_*.sql` contendo `ALTER TABLE ...`.
3. Teste de regressão em `tests/path/foo.spec.ts`.

## Teste de regressão

Descrição do teste que valida a correção. Se `test_required: true`, este bloco **não pode estar vazio** quando `status: fixed`.

## Cross-refs

- Outras lentes que tocam o mesmo componente: `L01-03`, `L09-05`, ...
- Runbook relacionado: `runbooks/XXX.md`

## Histórico

- `2026-04-17` — Descoberto (auditoria inicial).
- `YYYY-MM-DD` — PR #NNN mergeado, status → fixed.
