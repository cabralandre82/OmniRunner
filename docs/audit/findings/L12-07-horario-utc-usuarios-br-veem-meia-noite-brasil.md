---
id: L12-07
audit_ref: "12.7"
lens: 12
title: "Horário UTC → usuários BR veem \"meia-noite Brasil\""
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
tags: ["finance", "cron", "ux"]
files:
  - "supabase/migrations/20260421260000_l12_07_onboarding_nudge_user_timezone.sql"
  - "supabase/functions/onboarding-nudge/index.ts"
  - "tools/test_l12_07_onboarding_nudge_timezone.ts"
  - "docs/runbooks/ONBOARDING_NUDGE_TIMEZONE_RUNBOOK.md"
correction_type: code
test_required: true
tests:
  - "tools/test_l12_07_onboarding_nudge_timezone.ts"
linked_issues: []
linked_prs: ["4f14773"]
owner: coo
runbook: "docs/runbooks/ONBOARDING_NUDGE_TIMEZONE_RUNBOOK.md"
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: "fix também encerra L07-06 (profiles.timezone)."
---
# [L12-07] Horário UTC → usuários BR veem "meia-noite Brasil"
> **Lente:** 12 — Cron/Scheduler · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fixed
**Camada:** backend/db + edge
**Personas impactadas:** COO, CXO, usuários finais

## Achado
— `clearing-cron` roda 02:00 UTC = 23:00 BRT. Aceitável. Mas `onboarding-nudge-daily` 10:00 UTC = 07:00 BRT — pode ser cedo demais para notificação push.

## Correção proposta

— Ajustar para 12:00 UTC (09:00 BRT). Ou, melhor: job consulta `profiles.timezone` ([7.6]) e envia push nas "09:00 locais" de cada usuário (exigindo granularidade por timezone).

## Correção aplicada

Adotado o caminho "melhor" (per-user timezone) em vez de simplesmente deslocar o schedule:

1. **Schema em `public.profiles`** (co-fecha L07-06): `timezone text NOT NULL DEFAULT 'America/Sao_Paulo'` + `notification_hour_local smallint NOT NULL DEFAULT 9` + CHECK `profiles_timezone_valid` (via `fn_is_valid_timezone`, rejeita `'Mars/Olympus'`, `'America/Sao Paulo'` com espaço, NULL, string vazia) + CHECK `profiles_notification_hour_local_range (0..23)`.
2. **3 helpers SQL**: `fn_is_valid_timezone(text)` IMMUTABLE (usável na CHECK e via RPC), `fn_user_local_hour(uuid)` STABLE SECURITY DEFINER (retorna `EXTRACT(HOUR FROM now() AT TIME ZONE tz)`, fallback defensivo para Sao_Paulo quando TZ corrompido), `fn_should_send_nudge_now(uuid, preferred?)` STABLE SECURITY DEFINER (boolean = TRUE iff hora local == preferida). REVOKE PUBLIC + GRANT service_role nas SECURITY DEFINER.
3. **Reschedule do cron**: `cron.unschedule('onboarding-nudge-daily')` + `cron.schedule('onboarding-nudge-hourly', '0 * * * *', 'SELECT public.fn_invoke_onboarding_nudge_safe();')`. O wrapper `fn_invoke_onboarding_nudge_safe` (L06-05) sobrevive intacto — apenas renomeamos o job name. Insert em `cron_run_state` para o novo nome via `ON CONFLICT DO NOTHING`.
4. **Edge Function `onboarding-nudge/index.ts` TZ-aware**: SELECT agora inclui `timezone` + `notification_hour_local` (com fallback para o schema antigo se as colunas não existirem, para compatibilidade em branches legados). `currentHourInTimezone(tz)` computa a hora local via `Intl.DateTimeFormat(..., { timeZone })`. Loop skipa quando `localHour !== userPrefHour` e incrementa `skipped_off_hour` no response body para observabilidade. L12-09 dedup (UNIQUE user_id+rule+context_id com `context_id='d<N>'`) garante at-most-one push por usuário por dia, mesmo com 24 ticks/dia.
5. **Testes**: `tools/test_l12_07_onboarding_nudge_timezone.ts` (18 cases via docker-exec psql): schema/DDL (colunas + CHECKs + IMMUTABLE/STABLE + SECURITY DEFINER + service_role grants + cron schedule hourly), `fn_is_valid_timezone` (aceita IANA canônicos, rejeita typos/NULL/empty), argument validation (NULL user → 22023, hour=24/-1 → 22023), behaviour (scalar fallback, CHECK em UPDATE inválido, consistência hora entre chamadas). 18/18 verdes.
6. **Runbook** `docs/runbooks/ONBOARDING_NUDGE_TIMEZONE_RUNBOOK.md` com queries de diagnóstico, cenários (usuário não recebe nudge, troca de hora preferida, storm hourly, TZ NULL histórico), interações com `notify-rules`/L12-08/L07-06, tunables, rollback (voltar para daily 10:00 UTC com SQL prontinho), observability signals.

### Impacto
- Antes: 07:00 BRT fixo para 100% dos usuários, 0 respeito a outras TZs.
- Depois: 09:00 local por padrão (user-configurável 00..23, TZ-configurável por IANA), mesmo efeito no orçamento APNs/FCM (cap de 24 ticks/dia mas L12-09 limita dispatches a 1/user/dia).

### L07-06 co-fechado
O finding L07-06 propunha exatamente `profiles.timezone text DEFAULT 'America/Sao_Paulo'` detectado no primeiro login. Esse PR entrega a coluna + a CHECK (usando `fn_is_valid_timezone`), habilitando formatação server-side de datas em `sessions.start_time_ms` nas próximas entregas (consumer side está fora de escopo desta PR; a coluna é a pré-condição).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[12.7]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 12 — Cron/Scheduler, item 12.7).
- `2026-04-21` — Correção aplicada (`4f14773`): profiles.timezone + notification_hour_local + 3 helpers SQL + cron hourly + Edge Function TZ-aware + 18 testes + runbook. Co-fecha L07-06.
