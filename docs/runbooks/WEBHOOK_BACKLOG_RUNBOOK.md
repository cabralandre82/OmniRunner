# WEBHOOK_BACKLOG_RUNBOOK

> **Trigger**: `payment_webhook_events.processed = false` count > 100
> sustentado por > 10min OU lag entre `created_at` mais antigo e agora
> > 30min.
> **Severidade**: P1 (cada webhook não processado = depósito não
> confirmado, customer experience degradada; potencial drift contábil).
> **Tempo alvo**: ack < 15min, drenagem < 1h.
> **Linked findings**: L06-01, L06-04 (cron monitoring), L06-05 (retry).
> **Última revisão**: 2026-04-17

---

## 1. Sintoma

```sql
-- Backlog atual
SELECT
  COUNT(*)                                         AS unprocessed_count,
  MIN(created_at)                                  AS oldest_unprocessed,
  age(now(), MIN(created_at))                      AS oldest_lag,
  COUNT(*) FILTER (WHERE error_message IS NOT NULL) AS with_errors
FROM public.payment_webhook_events
WHERE processed = false;
```

- `unprocessed_count > 100` ⇒ alert P1.
- `oldest_lag > 30min` ⇒ alert P1.
- Sentry: `webhook_backlog_size > 100`.
- Customer ticket: "paguei mas o portal não atualizou".

## 2. Diagnóstico (≤ 10min)

### 2.1 É backlog NOVO ou crescente?
```sql
SELECT date_trunc('minute', created_at) AS minute,
       COUNT(*) AS arrived,
       COUNT(*) FILTER (WHERE processed) AS processed,
       COUNT(*) FILTER (WHERE NOT processed) AS unprocessed
FROM public.payment_webhook_events
WHERE created_at > now() - interval '60 minutes'
GROUP BY 1 ORDER BY 1 DESC LIMIT 30;
```

| Padrão | Causa provável |
|---|---|
| `arrived` >> `processed` em todos minutos recentes | Edge function `asaas-webhook` parou |
| `arrived` normal, `processed` zerou de repente | Cron processor parado OU bug em tipo específico |
| `arrived` spike (10x normal) | Gateway retry-storm OU evento massivo (settle batch) |

### 2.2 Edge function `asaas-webhook` está respondendo?
```bash
curl -sS -o /dev/null -w "%{http_code} %{time_total}s\n" \
  -X POST "$SUPABASE_URL/functions/v1/asaas-webhook" \
  -H "Content-Type: application/json" \
  -H "asaas-access-token: $ASAAS_WEBHOOK_TOKEN" \
  -d '{"event":"PING","payment":{"id":"runbook-probe"}}'
```
- 200 ⇒ função OK, problema é processor downstream.
- 401/403 ⇒ webhook token quebrado (ver L01-17 vault rotation).
- 5xx OU timeout ⇒ edge function down. Ver logs:
  ```bash
  supabase functions logs asaas-webhook --tail 200
  ```

### 2.3 Quais event types estão atrasados?
```sql
SELECT event_type, COUNT(*) AS pending,
       MIN(created_at) AS oldest,
       COUNT(*) FILTER (WHERE error_message IS NOT NULL) AS errored
FROM public.payment_webhook_events
WHERE processed = false
GROUP BY event_type
ORDER BY pending DESC;
```

### 2.4 Tipos com erro — qual erro?
```sql
SELECT error_message, COUNT(*) AS n,
       array_agg(id ORDER BY created_at DESC)[:3] AS sample_ids
FROM public.payment_webhook_events
WHERE processed = false AND error_message IS NOT NULL
GROUP BY error_message
ORDER BY n DESC LIMIT 20;
```

| `error_message` típico | Causa |
|---|---|
| `null value in column "group_id"` | Webhook chegou sem `externalReference` mapeado — ver `asaas_customer_map` |
| `duplicate key value violates "uq_asaas_event"` | Já processado (race) — pode marcar `processed=true` manualmente (passo 3.4) |
| `function fn_confirm_deposit does not exist` | Migration drift — ver `OS06_RELEASE_RUNBOOK.md` |
| `permission denied for table custody_deposits` | service_role grant quebrado — `GRANT ALL ON public.custody_deposits TO service_role` |

## 3. Mitigação

### 3.1 Edge function down — restart

Re-deploy:
```bash
supabase functions deploy asaas-webhook --no-verify-jwt
```

Se persiste, hotfix em outra branch + deploy. Durante esse período,
gateway continua entregando webhooks → mas eles caem no buffer interno
do Asaas (retry policy típica: 3 tentativas, exponencial até 24h).

### 3.2 Processor cron parado

```sql
-- Identifica
SELECT jobid, jobname, schedule, last_start, last_finish, last_status
FROM cron.job_run_details JOIN cron.job USING (jobid)
WHERE jobname LIKE '%webhook_processor%' OR jobname LIKE '%asaas%'
ORDER BY last_start DESC LIMIT 5;

-- Re-roda manualmente
CALL public.run_webhook_processor_batch(100);
```

Se função não existe → processor é chamado em-line pelo edge function;
ver §3.1.

