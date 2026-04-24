---
id: L05-15
audit_ref: "5.15"
lens: 5
title: "Mobile: logout não revoga tokens Strava/TrainingPeaks"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
tags: ["integration", "mobile", "ux"]
files:
  - docs/runbooks/MOBILE_LOGOUT_REVOKE_OAUTH.md
correction_type: spec
test_required: false
tests: []
linked_issues: []
linked_prs:
  - 3af9c9b
  - 15a8b4b
owner: mobile+integrations
runbook: docs/runbooks/MOBILE_LOGOUT_REVOKE_OAUTH.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Documented in docs/runbooks/MOBILE_LOGOUT_REVOKE_OAUTH.md the UX
  contract (opt-in disconnect at logout sheet; forced revoke on
  security funnel) and server-side flow (fn_revoke_user_integrations
  RPC + revoke-integrations Edge Function with retry queue, plus
  audit_logs domain events). Implementation tickets created for
  mobile and integrations squads; spec is the gating artefact.
---
# [L05-15] Mobile: logout não revoga tokens Strava/TrainingPeaks
> **Lente:** 5 — CPO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Em `profile_screen.dart`, botão "Sair" chama Supabase `signOut()` mas refresh_token Strava (`strava_connections`) fica no Supabase. Próximo login do usuário recupera conexão sem reautorização.
## Risco / Impacto

— Quebra expectativa do atleta ("logout deveria desconectar tudo"). Misunderstanding comum.

## Correção proposta

— UX: logout pergunta "Desconectar também Strava/TP?". Se sim, chama `POST /oauth/deauthorize` (ver [4.9]) e deleta row.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[5.15]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 5 — CPO, item 5.15).