# CUSTODY_INCIDENT_RUNBOOK

> **Trigger**: `check_custody_invariants()` retorna ≥ 1 violação.
> **Severidade**: SEV-0 / P1 — pages on-call imediatamente.
> **Tempo alvo**: ack < 5min, mitigação < 30min, root cause < 4h.
> **Linked findings**: L06-01, L02-01, L02-02 (orquestração não-atômica),
> L01-02 (withdraw atomic), L19-01 (coin_ledger partitioning).
> **Última revisão**: 2026-04-17

---

## 1. Sintoma

- Dashboard `observability/grafana/dashboards/financial-ops.json` painel
  3 ("Invariant violations") fica vermelho com valor ≥ 1.
- `/api/health` retorna `503` com `checks.invariants: "<N> violation(s)"`.
- Sentry alert P1: `health_invariant_violations > 0`.
- (raro mas possível) Burn rate alert do SLO
  `custody_invariants_correctness` (target 99.99%).

## 2. NÃO faça

- ❌ Não execute UPDATE/DELETE em `custody_accounts` ou `coin_ledger`
  diretamente sem **diagnóstico completo** (passo 4).
- ❌ Não desabilite o `check_custody_invariants()` para silenciar o
  alerta. Violation = corrupção real, esconder torna pior.
- ❌ Não faça rollback de migration sem ler `ROLLBACK_RUNBOOK.md`.

## 3. Contenção (T0 → T+10min)

Decisão: pausar emissão de coins novas?

| Cenário | Pausar? |
|---|---|
| Violation tipo `committed_negative` ou `deposited_negative` | **SIM** — kill switch (passo 3.1) |
| `deposited_less_than_committed` (1 grupo afetado) | **NÃO** — mas isolar o grupo (passo 3.2) |
| `committed_mismatch` com `diff < 100 coins` | **NÃO** — investigar primeiro |
| `committed_mismatch` com `diff > 100 coins` | **SIM** — kill switch |

### 3.1 Kill switch — pausar distribute-coins

L06-06 introduziu kill switches via `public.feature_flags` (categoria
`kill_switch`). Para PARAR a emissão, set `enabled=false`:

**Opção A — UI (preferido)**: `/platform/feature-flags` → procure
`distribute_coins.enabled` → toggle → preencha "Motivo" (obrigatório) →
Salvar. Cache invalida instantaneamente.

**Opção B — SQL (off-hours, sem UI disponível)**:
```sql
UPDATE public.feature_flags
SET enabled = false,
    reason = 'CUSTODY_INCIDENT_RUNBOOK — invariant violation detected',
    updated_by = auth.uid(),  -- NULL via service_role direto também ok
    updated_at = now()
WHERE key = 'distribute_coins.enabled' AND scope = 'global';

-- Confirma
SELECT key, enabled, reason, updated_at, updated_by
FROM public.feature_flags
WHERE key = 'distribute_coins.enabled';

-- Audit trail completo (incluindo OLD vs NEW)
SELECT changed_at, action, old_enabled, new_enabled, reason, actor_user_id, actor_role
FROM public.feature_flag_audit
WHERE flag_key = 'distribute_coins.enabled'
ORDER BY changed_at DESC LIMIT 5;
```

Route handler `/api/distribute-coins` checa via `assertSubsystemEnabled`
e retorna `503` com `Retry-After: 30` quando bloqueado. Edge function
shared lib em `supabase/functions/_shared/feature_flags.ts`.

> **Se a tabela ainda não tiver a flag** (setup novo): `isSubsystemEnabled`
> faz **fail-open** (retorna `true`). Para fail-closed temporário usar
> Vercel env var `KILL_SWITCH_DISTRIBUTE_COINS=true` + redeploy (2-3min)
> e abrir incident em paralelo.

### 3.2 Isolamento de grupo (alternativa cirúrgica)

```sql
-- Marcar grupo como suspended (assume coluna existe; senão usar tag)
UPDATE public.coaching_groups
SET status = 'suspended_custody_review'
WHERE id = '<GROUP_ID>';
```

## 4. Diagnóstico (≤ 15min)

### 4.1 Listar todas as violações
```sql
SELECT * FROM public.check_custody_invariants();
```
Capturar output em `docs/postmortems/YYYY-MM-DD-custody-incident.md`
(seção "Apêndice — evidências").

