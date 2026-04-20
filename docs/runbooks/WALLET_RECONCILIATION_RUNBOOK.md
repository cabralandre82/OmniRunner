# WALLET_RECONCILIATION_RUNBOOK

> **Trigger**: `reconcile-wallets-cron` reportou `severity ∈ {warn, critical}`,
> i.e. uma ou mais carteiras tiveram `balance_coins ≠ SUM(coin_ledger)` na
> última execução diária. Detectado por (em ordem de chegada):
>
> 1. Slack `#incidents` (warn) ou page on-call (critical) via webhook
>    `WALLET_DRIFT_ALERT_WEBHOOK`.
> 2. Linha em `public.wallet_drift_events` com `alerted=false` e
>    `severity != 'ok'` (forensic / fallback se Slack/PagerDuty falhou).
> 3. Log estruturado `severity: ALERT|CRITICAL` + `event:
>    wallet_drift_detected` no agregador.
>
> **Severidade**: P2 (warn, drift ≤ `WALLET_DRIFT_WARN_THRESHOLD`) /
> P1 (critical, drift > threshold).
> **Tempo alvo**: ack < 1 h, mitigação < 4 h (P1) / < 24 h (P2).
> **Linked findings**: L06-03 (alerting absent), L08-07 (real-time check
> off-cron-cycle), L18-01 (mutation guard), L12-01 (cron schedule),
> L20-05 (severity routing).
> **Última revisão**: 2026-04-20

---

## 1. Por que isto importa

`reconcile_all_wallets()` não falha em produção quando encontra drift —
ela **silenciosamente corrige** (atualiza `balance_coins` para
`SUM(coin_ledger)` e escreve um `admin_adjustment` zero-delta). A
correção mascara a causa-raiz, então a única coisa que diferencia "drift
benigno em uma wallet" de "vazamento sistemático no `execute_burn_atomic`"
é o ALERTA. Sem alert (estado pré-L06-03), o time só descobria via:

- Reclamação de atleta ("meu saldo está errado") — semanas depois.
- Auditoria trimestral.
- L18-01 trigger guard explodindo em RPC nova — só pega regressões em
  *novas* RPCs, não bugs em RPCs antigas.

A pipeline L06-03 fecha esse gap: cada drift > 0 vira (a) row em
`wallet_drift_events`, (b) log estruturado com `severity: ALERT/CRITICAL`,
(c) Slack message com `:warning:` ou `:rotating_light:`, (d) opcional
escalation P1 quando `drifted > WALLET_DRIFT_WARN_THRESHOLD`.

## 2. Sintoma → Severity → Ação imediata

| Sinal | Severity | Ação imediata |
|---|---|---|
| Slack `:warning: P2 — Wallet drift detected` (drift entre 1 e `WARN_THRESHOLD`) | P2 | Investigar dentro de 1 h. Não acordar on-call. |
| Slack `:rotating_light: P1 — Wallet drift CRITICAL` (drift > threshold) | P1 | Page on-call. Pausar deploys até identificar root cause. |
| Linha em `wallet_drift_events` com `alerted=false` e `severity!='ok'` por > 30 min | P2 | Slack/PagerDuty falhou. Re-disparar manual + investigar webhook. |
| Drift recorrente (≥ 3 dias seguidos com mesma magnitude) | P1 | Bug sistêmico. NÃO ignorar — abre incident dedicated. |
| `wallet_drift_events` para após N dias sem rows novas | OK | Reconcile-cron caiu / não está sendo chamada. Ver §6 abaixo. |

## 3. Diagnóstico

### 3.0 Real-time check (L08-07) — confirmar drift AGORA, sem esperar 24h

A partir de L08-07, três superfícies estão disponíveis para detecção
real-time (sem precisar esperar a próxima execução do reconcile-cron
às 04:30 UTC):

#### 3.0.1 Endpoint admin (composto)

