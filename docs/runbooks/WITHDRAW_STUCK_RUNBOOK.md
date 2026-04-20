# WITHDRAW_STUCK_RUNBOOK

> **Trigger**: `custody_withdrawals.status = 'processing'` há > 48h
> (alerta automático cron `stale-withdrawals-alert` dispara em 7d via
> L02-06).
> **Severidade**: P1 (admin_master percebe e abre ticket; risco
> reputacional alto).
> **Tempo alvo**: ack < 1h, mitigação < 4h.
> **Linked findings**: L06-01, L01-02 (withdraw atomic), L02-01,
> L02-06 (lifecycle completion), L03-03 (provider_fee revenue trail).
> **Última revisão**: 2026-04-20

---

## 1. Sintoma

- Query monitor:
  ```sql
  SELECT COUNT(*) FROM public.custody_withdrawals
  WHERE status = 'processing' AND created_at < now() - interval '48 hours';
  ```
  Retorna ≥ 1.
- Sentry alert: `withdraw_stuck_processing_48h > 0`.
- Ticket support: "saquei R$ X há 3 dias e não caiu na conta".

## 2. Diagnóstico

### 2.1 Quais withdraws stuck?
```sql
SELECT w.id, w.group_id, w.amount_usd, w.target_currency,
       w.fx_rate, w.fx_spread_usd, w.provider_fee_usd, w.net_local_amount,
       w.payout_reference, w.created_at,
       age(now(), w.created_at) AS stuck_for,
       g.name AS group_name
FROM public.custody_withdrawals w
LEFT JOIN public.coaching_groups g ON g.id = w.group_id
WHERE w.status = 'processing'
  AND w.created_at < now() - interval '48 hours'
ORDER BY w.created_at ASC;
```

### 2.2 O withdraw chegou ao gateway?

`payout_reference` é a chave de correlação com o provider (Asaas → ID
de transferência; Stripe → payout ID).

```sql
-- Asaas: buscar evento webhook que confirma transferência
SELECT id, event_type, asaas_payment_id, processed, created_at, processed_at
FROM public.payment_webhook_events
WHERE payload->>'transferReference' = '<PAYOUT_REFERENCE>'
   OR asaas_payment_id = '<PAYOUT_REFERENCE>'
ORDER BY created_at DESC LIMIT 10;
```

| Resultado | Causa |
|---|---|
| ≥ 1 webhook `event_type LIKE 'TRANSFER_%'` com `processed=true` | Webhook chegou mas não atualizou withdraw (bug processor) |
| ≥ 1 webhook com `processed=false` | Backlog — abrir WEBHOOK_BACKLOG_RUNBOOK |
| 0 webhooks | Withdraw não chegou ao gateway OU webhook nunca enviado |

### 2.3 Confirmar manualmente no painel do gateway

1. Asaas: painel.asaas.com → Transferências → buscar por
   `payout_reference`.
2. Stripe: dashboard.stripe.com → Payouts → ID.

Status no provider:
- **`completed`/`paid`**: dinheiro saiu — webhook perdido (bug); aplicar 3.1
- **`processing`/`pending`**: ainda na fila do banco — esperar (3.2)
- **`failed`/`returned`**: rejeitado pelo banco — aplicar 3.3
- **Não encontrado**: NUNCA chegou — aplicar 3.4

## 3. Remediação

### 3.0 Caminho canônico (L02-06) — endpoints de plataforma

> **Use estes endpoints sempre que o portal estiver online.** Eles
> embrulham as RPCs `complete_withdrawal` / `fail_withdrawal` (atômicas
> + idempotentes) com `withIdempotency()` (L18-02), `portal_audit_log`,
> e re-validação automática de `check_custody_invariants()`. As seções
> 3.1 / 3.3 abaixo permanecem como **fallback last-resort** quando o
> portal está fora.

**3.0.1 — Marcar como concluído** (substitui §3.1 manual):

