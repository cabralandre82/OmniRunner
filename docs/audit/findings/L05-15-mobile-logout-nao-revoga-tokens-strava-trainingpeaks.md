---
id: L05-15
audit_ref: "5.15"
lens: 5
title: "Mobile: logout não revoga tokens Strava/TrainingPeaks"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["integration", "mobile", "ux"]
files: []
correction_type: code
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
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