### 3.3 Drenagem manual em batch

Se backlog > 500, drenar em batches pra não estourar lock contention:

```sql
DO $$
DECLARE
  v_batch_size  int := 50;
  v_processed   int;
  v_total       int := 0;
BEGIN
  LOOP
    WITH batch AS (
      SELECT id FROM public.payment_webhook_events
      WHERE processed = false AND error_message IS NULL
      ORDER BY created_at ASC
      LIMIT v_batch_size
      FOR UPDATE SKIP LOCKED
    )
    UPDATE public.payment_webhook_events e
    SET    processed_at = now()  -- placeholder, real handler abaixo
    FROM   batch
    WHERE  e.id = batch.id
    RETURNING e.id INTO v_processed;

    -- TODO: para cada id retornado, chamar processador real (handler
    -- por event_type). Ver supabase/functions/asaas-webhook/handler.ts
    -- como referência.

    GET DIAGNOSTICS v_processed = ROW_COUNT;
    v_total := v_total + v_processed;
    EXIT WHEN v_processed = 0;
    PERFORM pg_sleep(0.1);  -- breathe
  END LOOP;
  RAISE NOTICE 'Processed % rows', v_total;
END $$;
```

> **NOTA**: o template acima só MARCA como processado — não invoca o
> handler. Para drenar de verdade, invocar a edge function via CLI:
> ```bash
> ./tools/replay-webhook-events.sh --since "<OUTAGE_START>" --batch 50
> ```
> (script a criar como follow-up se ainda não existir.)

### 3.4 Marcar duplicatas como processadas

```sql
-- Eventos com mesmo asaas_event_id já têm 1 processado → marcar duplicata como processed
WITH duplicates AS (
  SELECT id FROM (
    SELECT id, asaas_event_id,
           ROW_NUMBER() OVER (PARTITION BY asaas_event_id ORDER BY created_at) AS rn
    FROM public.payment_webhook_events
    WHERE asaas_event_id IS NOT NULL
  ) t WHERE rn > 1 AND id IN (
    SELECT id FROM public.payment_webhook_events WHERE processed = false
  )
)
UPDATE public.payment_webhook_events e
SET processed = true,
    processed_at = now(),
    error_message = COALESCE(e.error_message, 'duplicate of earlier event_id; skipped via WEBHOOK_BACKLOG_RUNBOOK#3.4')
FROM duplicates d WHERE e.id = d.id;
```

### 3.5 Eventos com erro permanente — quarantena

Após análise (passo 2.4), se `error_message` indica corrupção/payload
inválido sem possibilidade de processar:

```sql
UPDATE public.payment_webhook_events
SET processed = true,
    processed_at = now(),
    error_message = COALESCE(error_message, '') || ' | quarantined manually via runbook'
WHERE id IN (<LISTA_IDS>);
```

Anotar em `docs/postmortems/...` para revisão posterior. NUNCA aplicar
em massa sem revisar payload de cada um.

## 4. Validação

- [ ] `payment_webhook_events WHERE processed = false` count → < 10
      (baseline)
- [ ] `payment_webhook_events WHERE processed = false AND error_message IS NULL` → 0
- [ ] Webhook test: `POST /functions/v1/asaas-webhook` com payload
      `PING` retorna 200 < 1s
- [ ] `check_custody_invariants()` → 0 rows (já que depósitos foram
      confirmados, saldo está consistente)
- [ ] Painel "Webhook success rate" do dashboard → > 99%

## 5. Comunicação

- Se backlog > 200 OU tempo > 1h: postar em `#incidents` com timestamp
  início e estimativa.
- Customer-facing apenas se causou demora visível em depósito (> 15min):
  notificação in-app discreta ("Depósito #X confirmado.").

## 6. Postmortem

Obrigatório se:
- Backlog > 500 OU oldest_lag > 4h
- Algum depósito ficou > 1h não-confirmado E user reclamou
- Bug em handler causou quarantena de > 10 eventos

## 7. Prevenção (action items recorrentes)

- Alerta `webhook_backlog > 50 sustentado 5min` em Sentry/Grafana
  (atualmente threshold sugerido: 100 por 10min — verificar se calibrou
  após este incident).
- Considerar mover handler para queue dedicada (e.g.
  `pg_cron` + `pg_dequeue` ou Inngest) — ver finding novo se ainda não
  existir.
- Idempotency unit test no `asaas-webhook` handler.

## Apêndice — replay seguro de evento individual

```bash
# Pega payload do evento e re-envia como se fosse novo
psql -At -c "SELECT payload::text FROM public.payment_webhook_events WHERE id = '<EVENT_ID>'" \
  | curl -sS -X POST "$SUPABASE_URL/functions/v1/asaas-webhook" \
      -H "Content-Type: application/json" \
      -H "asaas-access-token: $ASAAS_WEBHOOK_TOKEN" \
      -H "x-replay-of: <EVENT_ID>" \
      -d @-

# Confirmar processamento
psql -c "SELECT id, processed, processed_at, error_message FROM public.payment_webhook_events WHERE id = '<EVENT_ID>'"
```