```bash
curl -X POST "$PORTAL_URL/api/platform/custody/withdrawals/<WITHDRAW_ID>/complete" \
  -H "Authorization: Bearer $PORTAL_PLATFORM_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: $(uuidgen)" \
  -d '{
    "payout_reference": "<gateway transfer id, e.g. asaas_transfer_xyz>",
    "note": "Confirmado em painel.asaas.com — webhook perdido"
  }'
```

Respostas esperadas:
- `200 { ok: true, data: { status: "completed", was_terminal: false } }` — transição feita.
- `200 { ok: true, data: { was_terminal: true } }` — já estava completed (re-clique seguro).
- `404 NOT_FOUND` — id inexistente.
- `409 INVALID_TRANSITION` — withdrawal não está em `processing` (ex: já `cancelled`).

**3.0.2 — Marcar como falhou + estornar** (substitui §3.3 manual):

```bash
curl -X POST "$PORTAL_URL/api/platform/custody/withdrawals/<WITHDRAW_ID>/fail" \
  -H "Authorization: Bearer $PORTAL_PLATFORM_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: $(uuidgen)" \
  -d '{
    "reason": "Banco rejeitou: dados de conta inválidos"
  }'
```

O endpoint executa em uma única transação:
1. Reverte `total_deposited_usd += amount_usd` no `custody_accounts`.
2. Deleta a linha `platform_revenue` de `fee_type='fx_spread'` ligada à withdrawal.
3. Re-valida `check_custody_invariants()` para o grupo; aborta com
   `409 INVARIANT_VIOLATION` se o estorno desbalancearia a custody —
   nesse caso aplique §3.3 manual.
4. Marca a withdrawal como `failed` e prefixa `payout_reference` com
   `| reverted: <reason> @ <ts>` para forense.
5. Escreve `portal_audit_log` com `action='custody.withdrawal.fail'`.

Resposta de sucesso:
```json
{
  "ok": true,
  "data": {
    "status": "failed",
    "was_terminal": false,
    "refunded_usd": 250.00,
    "revenue_reversed_usd": 1.88
  }
}
```

> **L03-03**: a partir de 2026-04-20, `revenue_reversed_usd` inclui o
> SOMATÓRIO de `fx_spread` + `provider_fee` da retirada. O audit-log
> (`portal_audit_log.metadata`) carrega o detalhamento em
> `fx_spread_reversed_usd` e `provider_fee_reversed_usd` separados —
> use estes campos para reconciliação fiscal (provider_fee é
> pass-through, não vira NFS-e).

> ⚠️ **Antes de chamar `/complete`**: confirme no painel do gateway
> (passo 2.3) que o dinheiro saiu de fato. Marcar `completed` sem o
> banco ter pago gera ticket pior.

### 3.1 Webhook perdido — finalizar manualmente (FALLBACK)

> Use somente se o portal estiver fora ou o endpoint §3.0.1 falhar.

```sql
BEGIN;
  -- Trava o registro
  SELECT id, status FROM public.custody_withdrawals
  WHERE id = '<WITHDRAW_ID>' AND status = 'processing'
  FOR UPDATE;

  UPDATE public.custody_withdrawals
  SET status = 'completed',
      completed_at = now()
  WHERE id = '<WITHDRAW_ID>' AND status = 'processing';

  -- Audit
  INSERT INTO public.admin_audit_log (action, target_type, target_id, actor_user_id, details)
  VALUES ('withdraw_manual_complete', 'custody_withdrawal', '<WITHDRAW_ID>',
          auth.uid(),
          jsonb_build_object(
            'reason', 'webhook_lost',
            'provider_status', 'completed',
            'verified_via', 'asaas_dashboard',
            'runbook', 'WITHDRAW_STUCK_RUNBOOK#3.1'
          ));
COMMIT;
```

> ⚠️ Confirmar **antes** que o dinheiro saiu de fato (passo 2.3). Se
> marcar `completed` sem o gateway ter pago, surge ticket pior.

### 3.2 Provider ainda processando — aguardar

Criar reminder no calendário pessoal: voltar em 24h. Adicionar comentário no
ticket: "Confirmado pelo Asaas — payout #X em fila do banco. Prazo
máximo D+5. Voltarei aqui em 24h."

