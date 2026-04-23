---
id: L10-09
audit_ref: "10.9"
lens: 10
title: "Falta defesa anti credential stuffing no Mobile/Portal"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
tags: ["rate-limit", "edge-function", "testing"]
files:
  - supabase/migrations/20260421340000_l10_09_anti_credential_stuffing.sql
  - tools/audit/check-anti-credential-stuffing.ts
  - tools/test_l10_09_anti_credential_stuffing.ts
  - package.json
  - docs/runbooks/ANTI_CREDENTIAL_STUFFING_RUNBOOK.md
correction_type: code
test_required: true
tests:
  - tools/test_l10_09_anti_credential_stuffing.ts
linked_issues: []
linked_prs:
  - b2fb402
owner: platform-security
runbook: docs/runbooks/ANTI_CREDENTIAL_STUFFING_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: "DB foundation + CI done; login-pre-check Edge Function wiring is a non-blocking follow-up."
---
# [L10-09] Falta defesa anti credential stuffing no Mobile/Portal
> **Lente:** 10 — CSO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** ✅ fixed
**Camada:** DB + Edge Function (wiring TODO)
**Personas impactadas:** mobile (login), portal (login)
## Achado
— Supabase Auth faz rate-limit por IP mas não por email. Ataque distribuído testa mil emails × senha comum.
## Correção proposta

— Supabase Edge Function pré-login que mantém contador por `email_hash` e aplica `CAPTCHA` (hCaptcha) após 3 falhas.

## Correção aplicada (2026-04-21)
Migration `20260421340000_l10_09_anti_credential_stuffing.sql` (~620 LOC):
- `auth_login_attempts` (email_hash SHA-256 CHECK, RLS forced,
  service_role only) + `auth_login_throttle_config` singleton com 4
  CHECKs em thresholds/windows.
- `fn_login_throttle_record_failure/record_success/probe/cleanup` +
  `fn_login_throttle_assert_shape` — SECURITY DEFINER, service_role only,
  sanity-check de hash SHA-256 hex 64 chars.
- Default policy: CAPTCHA em 3 falhas, lock em 10 falhas, rolling 15 min,
  lock 15 min — tunável sem ship de código.
- CI `npm run audit:anti-credential-stuffing` + 21 integration tests +
  runbook [`ANTI_CREDENTIAL_STUFFING_RUNBOOK.md`](../../runbooks/ANTI_CREDENTIAL_STUFFING_RUNBOOK.md)
  com contract da Edge Function `login-pre-check` (follow-up não-blocking).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[10.9]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 10 — CSO, item 10.9).
- `2026-04-21` — Corrigido (commit `b2fb402`): DB primitives + CI + runbook. Edge Function wiring (login-pre-check) é follow-up.