```bash
curl -H "Cookie: ..." https://portal.../api/platform/invariants
# {
#   "healthy": false,
#   "violations": [...],                       # custody invariants
#   "wallet_drift": {
#     "healthy": false,
#     "count": 3,
#     "severity": "warn",
#     "sample": [ { "user_id": "...", "balance_coins": 100,
#                   "ledger_sum": 73, "drift": -27, ... } ],
#     "scanned_max_users": 5000,
#     "recent_hours": 24,
#     "drift_event_id": "uuid"               # row in wallet_drift_events
#   },
#   "checked_at": "..."
# }
```

`drift_event_id` aponta para a row em `public.wallet_drift_events`
(L06-03) — i.e. ad-hoc check vai disparar Slack se severity ≥ warn,
mesma policy do cron diário.

#### 3.0.2 Endpoint admin (wallet-only com knobs)

Útil quando o operador quer ajustar sample size ou janela de recência
durante triagem (ex.: investigando uma suspeita pontual nas últimas 2 h):

```bash
curl -H "Cookie: ..." \
  "https://portal.../api/platform/invariants/wallets?max_users=20000&recent_hours=2&warn_threshold=5"
# Retorna FULL drift rows (sem cap de 50) + drift_event_id.
```

Bounds (DB-clamped): `max_users ∈ [1, 100000]`, `recent_hours ∈ [0, 720]`,
`warn_threshold ∈ [0, 100000]`. Inputs fora-da-faixa retornam HTTP 400.

#### 3.0.3 SQL direto (psql/Studio)

```sql
-- Cheap default: 5000 wallets, 24h window
SELECT *
FROM   public.fn_check_wallet_ledger_drift(p_max_users => 5000, p_recent_hours => 24)
ORDER  BY ABS(drift) DESC
LIMIT  20;

-- Heavy ad-hoc (full audit; usar fora de horário pico):
SELECT count(*) AS total_drifted
FROM   public.fn_check_wallet_ledger_drift(p_max_users => 100000, p_recent_hours => 720);

-- Drift por activity status (ajuda a separar "bug recente" vs. "drift histórico"):
SELECT recent_activity, count(*), SUM(drift) AS net_drift
FROM   public.fn_check_wallet_ledger_drift(p_max_users => 100000, p_recent_hours => 720)
GROUP  BY recent_activity;
```

**Quando usar real-time vs. cron**: o cron diário (`reconcile-wallets-cron`)
*também corrige* (auto-aplica `reconcile_wallet`); a função L08-07 é
**read-only** (pure observação). Use a função real-time durante incident
para confirmar/quantificar; deixe a correção para o cron OU dispare-o
manualmente depois (ver §5 passo 6 mais abaixo).

### 3.1 Estado atual e histórico recente

```sql
-- Últimos 30 eventos de drift, mais recentes primeiro:
SELECT id,
       run_id,
       observed_at,
       total_wallets,
       drifted_count,
       severity,
       alerted,
       alert_channel,
       alert_error,
       notes
FROM   public.wallet_drift_events
ORDER  BY observed_at DESC
LIMIT  30;
```

### 3.2 Eventos não-alertados (Slack/PagerDuty falhou)

```sql
SELECT id, observed_at, severity, drifted_count, alert_error
FROM   public.wallet_drift_events
WHERE  severity != 'ok'
  AND  alerted   = false
ORDER  BY observed_at DESC;
```

Em estado saudável esta query retorna **zero rows** (todas as detecções
foram entregues). Linhas aqui significam: webhook desconfigurado, Slack
fora do ar quando o cron rodou, ou `WALLET_DRIFT_ALERT_WEBHOOK` não
provisionada no env do edge function.

### 3.3 Tendência (drift recorrente?)

```sql
-- Drift por dia nos últimos 14 dias:
SELECT date_trunc('day', observed_at) AS day,
       max(severity)                  AS worst_severity,
       sum(drifted_count)             AS total_drifted,
       count(*)                       AS events
FROM   public.wallet_drift_events
WHERE  observed_at > now() - interval '14 days'
GROUP  BY 1
ORDER  BY 1 DESC;
```

Drift > 0 em ≥ 3 dias consecutivos é **bug sistêmico** — pular para §5.

### 3.4 Quais wallets driftaram (post-correção)

`reconcile_all_wallets` escreve uma linha `admin_adjustment` zero-delta
por wallet corrigida, com o drift codificado em `ref_id`:

