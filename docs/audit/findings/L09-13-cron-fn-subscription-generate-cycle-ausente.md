---
id: L09-13
audit_ref: "9.13"
lens: 9
title: "Cron fn_subscription_generate_cycle ausente — faturas mensais nunca são geradas"
severity: critical
status: fix-pending
wave: 0
discovered_at: 2026-04-24
fixed_at: null
closed_at: null
tags: ["finance", "cron", "subscriptions", "billing", "reliability"]
files:
  - supabase/migrations/20260424160000_l09_13_subscription_crons.sql
correction_type: code
test_required: true
tests:
  - tools/audit/check-cron-idempotency.ts
linked_issues: []
linked_prs: []
owner: platform-finance
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L09-13] Cron fn_subscription_generate_cycle ausente — faturas mensais nunca são geradas

> **Lente:** 9 — CRO/Finance · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending

**Camada:** DB (pg_cron)
**Personas impactadas:** admin master (esperava receber mensalidade
automática e tem que gerar manualmente), coach (não consegue explicar
ao atleta por que o boleto desse mês não chegou), atleta (acredita que
está inadimplente porque "nunca recebeu cobrança"), plataforma (MRR
reportado é um subconjunto arbitrário do real)

## Achado

A migration `20260421670000_l23_09_athlete_subscriptions.sql` criou
toda a infra de assinaturas recorrentes (Wave 1 do finding L23-09):

- Tabela `public.athlete_subscriptions` com state machine completa.
- Tabela `public.athlete_subscription_invoices` com `due_date`, status
  `pending|paid|overdue|cancelled`, UNIQUE `(subscription_id,
  period_month)` para idempotência.
- Função `fn_subscription_generate_cycle(p_period_month DATE)` —
  idempotente, insere 1 row por (subscription ativa, período) com
  `ON CONFLICT DO NOTHING`.
- Grant `fn_subscription_generate_cycle(DATE) TO service_role`.
- Runtime guard `IF current_setting('role') IS DISTINCT FROM
  'service_role' THEN RAISE`.

**O que falta:** nenhum `cron.schedule(...)` registra a função. Nenhuma
Edge Function a chama. Nenhum webhook a dispara.

Resultado em produção:

- Depois do dia 01 de cada mês, `athlete_subscription_invoices` fica
  sem rows pro período corrente.
- `next_due_date` em `coaching_subscriptions` continua sendo calculado
  (é o modelo legado lido pelo portal hoje), mas o modelo novo está
  vazio.
- Qualquer superfície que venha a consumir `athlete_subscription_invoices`
  (agenda de recebíveis, "minhas mensalidades" do atleta, dashboard
  de aging) mostra estado vazio.

Esse é o mesmo padrão de bug que achamos em L12-01 (reconcile-wallets:
função existe, cron nunca foi agendado). A diferença: L12-01 só
causava drift invisível; L09-13 bloqueia diretamente monetização.

## Impacto

- **Receita recorrente**: bloqueada end-to-end. Qualquer assessoria
  que quiser cobrar mensalidade via portal precisa gerar invoice
  manualmente via SQL como service_role — cenário operacional
  inviável para qualquer usuário não-técnico.
- **Inadimplência invisível**: L09-14 (mark_overdue sem cron) depende
  desta migration rodar primeiro — sem rows em `athlete_subscription_invoices`,
  não há o que marcar como atrasado.
- **MRR/ARR report**: relatório de receita recorrente retorna zero
  no modelo novo, o que esconde a real saúde financeira da plataforma
  caso o relatório seja conectado a essa tabela no futuro.
- **Gates F1/F2 bloqueados**: agenda de recebíveis e "minhas mensalidades"
  (ambas já identificadas como gaps críticos para go-to-market do
  portal financeiro) pressupõem invoices existentes.

Critical porque (1) bloqueia monetização, (2) não há workaround
operacional razoável, (3) fix é curto (~30 linhas de SQL) e (4) o
risco de shipar a Wave F1 antes é shipar uma UI que sempre mostra
estado vazio.

