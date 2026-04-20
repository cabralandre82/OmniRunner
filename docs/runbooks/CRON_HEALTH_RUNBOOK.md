# CRON_HEALTH_RUNBOOK

> **Trigger**: cron job ausente, atrasado, com `last_status='failed'`,
> ou `skip_count` crescendo a cada 5 min.
> **Severidade**: P1 (reconcile-wallets ou clearing) / P2 (lifecycle,
> matchmaking, releases) / P3 (archive, partition).
> **Tempo alvo**: ack < 1h, mitigação < 4h.
> **Linked findings**: L12-01 (reconcile-wallets schedule),
> L12-02 (thundering herd 02:00–04:00 UTC),
> L12-03 (`*/5` overlap risk).
> **Última revisão**: 2026-04-19

---

## 1. Sintoma

| Sinal | Possível causa |
|---|---|
| `cron_run_state.last_status = 'failed'` por > 1 ciclo | Erro no SQL ou no Edge Function |
| `cron_run_state.skip_count` cresce a cada minuto | Job anterior travado / dura mais que `max_runtime_seconds` |
| `cron_run_state.last_status = 'timeout'` recorrente | EF/SQL excede o safety window (4 min p/ jobs `*/5`) |
| Sem rows em `cron_run_state` para job esperado | Job nunca rodou OU migração não aplicada |
| `wallets.balance_coins` divergindo de `SUM(coin_ledger)` | `reconcile-wallets-daily` parou (P1 imediato) |
| Sentry alert `cron_thundering_herd_03utc` | Schedule de algum job voltou para a janela 03:00 UTC |
| Portal lento aos domingos 03:00 UTC | Algum job voltou para o cluster archive/eval-verification (regressão de L12-02) |

## 2. Diagnóstico

### 2.1 Inventário de schedules atuais

```sql
SELECT jobname, schedule, command, active
FROM   cron.job
ORDER  BY schedule, jobname;
```

Esperado pós-L12-01/02/03 (windows em UTC):

| jobname | schedule | observação |
|---|---|---|
| `clearing-cron` | `0 2 * * *` | unchanged |
| `eval-verification-cron` | `15 3 * * *` | shifted (+15min) por L12-02 |
| `archive-old-sessions` | `45 3 * * 0` | shifted (+45min) por L12-02 |
| `reconcile-wallets-daily` | `30 4 * * *` | adicionado por L12-01 |
| `archive-old-ledger` | `15 5 * * 0` | shifted (+1h15m) por L12-02 |
| `coin_ledger_ensure_partition_monthly` | `30 5 1 * *` | shifted (+2h30m) por L12-02 |
| `auto-topup-hourly` | `0 * * * *` | unchanged |
| `lifecycle-cron` | `*/5 * * * *` | wrapped em `fn_invoke_lifecycle_cron_safe()` |
| `expire-matchmaking-queue` | `*/5 * * * *` | wrapped em `fn_expire_queue_entries_safe()` |
| `process-scheduled-workout-releases` | `*/5 * * * *` | wrapped em `fn_process_scheduled_releases_safe()` |
| `settle-clearing-batch` | `* * * * *` | adicionado por L02-10 — drena `clearing_settlements` em chunks de 50 dentro do banco (sem Vercel) |
| `swap-expire` | `*/10 * * * *` | unchanged |
| `onboarding-nudge-daily` | `0 10 * * *` | unchanged |

Se algum schedule diverge: **regressão**. Identifique a migration
posterior que reescreveu e reagende manualmente:

```sql
-- Exemplo: re-aplicar redistribuição L12-02 manualmente
SELECT cron.unschedule('eval-verification-cron');
SELECT cron.schedule('eval-verification-cron', '15 3 * * *',
  $$ SELECT extensions.http(...); $$);
```

### 2.2 Estado de execução

```sql
SELECT name,
       last_status,
       run_count,
       skip_count,
       started_at,
       finished_at,
       age(now(), started_at)  AS since_start,
       age(now(), finished_at) AS since_finish,
       last_error,
       last_meta
FROM   public.cron_run_state
ORDER  BY GREATEST(COALESCE(started_at, 'epoch'),
                   COALESCE(finished_at, 'epoch')) DESC;
```

Sinais críticos:

- `last_status='running'` AND `since_start > 4 min` → job presumido morto
  (a próxima execução vai marcar `timeout` e seguir).
- `last_status='failed'` AND `last_error` populado → ler `last_meta.sqlstate`
  e a stack do EF correspondente em Supabase Dashboard → Functions → logs.
- `skip_count` crescendo > 3/min → previous run travado; ver §3.2.

### 2.3 Identificar causa de travamento

```sql
-- Quem segura advisory locks de cron?
SELECT pid,
       state,
       wait_event_type,
       wait_event,
       query,
       now() - query_start AS running_for
FROM   pg_stat_activity
WHERE  query ILIKE '%fn_%_safe%'
   OR  query ILIKE '%pg_advisory%';
```