```sql
SELECT user_id,
       created_at_ms,
       ref_id  -- format: 'reconcile:drift=<delta>:old=<bal>:sum=<sum>'
FROM   public.coin_ledger
WHERE  reason = 'admin_adjustment'
  AND  ref_id LIKE 'reconcile:drift=%'
  AND  created_at_ms >= (extract(epoch from (now() - interval '24 hours')) * 1000)::bigint
ORDER  BY created_at_ms DESC;
```

Com isto você tem (a) **quais users**, (b) **direção do drift** (delta
positivo = ledger > balance = wallet estava sub-creditada;
delta negativo = balance > ledger = wallet super-creditada), e (c)
**magnitude** por wallet — base para reverse-engineer da RPC culpada.

### 3.5 Estado do cron schedule

```sql
SELECT name, last_status, run_count, skip_count,
       started_at, finished_at, last_error, last_meta,
       age(now(), finished_at) AS since_finish
FROM   public.cron_run_state
WHERE  name = 'reconcile-wallets-daily';
```

Esperado: `last_status='completed'` em < 25 h. Ver
[`CRON_HEALTH_RUNBOOK.md`](./CRON_HEALTH_RUNBOOK.md) §3.4 se ausente.

## 4. Mitigação — drift detectado (P2)

Drift entre 1 e `WALLET_DRIFT_WARN_THRESHOLD` (default 10 wallets):

1. **Confirmar correção foi aplicada** — `reconcile_all_wallets` já
   corrige sem feature-flag de bloqueio, então `balance_coins` está
   alinhada ao `SUM(coin_ledger)` desde o momento do alert.

2. **Identificar quais wallets** via §3.4.

3. **Correlacionar com mutações recentes** — para cada `user_id`
   afetado:

   ```sql
   SELECT created_at_ms, delta_coins, reason, ref_id
   FROM   public.coin_ledger
   WHERE  user_id = '<user-id>'
     AND  created_at_ms >= (extract(epoch from (now() - interval '7 days')) * 1000)::bigint
   ORDER  BY created_at_ms DESC;
   ```

4. **Procure padrões**: mesmo `reason` em todas as wallets driftadas?
   Mesma janela horária? Mesma RPC suspeita (cross-ref com `audit_logs`)?
   Se sim, abrir issue + adicionar regression test.

5. **Atualizar `wallet_drift_events.notes`** com contexto da
   investigação (post-mortem-friendly):

   ```sql
   UPDATE public.wallet_drift_events
   SET    notes = notes || jsonb_build_object(
            'investigated_by', '<your-handle>',
            'root_cause',      '<short hypothesis>',
            'follow_up_issue', 'GH#<n>'
          )
   WHERE  id = '<event-id>';
   ```

## 5. Mitigação — drift CRITICAL (P1)

Drift > `WALLET_DRIFT_WARN_THRESHOLD` (default 10 wallets afetadas em
uma única execução). Indica problema sistêmico em uma das mutadoras.

1. **Pausar deploys** que tocam módulos financeiros (custody, swap,
   challenge, distribute) — congelar a superfície enquanto investiga.

2. **NÃO desabilitar o reconcile-cron** — ele continua corrigindo
   diariamente. Desabilitar agrava o problema.

3. **Considerar pausar mutadoras suspeitas via kill switch** (L06-06):

   ```sql
   -- Exemplo: parar swap se drift parece originário do execute_swap.
   UPDATE public.feature_flags
   SET    is_enabled = false,
          updated_by = '<your-user-id>',
          reason     = 'L06-03 P1 drift incident <date> — paused for triage'
   WHERE  flag_key = 'swap.enabled';
   ```

4. **Dump completo das wallets afetadas** + último mês de ledger:

   ```sql
   COPY (
     SELECT u.id, u.email, w.balance_coins, w.lifetime_earned_coins,
            w.lifetime_spent_coins, w.last_reconciled_at_ms
     FROM   public.wallets w
     JOIN   auth.users u ON u.id = w.user_id
     WHERE  w.user_id IN (
       SELECT DISTINCT user_id
       FROM   public.coin_ledger
       WHERE  reason = 'admin_adjustment'
         AND  ref_id LIKE 'reconcile:drift=%'
         AND  created_at_ms >= (extract(epoch from (now() - interval '24 hours')) * 1000)::bigint
     )
   ) TO STDOUT WITH CSV HEADER;
   ```

