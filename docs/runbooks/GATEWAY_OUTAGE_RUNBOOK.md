# GATEWAY_OUTAGE_RUNBOOK

> **Trigger**: Asaas/Stripe/MercadoPago API down OU error rate > 50% por
> ≥ 5min consecutivos.
> **Severidade**: P1 (degradação visível mas dinheiro existente está
> seguro).
> **Tempo alvo**: ack < 10min, mitigação < 15min.
> **Linked findings**: L06-01, L06-05 (edge functions sem retry), L06-06
> (kill switches).
> **Última revisão**: 2026-04-17

---

## 1. Sintoma

- Sentry alert: `gateway_error_rate > 0.5` na route
  `/api/billing/asaas/*` ou edges `payout-asaas`, `asaas-webhook`.
- StatusGator / Asaas status page (status.asaas.com) mostra incident.
- Ticket support: "não consigo pagar".
- Painel `financial-ops.json` panel "Withdraw availability" cai.

## 2. Diagnóstico (≤ 5min)

### 2.1 Confirmar que é gateway, não nosso código
```bash
# Asaas
curl -sS -o /dev/null -w "%{http_code} %{time_total}s\n" \
  -H "access_token: $ASAAS_PROD_API_KEY" \
  https://api.asaas.com/v3/myAccount/status

# Stripe
curl -sS -o /dev/null -w "%{http_code} %{time_total}s\n" \
  -u "$STRIPE_SECRET_KEY:" https://api.stripe.com/v1/balance
```

| Resposta | Conclusão |
|---|---|
| HTTP 5xx OU timeout > 10s | Gateway down — seguir runbook |
| HTTP 200 < 1s | Gateway OK — problema é nosso (SAIR deste runbook, abrir incident interno) |
| HTTP 401/403 | Credenciais (passo 2.2) |

### 2.2 Credenciais válidas?
```sql
-- Asaas: secret no vault
SELECT public.fn_ppc_get_api_key('<GROUP_ID>'::uuid, 'gateway_outage_diag') IS NOT NULL AS has_key;
```
Se `false` → ver L01-17 / `docs/audit/runbooks/L01-17-asaas-vault-rotation.md`.

### 2.3 Quantas operações estão sendo afetadas?
```sql
-- Edge function failures last 15min (assume L06-09 instrumentado)
SELECT route, status_code, COUNT(*) AS errors
FROM public.edge_function_metrics
WHERE created_at > now() - interval '15 minutes'
  AND status_code >= 500
GROUP BY route, status_code
ORDER BY errors DESC;
```

## 3. Mitigação (≤ 10min)

### 3.1 Habilitar kill switch para evitar fila lixo

UI (preferido): `/platform/feature-flags` → toggle `custody.deposits.enabled`
e `custody.withdrawals.enabled` para OFF, motivo "Asaas down".

SQL (off-hours):
```sql
UPDATE public.feature_flags
SET enabled = false,
    reason = 'GATEWAY_OUTAGE_RUNBOOK: Asaas down',
    updated_by = auth.uid(),
    updated_at = now()
WHERE key IN ('custody.deposits.enabled', 'custody.withdrawals.enabled')
  AND scope = 'global';

-- Confirma estado + audit
SELECT key, enabled, reason FROM public.feature_flags
WHERE key LIKE 'custody.%' OR key = 'distribute_coins.enabled';

SELECT changed_at, flag_key, action, old_enabled, new_enabled, reason
FROM public.feature_flag_audit
WHERE changed_at > now() - interval '15 minutes'
ORDER BY changed_at DESC;
```

Routes `/api/custody/withdraw` e `/api/custody/deposit` retornam 503
com `Retry-After: 60` quando flag é false.

> **Fail-open**: se a flag não existir (setup novo), `isSubsystemEnabled`
> retorna `true` por design (sistema continua operando). Para fail-closed
> imediato use Vercel env var `KILL_SWITCH_DEPOSIT_CREATE=true` +
> redeploy (2-3min) em paralelo ao incident.

### 3.2 Banner público de degradação

```sql
UPDATE public.feature_flags
SET enabled = true,
    reason = 'GATEWAY_OUTAGE_RUNBOOK: gateway down, mostrar banner público',
    updated_by = auth.uid(),
    updated_at = now()
WHERE key = 'banner.gateway_outage' AND scope = 'global';
```

Portal lê via `isFeatureEnabled('banner.gateway_outage')` e renderiza
mensagem do `metadata->>i18n_key`.

Mensagem padrão (i18n key `banner.gateway_outage_message`):
> "Estamos enfrentando intermitência no provedor de pagamentos.
> Depósitos e saques podem demorar mais que o normal. Saldo existente
> está seguro. Acompanhe em status.omnirunner.app."