Procure por `wait_event = 'advisory'` — é o sintoma clássico de overlap.

```sql
-- Bloqueios atuais (advisory locks)
SELECT locktype, classid, objid, mode, granted, pid
FROM   pg_locks
WHERE  locktype = 'advisory'
ORDER  BY pid;
```

## 3. Mitigação

### 3.1 Cron ausente (regressão de L12-01)

```sql
-- Se reconcile-wallets-daily desapareceu (não existe row em cron.job):
SELECT cron.schedule(
  'reconcile-wallets-daily',
  '30 4 * * *',
  $cron$
  SELECT extensions.http(
    (
      'POST',
      current_setting('app.settings.supabase_url') || '/functions/v1/reconcile-wallets-cron',
      ARRAY[
        extensions.http_header('Authorization', 'Bearer ' || current_setting('app.settings.service_role_key')),
        extensions.http_header('Content-Type', 'application/json')
      ],
      'application/json',
      '{}'
    )::extensions.http_request
  );
  $cron$
);
```

Validar: `SELECT * FROM cron.job WHERE jobname='reconcile-wallets-daily';`

### 3.2 Job travado (`skip_count` crescendo)

1. **Identificar PID travado** (§2.3).
2. **Cancelar query** (preferir `pg_cancel_backend` antes de `pg_terminate_backend`):

   ```sql
   SELECT pg_cancel_backend(<pid>);   -- educado
   SELECT pg_terminate_backend(<pid>); -- se cancel ignorado por 30s
   ```

3. **Limpar estado órfão** (a próxima execução faria isso automaticamente
   após 4 min, mas se for crítico):

   ```sql
   UPDATE public.cron_run_state
   SET    last_status = 'timeout',
          finished_at = now(),
          last_error  = 'manually marked timeout by SRE — pid ' || <pid>::text,
          updated_at  = now()
   WHERE  name = '<job-name>';
   ```

4. **Investigar causa** — se for o mesmo PID/stack todo dia, abrir issue
   contra o time dono do EF/RPC.

### 3.3 Job falhando (`last_status='failed'`)

1. Ler `last_error` + `last_meta.sqlstate` em `cron_run_state`.
2. Para EFs (lifecycle/clearing/reconcile/eval-verification): Supabase
   Dashboard → Functions → escolher função → Logs → filtrar pelo timestamp
   do `started_at`.
3. Para SQL puros (matchmaking expirer, releases): a stack costuma vir
   inline no `last_error`.
4. **Hot-patch** (último recurso): unschedule, corrigir RPC ou EF, schedule
   de volta.

### 3.4 Reconcile não rodou (`reconcile-wallets-daily`)

P1 — drift entre `wallets.balance_coins` e ledger acumula a cada dia.

1. **Disparo manual**:

   ```sql
   SELECT extensions.http(
     (
       'POST',
       current_setting('app.settings.supabase_url') || '/functions/v1/reconcile-wallets-cron',
       ARRAY[
         extensions.http_header('Authorization', 'Bearer ' || current_setting('app.settings.service_role_key')),
         extensions.http_header('Content-Type', 'application/json')
       ],
       'application/json',
       '{}'
     )::extensions.http_request
   );
   ```

2. **Verificar resultado** após ~30s:

   ```sql
   SELECT * FROM public.cron_run_state WHERE name='reconcile-wallets-daily';
   -- Esperar last_status='completed', last_meta com contadores.
   ```

3. **Conferir drift residual**:

   ```sql
   SELECT w.id, w.group_id, w.balance_coins,
          COALESCE(SUM(l.delta_coins), 0) AS ledger_sum,
          w.balance_coins - COALESCE(SUM(l.delta_coins), 0) AS drift
   FROM   public.wallets w
   LEFT   JOIN public.coin_ledger l ON l.wallet_id = w.id
   GROUP  BY w.id
   HAVING w.balance_coins <> COALESCE(SUM(l.delta_coins), 0)
   LIMIT  20;
   ```

4. Se drift > 0 ainda: abrir CUSTODY_INCIDENT_RUNBOOK.

### 3.5 Settle-clearing batch parado / backlog crescendo (L02-10)

Sinal: `cron_run_state` para `settle-clearing-batch` com
`last_status='failed'` ou `last_meta.remaining` crescendo a cada
ciclo (deveria sempre cair para 0).

1. **Estado atual e tamanho do backlog**:

   ```sql
   SELECT name, last_status, run_count, skip_count,
          last_meta, last_error,
          age(now(), finished_at) AS since_finish
   FROM   public.cron_run_state
   WHERE  name = 'settle-clearing-batch';

   SELECT count(*)
   FROM   public.clearing_settlements
   WHERE  status = 'pending';
   ```

