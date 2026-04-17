---
id: L04-03
audit_ref: "4.3"
lens: 4
title: "Não há registro de consentimento (opt-in explícito LGPD Art. 8)"
severity: critical
status: fix-pending
wave: 0
discovered_at: 2026-04-17
tags: ["lgpd", "integration", "mobile", "portal", "migration", "ux"]
files: []
correction_type: process
test_required: true
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L04-03] Não há registro de consentimento (opt-in explícito LGPD Art. 8)
> **Lente:** 4 — CLO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `grep -i "terms_accepted|consent|privacy_accepted|lgpd_consent" supabase/migrations/*.sql` → **zero** matches. A tabela `profiles` não tem `terms_accepted_at`, `privacy_accepted_at`, `terms_version`, `marketing_consent`.
## Risco / Impacto

— LGPD Art. 7º, I exige consentimento comprovável. Em auditoria/ação judicial, plataforma não consegue provar que o titular consentiu. Multa até 2 % faturamento.

## Correção proposta

— Migration:

```sql
ALTER TABLE public.profiles ADD COLUMN terms_accepted_at timestamptz;
ALTER TABLE public.profiles ADD COLUMN terms_version text;
ALTER TABLE public.profiles ADD COLUMN privacy_accepted_at timestamptz;
ALTER TABLE public.profiles ADD COLUMN privacy_version text;
ALTER TABLE public.profiles ADD COLUMN marketing_consent_at timestamptz;
ALTER TABLE public.profiles ADD COLUMN health_data_consent_at timestamptz;

CREATE TABLE public.consent_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id),
  consent_type text NOT NULL CHECK (consent_type IN
    ('terms','privacy','marketing','health_data','third_party_strava','third_party_trainingpeaks')),
  version text NOT NULL,
  granted boolean NOT NULL,
  ip_address inet,
  user_agent text,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX idx_consent_log_user ON public.consent_log(user_id, consent_type, created_at DESC);
```

No onboarding (`complete-social-profile`): inserir em `consent_log` cada toggle aceito + `UPDATE profiles SET terms_accepted_at=now()`.

## Teste de regressão

— e2e: cadastrar usuário sem aceitar termos → `auth.users` criado mas `profiles.terms_accepted_at IS NULL` → app/portal bloqueia acesso até consentimento.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[4.3]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 4 — CLO, item 4.3).