### 4.2 Para cada `group_id` afetado, comparar fontes
```sql
-- A — saldo declarado em custody_accounts
SELECT
  group_id,
  total_deposited_usd,
  total_committed,
  total_deposited_usd - total_committed AS available_declared,
  updated_at
FROM public.custody_accounts
WHERE group_id = '<GROUP_ID>';

-- B — soma de depósitos confirmados
SELECT
  group_id,
  SUM(amount_usd) FILTER (WHERE status = 'confirmed') AS deposits_sum,
  SUM(amount_usd) FILTER (WHERE status = 'pending') AS deposits_pending,
  COUNT(*) FILTER (WHERE status = 'confirmed') AS count_confirmed
FROM public.custody_deposits
WHERE group_id = '<GROUP_ID>'
GROUP BY group_id;

-- C — moedas vivas no ledger (delta_coins acumulado)
SELECT
  issuer_group_id,
  SUM(delta_coins) AS coins_alive,
  COUNT(*) AS ledger_entries,
  MIN(created_at_ms) AS first_entry,
  MAX(created_at_ms) AS last_entry
FROM public.coin_ledger
WHERE issuer_group_id = '<GROUP_ID>'
GROUP BY issuer_group_id;

-- D — withdrawals que reduziram total_deposited_usd
SELECT id, amount_usd, status, created_at, completed_at
FROM public.custody_withdrawals
WHERE group_id = '<GROUP_ID>'
ORDER BY created_at DESC LIMIT 20;
```

### 4.3 Identificar causa-raiz

| Sintoma das queries | Causa provável |
|---|---|
| `committed > deposits_sum` | Coins emitidas sem depósito (bug em `distribute-coins`, possivelmente race) |
| `coins_alive > committed` | Burn não atualizou `total_committed` (bug em `execute_burn_atomic`) |
| `coins_alive < committed` | Coins emitidas e nunca registradas no ledger (bug grave) |
| `total_deposited_usd` cresceu sem entry em `custody_deposits` | Manual UPDATE OU webhook duplicado |
| `total_committed < 0` | Bug aritmético em settle_clearing OU rollback parcial |

### 4.4 Buscar deploy/migration recente

```sql
-- Últimos commits em coin_ledger / custody (timeline)
SELECT MAX(created_at_ms) AS latest_ledger_ms FROM public.coin_ledger;

-- Último settle/burn por grupo
SELECT MAX(created_at) FROM public.clearing_events WHERE redeemer_group_id = '<GROUP_ID>';
```

Cross-reference com `git log --since='4 hours ago' -- supabase/migrations/`.

### 4.5 Verificar `coin_ledger_idempotency`
```sql
SELECT idempotency_key, created_at, COUNT(*) OVER ()
FROM public.coin_ledger_idempotency
WHERE created_at > now() - interval '4 hours'
ORDER BY created_at DESC LIMIT 50;
```
Spike sustentado de chaves duplicadas indica retry-storm que pode ter
contornado idempotência (bug grave — escalar L18-02).

## 5. Remediação por tipo de violação

### 5.1 `committed_negative` (P0)

Causa: settle ou burn subtraiu de `total_committed` mais do que deveria.

```sql
-- Identificar o último settle que poderia ter zerado:
SELECT id, clearing_event_id, debtor_group_id, coin_amount, gross_amount_usd,
       fee_amount_usd, status, settled_at
FROM public.clearing_settlements
WHERE debtor_group_id = '<GROUP_ID>' AND status = 'settled'
ORDER BY settled_at DESC LIMIT 10;
```

Reconciliação: ZERAR e RECALCULAR — NUNCA somar manualmente.

```sql
BEGIN;
  -- Trava cabeçalho
  SELECT * FROM public.custody_accounts WHERE group_id = '<GROUP_ID>' FOR UPDATE;

  -- Recalcula committed = soma de coins vivas
  UPDATE public.custody_accounts ca
  SET total_committed = COALESCE((
    SELECT SUM(delta_coins) FROM public.coin_ledger
    WHERE issuer_group_id = ca.group_id
  ), 0),
      updated_at = now()
  WHERE ca.group_id = '<GROUP_ID>';

  -- Verifica: deve ser >= 0 e <= total_deposited_usd
  SELECT * FROM public.check_custody_invariants() WHERE group_id = '<GROUP_ID>';
COMMIT;  -- ROLLBACK se invariants ainda violados
```

### 5.2 `deposited_less_than_committed` (P0)

Causa: alguém moveu `total_deposited_usd` para baixo (chargeback?
withdrawal sem decrementar committed?).

