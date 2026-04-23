---
id: L10-07
audit_ref: "10.7"
lens: 10
title: "Zero-trust entre microserviços — Edge Functions confiam no JWT sem validar audience"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
tags: ["mobile", "portal", "edge-function"]
files:
  - supabase/functions/_shared/auth.ts
  - tools/audit/check-jwt-claims-validation.ts
  - tools/test_l10_07_jwt_claims_validation.ts
  - docs/runbooks/JWT_ZERO_TRUST_RUNBOOK.md
correction_type: code
test_required: true
tests:
  - tools/test_l10_07_jwt_claims_validation.ts
linked_issues: []
linked_prs:
  - 15601fa
owner: platform
runbook: docs/runbooks/JWT_ZERO_TRUST_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: "2026-04-21 — fixed. Shared _shared/auth.ts requireUser now enforces iss/aud validation with env overrides, optional per-route allowedAudiences and allowedClients (x-omni-client header), and machine-readable reason codes. CI guard npm run audit:jwt-claims-validation blocks bypasses."
---
# [L10-07] Zero-trust entre microserviços — Edge Functions confiam no JWT sem validar audience
> **Lente:** 10 — CSO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `supabase/functions/_shared/auth.ts` valida JWT mas não valida `aud` claim específica. Qualquer JWT válido do Supabase acessa qualquer função.
## Correção proposta

— JWT assinado com `aud=omni-runner-mobile` ou `aud=omni-runner-portal` + validação por-função de quem pode chamar o quê.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[10.7]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 10 — CSO, item 10.7).
- `2026-04-21` — Corrigido. `supabase/functions/_shared/auth.ts` `requireUser` agora aplica zero-trust claims validation: `iss` deve pertencer a `AUTH_JWT_EXPECTED_ISSUERS` (default `${SUPABASE_URL}/auth/v1`), `aud` deve intersectar `AUTH_JWT_ALLOWED_AUDIENCES` (default `authenticated`). Rotas podem apertar com `allowedAudiences` e `allowedClients` (header `x-omni-client`). Erros carregam `reason` (`invalid_issuer`, `audience_mismatch`, `client_mismatch`, ...). CI (`npm run audit:jwt-claims-validation`) falha o build se `_shared/auth.ts` perder a forma, se alguma função fora de `_shared` chamar `auth.getUser` direto, ou se `skipClaimsCheck: true` for commitado. Testes em `tools/test_l10_07_jwt_claims_validation.ts`. Runbook: `docs/runbooks/JWT_ZERO_TRUST_RUNBOOK.md`.