---
id: L04-06
audit_ref: "4.6"
lens: 4
title: "Campo instagram_handle, tiktok_handle em profiles sem política de uso"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
tags: ["rls", "rate-limit", "mobile"]
files:
  - supabase/migrations/20260421570000_l04_06_social_handles_policy.sql
  - tools/audit/check-social-handles-policy.ts
correction_type: process
test_required: true
tests: []
linked_issues: []
linked_prs:
  - local:7ea0ef8
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
fixed_at: 2026-04-21
closed_at: 2026-04-21
note: |
  Social-handle policy now enforced at three layers.
  - CHECK-bound format validation via
    `fn_validate_social_handle(text)` applied to both
    `profiles.instagram_handle` and `profiles.tiktok_handle`
    (1-30 chars of `[A-Za-z0-9._]`, rejects http / bit.ly /
    slashes).
  - `profiles.profile_public jsonb` with privacy-first
    defaults (`show_instagram:false`, `show_tiktok:false`,
    `show_pace:false`, `show_location:false`) and a shape
    CHECK via `fn_validate_profile_public`. This decouples
    social visibility from `display_name`, the concrete ask
    in the finding.
  - `profiles.social_handles_updated_at` + BEFORE UPDATE
    trigger `fn_profiles_social_handles_rate_limit` enforcing
    a configurable min-interval
    (`app.social_handle_min_interval_seconds`, default 24h,
    service_role waived), raising P0001 on violation, and
    writing `profile.social_handle_changed` rows into
    `portal_audit_log` for anti-impersonation investigations
    (fail-open audit).
  - `fn_public_profile_view(uuid)` viewer-scoped accessor —
    handles returned only to self / platform_admin / when the
    owner toggled the corresponding `show_*` flag; also
    surfaces `show_pace` / `show_location` so feeds honour
    them without re-reading profiles.
  - Self-test asserts validator accept/reject (9 cases) +
    profile_public shape accept/reject.
  - CI guard `npm run audit:social-handles-policy` enforces
    37 invariants.
---
# [L04-06] Campo instagram_handle, tiktok_handle em profiles sem política de uso
> **Lente:** 4 — CLO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— `profiles.instagram_handle` é lido via RLS `select_profile_public` (se existir). Não há:
- Toggle "esconder do público" independente do display_name.
- Validação (evitar links maliciosos, "@bitly/x").
- Rate limit de changes (evita impersonation: trocar o handle a cada 10 s).
## Risco / Impacto

— Stalkers usam Omni Runner como diretório de atletas por rede social.

## Correção proposta

— Adicionar `profile_public jsonb` com flags granulares (`show_instagram`, `show_tiktok`, `show_pace`, `show_location`) e aplicar na RLS de views públicas.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[4.6]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 4 — CLO, item 4.6).