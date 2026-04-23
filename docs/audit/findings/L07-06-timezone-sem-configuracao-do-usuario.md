---
id: L07-06
audit_ref: "7.6"
lens: 7
title: "Timezone sem configuração do usuário"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
tags: ["portal"]
files:
  - "supabase/migrations/20260421260000_l12_07_onboarding_nudge_user_timezone.sql"
correction_type: code
test_required: true
tests:
  - "tools/test_l12_07_onboarding_nudge_timezone.ts"
linked_issues: []
linked_prs: ["4f14773"]
owner: cxo
runbook: "docs/runbooks/ONBOARDING_NUDGE_TIMEZONE_RUNBOOK.md"
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: "Encerrado como side-effect de L12-07 (profile timezone era pré-requisito)."
---
# [L07-06] Timezone sem configuração do usuário
> **Lente:** 7 — CXO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fixed
**Camada:** backend/db
**Personas impactadas:** CXO, COO, usuários finais

## Achado
— `sessions.start_time_ms` é UTC timestamp. Portal renderiza datas com `new Date(ms).toLocaleString("pt-BR")` → respeita timezone do browser, mas:

- Atleta no Brasil em fuso `America/Noronha` vê "3:00 AM" quando rodou às "4:00 AM locais".
- Portal admin vendo atletas de grupos em múltiplos países mistura fusos.
## Correção proposta

— Campo `profiles.timezone text DEFAULT 'America/Sao_Paulo'` detectado no primeiro login. Backend formata datas server-side quando necessário.

## Correção aplicada

Encerrado como side-effect de L12-07 (`4f14773`). A migration `20260421260000_l12_07_onboarding_nudge_user_timezone.sql` adiciona exatamente a coluna proposta:

- `profiles.timezone text NOT NULL DEFAULT 'America/Sao_Paulo'` com CHECK `profiles_timezone_valid` que valida via `fn_is_valid_timezone` (rejeita IANA inválidos como `'America/Sao Paulo'`, `'Mars/Olympus'`, NULL, string vazia).
- `profiles.notification_hour_local smallint NOT NULL DEFAULT 9 CHECK (0..23)` — bônus da L12-07 que reaproveita a mesma tabela.
- Helpers `fn_is_valid_timezone(text)` IMMUTABLE e `fn_user_local_hour(uuid)` STABLE SECURITY DEFINER para uso em outros jobs que queiram semântica "hora local do usuário".

### Consumer side (follow-up)
A coluna é a pré-condição de duas melhorias pendentes (não no escopo desta PR):
- Portal: trocar `new Date(ms).toLocaleString("pt-BR")` por `new Intl.DateTimeFormat("pt-BR", { timeZone: user.timezone }).format(...)` em views de sessions/challenges.
- Mobile: detectar `Intl.DateTimeFormat().resolvedOptions().timeZone` no primeiro login e `PATCH /api/profile` para alinhar o valor.

Essas duas tarefas estão tracked como improvements separadas (sem audit finding — L07-06 só cobria "coluna não existe").

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[7.6]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 7 — CXO, item 7.6).
- `2026-04-21` — Encerrado (`4f14773`, co-fix com L12-07): `profiles.timezone` + CHECK + helpers instalados via `20260421260000_l12_07_onboarding_nudge_user_timezone.sql`. Consumer side (portal/mobile) fica como follow-up não-blocking.
