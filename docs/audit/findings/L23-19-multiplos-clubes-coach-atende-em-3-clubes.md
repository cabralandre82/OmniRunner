---
id: L23-19
audit_ref: "23.19"
lens: 23
title: "Múltiplos clubes (coach atende em 3 clubes)"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-24
closed_at: 2026-04-24
tags: ["personas", "coach", "portal", "mobile"]
files:
  - docs/product/COACH_BASELINE.md

correction_type: docs
test_required: false
tests: []
linked_issues: []
linked_prs:
  - "fce133b"

owner: product+backend+portal+mobile
runbook: docs/product/COACH_BASELINE.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Coberto em `docs/product/COACH_BASELINE.md` § 5
  (Multi-club aggregate dashboard). Sem novas tabelas —
  apenas RPC `coach_today_aggregate()` SECURITY DEFINER
  com `auth.uid()` gate + filtro por
  `coaching_members.role in (admin_master, coach)`
  (padrão canônico de L18-03). Agrega 6 "kinds":
  feedback, injury, approval, session_soon, no_show,
  lead. Cada linha deep-linka para screen existente
  group-scoped. Portal `/platform/coach/today` + card
  em `staff_dashboard_screen.dart`. Cache cliente 60s,
  cap 100 rows/kind. Target scale: 3-5 clubes
  (coaches com 10+ são rounding error). Ship Wave 4
  fase W4-O (fastest — zero tabelas novas).
---
# [L23-19] Múltiplos clubes (coach atende em 3 clubes)
> **Lente:** 23 — Treinador · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— `coaching_members` 1:N, mas UI esconde bem? Coach com 3 clubes troca grupo via `select-group`. Cada troca exige recarga completa.
## Correção proposta

— Dashboard multi-clube agregado "Meu dia em todos os clubes".

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[23.19]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 23 — Treinador, item 23.19).
- `2026-04-24` — Consolidado em `docs/product/COACH_BASELINE.md` § 5 (batch K12); implementação Wave 4 fase W4-O.
