---
id: L09-14
audit_ref: "9.14"
lens: 9
title: "Cron fn_subscription_mark_overdue ausente — inadimplência invisível"
severity: high
status: fixed
wave: 0
discovered_at: 2026-04-24
fixed_at: 2026-04-24
closed_at: 2026-04-24
tags: ["finance", "cron", "subscriptions", "billing", "reliability", "dunning"]
files:
  - supabase/migrations/20260424160000_l09_13_subscription_crons.sql
correction_type: code
test_required: true
tests:
  - tools/audit/check-cron-idempotency.ts
linked_issues: []
linked_prs: ["1521561"]
owner: platform-finance
runbook: null
effort_points: 1
blocked_by: ["L09-13"]
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L09-14] Cron fn_subscription_mark_overdue ausente — inadimplência invisível

> **Lente:** 9 — CRO/Finance · **Severidade:** 🟠 High · **Onda:** 0 · **Status:** fix-pending

**Camada:** DB (pg_cron)
**Personas impactadas:** coach/admin (dashboard mostra zero
inadimplentes mesmo quando há atletas atrasados), atleta inadimplente
(não recebe sinal de cobrança, continua aparecendo como ativo),
plataforma (aging report vira inválido)

## Achado

A migration L23-09 criou `fn_subscription_mark_overdue()` —
idempotente, procura rows em `athlete_subscription_invoices` com
`status='pending' AND due_date < CURRENT_DATE` e flipa para `overdue`
(populando `overdue_at = now()`).

Grant está presente: `GRANT EXECUTE TO service_role`. Runtime guard
`IF current_setting('role') IS DISTINCT FROM 'service_role' THEN RAISE`.

**O que falta:** nenhum `cron.schedule(...)` chama a função. Sem cron,
status fica eterno em `pending` mesmo depois do `due_date` passar.

Dependência de `L09-13`: sem o cron de geração rodando, não há
`athlete_subscription_invoices` para processar. Mas ainda assim este
finding precisa ser tratado explicitamente — quando L09-13 gerar as
primeiras rows em produção, o gap de L09-14 vira imediatamente
visível (invoices nascendo pending, envelhecendo pending, nunca
viram overdue).

## Impacto

- **KPI "inadimplentes" do dashboard financeiro**: hoje lê
  `coaching_subscriptions.status='late'` (modelo legado). Quando a
  migração para o modelo novo acontecer, o KPI lê
  `athlete_subscription_invoices.status='overdue'` e retornará zero
  permanentemente — comunicando saúde financeira fantasia ao coach.
- **Aging report**: "R$ X em atraso há 0-7d / 8-15d / 16-30d / 30+"
  depende de `overdue_at` estar populado. Sem cron, buckets ficam
  vazios. Dashboard de aging inútil.
- **Automação de cobrança (dunning)**: trigger "atleta atrasou há 3
  dias → enviar notificação push" depende do flip pending→overdue.
  Sem cron, a notificação nunca dispara.
- **Reconciliação contábil**: DRE do mês mistura invoices pending
  (reais a receber no futuro) com invoices que deveriam estar
  overdue (reais a receber atrasados, provisão de perda diferente).

High (não critical) porque: (1) não bloqueia cobrança em si (invoice
continua existindo); (2) coach consegue ver `due_date` na tabela e
inferir atraso manualmente; (3) o modelo legado `coaching_subscriptions`
com `status='late'` continua em uso como fallback. Mas assim que a
consolidação de modelos (Gate F0 slice 2) for feita, este finding
vira blocker.

## Correção proposta

Mesmo arquivo de migration que L09-13 (mantém os dois crons juntos
para facilitar ops). Segundo bloco `DO` no mesmo arquivo:

```sql
DO $cron$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RETURN;
  END IF;

  BEGIN PERFORM cron.unschedule('l09_14_subscription_mark_overdue');
  EXCEPTION WHEN OTHERS THEN NULL; END;

  PERFORM cron.schedule(
    'l09_14_subscription_mark_overdue',
    '30 5 * * *',  -- 05:30 UTC diário
    $job$
    SET LOCAL role = 'service_role';
    SELECT public.fn_subscription_mark_overdue();
    $job$
  );

  INSERT INTO public.cron_run_state(name, last_status)
  VALUES ('l09_14_subscription_mark_overdue', 'never_run')
  ON CONFLICT (name) DO NOTHING;
END
$cron$;
```

**Decisão de horário (`30 5 * * *` = 05:30 UTC diário)**:

- 30 minutos depois do L09-13 (dia 1 tem ambos rodando sem conflito,
  generate_cycle é <1s).
- Diário porque `due_date` resolve em dia. Rodar a cada hora não
  agrega valor (UPDATE vazio 23x de 24 por dia) e aumenta lock contention.
- 05:30 UTC (02:30 BRT): fora de horário comercial, mesma janela do
  L09-13.

**Decisão de não usar advisory lock (L12-03)**: `UPDATE ... SET
status='overdue' WHERE status='pending' AND due_date < CURRENT_DATE`
é fully idempotent. Concurrent runs convergem para o mesmo estado.
O wrapper de lock existe para crons */5 ou mais curtos; não vale a
pena pra diário.

## Teste de regressão

Self-test:

```sql
DO $selftest$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM cron.job
    WHERE jobname = 'l09_14_subscription_mark_overdue'
  ) THEN
    RAISE EXCEPTION 'L09-14 self-test: cron job missing';
  END IF;
END $selftest$;
```

Manual (após L09-13 rodar):

```sql
-- Forçar cenário: criar invoice pending com due_date passado
-- (requer ambiente de staging)
SET LOCAL role = 'service_role';
SELECT public.fn_subscription_mark_overdue();
-- Deve retornar número > 0 em staging com invoices antigas.
```

## Cross-refs

- L09-13 (fix-pending) — prerequisito operacional; mesma migration.
- L23-09 (fixed) — criou a função mas não agendou.
- L12-11 (fixed) — idempotency guard.

## Histórico

- `2026-04-24` — Descoberto junto com L09-13 na análise de prontidão
  do financeiro. Mesmo padrão ("function existe, cron ausente").
- `2026-04-24` — Fixed em `1521561`. Agendado 05:30 UTC diário (30min
  depois do L09-13 para não competir no dia 1). Sem advisory lock
  porque UPDATE é 100% idempotente. Mesma migration que L09-13.
