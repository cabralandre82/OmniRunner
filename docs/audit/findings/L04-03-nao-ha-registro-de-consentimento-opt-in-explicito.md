---
id: L04-03
audit_ref: "4.3"
lens: 4
title: "Não há registro de consentimento (opt-in explícito LGPD Art. 8)"
severity: critical
status: in-progress
wave: 0
discovered_at: 2026-04-17
fix_ready_at: 2026-04-17
tags: ["lgpd", "integration", "mobile", "portal", "migration", "backend", "edge-function", "audit-log"]
files:
  - supabase/migrations/20260417220000_lgpd_consent_management.sql
  - supabase/functions/consent-record/index.ts
  - supabase/config.toml
  - portal/src/app/api/consent/route.ts
  - tools/integration_tests.ts
correction_type: process
test_required: true
tests:
  - integration/L04-03-consent-policy-seed
  - integration/L04-03-profiles-snapshot-cols
  - integration/L04-03-fn-consent-grant-happy-path
  - integration/L04-03-fn-consent-grant-version-too-old
  - integration/L04-03-fn-consent-grant-invalid-type
  - integration/L04-03-fn-consent-revoke-terms-blocked
  - integration/L04-03-marketing-grant-revoke-last-wins
  - integration/L04-03-has-required-athlete
  - integration/L04-03-status-returns-8-rows
  - integration/L04-03-status-cross-user-forbidden
  - integration/L04-03-append-only-update-blocked
  - integration/L04-03-anon-preserves-row-on-auth-delete
  - integration/L04-03-registered-in-lgpd-strategy
linked_issues: []
linked_prs: []
owner: platform-privacy
runbook: docs/audit/runbooks/L04-03-lgpd-consent-management.md
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L04-03] Não há registro de consentimento (opt-in explícito LGPD Art. 8)
> **Lente:** 4 — CLO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** 🟡 in-progress
**Camada:** backend + integração + mobile + portal
**Personas impactadas:** Atletas, Coaches, Admin Master, DPO/Legal
## Achado
— `grep -i "terms_accepted|consent|privacy_accepted|lgpd_consent" supabase/migrations/*.sql` → **zero** matches. A tabela `profiles` não tem `terms_accepted_at`, `privacy_accepted_at`, `terms_version`, `marketing_consent`.
## Risco / Impacto

— LGPD Art. 7º, I exige consentimento comprovável. Em auditoria/ação judicial, plataforma não consegue provar que o titular consentiu. Multa até 2 % faturamento.

## Correção implementada

**Migration [`20260417220000_lgpd_consent_management.sql`](../../../supabase/migrations/20260417220000_lgpd_consent_management.sql):**

1. **`public.consent_policy_versions`** — catálogo versionado (8 tipos
   canônicos: `terms`, `privacy`, `health_data`, `location_tracking`,
   `marketing`, `third_party_strava`, `third_party_trainingpeaks`,
   `coach_data_share`). Seed inicial em v1.0 idempotente.

2. **`public.consent_events`** — log append-only imutável:
   - FK `user_id → auth.users(id) ON DELETE SET DEFAULT` (preserva row em
     erasure com `user_id = zero UUID`).
   - Trigger `_consent_events_append_only` bloqueia UPDATE de campos de
     auditoria; permite apenas a transição `user_id → zero UUID` que
     automaticamente nula `ip_address`/`user_agent`.
   - RLS: `SELECT` own (authenticated) + service_role; `INSERT/UPDATE/DELETE`
     direto revogado para authenticated — escrita sempre via RPC.

3. **Snapshot desnormalizado em `public.profiles`**: colunas
   `terms_accepted_at`, `terms_version`, `privacy_accepted_at`,
   `privacy_version`, `health_data_consent_at`, `location_consent_at`,
   `marketing_consent_at`. Atualizadas transactionalmente pelos RPCs.

4. **5 RPCs `SECURITY DEFINER` hardened** (`SET search_path`, `SET
   lock_timeout`):
   - `fn_consent_grant(consent_type, version, source, ip, user_agent, request_id)`
     — authenticated; valida `version ≥ minimum_version`; erros tipados
     (P0001/P0002/P0004).
   - `fn_consent_revoke(consent_type, source, request_id)` — authenticated;
     `terms`/`privacy` bloqueados (`NOT_REVOCABLE_STANDALONE`) → força fluxo
     `fn_delete_user_data`.
   - `fn_consent_status(user_id?)` — lista estado por tipo; cross-user só
     para service_role.
   - `fn_consent_has_required(user_id?, role?)` — boolean fail-closed para
     gating de endpoints sensíveis (STABLE; usa
     `required_for_role IN (NULL, 'any', <role>)`).
   - `fn_anonymize_consent_events(user_id)` — service_role only; reservada
     para a pipeline de erasure LGPD.

5. **View `public.v_user_consent_status`** — último evento por
   (`user_id`, `consent_type`) + `is_valid` (granted ∧ versão ≥ mínima).

6. **Integração `lgpd_deletion_strategy` (L04-01)**: `consent_events.user_id`
   registrado como `anonymize` — satisfaz simultaneamente LGPD Art. 16
   (prova documental) e Art. 18 VI (direito ao esquecimento).

**Callers reescritos**:

- **`supabase/functions/consent-record/index.ts`** (novo) — canonical endpoint
  para o mobile (Flutter). Aceita `POST { action: grant|revoke|status,
  consent_type, version? }`. Source-de-verdade para IP/UA.
- **`portal/src/app/api/consent/route.ts`** (novo) — equivalente web; `GET`
  retorna status (shortcut para UI); `POST` executa grant/revoke.
- **`supabase/config.toml`** — registra `consent-record` com `verify_jwt = true`.

**Runbook**: [`docs/audit/runbooks/L04-03-lgpd-consent-management.md`](../runbooks/L04-03-lgpd-consent-management.md)
cobre: adicionar novo tipo, rotação de versão, auditoria, revogação
pontual, pipeline de erasure, alertas / SLOs, resposta a subject-access-
request ("a ANPD pede prova").

## Teste de regressão

Cobertura em `tools/integration_tests.ts` (13 testes novos):

1. Seed com 8 políticas canônicas (≥4 required).
2. Colunas de snapshot presentes em `profiles`.
3. Grant cria evento + popula snapshot.
4. Grant rejeita `version < minimum_version` (`VERSION_TOO_OLD`).
5. Grant rejeita `consent_type` inválido (check constraint).
6. Revoke de `terms`/`privacy` bloqueado (`NOT_REVOCABLE_STANDALONE`).
7. Grant+revoke — último estado consolidado = revoked.
8. `fn_consent_has_required(role='athlete')` = false até consents
   required-for-athlete serem granted.
9. `fn_consent_status()` retorna 8 linhas (uma por policy).
10. Cross-user read bloqueado (`FORBIDDEN`).
11. UPDATE direto em `consent_events` rejeitado pelo trigger
    append-only.
12. **`auth.users` DELETE preserva row anonimizada**: FK SET DEFAULT +
    trigger zera `ip_address`/`user_agent`; `consent_type`/`action`/
    `version`/`granted_at` preservados.
13. `consent_events.user_id` registrado em `lgpd_deletion_strategy`
    com estratégia `anonymize`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[4.3]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 4 — CLO, item 4.3).
- `2026-04-17` — Fix implementado: migration + 2 thin wrappers (edge fn + portal route) + 13 testes integração + runbook.