```sql
-- Buscar withdrawals recentes que possam ter rebaixado o saldo:
SELECT id, amount_usd, status, created_at, completed_at, payout_reference
FROM public.custody_withdrawals
WHERE group_id = '<GROUP_ID>' AND status IN ('processing', 'completed')
ORDER BY created_at DESC LIMIT 5;
```

Decisão:
- Withdraw legítimo + bug = recalcular `total_deposited_usd` somando
  `custody_deposits` confirmados − `custody_withdrawals` processed/completed.
- Chargeback recebido = ver `CHARGEBACK_RUNBOOK.md`.

```sql
BEGIN;
  SELECT * FROM public.custody_accounts WHERE group_id = '<GROUP_ID>' FOR UPDATE;
  UPDATE public.custody_accounts ca
  SET total_deposited_usd = COALESCE((
    SELECT SUM(amount_usd) FROM public.custody_deposits
    WHERE group_id = ca.group_id AND status = 'confirmed'
  ), 0) - COALESCE((
    SELECT SUM(amount_usd) FROM public.custody_withdrawals
    WHERE group_id = ca.group_id AND status IN ('processing', 'completed')
  ), 0),
      updated_at = now()
  WHERE ca.group_id = '<GROUP_ID>';
  SELECT * FROM public.check_custody_invariants() WHERE group_id = '<GROUP_ID>';
COMMIT;
```

### 5.3 `committed_mismatch` (P1)

Causa: drift entre `total_committed` e `coin_ledger` aggregate.

Aplicar 5.1 (recalculo do `total_committed`). Validar com:
```sql
SELECT
  ca.group_id,
  ca.total_committed AS now_committed,
  cl.coins_alive,
  ca.total_committed - cl.coins_alive AS drift_zero_expected
FROM public.custody_accounts ca
LEFT JOIN (
  SELECT issuer_group_id, SUM(delta_coins) AS coins_alive
  FROM public.coin_ledger GROUP BY issuer_group_id
) cl ON cl.issuer_group_id = ca.group_id
WHERE ca.group_id = '<GROUP_ID>';
-- drift_zero_expected DEVE ser 0
```

## 6. Validação pós-remediação

- [ ] `SELECT COUNT(*) FROM public.check_custody_invariants();` retorna 0
- [ ] `/api/health` retorna 200 com `checks.invariants: "healthy"`
- [ ] Painel 3 do dashboard volta a verde
- [ ] Smoke test: criar deposit teste 1 USD em grupo NÃO-afetado +
      withdraw teste para confirmar fluxo intacto

## 7. Restart (se kill switch foi usado)

UI: `/platform/feature-flags` → toggle `distribute_coins.enabled` para
ON → motivo "incident resolved, smoke OK".

OU SQL:
```sql
UPDATE public.feature_flags
SET enabled = true,
    reason = 'CUSTODY_INCIDENT_RUNBOOK — incident resolved, smoke OK',
    updated_by = auth.uid(),
    updated_at = now()
WHERE key = 'distribute_coins.enabled' AND scope = 'global';
```

OU Vercel env var → `KILL_SWITCH_DISTRIBUTE_COINS=false` → Redeploy.

## 8. Postmortem (T+24h)

Usar `docs/postmortems/TEMPLATE.md`. Obrigatório porque:
- Toda invariant violation é SEV-0
- Money-touching incident
- Atinge SLO `custody_invariants_correctness` (P1)

Action items mínimos a considerar:
- Adicionar test E2E para o cenário específico que causou o drift
- Adicionar alerta extra (e.g. spike em `coin_ledger_idempotency`)
- Considerar finding novo se gap de design (e.g. falta lock em
  fn_settle_clearing → criar `LXX-YY-clearing-race-condition.md`)

## Apêndice — queries úteis para investigação

```sql
-- Top 10 grupos por volume de coins ativas
SELECT issuer_group_id, SUM(delta_coins) AS coins_alive
FROM public.coin_ledger GROUP BY issuer_group_id
ORDER BY coins_alive DESC LIMIT 10;

-- Settlements settled hoje (cross-check com clearing_events)
SELECT s.id, s.creditor_group_id, s.debtor_group_id, s.coin_amount,
       s.gross_amount_usd, s.status, s.settled_at
FROM public.clearing_settlements s
WHERE s.settled_at > date_trunc('day', now())
ORDER BY s.settled_at DESC;

-- Idempotency keys nos últimos 30min
SELECT idempotency_key, created_at FROM public.coin_ledger_idempotency
WHERE created_at > now() - interval '30 minutes' ORDER BY created_at DESC;
```
