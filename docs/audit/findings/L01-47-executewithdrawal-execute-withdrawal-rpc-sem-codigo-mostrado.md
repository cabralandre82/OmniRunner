---
id: L01-47
audit_ref: "1.47"
lens: 1
title: "executeWithdrawal — execute_withdrawal RPC sem código mostrado"
severity: safe
status: fixed
wave: 3
discovered_at: 2026-04-17
reaudited_at: 2026-04-24
tags: ["finance", "portal", "migration", "reliability", "custody"]
files:
  - "portal/src/lib/custody.ts"
  - "supabase/migrations/20260228170000_custody_gaps.sql"
  - "supabase/migrations/20260420090000_l03_provider_fee_revenue_track.sql"
  - "supabase/migrations/20260303900000_security_definer_hardening_remaining.sql"
correction_type: code
test_required: false
tests: []
linked_issues: []
linked_prs:
  - "02f9c5d"
  - "d2de1fd"
owner: unassigned
runbook: null
effort_points: 0
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: "Re-auditoria 2026-04-24: RPC robusto — FOR UPDATE, status-gated idempotency, search_path pinned, lock_timeout, service_role-only."
---
# [L01-47] executeWithdrawal — execute_withdrawal RPC sem código mostrado
> **Lente:** 1 — CISO · **Severidade:** 🟢 Safe · **Onda:** 3 · **Status:** ✅ fixed
**Camada:** BACKEND
**Personas impactadas:** —

## Achado original
`executeWithdrawal` chamada em `portal/src/lib/custody.ts:500-504` mas a implementação SQL não foi lida. Verificar: FOR UPDATE em `custody_accounts`, verificação de `status='pending'`, idempotência.

## Re-auditoria 2026-04-24

### Análise de `public.execute_withdrawal(p_withdrawal_id uuid)`
Implementação final em `supabase/migrations/20260420090000_l03_provider_fee_revenue_track.sql:168-244` (supersede a inicial em `20260228170000_custody_gaps.sql:96`).

Checklist de segurança:

| Requisito | Status | Evidência |
|---|---|---|
| `SECURITY DEFINER` + `SET search_path = public, pg_temp` | ✅ | linha 173-174 (`SECURITY DEFINER` + `SET search_path`); hardening adicional em `20260303900000_security_definer_hardening_remaining.sql` |
| `lock_timeout` para evitar starvation | ✅ | `PERFORM set_config('lock_timeout', '2s', true)` (linha 185, convenção L19-05) |
| `FOR UPDATE` em `custody_withdrawals` | ✅ | linha 187-191 |
| Guard `status = 'pending'` | ✅ | linha 190: `WHERE id = p_withdrawal_id AND status = 'pending'` |
| Idempotência | ✅ | via state-transition: 2ª chamada encontra `status='processing'` → `v_group_id IS NULL` → `RAISE EXCEPTION 'Withdrawal not found or not pending'`. Rollback deixa 'processing' intacto. |
| `FOR UPDATE` em `custody_accounts` | ✅ | linha 197-201 |
| Check de saldo disponível | ✅ | linha 203: `v_available < v_amount` → RAISE (TX rollback, withdrawal volta para 'pending' para retry manual) |
| Atomic state transition + ledger insert | ✅ | UPDATE 'processing' + INSERT `platform_revenue` (fx_spread + provider_fee) tudo em única TX |
| REVOKE/GRANT restrito | ✅ | `GRANT EXECUTE ... TO service_role` apenas (linha 415). `authenticated` **não** pode invocar. |

### Caller-side (`portal/src/lib/custody.ts:500-504`)
```ts
export async function executeWithdrawal(withdrawalId: string): Promise<void> {
  const db = createServiceClient();
  const { error } = await db.rpc("execute_withdrawal", { p_withdrawal_id: withdrawalId });
  if (error) throw new Error(error.message);
}
```

Usa `createServiceClient()` (service-role key, único role com GRANT EXECUTE). Caller pré-autoriza via route handler (admin_master only). Defense-in-depth: mesmo se o caller fosse burlado, a RPC tem todas as guards.

### Conclusão
**RPC atende todos os requisitos do achado + mais.** Nada a corrigir. Os únicos melhoramentos sugeridos são fora de escopo deste finding:
- (L01-44 — já fixed) `platform_fee_config.fee_type` aceita `'fx_spread'` e `'provider_fee'`.
- (L03-03 — já fixed) Provider fee accounting separado do fx_spread.

**Reclassificado**: severity `na` → `safe`, status `fix-pending` → `fixed`.

## Referência narrativa
Contexto completo em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.47]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.47).
- `2026-04-24` — Re-auditoria validou todos os guards (FOR UPDATE, status='pending', SECURITY DEFINER, service_role-only). Flipped para `fixed` (safe).
