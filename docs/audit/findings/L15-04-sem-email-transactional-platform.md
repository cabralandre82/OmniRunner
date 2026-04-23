---
id: L15-04
audit_ref: "15.4"
lens: 15
title: "Sem email transactional platform"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
tags: ["portal", "edge-function", "reliability", "email", "idempotency", "security"]
files:
  - supabase/migrations/20260421360000_l15_04_email_outbox.sql
  - supabase/functions/_shared/email.ts
  - supabase/functions/send-email/index.ts
  - supabase/email-templates/manifest.json
  - supabase/email-templates/coaching_group_invite.html
  - supabase/email-templates/championship_invite.html
  - supabase/email-templates/weekly_training_summary.html
  - supabase/email-templates/payment_confirmation.html
  - tools/audit/check-email-platform.ts
correction_type: code
test_required: true
tests:
  - supabase/functions/_shared/email.test.ts
  - tools/test_l15_04_email_outbox.ts
linked_issues: []
linked_prs:
  - "local/2beeb1f — fix(email): transactional platform — outbox + provider abstraction + send-email edge fn (L15-04)"
owner: platform
runbook: docs/runbooks/EMAIL_TRANSACTIONAL_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Landed 2026-04-21 across three pillars:

  DB FOUNDATION (20260421360000_l15_04_email_outbox.sql)
  • public.email_outbox — canonical queue, 1 row/lifecycle, UNIQUE idempotency_key
    (CHECK length 8..256), RLS ENABLE+FORCE, service_role FOR ALL only. 5 CHECKs.
  • fn_enqueue_email (SECURITY DEFINER) — INSERT ON CONFLICT DO NOTHING;
    normalises recipient_email (lower+trim); returns row id either way.
  • fn_mark_email_sent / fn_mark_email_failed (SECURITY DEFINER) — idempotent
    transitions; raise P0010 INVALID_TRANSITION on sent/suppressed→failed and
    failed/suppressed→sent.
  • fn_email_outbox_assert_shape (SECURITY DEFINER) — raises P0010 if schema /
    RLS / indexes / CHECKs / privileges drift. Used by CI guard.
  • REVOKE ALL FROM PUBLIC, anon, authenticated on all 4 helpers;
    GRANT EXECUTE TO service_role explicitly.

  EDGE-FN / SHARED LIB (supabase/functions/_shared/email.ts + send-email/)
  • EmailProvider abstraction: ResendProvider (prod), InbucketProvider (supabase
    start), NullProvider (default — zero outbound HTTP, safe for CI). Selected
    via EMAIL_PROVIDER env var.
  • escapeHtml applied to every {{var}} in body (subjects opt-out, plain text).
  • TEMPLATE_MANIFEST mirrors email-templates/manifest.json as the typed
    EmailTemplateKey surface. CI enforces parity.
  • POST /send-email (service-role gated) orchestrates enqueue → dispatch →
    mark_sent/failed. Short-circuits replays of already-sent rows with
    HTTP 200 + status:already_sent.

  TEMPLATES (supabase/email-templates/)
  • 4 shipped: coaching_group_invite, championship_invite, weekly_training_summary,
    payment_confirmation. Responsive 600px, brand palette, required_vars
    registered in manifest.

  TESTING
  • Deno unit tests (_shared/email.test.ts): 27 green — escapeHtml, renderTemplate,
    validateEmailAddress, assertRequiredVars (per template), resolveProvider,
    NullProvider, InMemoryLoader, sendEmail end-to-end including XSS
    neutralisation and terminal-vs-transient classification.
  • Integration tests (tools/test_l15_04_email_outbox.ts): 18 green — schema
    (table + RLS forced, 4 helpers SECURITY DEFINER, service_role vs
    anon/authenticated privileges, unique index, 5 CHECKs), argument
    validation, behaviour (enqueue idempotency + normalisation, mark_sent
    idempotency, mark_failed non-terminal/terminal, INVALID_TRANSITION).

  CI GUARD (npm run audit:email-platform)
  • 6 invariants: DB shape via fn_email_outbox_assert_shape; shared/email.ts
    exports; send-email service-role gating + correct wiring; manifest parity;
    no direct provider HTTP outside sanctioned modules; runbook exists.

  RUNBOOK (docs/runbooks/EMAIL_TRANSACTIONAL_RUNBOOK.md)
  • Architecture diagram, "add new template" checklist, 6 operational
    playbooks (provider outage, missing vars, failure spike, batch replay,
    GC retention, CI guard failure), security posture, detection signals,
    rollback, cross-refs to L10-09/L12-09/L18-04/L04-07/L03-17.

  Related follow-ups (not in this PR): L15-05 (scheduled drain cron + 90-day
  GC), L15-06 (category=pii retention carve-out), L15-07 (bounce/complaint
  webhook).
---
# [L15-04] Sem email transactional platform
> **Lente:** 15 — CMO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** ✅ fixed (2026-04-21)
**Camada:** —
**Personas impactadas:** —
## Achado
— Grep `resend|postmark|sendgrid|mailgun` em `portal/src` e Edge Functions → zero provider integrado. Supabase Auth envia email de confirmação via SMTP padrão (quota limitada).
## Risco / Impacto

— Notificações importantes ("seu withdraw foi processado") não chegam ou caem em spam.

## Correção proposta

— Integrar Resend ou Postmark; templates versionados em `supabase/email-templates/`; log de entregas.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[15.4]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 15 — CMO, item 15.4).
- `2026-04-21` — ✅ **Fixed** (commit `2beeb1f`). Construída a plataforma transactional completa em três pilares: (1) **DB** — `public.email_outbox` + 4 helpers SECURITY DEFINER (`fn_enqueue_email`, `fn_mark_email_sent`, `fn_mark_email_failed`, `fn_email_outbox_assert_shape`) com RLS forçado, `UNIQUE idempotency_key` (8..256 chars) e CHECKs de transição; `REVOKE ALL FROM PUBLIC, anon, authenticated` + `GRANT EXECUTE TO service_role`; self-test DO-block válida enqueue idempotente, transições `sent`/`failed` (idempotentes) e raise `P0010 INVALID_TRANSITION` em `sent→failed` / `failed→sent`. (2) **Edge-fn** — `_shared/email.ts` com `EmailProvider` abstrato (Resend/Inbucket/Null; default=Null), `escapeHtml` aplicado a todo `{{var}}` de body, `assertRequiredVars` por template, `validateEmailAddress` RFC-compliant; `send-email/index.ts` service-role gated, orquestra `fn_enqueue_email → sendEmail → fn_mark_email_{sent,failed}` com short-circuit para replays (`already_sent`). (3) **Templates** — 4 templates HTML responsivos (`coaching_group_invite`, `championship_invite`, `weekly_training_summary`, `payment_confirmation`) registrados em `manifest.json` espelhado por `TEMPLATE_MANIFEST` em `_shared/email.ts`. **Testes:** 27/27 Deno unit (`_shared/email.test.ts`) + 18/18 pg integration (`tools/test_l15_04_email_outbox.ts`). **CI guard:** `npm run audit:email-platform` com 6 invariantes (DB shape, shared exports, edge-fn gating, manifest parity, provider isolation, runbook presence). **Runbook:** `docs/runbooks/EMAIL_TRANSACTIONAL_RUNBOOK.md` com diagrama, checklist para novo template, 6 playbooks operacionais (outage, missing vars, failure spike, replay, GC retention, CI failure), postura de segurança e cross-refs (L10-09, L12-09, L18-04, L04-07, L03-17). Follow-ups parkados: L15-05 (cron drain + GC 90d), L15-06 (PII retention), L15-07 (bounce webhook).