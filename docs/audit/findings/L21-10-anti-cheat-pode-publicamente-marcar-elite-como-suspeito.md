---
id: L21-10
audit_ref: "21.10"
lens: 21
title: "Anti-cheat pode publicamente marcar elite como suspeito"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
tags: ["personas", "athlete-pro"]
files:
  - supabase/migrations/20260421550000_l21_10_athlete_review_quarantine.sql
  - tools/audit/check-athlete-review-quarantine.ts
correction_type: process
test_required: true
tests: []
linked_issues: []
linked_prs:
  - local:6a9eb88
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
fixed_at: 2026-04-21
closed_at: 2026-04-21
note: |
  Elite athlete reputation protection now layered across the
  product.

  - `sessions.review_status` column + CHECK-bound state machine
    (none → pending_review → in_review →
    approved|rejected|none) provides a formal lifecycle for
    flagged sessions.
  - `fn_session_visibility_status(uuid)` (STABLE SECURITY
    DEFINER) returns a viewer-scoped payload: non-owners see
    only neutral labels (`verified`, `pending_review`,
    `verification_pending`) with NO integrity_flags exposure;
    session owners and platform_admin receive integrity_flags +
    review_status. This is the contract feeds/leaderboards must
    call instead of reading `sessions.is_verified /
    integrity_flags` directly.
  - `athlete_review_requests` queue stores manual-review
    submissions: athlete_id, session_id, status (pending /
    in_review / approved / rejected / auto_dismissed),
    athlete_note, evidence_urls (https-only, max 5),
    reviewer_id, resolution_note. UNIQUE partial index on
    status IN (pending, in_review) prevents parallel open
    requests per session. RLS: athlete owns read+insert of
    their own rows; platform_admin reads + updates
    everything.
  - `fn_request_session_review(session_id, note,
    evidence_urls)` gates on session ownership, reviewable
    state (`review_status IN (none, rejected)`), and
    NOTHING_TO_REVIEW (requires integrity_flags IS NOT NULL OR
    is_verified = false). Returns the full request row; flips
    `sessions.review_status = pending_review` atomically.
  - BEFORE UPDATE OF review_status trigger
    `fn_sessions_review_status_guard` enforces legal state
    transitions; illegal transitions raise INVALID_TRANSITION.

  CI guard: `npm run audit:athlete-review-quarantine` — 32
  invariants on column, state-machine CHECKs, visibility
  helper, queue table shape, RPC gating, trigger behaviour, and
  self-test block.
---
# [L21-10] Anti-cheat pode publicamente marcar elite como suspeito
> **Lente:** 21 — Atleta Pro · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— Quando `is_verified = false` por flag, outros atletas podem ver "session not verified" em feed/leaderboard. Atleta profissional com sua integridade em jogo fica exposto a um falso positivo.
## Correção proposta

— Flags só visíveis a `platform_admin` + atleta. Feed mostra "verificação pendente" neutro (sem razão pública). Elite pode solicitar revisão manual antes de virar público.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[21.10]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 21 — Atleta Pro, item 21.10).