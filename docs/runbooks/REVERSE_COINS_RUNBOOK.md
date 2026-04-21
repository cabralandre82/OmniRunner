# REVERSE_COINS_RUNBOOK

> **Trigger**: ops precisa desfazer uma emissão, burn ou depósito de
> custódia já confirmado (chargeback do gateway, bug de UI que disparou
> duplo clique, erro de admin_master, etc.).
> **Severidade**: P2 por padrão (P1 se envolve chargeback de gateway
> em cima de coins já distribuídas — ver também `CHARGEBACK_RUNBOOK`).
> **Tempo alvo**: decisão < 2h, remediação < 24h.
> **Linked findings**: L03-13 (este runbook), L06-01, L08-07.
> **Última revisão**: 2026-04-21

---

## 0. Quando usar este runbook

Use este runbook quando precisar reverter:

1. **Emissão** (`coin_ledger.reason='institution_token_issue'`) — erro
   na distribuição, chargeback do Stripe/Asaas sobre o depósito que
   financiou a emissão, etc.
2. **Burn** (`coin_ledger.reason='institution_token_burn'`) — cliente
   usou coins por engano, bug na UI de resgate disparou burn duplicado,
   etc.
3. **Custody deposit confirmado** (`custody_deposits.status='confirmed'`)
   — chargeback direto no depósito antes de qualquer emissão, fraude
   detectada pelo compliance, etc.

Se a situação é **chargeback em cima de emissão já gasta pelo atleta**,
este runbook **não basta**: a reversão vai levantar `INSUFFICIENT_BALANCE`
e você precisa ir para `CHARGEBACK_RUNBOOK §3.3` (dívida do grupo).

Se há **settlement inter-clube já liquidado** para o burn, este runbook
também **não basta**: `reverse_burn_atomic` vai levantar `NOT_REVERSIBLE`
e você precisa ir para o unwind manual da §5 aqui.

**Reversão de withdrawal** (chargeback no cash-out) NÃO passa por esta
API — use `fail_withdrawal`/`complete_withdrawal` (L02-06).

---

## 1. Pré-checagem (5 min)

Antes de chamar qualquer endpoint:

```bash
# 1.1 Subsistema precisa estar saudável. Se drift ativo, ops resolve
#     PRIMEIRO a invariante (ver CUSTODY_INCIDENT_RUNBOOK) antes da
#     reversão — senão acumula dívida.
curl -s https://<host>/api/platform/invariants/wallets | jq .

# 1.2 Kill switch precisa estar ON:
curl -s https://<host>/api/platform/feature-flags?keys=coins.reverse.enabled
```

Se o kill switch estiver OFF: confirme por que foi desligado (#finance
no Slack) antes de reativar.

---

## 2. Emission reversal (erro de distribuição ou chargeback)

### 2.1 Identificar o ledger entry

```sql
SELECT id, user_id, delta_coins, reason, ref_id, issuer_group_id,
       created_at_ms
FROM public.coin_ledger
WHERE id = '<LEDGER_ID>';
-- Espera-se reason='institution_token_issue' e delta_coins > 0.
```

### 2.2 Confirmar que o atleta ainda tem saldo

```sql
SELECT balance_coins FROM public.wallets WHERE user_id = '<USER_ID>';
-- balance_coins precisa ser >= delta_coins do ledger acima.
-- Se menor → vá para §4.
```

### 2.3 Chamar a API

```bash
curl -X POST https://<host>/api/coins/reverse \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: rev-emi-$(date +%s)-$(uuidgen | cut -c1-8)" \
  --cookie "<platform_admin_session>" \
  -d '{
    "kind": "emission",
    "original_ledger_id": "<LEDGER_ID>",
    "reason": "Chargeback Stripe CH_123ABC. Postmortem #PR-4815."
  }'
```

Sucesso:
```json
{
  "ok": true,
  "kind": "emission",
  "reversal_id": "...",
  "reversal_ledger_id": "...",
  "athlete_user_id": "...",
  "reversed_amount": 100,
  "new_balance": 0,
  "was_idempotent": false
}
```

### 2.4 Erros esperados

