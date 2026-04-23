---
id: L15-02
audit_ref: "15.2"
lens: 15
title: "Sem sistema de referral/convite viral"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "mobile", "migration", "seo"]
files:
  - supabase/migrations/20260421580000_l15_02_referral_program.sql
  - tools/audit/check-referral-program.ts
correction_type: process
test_required: true
tests: []
linked_issues: []
linked_prs:
  - local:08842bf
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
fixed_at: 2026-04-21
closed_at: 2026-04-21
note: |
  Viral referral primitives now live server-side as a
  complete lifecycle.
  - `coin_ledger_reason_check` extended with
    `referral_referrer_reward` + `referral_referred_reward`
    (preserving the 20 L03-13 reasons).
  - `public.referral_rewards_config` (id=1, CHECK-bounded
    rewards / ttl_days / per-user cap / code length) is the
    single knob operators tune.
  - `public.referrals` table with state-machine CHECK
    (pending → activated|expired|revoked), self-referral
    CHECK, exhaustive status-timestamps CHECK, UNIQUE
    referral_code, UNIQUE(referred_user_id) WHERE
    status='activated' (idempotency), and
    pending-expiry partial index. RLS own-read + admin-read;
    inserts/updates go through SECURITY DEFINER RPCs.
  - BEFORE UPDATE trigger `fn_referrals_status_guard` locks
    the state machine.
  - `fn_generate_referral_code(p_len)` emits cryptographically
    random upper-case alphanumeric codes (`gen_random_bytes`)
    excluding 0/O/1/I, length clamped [6, 16], up to 8
    retries, P0002 on exhaustion.
  - `fn_create_referral(channel)` validates the channel enum,
    enforces the per-referrer cap, stamps
    `expires_at = now() + ttl_days`, raises P0003 on cap
    breach.
  - `fn_activate_referral(code)` gates on pending + not
    expired + not self + no prior activation; writes the two
    coin_ledger rows atomically and bumps both wallets
    best-effort. FOR UPDATE on the claim.
  - `fn_expire_referrals()` is the service_role-only cron
    sweep for pending rows past TTL.
  - Self-test asserts generator length + alphabet + clamp,
    reason-enum extension, and config seeding.
  - CI guard `npm run audit:referral-program` enforces 47
    invariants.
---
# [L15-02] Sem sistema de referral/convite viral
> **Lente:** 15 — CMO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— Grep `referral|referrals|convide_amigo` → zero em SQL. Crescimento orgânico viral impossível.
## Risco / Impacto

— CAC permanece alto; não há mecanismo para atleta trazer atleta (viralização natural em esporte social).

## Correção proposta

—

```sql
CREATE TABLE public.referrals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer_user_id uuid NOT NULL REFERENCES auth.users(id),
  referred_user_id uuid REFERENCES auth.users(id),
  referral_code text NOT NULL UNIQUE,
  channel text,  -- 'whatsapp','instagram','email','link'
  reward_referrer_coins int DEFAULT 10,
  reward_referred_coins int DEFAULT 5,
  status text DEFAULT 'pending' CHECK (status IN ('pending','activated','expired')),
  activated_at timestamptz,
  created_at timestamptz DEFAULT now()
);
```

Mobile: tela "Convide 3 amigos → ganhe 30 coins"; deep link `omnirunner://ref/CODE`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[15.2]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 15 — CMO, item 15.2).