5. **Forense por mutador** — para cada RPC autorizada (L18-01) verificar
   chamadas recentes para os user_ids afetados:

   ```sql
   SELECT actor_user_id, action, target_user_id, created_at, payload
   FROM   public.portal_audit_log
   WHERE  target_user_id = ANY(ARRAY[<user_ids>]::uuid[])
     AND  created_at > now() - interval '30 days'
   ORDER  BY created_at DESC;
   ```

6. **Re-disparar reconcile manualmente** (curto-circuita o cron schedule
   diário; útil para confirmar que a investigação se estabilizou):

   ```sql
   SELECT extensions.http(
     ('POST',
      current_setting('app.settings.supabase_url') ||
      '/functions/v1/reconcile-wallets-cron',
      ARRAY[
        extensions.http_header('Authorization',
          'Bearer ' || current_setting('app.settings.service_role_key')),
        extensions.http_header('Content-Type','application/json')
      ],
      'application/json',
      '{}'
     )::extensions.http_request
   );
   ```

7. **Postmortem mandatório** — qualquer P1 dispara
   `docs/postmortems/<YYYY-MM-DD>-wallet-drift.md` usando o
   `docs/postmortems/TEMPLATE.md`.

## 6. Mitigação — pipeline de alerta quebrada (linhas `alerted=false`)

`wallet_drift_events` recebeu rows mas Slack não chegou:

1. **Confirmar webhook está provisionada**:

   ```bash
   supabase secrets list --project-ref <ref> | grep WALLET_DRIFT
   # Esperado: WALLET_DRIFT_ALERT_WEBHOOK presente
   ```

2. **Inspecionar `alert_error`**:

   ```sql
   SELECT id, severity, drifted_count, alert_error, notes
   FROM   public.wallet_drift_events
   WHERE  alerted = false AND severity != 'ok'
   ORDER  BY observed_at DESC;
   ```

   Padrões comuns em `alert_error`:

   - `HTTP 404` — webhook URL revogada (Slack rotacionou). Provisionar
     nova URL, atualizar secret.
   - `HTTP 429` — rate-limited (Slack incoming-webhook é ~1 msg/sec).
     Improvável dado o volume diário do reconcile, mas se retornar
     repetido, agregar drifts da semana em uma única mensagem.
   - `aborted` — timeout de 5s (rede ruim ou Slack lento). Re-disparo
     manual (passo 3) costuma resolver.
   - `dns failure` — Edge Function sem internet outbound. Verificar
     status do Supabase.

3. **Re-disparo manual da notificação** (sem re-rodar `reconcile`):

   ```bash
   # Get the unalerted event details:
   psql ... -c "SELECT id, severity, drifted_count, total_wallets,
                     run_id::text, observed_at::text
                FROM public.wallet_drift_events
                WHERE alerted=false AND severity!='ok' LIMIT 1;"

   # Hand-craft a Slack message and POST:
   curl -X POST "$WALLET_DRIFT_ALERT_WEBHOOK" \
        -H "Content-Type: application/json" \
        -d '{"text":":warning: Wallet drift (re-fired) — <event id>"}'

   # Mark the event alerted:
   psql ... -c "SELECT public.fn_mark_wallet_drift_event_alerted(
                  '<event id>'::uuid, 'slack-manual', NULL);"
   ```

## 7. Verificação pós-mitigação

```sql
-- 1. Sem eventos não-alertados pendentes
SELECT count(*) AS pending_alerts
FROM   public.wallet_drift_events
WHERE  alerted = false AND severity != 'ok';
-- Esperado: 0

-- 2. Próxima execução do cron passou e veio severity='ok' (na próxima
--    janela 04:30 UTC):
SELECT observed_at, severity, drifted_count
FROM   public.wallet_drift_events
ORDER  BY observed_at DESC
LIMIT  1;
-- Esperado: severity='ok' OU sem rows (`reconcile_all_wallets` só
-- escreve quando severity != 'ok' — silêncio é vitória).

-- 3. Próximas 7 execuções estáveis:
SELECT date_trunc('day', observed_at) AS day, max(severity)
FROM   public.wallet_drift_events
WHERE  observed_at > now() - interval '7 days'
GROUP  BY 1 ORDER BY 1;
```

