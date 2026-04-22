# DISPUTE_CHARGEBACK_RUNBOOK

> **Trigger**: chegou um webhook de disputa/refund/chargeback
> (Stripe `charge.dispute.*` / `charge.refunded`; MercadoPago
> `payment.refunded` / `payment.charged_back`) que o receiver
> `/api/custody/webhook` roteou para `fn_handle_custody_dispute_atomic`
> e abriu um caso em `custody_dispute_cases`. Ops precisa triar,
> resolver ou escalar.
> **Severidade**: P2 para casos `RESOLVED_REVERSED` (já fechados
> sozinhos); **P1** para `ESCALATED_CFO` (coins já gastas — dinheiro em
> risco). **P3** para `DEPOSIT_NOT_FOUND` / `DISMISSED`.
> **Tempo alvo**: triagem da fila < 4h; resolução de ESCALATED_CFO
> < 72h (antes da janela Stripe de contestar o chargeback fechar).
> **Linked findings**: L03-20 (este runbook), L03-13
> (`REVERSE_COINS_RUNBOOK`), L03-19 (`CHARGEBACK_RUNBOOK`).
> **Última revisão**: 2026-04-21

---

## 0. Escopo de gateways

| Gateway     | Dirige `custody_deposits`? | Webhook path                         |
| ----------- | -------------------------- | ------------------------------------ |
| Stripe      | ✅ sim                     | `POST /api/custody/webhook`          |
| MercadoPago | ✅ sim                     | `POST /api/custody/webhook`          |
| Asaas       | ❌ não (só subscriptions)  | `supabase/functions/asaas-webhook`   |

Para Asaas, `PAYMENT_REFUNDED` apenas transiciona
`coaching_subscriptions.status='cancelled'` — não há custody a desfazer,
portanto este runbook NÃO se aplica. Se/quando Asaas vier a alimentar
`custody_deposits`, a mesma RPC `fn_handle_custody_dispute_atomic`
aceita `gateway='asaas'` e o fluxo abaixo passa a valer.

---

## 1. Estados de `custody_dispute_cases`

```
            ┌─── reverse OK ───► RESOLVED_REVERSED  (auto-fechado)
            │
OPEN ──────┤─── P0008 ────────► ESCALATED_CFO       ◄── sua atenção aqui
            │
            └─── deposit≠confirmed ────► DISMISSED   (auto-fechado)

 (sem deposit)                   ────► DEPOSIT_NOT_FOUND  (auto-fechado)
```

| state               | ação requerida                                                                 |
| ------------------- | ------------------------------------------------------------------------------ |
| `OPEN`              | anormal — só acontece se um worker async existir; hoje = bug, abrir incidente  |
| `RESOLVED_REVERSED` | nenhuma (arquivar; só confirmar que Stripe recebeu o evidence que enviamos)    |
| `ESCALATED_CFO`     | **§3** (dívida-do-grupo) — **P1**                                              |
| `DEPOSIT_NOT_FOUND` | investigar (§4) — geralmente ruído, mas pode sinalizar webhook crossover       |
| `DISMISSED`         | nenhuma (deposit já estava `refunded`/`pending`/`failed`)                      |

---

## 2. Pré-checagem (5 min)

```bash
# 2.1 Subsistema saudável?
curl -s https://<host>/api/platform/invariants/wallets | jq .

# 2.2 Fila aberta?
psql $DATABASE_URL -c "
  SELECT state, COUNT(*) FROM public.custody_dispute_cases
   WHERE state IN ('OPEN','ESCALATED_CFO')
   GROUP BY state;
"
```

Ideal: 0 linhas. Qualquer `ESCALATED_CFO` é P1 — pular para §3.

---

## 3. Resolver `ESCALATED_CFO` (P1) — dívida-do-grupo

`reverse_custody_deposit_atomic` recusou porque
`total_deposited - amount < total_committed` — o grupo já emitiu coins
lastreadas por esse depósito E atletas gastaram. A restituição do
dinheiro ao cliente é inevitável (Stripe já processou); a pergunta é
**quem absorve o prejuízo**.

### 3.1 Levantar contexto