2. **Disparo manual de um chunk** (via Edge endpoint, útil quando
   pg_cron está parado mas Postgres está saudável):

   ```bash
   curl -X POST "$PORTAL_URL/api/cron/settle-clearing-batch" \
     -H "Authorization: Bearer $CRON_SECRET" \
     -H "Content-Type: application/json" \
     -d '{"limit":50,"max_chunks":4,"window_hours":168}'
   ```

   Resposta esperada:

   ```json
   { "ok": true,
     "chunks_processed": 4,
     "total_processed": 200,
     "total_settled":   195,
     "remaining":       312,
     "stop_reason":     "max_chunks" }
   ```

3. **Disparo manual via SQL** (não depende do portal Vercel — preferir
   este caminho quando o serverless estiver indisponível):

   ```sql
   -- Reset da safety window e força um ciclo:
   UPDATE public.cron_run_state
   SET    last_status='never_run', started_at=NULL, finished_at=NULL,
          updated_at=now()
   WHERE  name = 'settle-clearing-batch';

   SELECT public.fn_settle_clearing_batch_safe(50, 168);
   ```

4. **Drenar manualmente um chunk** (sem cron-state — útil para
   investigar uma janela suspeita):

   ```sql
   SELECT * FROM public.fn_settle_clearing_chunk(
     p_window_start => now() - interval '24 hours',
     p_window_end   => now(),
     p_limit        => 100,
     p_debtor_group_id => NULL
   );
   ```

5. **Causas comuns**
   - Backlog real (campanha de novos pagadores) — `remaining` cai a
     cada ciclo, mas devagar. Aumentar temporariamente o
     `max_chunks` no `/api/cron/settle-clearing-batch` ou rodar o
     SQL acima em loop manual.
   - Linhas individuais falhando (`last_meta.failed > 0`) — checar
     `RAISE NOTICE '[L02-10.chunk_row_failed]'` em
     `pg_stat_statements` ou nos logs do Postgres; abrir
     CUSTODY_INCIDENT_RUNBOOK.
   - `lock_timeout` (`SQLSTATE 55P03`) recorrente — outro processo
     segura linhas de `clearing_settlements`; ver §2.3.

### 3.6 Thundering herd voltou (regressão de L12-02)

Sinal: portal lento aos domingos 03:00 UTC, `pg_stat_activity` mostra
≥ 3 jobs concorrentes na mesma janela.

1. Ver §2.1 e identificar quais jobs voltaram para `0 3 *`.
2. Re-aplicar a janela engineered (15 min mínimo de espaçamento):
   - clearing-cron        → `0 2 * * *`
   - eval-verification    → `15 3 * * *`
   - archive-old-sessions → `45 3 * * 0`
   - reconcile-wallets    → `30 4 * * *`
   - archive-old-ledger   → `15 5 * * 0`
   - partition-monthly    → `30 5 1 * *`
3. Validar com query da §2.1.

## 4. Verificação pós-mitigação

```sql
-- 1) Inventário de schedules bate com a tabela esperada
SELECT jobname, schedule
FROM   cron.job
WHERE  jobname IN (
  'clearing-cron','eval-verification-cron','archive-old-sessions',
  'archive-old-ledger','reconcile-wallets-daily','expire-matchmaking-queue',
  'process-scheduled-workout-releases','lifecycle-cron','swap-expire',
  'auto-topup-hourly','onboarding-nudge-daily','coin_ledger_ensure_partition_monthly'
)
ORDER  BY schedule;

-- 2) Nenhum job ficou em 'failed' ou 'timeout' por mais de 1 ciclo
SELECT name, last_status, age(now(), updated_at) AS staleness
FROM   public.cron_run_state
WHERE  last_status IN ('failed','timeout')
   AND updated_at > now() - interval '1 hour';

-- 3) Skip count zerado para jobs */5 nos próximos 15 min (3 ciclos)
SELECT name, skip_count
FROM   public.cron_run_state
WHERE  name IN (
  'expire-matchmaking-queue','process-scheduled-workout-releases','lifecycle-cron'
);
```

## 5. Pós-incidente

- Postmortem se incidente durou > 4h ou se `reconcile-wallets-daily`
  ficou ausente > 24h (drift acumulado).
- Atualizar este runbook se descobrir nova causa-raiz.
- Considerar adicionar Sentry alert para qualquer job com
  `skip_count > 5` em janela de 15 min.

## 6. Referências

- Migration L12-03: `supabase/migrations/20260419100000_l12_cron_overlap_protection.sql`
- Migration L12-02: `supabase/migrations/20260419100001_l12_cron_redistribute_thundering_herd.sql`
- Migration L12-01: `supabase/migrations/20260419100002_l12_reconcile_wallets_schedule.sql`
- Findings: [`docs/audit/findings/L12-01-*.md`](../audit/findings/L12-01-reconcile-wallets-cron-existe-mas-nao-esta-agendado.md), [`L12-02`](../audit/findings/L12-02-thundering-herd-em-02-00-04-00-utc.md), [`L12-03`](../audit/findings/L12-03-5-crons-sem-lock-overlap-risk.md)
- Tests: `tools/test_cron_health.ts`