| HTTP | Código                 | Causa                                                                                   | Remediação                                                                 |
|------|------------------------|-----------------------------------------------------------------------------------------|----------------------------------------------------------------------------|
| 404  | `NOT_FOUND`            | `LEDGER_NOT_FOUND` — ID não existe                                                      | Revalidar o UUID                                                           |
| 422  | `INVALID_TARGET_STATE` | reason original ≠ `institution_token_issue`                                             | Use `kind=burn` se era burn                                                |
| 422  | `INSUFFICIENT_BALANCE` | atleta já gastou as coins (burn, distribuição, etc.)                                    | Vá para `CHARGEBACK_RUNBOOK §3.3` (dívida do grupo, tratamento manual)     |
| 422  | `INVARIANT_VIOLATION`  | estado geral drifta; assertInvariantsHealthy recusou                                    | Resolver drift primeiro via `CUSTODY_INCIDENT_RUNBOOK`                     |
| 503  | `FEATURE_DISABLED`     | kill switch `coins.reverse.enabled` OFF                                                 | Verificar `/platform/feature-flags`                                        |
| 503  | `LOCK_NOT_AVAILABLE`   | `lock_timeout` — contención em `coin_ledger`/`wallets`                                  | Retry com back-off de 2s                                                   |

---

## 3. Burn reversal (burn errado)

### 3.1 Identificar o burn

```sql
SELECT id, burn_ref_id, athlete_user_id, redeemer_group_id,
       total_coins, breakdown, created_at
FROM public.clearing_events
WHERE burn_ref_id = '<BURN_REF_ID>';
```

### 3.2 Verificar settlements

```sql
SELECT id, creditor_group_id, debtor_group_id, amount_usd, status,
       settled_at
FROM public.clearing_settlements
WHERE clearing_event_id = '<EVENT_ID>';
```

- Se **todas** são `pending/insufficient/failed`: pode seguir com
  `reverse_burn_atomic`.
- Se **alguma** está `settled`: os USD já passaram entre custódias.
  Você **não pode** usar a API — vá para §5.

### 3.3 Chamar a API

```bash
curl -X POST https://<host>/api/coins/reverse \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: rev-burn-$(date +%s)-$(uuidgen | cut -c1-8)" \
  --cookie "<platform_admin_session>" \
  -d '{
    "kind": "burn",
    "burn_ref_id": "<BURN_REF_ID>",
    "reason": "Bug UI redeem duplicou. Postmortem #PR-4890."
  }'
```

### 3.4 Erros esperados

| HTTP | Código                     | Causa                                                                        | Remediação                                                       |
|------|----------------------------|------------------------------------------------------------------------------|------------------------------------------------------------------|
| 404  | `NOT_FOUND`                | `BURN_NOT_FOUND`                                                             | Revalidar `burn_ref_id`                                          |
| 422  | `NOT_REVERSIBLE`           | Um ou mais settlements já `settled`                                          | Vá para §5 (unwind manual inter-club)                            |
| 422  | `CUSTODY_RECOMMIT_FAILED`  | Lastro do grupo emissor insuficiente para re-commitar                        | Depositar lastro adicional antes de retentar                     |

---

## 4. Custody deposit reversal (chargeback direto)

### 4.1 Identificar o depósito

```sql
SELECT id, group_id, amount_usd, status, confirmed_at, gateway_payment_id
FROM public.custody_deposits
WHERE id = '<DEPOSIT_ID>';
-- Só vale para status='confirmed'.
```

### 4.2 Verificar lastro residual

```sql
SELECT total_deposited_usd, total_committed,
       total_deposited_usd - <AMOUNT> AS deposited_after,
       (total_deposited_usd - <AMOUNT>) >= total_committed AS refund_safe
FROM public.custody_accounts
WHERE group_id = '<GROUP_ID>';
```

- Se `refund_safe = true`: pode chamar a API.
- Se `refund_safe = false`: **reverta emissões primeiro** (§2), repita a
  query e só então chame a API.

### 4.3 Chamar a API

```bash
curl -X POST https://<host>/api/coins/reverse \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: rev-dep-$(date +%s)-$(uuidgen | cut -c1-8)" \
  --cookie "<platform_admin_session>" \
  -d '{
    "kind": "deposit",
    "deposit_id": "<DEPOSIT_ID>",
    "reason": "Chargeback Stripe CH_456DEF. Postmortem #PR-4815."
  }'
```

### 4.4 Erros esperados

| HTTP | Código                 | Causa                                                           | Remediação                                               |
|------|------------------------|-----------------------------------------------------------------|----------------------------------------------------------|
| 404  | `NOT_FOUND`            | `DEPOSIT_NOT_FOUND`                                             | Revalidar o UUID                                         |
| 422  | `INVALID_TARGET_STATE` | Deposit não está `confirmed` (pending/failed)                   | Use o fluxo payment-gateway-specific                     |
| 422  | `INVARIANT_VIOLATION`  | `deposited - amount < committed` — coins já emitidas            | Reverta emissões primeiro (§2), repita                   |