### 3.3 Provider rejeitou — refund interno

Quando banco devolve (ex: dados bancários inválidos), gateway marca
`failed`. **Modo preferido**: chamar `fail_withdrawal()` (L02-06 +
L03-03), que faz tudo atomicamente em uma única TX:

```sql
SELECT * FROM public.fail_withdrawal(
  '<WITHDRAW_ID>'::uuid,
  'invalid_bank_account',         -- razão (obrigatória)
  '<ACTOR_USER_ID>'::uuid          -- admin_master que está autorizando
);
```

A função:
1. Reverte `total_deposited_usd` (gross — inclui o que viraria
   `provider_fee` e o que viraria `fx_spread`);
2. **Deleta AMBAS** as linhas de `platform_revenue` ligadas ao
   withdraw (`fee_type IN ('fx_spread','provider_fee')`) — L03-03;
3. Marca o withdraw `failed` com `payout_reference` anotado;
4. Valida `check_custody_invariants()` no MESMO TX — aborta se
   quebrar;
5. Loga em `portal_audit_log` com breakdown
   (`fx_spread_reversed_usd`, `provider_fee_reversed_usd`).

> ⚠️ **Antes de L03-03 (2026-04-20)**: a função só reverteva
> `fx_spread` — o `provider_fee` ficava como receita-fantasma em
> `platform_revenue` mesmo após o refund. Withdraws falhados antes
> dessa data têm linhas órfãs; rodar a query de auditoria abaixo (§4.2)
> para identificar e reconciliar manualmente.

Fallback SQL (use só se `fail_withdrawal` falhar — ex.: invariante
quebrada antes do refund):

```sql
BEGIN;
  -- 1. Reverter saldo (execute_withdrawal subtraiu o GROSS amount_usd)
  WITH w AS (
    SELECT id, group_id, amount_usd, fx_spread_usd, provider_fee_usd
    FROM public.custody_withdrawals
    WHERE id = '<WITHDRAW_ID>' AND status = 'processing' FOR UPDATE
  )
  UPDATE public.custody_accounts ca
  SET total_deposited_usd = ca.total_deposited_usd + w.amount_usd,
      updated_at = now()
  FROM w
  WHERE ca.group_id = w.group_id;

  -- 2. Estorno de fx_spread + provider_fee (L03-03 — AMBOS)
  DELETE FROM public.platform_revenue
  WHERE source_ref_id = '<WITHDRAW_ID>'
    AND fee_type IN ('fx_spread', 'provider_fee');

  -- 3. Marca falha
  UPDATE public.custody_withdrawals
  SET status = 'failed',
      completed_at = now(),
      payout_reference = COALESCE(payout_reference, '') || ' | reverted: ' || now()::text
  WHERE id = '<WITHDRAW_ID>';

  -- Validate invariants
  SELECT * FROM public.check_custody_invariants();
COMMIT;
```

Notificar admin_master via portal.

### 3.4 Withdraw NUNCA chegou ao gateway

Causa raiz típica: edge function `payout-asaas` falhou silenciosamente
(L02-02 / L17-01). Ver logs:
```bash
supabase functions logs payout-asaas --tail 200 | grep '<WITHDRAW_ID>'
```

Re-disparar manualmente:
```bash
curl -X POST "$SUPABASE_URL/functions/v1/payout-asaas" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"withdrawal_id\":\"<WITHDRAW_ID>\",\"manual_replay\":true,\"runbook\":\"WITHDRAW_STUCK_RUNBOOK#3.4\"}"
```

Se idempotência funcionar, edge function detecta `status='processing'`
e tenta de novo no provider. Se não houver idempotência (gap a abrir),
aplicar manual: chamar API Asaas diretamente com `external_reference`
único e atualizar `payout_reference` aqui.

## 4. Validação

- [ ] `custody_withdrawals WHERE status='processing' AND created_at < now() - '48 hours'` → 0 OU itens com plano de ação documentado
- [ ] Saldo do grupo em `custody_accounts` bate com soma deposits − withdrawals (ver query 4.1 abaixo)
- [ ] `check_custody_invariants()` → 0 rows

