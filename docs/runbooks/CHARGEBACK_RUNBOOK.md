# CHARGEBACK_RUNBOOK

> **Trigger**: Asaas/Stripe abre dispute em depósito já creditado
> (`payment_webhook_events.event_type LIKE '%CHARGEBACK%'` OU
> `%DISPUTE%` OU `%REFUND_REQUEST%`).
> **Severidade**: P1 (loss real se moeda já foi distribuída).
> **Tempo alvo**: ack < 4h, resposta jurídica < 24h, prazo legal Asaas
> 7 dias / Stripe 21 dias.
> **Linked findings**: L06-01, L01-03 (distribute-coins), L09-04
> (fiscal receipts).
> **Última revisão**: 2026-04-17

---

## 1. Sintoma

- Webhook recebido:
  ```sql
  SELECT id, asaas_payment_id, event_type, payload->>'reason' AS reason,
         payload->>'amount' AS amount, created_at
  FROM public.payment_webhook_events
  WHERE event_type LIKE '%CHARGEBACK%'
     OR event_type LIKE '%DISPUTE%'
     OR event_type LIKE '%REFUND_REQUEST%'
  ORDER BY created_at DESC LIMIT 20;
  ```
- Email do gateway: "Dispute filed for transaction #X".
- Sentry alert: `chargeback_received`.

## 2. Diagnóstico (≤ 1h)

### 2.1 Localizar o depósito original

```sql
WITH e AS (
  SELECT id, asaas_payment_id, group_id, payload, created_at
  FROM public.payment_webhook_events
  WHERE id = '<WEBHOOK_EVENT_ID>'
)
SELECT
  d.id            AS deposit_id,
  d.group_id,
  d.amount_usd,
  d.status,
  d.created_at    AS deposit_at,
  d.confirmed_at,
  e.created_at    AS chargeback_received_at,
  age(e.created_at, d.confirmed_at) AS time_since_confirmation
FROM e
JOIN public.custody_deposits d
  ON d.gateway_payment_id = e.asaas_payment_id
     OR d.id::text = e.payload->>'externalReference';
```

### 2.2 As coins do depósito já foram distribuídas?

```sql
-- Coins emitidas com este deposit como referência
SELECT cl.id, cl.user_id, cl.delta_coins, cl.reason, cl.created_at_ms,
       to_timestamp(cl.created_at_ms / 1000.0) AS created_at_ts
FROM public.coin_ledger cl
WHERE cl.issuer_group_id = '<GROUP_ID>'
  AND cl.reason LIKE 'distribution%'
  AND cl.created_at_ms >= EXTRACT(EPOCH FROM '<DEPOSIT_AT>'::timestamptz) * 1000
ORDER BY cl.created_at_ms ASC;
```

### 2.3 Quanto dessas coins ainda está vivo (não queimado)?
```sql
SELECT
  cl.user_id,
  SUM(cl.delta_coins) AS net_balance_now
FROM public.coin_ledger cl
WHERE cl.user_id IN (<LISTA_USER_IDS_DA_2.2>)
GROUP BY cl.user_id
HAVING SUM(cl.delta_coins) > 0;
```

### 2.4 Decisão: contestar ou aceitar?

| Cenário | Decisão default |
|---|---|
| Pagamento legítimo + chargeback fraudulento | **Contestar** (passo 3.1) |
| Cartão clonado confirmado pelo banco | **Aceitar** + bloquear conta (passo 3.2) |
| Pagamento duplicado (cliente alega) | Verificar duplicação no banco; se confirmado, **aceitar refund**; senão **contestar** |
| Mais de 30 dias desde depósito | Geralmente já não há como contestar; **aceitar** |

## 3. Remediação

### 3.1 Contestar (representment)

Asaas fornece campo "evidência" no painel de disputes — tempo até deadline mostrado lá.

Coletar evidências:
- Print da factura/invoice gerada (rastrear via `payment_provider_events`)
- Logs de IP/timestamp do checkout
- Confirmação fiscal (se aplicável — L09-04)
- Histórico de uso do produto (sessões, runs, distribuições)

Submeter pelo painel Asaas/Stripe + atualizar audit log:
```sql
INSERT INTO public.admin_audit_log (action, target_type, target_id, actor_user_id, details)
VALUES ('chargeback_disputed', 'custody_deposit', '<DEPOSIT_ID>',
        auth.uid(),
        jsonb_build_object(
          'webhook_event_id', '<WEBHOOK_EVENT_ID>',
          'evidence_submitted_at', now(),
          'expected_resolution_days', 30,
          'runbook', 'CHARGEBACK_RUNBOOK#3.1'
        ));
```

NÃO reverter saldo até o gateway decidir (pode levar 30-60 dias). Marcar
deposit:
```sql
UPDATE public.custody_deposits
SET status = 'disputed'  -- assumindo enum estende; senão usar tag em metadata
WHERE id = '<DEPOSIT_ID>';
```

### 3.2 Aceitar — reverter coins + saldo

> **CRÍTICO**: ordem importa. Reverte coins primeiro (idealmente quando
> ainda estão vivas), depois saldo. Se coins já foram queimadas, aplicar
> 3.3 (debt).