```sql
SELECT c.id AS case_id, c.gateway, c.gateway_event_id, c.amount_usd,
       c.reason_code, c.kind, c.deposit_id, c.group_id,
       cd.payment_reference, cd.coins_equivalent, cd.created_at,
       ca.total_deposited_usd, ca.total_committed
  FROM public.custody_dispute_cases c
  JOIN public.custody_deposits cd ON cd.id = c.deposit_id
  JOIN public.custody_accounts ca ON ca.group_id = c.group_id
 WHERE c.id = '<CASE_ID>';
```

### 3.2 Identificar as emissões lastreadas nesse depósito

```sql
-- Coin ledger entries do grupo desde a data do depósito
SELECT cl.id, cl.user_id, cl.delta_coins, cl.reason, cl.ref_id, cl.created_at_ms
  FROM public.coin_ledger cl
 WHERE cl.issuer_group_id = '<GROUP_ID>'
   AND cl.reason = 'institution_token_issue'
   AND cl.created_at_ms >= (SELECT extract(epoch from created_at)*1000
                              FROM public.custody_deposits
                             WHERE id = '<DEPOSIT_ID>')
 ORDER BY cl.created_at_ms;
```

### 3.3 Decidir a rota

Três caminhos, em ordem de preferência:

1. **Reversão parcial** — se alguns atletas ainda têm o saldo:
   chame `reverse_coin_emission_atomic` para esses ledger IDs
   (via `REVERSE_COINS_RUNBOOK §2`). Cada reversão bem-sucedida solta
   custódia committed → pode permitir a reversão do depósito depois.

2. **Dívida do grupo + compensação futura** — assessoria concorda em
   cobrir o prejuízo a partir do próximo depósito. Atualize o caso:

   ```sql
   UPDATE public.custody_dispute_cases
      SET state           = 'ESCALATED_CFO',   -- mantém estado
          resolution_note = format('debt-of-group: %s USD pending compensation', amount_usd),
          resolved_by     = '<CFO_USER_UUID>',
          resolved_at     = now()
    WHERE id = '<CASE_ID>';
   ```

   Registre em `ACCOUNTS_RECEIVABLE` (ver `CHARGEBACK_RUNBOOK §3.3`).

3. **Prejuízo da plataforma** — quando o grupo não tem capacidade /
   bloqueio de risco / compliance sinaliza fraude do próprio grupo.
   Mesma SQL do (2), `resolution_note='platform_absorbed'`.

Em todos os casos escreva também uma linha de auditoria:

```sql
INSERT INTO public.portal_audit_log
  (actor_id, group_id, action, target_type, target_id, metadata)
VALUES
  ('<CFO_USER_UUID>', '<GROUP_ID>',
   'custody.dispute.cfo_resolution', 'custody_dispute_case',
   '<CASE_ID>',
   jsonb_build_object('route', 'debt_of_group', 'amount_usd', 100.00, 'note', '...'));
```

---

## 4. Investigar `DEPOSIT_NOT_FOUND`

Normalmente ruído — ex: chargeback de uma venda que nunca virou
custody_deposit (compra direta de merchandise, teste manual, etc.).

```sql
SELECT id, gateway_event_id, gateway_dispute_ref, raw_event->'type',
       created_at
  FROM public.custody_dispute_cases
 WHERE state = 'DEPOSIT_NOT_FOUND'
 ORDER BY created_at DESC
 LIMIT 50;
```

Sinais de problema **real** a investigar:

- `gateway_event_id` tem prefixo esperado de custody (ex. Stripe
  `payment_intent.succeeded` antes tinha `pi_...` matching — se agora
  tem `pi_...` sem deposit, houve race ou o receiver antigo não persistiu).
- `amount_usd` alto (>$500) — justifica 10 min de forensics.

Se investigação confirma que é ruído: deixar o caso como `DEPOSIT_NOT_FOUND`
(já é terminal). Nenhuma ação.

---

## 5. Replay seguro / reprocessamento manual

Webhooks são idempotentes via UNIQUE `(gateway, gateway_event_id)`.
Para reprocessar intencionalmente (ex. após corrigir um bug que
causou `DEPOSIT_NOT_FOUND` espúrio), **use um event_id novo** OU
delete a linha existente (perde a trilha de auditoria — só faça com
aprovação do CFO):