```sql
-- 4.1 — verificação manual de balance
SELECT
  ca.group_id,
  ca.total_deposited_usd AS declared,
  COALESCE(d.sum_deposits, 0) - COALESCE(w.sum_withdrawals, 0) AS computed,
  ca.total_deposited_usd - (COALESCE(d.sum_deposits, 0) - COALESCE(w.sum_withdrawals, 0)) AS drift
FROM public.custody_accounts ca
LEFT JOIN (SELECT group_id, SUM(amount_usd) AS sum_deposits
           FROM public.custody_deposits WHERE status='confirmed'
           GROUP BY group_id) d ON d.group_id = ca.group_id
LEFT JOIN (SELECT group_id, SUM(amount_usd) AS sum_withdrawals
           FROM public.custody_withdrawals WHERE status IN ('processing','completed')
           GROUP BY group_id) w ON w.group_id = ca.group_id
WHERE ca.group_id = '<GROUP_ID>';
```

### 4.2 — Auditoria de provider_fee orphans (L03-03)

Identifica withdraws **anteriores a 2026-04-20** com `provider_fee_usd > 0`
que NÃO tiveram a linha correspondente em `platform_revenue` (o gap
contábil que L03-03 corrigiu). Use para decidir reconciliação manual:

```sql
SELECT w.id, w.group_id, w.amount_usd, w.provider_fee_usd, w.fx_spread_usd,
       w.status, w.created_at,
       (SELECT count(*) FROM public.platform_revenue r
         WHERE r.source_ref_id = w.id::text AND r.fee_type = 'provider_fee') AS pf_rows,
       (SELECT count(*) FROM public.platform_revenue r
         WHERE r.source_ref_id = w.id::text AND r.fee_type = 'fx_spread') AS fx_rows
FROM public.custody_withdrawals w
WHERE w.created_at < '2026-04-20'::timestamptz
  AND w.provider_fee_usd > 0
  AND w.status IN ('processing','completed')   -- failed já foi refundado
  AND NOT EXISTS (
    SELECT 1 FROM public.platform_revenue r
    WHERE r.source_ref_id = w.id::text AND r.fee_type = 'provider_fee'
  )
ORDER BY w.created_at;
```

**Reconciliação manual** (rodar em janela de manutenção, com CFO
copiado):
```sql
INSERT INTO public.platform_revenue
  (fee_type, amount_usd, source_ref_id, group_id, description, created_at)
SELECT 'provider_fee', w.provider_fee_usd, w.id::text, w.group_id,
       'L03-03 backfill — provider fee on legacy withdrawal '
         || w.id::text || ' (run ' || now()::text || ')',
       w.created_at
FROM public.custody_withdrawals w
WHERE w.id = ANY('{<WITHDRAW_ID_1>,<WITHDRAW_ID_2>,...}'::uuid[]);
```
Logar em `admin_audit_log` com `runbook='WITHDRAW_STUCK_RUNBOOK#4.2'` +
`L03-03 backfill`.

## 5. Comunicação ao usuário

Templates Slack para o owner do ticket:
- **3.1 (resolved)**: "Confirmado: pagamento foi efetuado em <DATA>. O
  webhook do Asaas falhou e por isso o status no portal ficou
  'processando'. Acabei de atualizar — ver agora em <link>. Desculpe pelo
  atraso."
- **3.2 (waiting)**: "Withdraw #<N> está em fila bancária no Asaas
  (prazo D+5). Vou verificar em 24h e atualizar você."
- **3.3 (rejected)**: "O banco rejeitou a transferência (motivo: <X>).
  Re-creditamos o valor na sua conta de custódia. Por favor confira os
  dados bancários e refaça o saque em <link>."

## 6. Postmortem

Obrigatório se:
- ≥ 3 withdraws stuck simultaneamente, OU
- Causa = bug em payout edge function, OU
- Re-incidência (segundo incident em 60 dias).