Passo 1 — burn das coins emitidas (se ainda vivas):
```sql
BEGIN;
  -- Para cada user_id da query 2.3, criar ledger entry de revogação
  INSERT INTO public.coin_ledger (
    user_id, issuer_group_id, delta_coins, reason, created_at_ms,
    idempotency_key
  )
  SELECT
    user_id,
    '<GROUP_ID>'::uuid,
    -SUM(delta_coins),  -- negativo = burn
    'chargeback_revocation:' || '<DEPOSIT_ID>',
    EXTRACT(EPOCH FROM now())::bigint * 1000,
    'chargeback:' || '<DEPOSIT_ID>' || ':' || user_id::text
  FROM public.coin_ledger
  WHERE issuer_group_id = '<GROUP_ID>'
    AND reason LIKE 'distribution%' || '<DEPOSIT_ID>' || '%'
  GROUP BY user_id
  HAVING SUM(delta_coins) > 0;

  -- Não criar entry para users que já queimaram tudo (handled em 3.3)
COMMIT;
```

Passo 2 — reverter `custody_accounts.total_deposited_usd`:
```sql
BEGIN;
  SELECT * FROM public.custody_accounts WHERE group_id = '<GROUP_ID>' FOR UPDATE;

  UPDATE public.custody_accounts
  SET total_deposited_usd = total_deposited_usd - <AMOUNT_USD>,
      updated_at = now()
  WHERE group_id = '<GROUP_ID>';

  -- Recompute committed também (pois coins foram queimadas em 3.2#1):
  UPDATE public.custody_accounts ca
  SET total_committed = COALESCE((
    SELECT SUM(delta_coins) FROM public.coin_ledger
    WHERE issuer_group_id = ca.group_id
  ), 0)
  WHERE ca.group_id = '<GROUP_ID>';

  -- Mark deposit refunded
  UPDATE public.custody_deposits
  SET status = 'refunded'
  WHERE id = '<DEPOSIT_ID>';

  -- Validate
  SELECT * FROM public.check_custody_invariants() WHERE group_id = '<GROUP_ID>';
COMMIT;
```

### 3.3 Coins já queimadas — registrar dívida (group debt)

Se user já gastou as coins, não dá pra reverter sem causar saldo
negativo. Registrar a perda como custo do grupo:

```sql
INSERT INTO public.platform_revenue (fee_type, amount_usd, source_ref_id, group_id, description)
VALUES ('chargeback_loss', -<AMOUNT_USD>, '<DEPOSIT_ID>', '<GROUP_ID>',
        'Chargeback aceito sem reversão de coins (já queimadas)');
```

Adicionar ao backlog: melhorar política de hold (e.g. lock 14 dias antes
de creditar coins ao user) — abrir finding novo se ainda não existe.

### 3.4 Bloquear conta se padrão de fraude

Se for terceira recorrência do mesmo CPF/cartão:
```sql
UPDATE public.coaching_groups
SET status = 'suspended_fraud_review'
WHERE id = '<GROUP_ID>';

-- Bloquear cartão no provider (manual, painel Asaas/Stripe)
```

## 4. Validação

- [ ] `check_custody_invariants()` → 0 rows após reversão
- [ ] `custody_deposits.status = 'refunded'` (3.2) OU `'disputed'` (3.1)
- [ ] `coin_ledger` tem entry de revogação OU `platform_revenue` tem
      `chargeback_loss`
- [ ] `payment_webhook_events.processed=true` para o evento original

## 5. Comunicação

- **Admin_master do grupo**: email + ticket interno detalhando o que aconteceu, valor revertido, próximos passos. Manter tom factual.
- **User cujo saldo foi revertido (3.2)**: notificação in-app: "Coins recebidas em <DATA> foram revertidas devido a contestação de pagamento. Saldo atual: <X>."
- **Jurídico/finance** (sempre que > R$ 1000): forward por email para `legal@` + `finance@`.

## 6. Postmortem

Obrigatório se:
- ≥ 5 chargebacks no mesmo dia (possível breach OU fraud ring)
- Aceitar com loss > R$ 5.000
- Re-incidência no mesmo grupo

## Apêndice — métricas

```sql
-- Taxa de chargeback (rolling 90d)
SELECT
  COUNT(*) FILTER (WHERE event_type LIKE '%CHARGEBACK%') AS chargebacks_count,
  COUNT(*) FILTER (WHERE event_type IN ('PAYMENT_CONFIRMED', 'PAYMENT_RECEIVED')) AS confirmed_count,
  ROUND(
    100.0 * COUNT(*) FILTER (WHERE event_type LIKE '%CHARGEBACK%') /
    NULLIF(COUNT(*) FILTER (WHERE event_type IN ('PAYMENT_CONFIRMED','PAYMENT_RECEIVED')), 0),
    3
  ) AS chargeback_rate_pct
FROM public.payment_webhook_events
WHERE created_at > now() - interval '90 days';
-- Threshold gateway-level: > 1% pode levar a sanções do Asaas/Stripe.
```