```sql
-- Opção A: sintetizar um novo event_id (preferido)
SELECT * FROM public.fn_handle_custody_dispute_atomic(
  p_gateway             => 'stripe',
  p_gateway_event_id    => 'manual_replay_' || gen_random_uuid()::text,
  p_gateway_dispute_ref => '<original_du_or_re_id>',
  p_payment_reference   => '<pi_…>',
  p_kind                => 'chargeback',
  p_reason_code         => 'manual_replay_l03_20',
  p_raw_event           => jsonb_build_object('note','manual replay after bugfix')
);
```

---

## 6. Monitoramento e alertas

### 6.1 Painel `/platform/disputes` (read-only)

Lista `custody_dispute_cases WHERE state IN ('OPEN','ESCALATED_CFO')`
com filtros por gateway/kind/amount — serve como bandeja da fila.

### 6.2 Métricas emitidas pelo webhook

```
custody.webhook.dispute{gateway, kind, outcome}
custody.webhook.unsupported{gateway}
custody.webhook.error{gateway, reason=dispute|dispute_rpc_missing}
```

SLOs sugeridos:

- `custody.webhook.dispute{outcome=escalated}` → alerta em 1 (crítico).
- `custody.webhook.error{reason=dispute}` > 0 em 5 min → alerta.
- `custody.webhook.unsupported` crescendo consistentemente → revisitar
  o classificador (`classifyEvent`) para incluir novos event types.

### 6.3 Auditoria

Toda resolução gera `portal_audit_log` entries com ações:

- `custody.dispute.reversed` — auto-reverso funcionou.
- `custody.dispute.escalated_cfo` — P0008 capturada, CFO acionado.
- `custody.dispute.deposit_not_found` — sem deposit.
- `custody.dispute.cfo_resolution` — ops resolveu manualmente (§3.3).

Query útil:

```sql
SELECT action, COUNT(*)
  FROM public.portal_audit_log
 WHERE target_type = 'custody_dispute_case'
   AND created_at > now() - interval '30 days'
 GROUP BY action;
```

---

## 7. Troubleshooting

### Webhook retornou 500 — o gateway está tentando de novo

Por design: se `fn_handle_custody_dispute_atomic` throw (não uma
`INVARIANT_VIOLATION` — essa é capturada), o receiver devolve 500 e
Stripe/MP re-tenta. A RPC é idempotente por `(gateway, event_id)` —
o retry não cria duplicatas. Verifique logs:

```
logger.error("custody.webhook.dispute_failed", { gateway, event_id, ... })
```

Causa comum: lock timeout em `custody_deposits` concorrente com
`confirm_custody_deposit` — ignorar; o retry pega.

### Vejo `DISMISSED` com `reason_code='late_chargeback'` (custom)

Criamos `DISMISSED` quando deposit ≠ confirmed. Exemplo: o deposit
estava em `pending` (gateway adiou confirmação), veio chargeback ANTES
da confirmação. Nada a fazer — o próprio gateway já cancelou.

### Dois webhooks do mesmo gateway com `event_id` diferentes mas MESMO `payment_reference`

Cenário Stripe: `charge.dispute.created` chega, depois
`charge.dispute.funds_withdrawn` para o mesmo `du_…`. Ambos caem em
`chargeback`. O primeiro vira `RESOLVED_REVERSED`, o segundo vira
`DISMISSED` (deposit já refunded). Isso é **correto** — não há
duplicação.

---

## 8. Cross-links

- [`REVERSE_COINS_RUNBOOK.md`](REVERSE_COINS_RUNBOOK.md) — §2 (reverse emission) é a ferramenta de reversão parcial em §3.3 deste runbook.
- [`CHARGEBACK_RUNBOOK.md`](CHARGEBACK_RUNBOOK.md) — §3.3 (dívida-do-grupo) complementa o handling de `ESCALATED_CFO`.
- [`CUSTODY_INCIDENT_RUNBOOK.md`](CUSTODY_INCIDENT_RUNBOOK.md) — drift de invariantes.
- [`GATEWAY_OUTAGE_RUNBOOK.md`](GATEWAY_OUTAGE_RUNBOOK.md) — se o gateway para de mandar webhooks.
- [`IDEMPOTENCY_RUNBOOK.md`](IDEMPOTENCY_RUNBOOK.md) — contexto do
  primitivo `(gateway, event_id)` UNIQUE.
