---
id: L03-13
audit_ref: "3.13"
lens: 3
title: "Reembolso / Estorno — Não há função reverse_burn ou refund_deposit"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "migration", "reliability", "idempotency", "audit-trail"]
files:
  - supabase/migrations/20260421130000_l03_reverse_coin_flows.sql
  - portal/src/app/api/coins/reverse/route.ts
  - portal/src/app/api/v1/coins/reverse/route.ts
  - portal/src/lib/schemas.ts
  - portal/src/lib/openapi/routes/v1-financial.ts
  - portal/public/openapi.json
  - docs/runbooks/REVERSE_COINS_RUNBOOK.md
correction_type: code+migration+process
test_required: true
tests:
  - portal/src/app/api/coins/reverse/route.test.ts
  - portal/src/app/api/v1/v1-aliases.test.ts
  - portal/src/lib/schemas.test.ts
  - tools/test_l03_13_reverse_coins.ts
linked_issues: []
linked_prs: ["0d68c74"]
owner: platform-finance
runbook: docs/runbooks/REVERSE_COINS_RUNBOOK.md
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  L03-13 fechado (PR pendente). Três funções SECURITY DEFINER substituem os
  blocos SQL manuais do CHARGEBACK_RUNBOOK §3.2:
    • reverse_coin_emission_atomic (inverte emit_coins_atomic, debita
      wallet via fn_mutate_wallet com check_violation → INSUFFICIENT_BALANCE);
    • reverse_burn_atomic (inverte execute_burn_atomic, bloqueia se settlement
      já settled inter-club → NOT_REVERSIBLE, re-commita custódia intra-clube);
    • reverse_custody_deposit_atomic (inverte confirm_custody_deposit,
      valida total_deposited >= total_committed → INVARIANT_VIOLATION).
  Idempotência forte via coin_reversal_log (kind, idempotency_key) UNIQUE.
  Endpoint único POST /api/coins/reverse (+v1 alias) com discriminated union
  sobre `kind`, kill-switch `coins.reverse.enabled`, rate-limit 10/min/actor,
  authz platform_admin apenas, audit log por reversal. withdrawal reversal já
  coberto por complete/fail_withdrawal (L02-06) — fora do escopo. Cobertura
  vitest (25 testes route + 15 schema + 1 v1-alias) + PG sandbox runner
  (tools/test_l03_13_reverse_coins.ts) com purgeOrphans hermético.
---
# [L03-13] Reembolso / Estorno — Não há função reverse_burn ou refund_deposit
> **Lente:** 3 — CFO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fixed
**Camada:** BACKEND
**Personas impactadas:** Atleta, Assessoria, Plataforma
## Achado
Grepping por `refund`, `reverse`, `chargeback` em `supabase/migrations/` não encontra funções de reversão de: (a) emissão de coins após chargeback do gateway; (b) burn (coins queimadas por engano); (c) withdrawal falha externamente.
## Risco / Impacto

Chargeback Stripe/MP deixa coins emitidas sem lastro ↔ invariante quebra. Sem função de reversão, admin precisa fazer SQL manual — erro humano catastrófico.

## Correção proposta

Criar funções:
```sql
CREATE FUNCTION reverse_custody_deposit(p_deposit_id uuid, p_reason text)
  RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  -- 1. Lock deposit, verify status='confirmed'
  -- 2. Set status='refunded'
  -- 3. UPDATE custody_accounts SET total_deposited_usd -= amount_usd (with FOR UPDATE)
  -- 4. If total_committed > total_deposited, raise exception (can't refund what's already circulating)
  -- 5. INSERT INTO audit_log
END; $$;

CREATE FUNCTION reverse_burn(p_ref_id uuid, p_reason text) ...
CREATE FUNCTION reverse_withdrawal(p_withdrawal_id uuid, p_reason text) ...
```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[3.13]`.
## Correção aplicada (2026-04-21)

A migration `supabase/migrations/20260421130000_l03_reverse_coin_flows.sql`
introduz três funções `SECURITY DEFINER` + a tabela dedicada
`coin_reversal_log` (idempotency anchor `UNIQUE (kind, idempotency_key)`)
e expande `coin_ledger_reason_check` para aceitar:
`institution_token_reverse_emission`, `institution_token_reverse_burn`
e re-adiciona `institution_switch_burn` (drive-by fix, dropada
silenciosamente pelo particionamento L19-01).

Função → inversa canônica de:

| Função nova                           | Inverte              | Bloqueios                                                                                        |
|---------------------------------------|----------------------|--------------------------------------------------------------------------------------------------|
| `reverse_coin_emission_atomic`        | `emit_coins_atomic`  | `INSUFFICIENT_BALANCE` se atleta já gastou (→ CHARGEBACK_RUNBOOK §3.3, "dívida do grupo")        |
| `reverse_burn_atomic`                 | `execute_burn_atomic`| `NOT_REVERSIBLE` se settlement já `settled` inter-club; `CUSTODY_RECOMMIT_FAILED` sem lastro     |
| `reverse_custody_deposit_atomic`      | `confirm_custody_deposit` | `INVARIANT_VIOLATION` se `total_deposited - amount < total_committed`                       |

Cada função grava (a) `coin_reversal_log` (idempotency anchor + audit
material), (b) entrada negativa/positiva em `coin_ledger` via
`fn_mutate_wallet` (L18-01 guard) e (c) `portal_audit_log` com
`reason` postmortem. Replays com mesma `idempotency_key` devolvem
`was_idempotent=true` sem re-aplicar a mutação.

API exposta em `POST /api/coins/reverse` (+ alias v1 `POST
/api/v1/coins/reverse` via `wrapV1Handler`). Shape do body é uma
discriminated union Zod `kind ∈ {emission, burn, deposit}` validada em
runtime no handler e no RPC. Guards aplicados:

- `withErrorHandler` (L17-01) → financial-route contract.
- `assertSubsystemEnabled('coins.reverse.enabled')` (L06-06) → kill-switch.
- `rateLimit` 10/min por actor (baixa frequência esperada; reversões não
  são caminho quente).
- `assertInvariantsHealthy` (L08-07) → bloqueia se sistema já drifta.
- `withIdempotency` (L18-02) → replay protection.
- Authz: `profiles.platform_role='admin'` APENAS (`admin_master` do grupo
  não pode disparar chargeback).

Withdrawal reversal (`fail_withdrawal` / `complete_withdrawal`) já havia
sido fechado por L02-06 e fica fora do escopo desta finding — seu fluxo
canônico permanece em `supabase/migrations/20260419150000_l02_withdrawal_lifecycle_completion.sql`.

Runbook operacional `docs/runbooks/REVERSE_COINS_RUNBOOK.md` substitui
os blocos SQL manuais de `CHARGEBACK_RUNBOOK §3.2`. Entradas `§3.3`
(dívida do grupo) e `§3.4` (unwind inter-club) permanecem manuais
porque exigem juízo contábil.

### pt-BR

Fechamos a lacuna que exigia SQL manual para reembolsar emissão de coins,
cancelar um burn errado ou estornar um depósito de custódia. Agora existe
uma única rota autenticada (`POST /api/coins/reverse`) que aplica a
reversão em UMA transação atômica, com idempotência forte e audit trail
estruturado. A operação é restrita a `platform_admin` e se recusa a rodar
quando o sistema já está em estado degradado.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 3 — CFO, item 3.13).
- `2026-04-21` — Fix entregue (`0d68c74`): migration + API + OpenAPI + runbook + testes.