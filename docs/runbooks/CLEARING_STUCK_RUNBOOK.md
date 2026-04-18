# CLEARING_STUCK_RUNBOOK

> **Trigger**: `clearing_settlements.status = 'pending'` há > 24h.
> **Severidade**: P1 (no immediate money loss, mas erode confiança e
> contabilidade fica suja).
> **Tempo alvo**: ack < 30min, mitigação < 2h.
> **Linked findings**: L06-01, L02-02 (settle exception swallow), L19-05.
> **Última revisão**: 2026-04-17

---

## 1. Sintoma

- Query monitor (cron sugerido em L06-04 / L20-01):
  ```sql
  SELECT COUNT(*) FROM public.clearing_settlements
  WHERE status = 'pending' AND created_at < now() - interval '24 hours';
  ```
  Retorna ≥ 1.
- Sentry alert: `clearing_stuck_pending_24h > 0`.
- Slack `#finance-ops` ping de admin_master afetado.

## 2. Diagnóstico (≤ 15min)

### 2.1 Quantos e quais settlements?
```sql
SELECT s.id, s.clearing_event_id,
       s.creditor_group_id, s.debtor_group_id,
       s.coin_amount, s.gross_amount_usd, s.fee_amount_usd, s.net_amount_usd,
       s.created_at, age(now(), s.created_at) AS stuck_for
FROM public.clearing_settlements s
WHERE s.status = 'pending'
  AND s.created_at < now() - interval '24 hours'
ORDER BY s.created_at ASC;  -- mais antigos primeiro
```

### 2.2 Saldo do devedor permite settle?
Para cada `<DEBTOR_GROUP_ID>`:
```sql
SELECT ca.group_id,
       ca.total_deposited_usd,
       ca.total_committed,
       ca.total_deposited_usd - ca.total_committed AS available_usd,
       (SELECT SUM(net_amount_usd) FROM public.clearing_settlements
        WHERE debtor_group_id = ca.group_id AND status = 'pending') AS pending_total
FROM public.custody_accounts ca
WHERE ca.group_id = '<DEBTOR_GROUP_ID>';
```

| Resultado | Causa |
|---|---|
| `available_usd >= pending_total` | Bug em settle/cron — deveria ter rodado |
| `available_usd < pending_total` | Devedor sem saldo — esperar deposit OU mark `insufficient` |
| `available_usd < 0` | INVARIANT VIOLATION — abrir CUSTODY_INCIDENT_RUNBOOK |

### 2.3 Cron `settle_clearing` está rodando?
```sql
-- Buscar última execução do job (assume L06-04 instrumentou)
SELECT jobname, jobid, schedule, last_start, last_finish, last_status
FROM cron.job_run_details
JOIN cron.job USING (jobid)
WHERE jobname LIKE '%settle_clearing%' OR jobname LIKE '%clearing%'
ORDER BY last_start DESC LIMIT 5;
```
Se `last_status='failed'` repetido → ler `clearing_failure_log`:
```sql
SELECT id, settlement_id, attempted_at, error_code, error_message
FROM public.clearing_failure_log
WHERE attempted_at > now() - interval '48 hours'
ORDER BY attempted_at DESC LIMIT 30;
```

## 3. Remediação

### 3.1 Caso A — devedor TEM saldo, settle deveria ter rodado

Re-executar manualmente:
```sql
SELECT public.settle_clearing('<SETTLEMENT_ID>'::uuid);
-- Verifica
SELECT id, status, settled_at FROM public.clearing_settlements
WHERE id = '<SETTLEMENT_ID>';
```

Se sucesso (`status='settled'`), buscar próximos pending no FIFO:
```sql
SELECT id FROM public.clearing_settlements
WHERE status = 'pending' AND created_at < now() - interval '24 hours'
ORDER BY created_at ASC LIMIT 50;
```
Iterar (loop bash ou SQL DO block) chamando `settle_clearing` em cada.

### 3.2 Caso B — devedor SEM saldo (`insufficient`)

Conforme contrato (TBD via L09-03 / clearing policy doc), 2 opções:

**Opção 1 — aguardar deposit (default 7 dias)**
```sql
UPDATE public.clearing_settlements
SET status = 'pending'  -- mantém; só anota
-- (idealmente adicionar coluna last_attempted_at — backlog L06-04)
WHERE id = '<SETTLEMENT_ID>';
```

**Opção 2 — mark insufficient + escalar**
```sql
UPDATE public.clearing_settlements
SET status = 'insufficient'
WHERE id = '<SETTLEMENT_ID>' AND status = 'pending';

-- Notificar admin_master do devedor (manual via portal por enquanto)
SELECT id, name, contact_email FROM public.coaching_groups
WHERE id = '<DEBTOR_GROUP_ID>';
```

### 3.3 Caso C — bug em settle_clearing (failure log enche)

Pausar o cron (evitar retry-storm):
```sql
SELECT cron.unschedule('settle_clearing_hourly');
-- Reschedule depois do hotfix
```

Reproduzir localmente:
```bash
# Capturar payload exato
psql -c "SELECT jsonb_pretty(to_jsonb(s.*)) FROM public.clearing_settlements s WHERE id = '<SETTLEMENT_ID>';"
```

Aplicar fix (provavelmente em migration nova) — ver `OS06_RELEASE_RUNBOOK.md`.

Após hotfix, replay manual + reagendar cron:
```sql
SELECT cron.schedule(
  'settle_clearing_hourly',
  '0 * * * *',
  $$ CALL public.run_settle_clearing_batch(50); $$
);
```

## 4. Validação

- [ ] `clearing_settlements WHERE status='pending' AND created_at < now() - '24 hours'` → 0
- [ ] `clearing_failure_log` últimos 60min → 0 entradas novas
- [ ] `check_custody_invariants()` → 0 rows
- [ ] Painel "Queue backlog" do dashboard volta a verde

## 5. Comunicação

- Se ≤ 5 settlements afetados → silent fix.
- Se > 5 OU > 24h sem update → email para admin_master de cada
  creditor/debtor: "Identificamos atraso em settlement <ID> entre <X>
  e <Y>. Já está sendo processado. Acompanhamento em
  <portal/finance/settlements>."
- Se > 50 → status page público.

## 6. Postmortem

Obrigatório se:
- Mais de 10 settlements afetados, OU
- Bug em código/cron (não saldo insuficiente), OU
- Repetição (segundo incident em 30 dias).

Template: `docs/postmortems/TEMPLATE.md`.

## Apêndice — métricas a observar pós-incident

```sql
-- Tempo médio pending → settled (últimos 30d)
SELECT
  percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (settled_at - created_at))) AS p50_seconds,
  percentile_cont(0.95) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (settled_at - created_at))) AS p95_seconds,
  COUNT(*) AS settled_count
FROM public.clearing_settlements
WHERE status = 'settled' AND settled_at > now() - interval '30 days';
-- p95 deve ficar < 7200s (2h). Se subir, abrir L06-04 follow-up.
```