### 3.3 Pausar crons que dependem do gateway

```sql
-- Lista crons que tocam Asaas/Stripe
SELECT jobid, jobname, schedule
FROM cron.job
WHERE command LIKE '%asaas%' OR command LIKE '%stripe%' OR command LIKE '%payout%';

-- Pausar (NÃO unschedule — só temporariamente)
SELECT cron.alter_job(<JOBID>, schedule => '0 0 31 2 *');  -- 31 fev = nunca
```

Anotar `<JOBID>` original para restaurar em §6.

### 3.4 Edge functions com retry escalado (se L06-05 implementado)

Verificar circuit-breaker em `supabase/functions/_shared/asaas.ts`.
Se ainda em estado `closed`, aguardar — abrirá automaticamente após N
falhas. Se já `open`, edge functions retornam 503 imediato sem chamar
Asaas (correto).

## 4. Aguardar resolução do gateway

- Subscrever updates: status.asaas.com / status.stripe.com.
- Postar em `#incidents` cada 30min com status.
- Se outage > 4h, considerar migrar emissões NOVAS para fallback
  (Stripe se Asaas down, MercadoPago se Stripe down) — só se tier
  premium do produto justifica complexidade. Para v1, **aguardar é OK**.

## 5. Restart pós-recovery

Verificar que o gateway voltou (passo 2.1) e estável por ≥ 10min antes
de:

### 5.1 Drenar fila de webhooks acumulados
```sql
-- Quantos webhooks chegaram durante outage?
SELECT COUNT(*), MIN(created_at), MAX(created_at)
FROM public.payment_webhook_events
WHERE created_at > '<OUTAGE_START_UTC>' AND processed = false;
```

Ver `WEBHOOK_BACKLOG_RUNBOOK.md` para drenagem ordenada.

### 5.2 Reabrir kill switches
UI: toggle `custody.deposits.enabled` e `custody.withdrawals.enabled`
para ON com motivo "gateway recovered, smoke OK".

SQL:
```sql
UPDATE public.feature_flags
SET enabled = true,
    reason = 'GATEWAY_OUTAGE_RUNBOOK: gateway recovered, smoke OK',
    updated_by = auth.uid(),
    updated_at = now()
WHERE key IN ('custody.deposits.enabled', 'custody.withdrawals.enabled')
  AND scope = 'global';
```

Smoke test:
```bash
# Criar deposit teste 1 BRL pelo portal staging-mirroring-prod
# Aguardar webhook → processado → deposit confirmed
```

### 5.3 Reativar crons
```sql
SELECT cron.alter_job(<JOBID>, schedule => '<ORIGINAL_SCHEDULE>');
```

### 5.4 Remover banner
```sql
UPDATE public.feature_flags
SET enabled = false,
    reason = 'GATEWAY_OUTAGE_RUNBOOK: incident resolved, hide banner',
    updated_by = auth.uid(),
    updated_at = now()
WHERE key = 'banner.gateway_outage' AND scope = 'global';
```

## 6. Validação pós-incident

- [ ] Smoke test E2E: deposit + withdraw em staging passou
- [ ] `payment_webhook_events WHERE processed=false` count → < 10
- [ ] Sentry error rate em `/api/billing/*` → baseline (< 1%)
- [ ] `check_custody_invariants()` → 0 rows
- [ ] Cron jobs voltaram a `active=true` e `last_status='succeeded'`

## 7. Postmortem

Obrigatório se:
- Outage > 1h, OU
- Algum withdraw stuck causou loss/refund manual, OU
- Algum cliente pediu reembolso por SLA quebrado

Atenção especial no postmortem:
- A automação de kill switch funcionou? (Idealmente alguém adicionou
  alerta que ATIVA o kill switch automaticamente quando error_rate > 0.7
  por 10min — backlog se ainda não existe.)

## Apêndice — referência rápida

| Provider | Status page | API health endpoint |
|---|---|---|
| Asaas | https://status.asaas.com | `GET /v3/myAccount/status` |
| Stripe | https://status.stripe.com | `GET /v1/balance` |
| MercadoPago | https://status.mercadopago.com | `GET /users/me` |

| Métrica | Threshold P1 | Onde ver |
|---|---|---|
| Gateway error rate | > 50% por 5min | Sentry / Grafana panel withdraw availability |
| Webhook delivery lag | > 10min | `MAX(now() - created_at) WHERE processed=false` |
| In-flight withdraws | > 30 | `COUNT(*) WHERE status='processing'` |