---

## 5. Burn com settlement já liquidado (inter-club unwind manual)

Esse caminho é RARO e requer aprovação do CFO. Cenário: burn moveu
coins do atleta → assessoria X redeemer, e parte do débito foi
compensada com assessoria Y (clearing_settlement.status='settled' =
USD já transferido entre custódias via clearing_runner).

1. **NÃO chame** `reverse_burn_atomic` — ele vai retornar 422
   `NOT_REVERSIBLE` e não há caminho por ele para cruzar essa fronteira.
2. Rodar (em transação única, revisado com CFO):
   ```sql
   BEGIN;
   -- 1. Cancelar settlements ainda pending:
   UPDATE public.clearing_settlements
   SET status = 'cancelled', settled_at = now()
   WHERE clearing_event_id = '<EVENT_ID>'
     AND status IN ('pending', 'insufficient', 'failed');

   -- 2. Para cada settlement já settled: decidir se o grupo Y devolve
   --    o USD (preferido) ou se a dívida fica registrada como
   --    institution_debt (ver docs/architecture/institution_debt.md).
   --    AMBOS os caminhos exigem INSERT em portal_audit_log com
   --    target_type='clearing_settlement' e reason detalhado.

   -- 3. Re-credita wallet do atleta (use fn_mutate_wallet — nunca
   --    UPDATE direto em wallets):
   SELECT * FROM public.fn_mutate_wallet(
     '<ATHLETE_ID>'::uuid,
     <TOTAL_COINS>,
     'institution_token_reverse_burn',
     'reverse_burn_manual:' || '<BURN_REF_ID>',
     NULL
   );

   -- 4. Audit log obrigatório:
   INSERT INTO public.portal_audit_log (actor_id, group_id, action,
     target_type, target_id, metadata)
   VALUES ('<ADMIN_ID>', '<GROUP_ID>', 'coins.reverse.burn.manual',
     'clearing_event', '<EVENT_ID>',
     jsonb_build_object(
       'reason', '<POSTMORTEM_TEXT>',
       'settlements_affected', <N>,
       'approved_by', 'CFO'
     ));
   COMMIT;
   ```
3. Anexar memo ao postmortem com (a) valor da dívida institucional
   criada, (b) cronograma de liquidação acordado com o grupo Y, (c)
   link para o PR que criou o hotfix se aplicável.

---

## 6. Pós-remediação

- [ ] Verificar `coin_reversal_log` tem UMA row para esta operação:
  ```sql
  SELECT * FROM public.coin_reversal_log
  WHERE idempotency_key = '<YOUR_KEY>';
  ```
- [ ] `portal_audit_log` tem entrada com action `coins.reverse.{kind}`.
- [ ] Rodar invariants:
  ```sql
  SELECT * FROM public.check_custody_invariants();
  SELECT * FROM public.wallet_drift_audit();
  ```
  Nenhuma linha em drift.
- [ ] Notificar o atleta (template `coins_reverted.{kind}.pt-BR` no
  Notifications workspace).
- [ ] Atualizar o ticket de suporte com `coin_reversal_log.id`.

---

## 7. Observabilidade

- Grafana dashboard `finance / reverse-coins` tem painéis para:
  - rate de reversões por `kind` (últimos 7d),
  - distribuição de `reason` (postmortem tagging),
  - erros 422 por código (triagem do SLO).
- Sentry alerta se `NOT_REVERSIBLE` dispara mais de 3x/hora
  (sugere burst de bugs UI no redeem flow).
- Audit log queryable via `/platform/audit?action=coins.reverse`.

---

## Cross-refs

- `supabase/migrations/20260421130000_l03_reverse_coin_flows.sql` — migration canônica (L03-13).
- `portal/src/app/api/coins/reverse/route.ts` — handler Next.js.
- `docs/audit/findings/L03-13-reembolso-estorno-nao-ha-funcao-reverse-burn-ou.md` — finding.
- `CHARGEBACK_RUNBOOK.md` — fluxo ponta-a-ponta do chargeback (este runbook é §3.2 substituído).
- `CUSTODY_INCIDENT_RUNBOOK.md` — triagem de drift de invariante.
- `WALLET_MUTATION_GUARD_RUNBOOK.md` — contexto do L18-01 guard usado por `fn_mutate_wallet`.
