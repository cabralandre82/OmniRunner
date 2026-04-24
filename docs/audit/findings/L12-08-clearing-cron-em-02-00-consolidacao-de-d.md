---
id: L12-08
audit_ref: "12.8"
lens: 12
title: "clearing-cron em 02:00 — consolidação de D-1 antes de fim do dia"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
tags: ["cron", "finance"]
files:
  - "supabase/migrations/20260421270000_l12_08_clearing_cron_deterministic_cutoff.sql"
  - "tools/test_l12_08_clearing_cron_deterministic_cutoff.ts"
  - "docs/runbooks/CLEARING_CRON_CUTOFF_RUNBOOK.md"
correction_type: code
test_required: true
tests:
  - tools/test_l12_08_clearing_cron_deterministic_cutoff.ts
linked_issues: []
linked_prs: ["7f52a25"]
owner: cfo
runbook: "docs/runbooks/CLEARING_CRON_CUTOFF_RUNBOOK.md"
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L12-08] clearing-cron em 02:00 — consolidação de D-1 antes de fim do dia
> **Lente:** 12 — Cron/Scheduler · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fixed
**Camada:** backend/db
**Personas impactadas:** CFO, COO, assessorias

## Achado
— Aggregator consolida ledger de "a semana". Usuário que queima moeda às 01:55 está na agregação; às 02:05 está fora. Jitter no horário do job pode cruzar a fronteira.

## Correção proposta

— Função agrega com `WHERE created_at < date_trunc('day', now())` (estritamente < início de hoje UTC). Documento "cutoff = 00:00 UTC" no runbook.

## Correção aplicada

Implementada a versão **TZ-aware** do "cutoff = start-of-today" (em vez de UTC puro), alinhando com o produto BR-first:

1. **`public.fn_clearing_cutoff_utc(p_timezone text DEFAULT 'America/Sao_Paulo', p_as_of timestamptz DEFAULT NULL) RETURNS timestamptz`** STABLE SECURITY DEFINER — retorna `(date_trunc('day', p_as_of AT TIME ZONE p_timezone)) AT TIME ZONE p_timezone`, i.e., o início de hoje no fuso dado, expresso em UTC. Validação de argumentos (NULL/empty/IANA inválido → 22023) via `fn_is_valid_timezone` (L12-07). REVOKE PUBLIC + GRANT service_role.
2. **Reschedule do cron `clearing-cron`** de `0 2 * * *` (02:00 UTC = 23:00 BRT, **antes** da meia-noite BRT — causa do off-by-one para usuários BR) para `15 3 * * *` (03:15 UTC = 00:15 BRT, **depois** da meia-noite BRT, com offset 15 min para evitar o thundering herd das 03:00 UTC discutido em L12-02).
3. **Rewrite de `fn_invoke_clearing_cron_safe`** (L06-05 wrapper preservado): pré-computa `v_cutoff_utc` via o helper, monta body `{ "cutoff_utc": "YYYY-MM-DDTHH:MM:SSZ", "timezone": "America/Sao_Paulo", "run_kind": "daily_aggregate" }` e passa para `fn_invoke_edge_with_retry`. Persiste `cutoff_utc` + `timezone` em `cron_run_state.last_meta` (via merge jsonb no mark_completed/mark_failed), permitindo ao ops responder "qual janela fechou a run de ontem?" em um único SELECT. Shape de retorno idêntico (void). Proteção contra sandboxes sem `cron_run_state` via `IF EXISTS` gate idêntica a L06-05.
4. **Self-test DO-block** no fim da migration valida (a) helper registrado, (b) cutoff para 2026-04-21 17:00 UTC em BRT == 2026-04-21 03:00 UTC, (c) cutoff para 2026-04-21 02:00 UTC em BRT == 2026-04-20 03:00 UTC (dia BRT anterior — demonstra a correção do off-by-one), (d) cutoff para UTC retorna 00:00 UTC sem shift, (e) TZ inválido → 22023, (f) NULL TZ → 22023, (g) cron agendado em `15 3 * * *` quando pg_cron disponível.
5. **Tests**: `tools/test_l12_08_clearing_cron_deterministic_cutoff.ts` (14 casos docker-exec psql): schema/DDL (STABLE + SECURITY DEFINER + service_role grants + cron schedule), behaviour (BRT cutoff para 17:00 UTC, BRT cutoff para 02:00 UTC → dia anterior, UTC tz → UTC midnight, default `p_as_of` usa now() ≤ now(), determinismo entre duas chamadas consecutivas), argument validation (NULL/empty/invalid IANA → 22023, `p_as_of=NULL` usa now() sem erro), wrapper (existe + SECURITY DEFINER). 14/14 verdes.
6. **Runbook canônico** `docs/runbooks/CLEARING_CRON_CUTOFF_RUNBOOK.md` (~220 linhas, 7 seções): contrato do aggregator (código SQL canônico citando `fn_clearing_cutoff_utc`), dashboard queries (last cutoff + retry trail + pending-prize inventory usando o helper), shape saudável (03:15 UTC diário, duração <60s, `cutoff_utc` == start-of-BRT-day, `last_status=completed >95%`), cenário A (burn na sexta à noite BRT "sumiu do relatório" — 3 passos para entender se é pré-cutoff ou pós-cutoff e qual run próxima consolidará), cenário B (run falhou — `cron_run_state.last_error` + retry audit + rerun manual), cenário C (replay de dia específico — dois `fn_clearing_cutoff_utc` com `p_as_of` manuais para window determinístico), cenário D (mudança de TZ — NÃO fazer mid-run, migration-only change), tunables (schedule, TZ, L06-05 retries, L12-04 SLA inalterado), rollback (SQL pronto para voltar para 02:00 UTC), observability signals. Cross-refs L12-01/02/03/04/06/07 + L06-05 + CLEARING_STUCK.

### Impacto
- Antes: burn em 23:30 BRT (= 02:30 UTC day+1) entrava na consolidação do dia D+1, não D — desalinhava o relatório da assessoria com a percepção humana do próprio dia. Jitter do pg_cron (±segundos a minutos) tornava o cutoff não-determinístico — duas runs consecutivas podiam agregar conjuntos diferentes de rows para o mesmo bucket lógico.
- Depois: cutoff é sempre `date_trunc('day', now() AT TIME ZONE 'America/Sao_Paulo') AT TIME ZONE 'America/Sao_Paulo'` — determinístico, TZ-anchored, BRT-calendar-aligned, auditável via `cron_run_state.last_meta.cutoff_utc`.

### Escopo deliberadamente excluído
- A Edge Function `clearing-cron` em si (consumer do body `{cutoff_utc, timezone, run_kind}`) não existe ainda no repositório. Este PR entrega o CONTRATO e a infra de cutoff determinístico; quando a Edge Function for implementada (follow-up), ela deve usar `req.body.cutoff_utc` como limite superior estrito, não `Date.now()` ou `new Date().toISOString()`.
- `fn_settle_clearing_batch_safe` (L02-10) usa janela rolling de 168h e NÃO foi tocada — o escopo de L12-08 é a consolidação diária (`clearing-cron`), não o batch de settlement.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[12.8]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 12 — Cron/Scheduler, item 12.8).
- `2026-04-21` — Correção aplicada (`7f52a25`): `fn_clearing_cutoff_utc` TZ-aware + reschedule para 00:15 BRT + rewrite de `fn_invoke_clearing_cron_safe` + 14 testes + runbook.