## Correção proposta

Migration `20260424160000_l09_13_subscription_crons.sql` — agenda
ambos os crons da L09 (este e o L09-14) no mesmo arquivo para mantê-los
juntos operacionalmente:

```sql
-- Pattern L12-11: IF NOT EXISTS + unschedule defensivo.
-- Runtime role switch: pg_cron roda como postgres; função exige
-- service_role. SET LOCAL é isolado à transação da execução.

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;

DO $cron$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE NOTICE '[L09-13] pg_cron not installed; skipping';
    RETURN;
  END IF;

  BEGIN PERFORM cron.unschedule('l09_13_subscription_generate_cycle');
  EXCEPTION WHEN OTHERS THEN NULL; END;

  PERFORM cron.schedule(
    'l09_13_subscription_generate_cycle',
    '0 5 1 * *',  -- 05:00 UTC no dia 1 de cada mês
    $job$
    SET LOCAL role = 'service_role';
    SELECT public.fn_subscription_generate_cycle();
    $job$
  );

  INSERT INTO public.cron_run_state(name, last_status)
  VALUES ('l09_13_subscription_generate_cycle', 'never_run')
  ON CONFLICT (name) DO NOTHING;
END
$cron$;
```

**Decisão de horário (`0 5 1 * *` = 05:00 UTC no dia 1)**:

- Dia 1 do mês: garante que `due_date = period_month + (billing_day - 1)
  days` cai no futuro para todos os `billing_day_of_month ∈ [1, 28]`.
  Rodar mid-month causaria invoices nascerem atrasadas (e imediatamente
  marcadas como `overdue` pelo L09-14).
- 05:00 UTC (02:00 BRT): antes do horário comercial, depois do gap
  operacional da janela de backup da Supabase.
- Não conflita com outros jobs no repo (escaneado via grep por
  `0 5 * * *`).

**Decisão de runtime-role**:

O `SET LOCAL role = 'service_role'` dentro do comando SQL do cron é
necessário porque `pg_cron` executa como `postgres` (o owner do job),
e `fn_subscription_generate_cycle` tem `IF current_setting('role') IS
DISTINCT FROM 'service_role' THEN RAISE`. `SET LOCAL` vale só para a
transação do job e não afeta outras sessões.

**Seed de `cron_run_state`**: insere row `never_run` para ops terem
visibilidade imediata após deploy (padrão do L12-01).

## Teste de regressão

**Nível migration (self-test no próprio arquivo)**:

```sql
DO $selftest$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM cron.job
    WHERE jobname = 'l09_13_subscription_generate_cycle'
  ) THEN
    RAISE EXCEPTION 'L09-13 self-test: cron job missing after schedule';
  END IF;
END $selftest$;
```

**Nível CI (check-cron-idempotency.ts)**: o pattern `IF NOT EXISTS +
unschedule` já satisfaz o guard existente — sem mudança no script.

**Nível runbook**: op pode validar manualmente via:

```sql
-- Listar crons de subscription
SELECT jobname, schedule, active
FROM cron.job
WHERE jobname LIKE 'l09_1%subscription%';

-- Forçar execução imediata (sem esperar dia 1)
SET LOCAL role = 'service_role';
SELECT public.fn_subscription_generate_cycle();
```

## Cross-refs

- L12-01 (fixed) — mesmo padrão de bug: reconcile-wallets-cron Edge
  Function existia mas sem schedule.
- L12-11 (fixed) — idempotency guard que essa migration respeita.
- L12-03 (fixed) — `cron_run_state` spine que essa migration popula.
- L09-14 (fix-pending) — par desta: `fn_subscription_mark_overdue`
  também não está agendado. Mesmo arquivo de migration.
- L23-09 (fixed) — criou as funções mas não as agendou.

## Histórico

- `2026-04-24` — Descoberto durante análise de prontidão de
  go-to-market do financeiro (estudo de produto).
