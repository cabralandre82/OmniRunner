# Edge Function Retry Wrapper — Runbook (L06-05)

**Owner:** COO · **Scope:** pg_cron ↔ Edge Function invocations · **Last updated:** 2026-04-21

---

## 1. Modelo mental

Seis `pg_cron` jobs disparam Edge Functions via HTTP. Sem retry, qualquer
falha transiente (503, DNS blip, cold-start timeout, janela de deploy
Supabase) deixa a próxima janela do cron absorver o prejuízo. Em alguns
casos isso é catastrófico:

| Job                     | Cadência | Dano de 1 skip                          |
|-------------------------|----------|-----------------------------------------|
| `auto-topup-hourly`     | `0 * * * *`    | Atleta de saldo baixo fica sem moeda 60 min |
| `lifecycle-cron`        | `*/5 * * * *`  | Challenge não fecha, torneio atrasa 5 min   |
| `clearing-cron`         | `0 2 * * *`    | Issuer payout atrasa 24h                    |
| `eval-verification-cron`| `0 3 * * *`    | Athlete verification evaluation atrasa 24h  |
| `onboarding-nudge-daily`| `0 10 * * *`   | Push D0-D7 não sai — retenção degrada       |
| `reconcile-wallets-daily`| `30 4 * * *`  | Drift wallet↔ledger fica invisível 24h      |

A migration `20260421230000_l06_05_edge_retry_wrapper.sql` introduz UMA
porta de entrada única para chamadas HTTP a Edge Functions com retry
nativo + audit trail + alerta no L06-04 sink.

## 2. Arquitetura

### 2.1 Fluxo de uma chamada bem-sucedida

```
cron.schedule('auto-topup-hourly') fires
  → fn_invoke_auto_topup_cron()
     → fn_cron_mark_started('auto-topup-hourly')
     → fn_invoke_edge_with_retry(job='auto-topup-hourly', endpoint='auto-topup-cron',
                                  max_attempts=3, backoff_base=5s)
        → attempt 1 via extensions.http(...) → 200 OK
        → INSERT cron_edge_retry_attempts(attempt=1, http_status=200, ...)
        → RETURN { ok: true, status: 200, attempts: 1 }
     → fn_cron_mark_completed('auto-topup-hourly', { ok: true, status: 200, attempts: 1 })
```

### 2.2 Fluxo de uma chamada que precisa retry

```
attempt 1 → 503 Service Unavailable
  → INSERT cron_edge_retry_attempts(attempt=1, http_status=503, ...)
  → pg_sleep(5s)  [backoff linear: 5 * attempt]
attempt 2 → 503 again
  → INSERT cron_edge_retry_attempts(attempt=2, http_status=503, ...)
  → pg_sleep(10s)
attempt 3 → 200 OK
  → INSERT cron_edge_retry_attempts(attempt=3, http_status=200, ...)
  → RETURN { ok: true, status: 200, attempts: 3 }
```

### 2.3 Fluxo de uma chamada que esgota os retries

```
attempt 1 → 503
attempt 2 → connection timeout (status=NULL, error="could not connect")
attempt 3 → 503
  → fn_record_cron_health_alert(severity='critical', cooldown=60min,
      details={ kind: 'edge_invocation_failed_after_retries',
                attempts: 3, last_status: 503, ... })
  → RETURN { ok: false, status: 503, attempts: 3, alert_id: uuid, last_error: null }

Caller (fn_invoke_auto_topup_cron) sees ok=false:
  → fn_cron_mark_failed('auto-topup-hourly', 'edge invocation failed after retries', ...)

L06-04 monitor (running every 15 min) detects `last_status=failed` in
cron_run_state → emits its own warn alert (dedup'd by cooldown).
L06-04 fn_alert_unhealthy_crons_safe picks up our critical alert.
Sink (Datadog/Opsgenie/Slack) pages on-call.
```

## 3. Tabelas & Funções

### 3.1 `public.cron_edge_retry_attempts`

Append-only audit table. Uma linha por tentativa HTTP, não por cron run.
Um cron run com `max_attempts=3` e falha final grava 3 linhas.

```sql
SELECT id, job_name, endpoint, attempt, max_attempts,
       http_status, error,
       started_at, completed_at,
       meta
  FROM public.cron_edge_retry_attempts
 WHERE job_name = 'auto-topup-hourly'
 ORDER BY id DESC
 LIMIT 10;
```

Colunas úteis em forense:

- `http_status = NULL` → extensions.http raised (DNS/TLS/connect).
- `error` → SQLERRM truncado em 4096 chars.
- `meta.mode` ∈ {`'sync'`, `'async'`, `'skipped'`}.

Índices:

- `cron_edge_retry_job_started_idx (job_name, started_at DESC)` — "latest
  attempts for X".
- `cron_edge_retry_failures_idx (started_at DESC) WHERE http_status IS NULL
   OR http_status >= 400` — "all failures in the last hour".

RLS forçado, service_role only. Nenhum consumer autenticado vê.

### 3.2 `public.fn_invoke_edge_with_retry(...)`

Assinatura:

