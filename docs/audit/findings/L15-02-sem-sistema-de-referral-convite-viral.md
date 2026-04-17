---
id: L15-02
audit_ref: "15.2"
lens: 15
title: "Sem sistema de referral/convite viral"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "mobile", "migration", "seo"]
files: []
correction_type: process
test_required: true
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L15-02] Sem sistema de referral/convite viral
> **Lente:** 15 — CMO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
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