## 8. Pós-incidente

- Postmortem para qualquer P1.
- Atualizar este runbook se descobrir nova causa-raiz.
- Considerar bumping de threshold se a operação maturou e drift de 1-2
  wallets/semana é "ruído normal" (mas isto é decisão de produto +
  finance lead, NÃO unilateral do on-call).
- Adicionar regression test pra causa-raiz no `tools/test_*.ts` ou
  `portal/src/lib/*.test.ts`.

## 9. Configuração

| Env var | Default | Função |
|---|---|---|
| `WALLET_DRIFT_WARN_THRESHOLD` | `10` | Limite entre warn (P2) e critical (P1). Drift ≤ threshold → warn; > threshold → critical. Ajustar via `supabase secrets set` no Edge Function `reconcile-wallets-cron`. |
| `WALLET_DRIFT_ALERT_WEBHOOK` | _(unset)_ | Slack incoming-webhook URL. Sem isto, persistência em `wallet_drift_events` continua funcionando mas Slack não dispara — apenas o log estruturado vira sinal. |
| `WALLET_DRIFT_RUNBOOK_URL` | _(unset)_ | Link para esta página renderizado dentro da mensagem Slack. Recomendado apontar para a versão deployed (ex.: GitHub permalink na branch `master`). |
| `ENVIRONMENT_LABEL` | `unknown` | Tag environment renderizada na mensagem. Setar `production` em prod, `staging` em staging. |

## 10. Referências

- Migration L06-03: `supabase/migrations/20260420110000_l06_wallet_drift_events.sql`
- Migration L08-07: `supabase/migrations/20260420120000_l08_wallet_ledger_drift_check.sql`
- Edge Function: `supabase/functions/reconcile-wallets-cron/index.ts`
- Helper Deno: `supabase/functions/_shared/wallet_drift.ts`
- Helper TS: `portal/src/lib/wallet-invariants.ts`
- Endpoints (admin):
    - `GET /api/platform/invariants` (composto custody + wallet drift, sample 50)
    - `GET /api/platform/invariants/wallets?max_users=&recent_hours=&warn_threshold=` (wallet-only, full rows)
- Tests: `supabase/functions/_shared/wallet_drift.test.ts`,
  `portal/src/lib/wallet-invariants.test.ts`,
  `portal/src/app/api/platform/invariants/route.test.ts`,
  `portal/src/app/api/platform/invariants/wallets/route.test.ts`,
  `tools/test_l06_03_wallet_drift_events.ts`,
  `tools/test_l08_07_wallet_ledger_drift_check.ts`
- Finding L06-03: [`docs/audit/findings/L06-03-reconcile-wallets-cron-sem-alerta-em-drift-0.md`](../audit/findings/L06-03-reconcile-wallets-cron-sem-alerta-em-drift-0.md)
- Finding L08-07: [`docs/audit/findings/L08-07-drift-potencial-entre-coin-ledger-e-wallets-fora.md`](../audit/findings/L08-07-drift-potencial-entre-coin-ledger-e-wallets-fora.md)
- Cross-ref runbooks:
  [`CRON_HEALTH_RUNBOOK.md`](./CRON_HEALTH_RUNBOOK.md) (cron lifecycle),
  [`WALLET_MUTATION_GUARD_RUNBOOK.md`](./WALLET_MUTATION_GUARD_RUNBOOK.md)
  (root-cause da maioria dos drifts é uma RPC nova bypassando o guard L18-01),
  [`CUSTODY_INCIDENT_RUNBOOK.md`](./CUSTODY_INCIDENT_RUNBOOK.md)
  (drift cross-coin × custody-USD).
- Severity routing: [`docs/observability/ALERT_POLICY.md`](../observability/ALERT_POLICY.md).