```sql
public.fn_invoke_edge_with_retry(
  p_job_name              text,
  p_endpoint              text,
  p_body                  jsonb     DEFAULT '{}'::jsonb,
  p_max_attempts          integer   DEFAULT 3,
  p_backoff_base_seconds  integer   DEFAULT 5,
  p_success_statuses      integer[] DEFAULT ARRAY[200,201,202,204]
) RETURNS jsonb
```

Retorno:

```jsonc
// sucesso
{ "ok": true,  "status": 200, "attempts": 1, "endpoint": "auto-topup-cron" }
// falha após retries
{ "ok": false, "status": 503, "attempts": 3, "endpoint": "auto-topup-cron",
  "last_error": null, "alert_id": "uuid" }
// config ausente (supabase_url/service_role_key não configurados)
{ "ok": false, "skipped": true, "reason": "missing_config", "attempts": 0 }
// http extension ausente (sandbox local)
{ "ok": false, "skipped": true, "reason": "http_extension_missing", "attempts": 0 }
```

Invariantes:

- `p_max_attempts ∈ [1, 10]` — fora desse range → `22023 INVALID_MAX_ATTEMPTS`.
- `p_backoff_base_seconds ∈ [0, 120]` — fora → `22023 INVALID_BACKOFF`.
- Backoff efetivo: `LEAST(base * attempt, 120)` — 0s/10s/15s com base=5.
- Todas as chamadas usam `extensions.http` (SÍNCRONO). `pg_net.http_post`
  é async/fire-and-forget e NÃO satisfaz retry.
- `fn_record_cron_health_alert` é best-effort — falha não propaga.

### 3.3 `public.fn_invoke_edge_fire_and_forget(...)`

Para callers que queiram throughput sobre reliability OU que gerenciam
retry na própria Edge Function. Usa `pg_net.http_post` (async). Grava
uma única linha em `cron_edge_retry_attempts` com `meta.mode='async'`.

### 3.4 Wrappers por-job

Cada job tem um wrapper dedicado que combina o `cron_run_state` lifecycle
(L12-03) com o retry (L06-05):

- `fn_invoke_auto_topup_cron()` — sem advisory-lock (1x/hora, sem sobreposição).
- `fn_invoke_lifecycle_cron_safe()` — advisory-lock (sobreposição alta).
- `fn_invoke_clearing_cron_safe()` — advisory-lock (overlap improvável).
- `fn_invoke_verification_cron_safe()` — advisory-lock.
- `fn_invoke_onboarding_nudge_safe()` — advisory-lock.
- `fn_invoke_reconcile_wallets_safe()` — advisory-lock.

## 4. Cenários operacionais

### Cenário A — "auto-topup-hourly falhou, cliente reclama"

1. Abrir Supabase SQL editor.

2. Últimas 5 invocações do job:

   ```sql
   SELECT started_at,
          COUNT(*)                           AS attempts,
          MAX(http_status) FILTER (WHERE http_status BETWEEN 200 AND 299)
                                             AS success_status,
          STRING_AGG(DISTINCT http_status::text, ',' ORDER BY http_status::text)
                                             AS all_statuses,
          STRING_AGG(DISTINCT LEFT(error, 60), ' | ')
                                             AS errors
     FROM public.cron_edge_retry_attempts
    WHERE job_name = 'auto-topup-hourly'
      AND started_at > now() - interval '6 hours'
    GROUP BY date_trunc('minute', started_at)
    ORDER BY 1 DESC
    LIMIT 5;
   ```

3. Se `all_statuses = '503'` por várias janelas → incident no Supabase.
   Checar https://status.supabase.com. Se confirmado, avisar assessoria
   do cliente que next window retry vai rodar automaticamente.

4. Se `all_statuses = '500'` por várias janelas → bug na Edge Function
   `auto-topup-cron`. Logs do Supabase dashboard → `supabase functions
   logs auto-topup-cron`. Abrir ticket engenharia.

5. Se `errors LIKE '%could not translate%'` → DNS blip. Provavelmente
   já se auto-resolveu. Confirme com próxima janela.

6. NUNCA afrouxar `max_attempts` > 10 — cron roda em conexão dedicada,
   retries longos tomam slot.

### Cenário B — "cron_health_alerts tem um alerta crítico novo"

1. Identificar o job:

   ```sql
   SELECT job_name, severity, observed_at, details, acknowledged_at
     FROM public.cron_health_alerts
    WHERE severity = 'critical'
      AND acknowledged_at IS NULL
    ORDER BY observed_at DESC
    LIMIT 20;
   ```

2. Se `details.kind = 'edge_invocation_failed_after_retries'`, cruzar com
   `cron_edge_retry_attempts` (query do Cenário A) para o `details.attempts`
   e `details.last_status`.

3. Ações de mitigação (escolher UMA, não cumular):

   - **Aguardar próxima janela**: se job daily com cadência larga e
     status externo degradado, escrever no canal #ops "vou aguardar
     próxima janela" e reavaliar.
   - **Forçar re-fire manual**: `SELECT public.fn_invoke_<X>_safe();`
     como `service_role` no SQL editor. Grava nova linha em
     `cron_run_state` com `run_count += 1`.
   - **Rollback migration quebrada**: se a falha começou após um
     deploy Edge, reverter (supabase CLI `functions deploy <x>
     --ref-commit <last-good>`).

4. Ao finalizar investigação:

   ```sql
   UPDATE public.cron_health_alerts
      SET acknowledged_at = now(),
          acknowledged_by = 'oncall@omnirunner.com: mitigated via force re-fire'
    WHERE id = '<uuid>';
   ```

### Cenário C — "quero adicionar um novo cron HTTP-fired"

**NÃO USE `cron.schedule(..., 'SELECT net.http_post(...)')` inline.**
Sempre crie um wrapper `fn_invoke_<name>_safe()` que:

1. Consulta `fn_cron_should_run('<name>', max_runtime_seconds)`.
2. Adquire `pg_try_advisory_xact_lock(hashtext('cron:<name>_fire'))`.
3. `fn_cron_mark_started('<name>')`.
4. Chama `public.fn_invoke_edge_with_retry(job='<name>',
   endpoint='<edge-function>', max_attempts=3, backoff_base=5 or 10)`.
5. `fn_cron_mark_completed` ou `fn_cron_mark_failed` conforme `ok`.

Exemplo minimal:

```sql
CREATE OR REPLACE FUNCTION public.fn_invoke_my_cron_safe()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_result jsonb;
BEGIN
  IF NOT public.fn_cron_should_run('my-cron', 300) THEN RETURN; END IF;
  IF NOT pg_try_advisory_xact_lock(hashtext('cron:my_cron_fire')) THEN RETURN; END IF;
  PERFORM public.fn_cron_mark_started('my-cron');
  v_result := public.fn_invoke_edge_with_retry('my-cron', 'my-edge-fn');
  IF (v_result->>'ok')::boolean THEN
    PERFORM public.fn_cron_mark_completed('my-cron', v_result);
  ELSE
    PERFORM public.fn_cron_mark_failed('my-cron', v_result->>'last_error', v_result);
  END IF;
END;
$$;
```

### Cenário D — "ambiente local sem http extension"

Migration aplica cleanly; wrappers retornam `{ skipped: true, reason:
'http_extension_missing' }` no primeiro call. `cron_run_state` registra
`last_status = 'completed'` (tecnicamente sucesso no sentido "não falhou
no caller"). Para exercitar o retry real, configure staging ou suba
`http` extension local (`CREATE EXTENSION http`).

## 5. Métricas úteis

### Taxa de sucesso nas últimas 24h por job

```sql
SELECT job_name,
       COUNT(*) FILTER (WHERE http_status BETWEEN 200 AND 299)  AS ok,
       COUNT(*) FILTER (WHERE http_status >= 400)               AS http_err,
       COUNT(*) FILTER (WHERE http_status IS NULL)              AS no_response,
       ROUND(
         COUNT(*) FILTER (WHERE http_status BETWEEN 200 AND 299)::numeric
         / NULLIF(COUNT(*),0) * 100, 1
       ) AS success_pct
  FROM public.cron_edge_retry_attempts
 WHERE started_at > now() - interval '24 hours'
 GROUP BY job_name
 ORDER BY success_pct ASC NULLS FIRST;
```

### Attempts por run (média, p95)

```sql
WITH runs AS (
  SELECT job_name,
         date_trunc('minute', started_at) AS run_window,
         COUNT(*)                          AS attempts
    FROM public.cron_edge_retry_attempts
   WHERE started_at > now() - interval '7 days'
   GROUP BY 1, 2
)
SELECT job_name,
       ROUND(AVG(attempts), 2)                                           AS avg_attempts,
       percentile_cont(0.95) WITHIN GROUP (ORDER BY attempts)::numeric(10,2) AS p95_attempts,
       MAX(attempts)                                                     AS worst
  FROM runs
 GROUP BY job_name
 ORDER BY p95_attempts DESC;
```

Alvo: `avg_attempts < 1.05` (retries virtualmente sempre desnecessários).
Se `p95_attempts >= 2`, investigar a EF correspondente.

## 6. Rollback

Se a migration precisar ser revertida por regressão:

```sql
-- Restaurar implementação original de fn_invoke_auto_topup_cron
-- (ver 20260221000001_auto_topup_cron.sql).
-- Para as demais: cron.schedule inline com extensions.http / net.http_post
-- (ver migrations originais).

-- NÃO dropar public.cron_edge_retry_attempts — é audit trail; só parar
-- de escrever nela.
```

Preferir criar **nova** migration corretiva acima da 20260421230000
(exemplo 20260421230001_l06_05_rollback.sql) ao invés de editar a anterior.

## 7. Referências cruzadas

- **L06-04** (`cron_health_alerts`) — downstream sink de alertas críticos.
- **L12-03** (`cron_run_state`) — lifecycle state por job.
- **L12-04** (SLA monitor) — alerta `sla_breach` ao lado dos nossos.
- **L06-03** (`wallet_drift_events`) — tabela irmã de alertas, contexto
  `wallets`.
- Audit finding: `docs/audit/findings/L06-05-edge-functions-sem-retry-em-falha-de-pg.md`.
