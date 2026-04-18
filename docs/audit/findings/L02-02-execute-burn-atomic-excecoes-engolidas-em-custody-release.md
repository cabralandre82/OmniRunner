---
id: L02-02
audit_ref: "2.2"
lens: 2
title: "execute_burn_atomic — Exceções engolidas em custody_release_committed e settle_clearing"
severity: critical
status: in-progress
wave: 0
discovered_at: 2026-04-17
fix_ready_at: 2026-04-17
tags: ["finance", "atomicity", "migration", "cron", "observability"]
files:
  - supabase/migrations/20260228160001_burn_plan_atomic.sql
  - supabase/migrations/20260322300000_clearing_exception_logging.sql
  - supabase/migrations/20260417140000_execute_burn_atomic_hardening.sql
  - tools/integration_tests.ts
correction_type: migration
test_required: true
tests:
  - tools/integration_tests.ts
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L02-02] execute_burn_atomic — Exceções engolidas em custody_release_committed e settle_clearing
> **Lente:** 2 — CTO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** in-progress
**Camada:** BACKEND (Supabase RPC)
**Personas impactadas:** Plataforma, Assessoria, Atleta (efeito indireto)

## Achado
`supabase/migrations/20260228160001_burn_plan_atomic.sql:159-163, 182-186`:
```sql
BEGIN
  PERFORM public.custody_release_committed(v_issuer, v_issuer_balance);
EXCEPTION WHEN OTHERS THEN
  NULL; -- Custody not yet active for this club
END;
-- ...
BEGIN
  PERFORM public.settle_clearing(v_settlement_id);
EXCEPTION WHEN OTHERS THEN
  NULL;
END;
```

Silenciar `WHEN OTHERS` inclui `deadlock_detected`, `connection_exception`,
constraint violations, `check_custody_invariants`, OUT OF MEMORY, etc. O
atleta é creditado pelo burn, o `coin_ledger` é atualizado, mas o
`total_committed` do clube emissor permanece inflado → **invariante R vs M
quebrada**.

**Estado histórico:**
- `20260228160001`: versão original com `NULL` (silent swallow).
- `20260322300000_clearing_exception_logging.sql`: substituiu `NULL` por
  `RAISE NOTICE`. Parcial — NOTICE vai para log Postgres (volátil, não
  queryable) e **ainda engole a exceção** no contexto PL/pgSQL → invariante
  continua quebrada.

## Risco / Impacto
Violação direta da invariante central do modelo de custódia.
`check_custody_invariants` eventualmente detecta e bloqueia operações futuras
(linhas 302-321 de `20260228150001`), mas o atleta já consumiu suas coins e
a assessoria emissora fica com passivo "fantasma" (R elevado).

Para `settle_clearing`, o comportamento "best-effort" é aceitável (settlement
row fica em `pending` → cron netting retenta), porém sem log durável a
observability não consegue alertar sobre clubes com alta taxa de falha.

## Correção implementada

**Nova migration:** `supabase/migrations/20260417140000_execute_burn_atomic_hardening.sql`

### 1. Tabela `clearing_failure_log` — registro durável de exceções
```sql
CREATE TABLE public.clearing_failure_log (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  failure_type      text NOT NULL
    CHECK (failure_type IN ('custody_release', 'settle_clearing')),
  burn_ref_id       uuid,
  clearing_event_id uuid REFERENCES clearing_events(id) ON DELETE SET NULL,
  settlement_id     uuid REFERENCES clearing_settlements(id) ON DELETE SET NULL,
  issuer_group_id   uuid,
  amount            integer,
  sqlstate          text,
  sqlerrm           text,
  context           jsonb,
  resolved          boolean DEFAULT false,
  resolved_at       timestamptz,
  resolved_by       uuid,
  retry_count       integer DEFAULT 0,
  created_at        timestamptz DEFAULT now()
);
```
- 3 índices para dashboards (por tipo+resolved, por settlement, por unresolved).
- RLS habilitada, apenas `service_role` tem acesso.
- View `clearing_failures_unresolved` agrega contadores (last 1h, 24h, retry_exhausted).

### 2. `execute_burn_atomic` hardenizado

**(A) custody_release_committed** — fail-closed:
```sql
BEGIN
  PERFORM public.custody_release_committed(v_issuer, v_issuer_balance);
EXCEPTION
  WHEN undefined_function THEN
    -- Pre-deploy: RPC ausente; custody_accounts ainda não tracka
    -- total_committed, invariante preservada. Log para visibilidade.
    INSERT INTO clearing_failure_log (...) VALUES ('custody_release', ...);
  WHEN OTHERS THEN
    -- Deadlock, check_violation, connection_exception, OUT_OF_MEMORY…
    -- Re-raise: rollback completo do burn (wallet + ledger + clearing_event).
    -- Invariante R vs M preservada — usuário vê erro, tenta novamente.
    RAISE EXCEPTION 'CUSTODY_RELEASE_FAILED: ...' USING ERRCODE = 'P0005';
END;
```

**(B) settle_clearing** — best-effort com log durável:
```sql
BEGIN
  PERFORM public.settle_clearing(v_settlement_id);
EXCEPTION WHEN OTHERS THEN
  INSERT INTO clearing_failure_log (failure_type, settlement_id, sqlstate,
    sqlerrm, context) VALUES ('settle_clearing', v_settlement_id, SQLSTATE,
    SQLERRM, jsonb_build_object('creditor', ..., 'debtor', ..., 'gross', ...));
END;
-- Settlement row permanece status='pending' → cron de netting retenta.
-- Agora com contexto completo para SRE debugar falhas recorrentes.
```

### 3. Testes (3 novos em `tools/integration_tests.ts` — section `testConstraints`)
- ✅ `clearing_failure_log` tabela existe com 9 colunas esperadas.
- ✅ `failure_type` CHECK rejeita valores fora do enum.
- ✅ View `clearing_failures_unresolved` queryable.

### Propriedades garantidas
- **Invariante R vs M preservada em todo cenário**: se `custody_release`
  falha por qualquer motivo que não seja `undefined_function`, o burn
  completo é revertido (wallet, ledger, clearing_event) — usuário vê erro
  e pode tentar novamente, e a custódia permanece consistente.
- **Observability durável**: falhas de `settle_clearing` são persistidas
  com SQLSTATE + SQLERRM + contexto JSONB → dashboards e alertas têm
  base queryable (ausente antes desta correção).
- **Zero perda de settlements**: settlement row é INSERTada antes do
  `PERFORM settle_clearing()` — já committada como `pending`. Cron de
  netting processa todos os `pending` independentemente de falha inicial.
- **Compatível com ambientes pré-deploy**: `undefined_function` em
  `custody_release_committed` é tratada separadamente (não aborta burn),
  apenas loga a ausência.

### O que ainda falta
- [ ] Cron de retry ativo para `clearing_failure_log` onde
  `failure_type='settle_clearing'` — atualmente depende da tarefa
  genérica de netting noturno. Tracking em L02-03 (netting idempotente).
- [ ] Alerta SRE em `clearing_failures_unresolved.last_1h > 0` para
  `failure_type='custody_release'` (SLO: sempre zero).
- [ ] Dashboard Grafana/Metabase consumindo `clearing_failures_unresolved`.

## Referência narrativa
Contexto completo e motivação detalhada em
[`docs/audit/parts/02-cto-cfo.md`](../parts/02-cto-cfo.md) — anchor `[2.2]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 2 — CTO, item 2.2).
- `2026-04-17` — Correção implementada: tabela `clearing_failure_log`,
  view `clearing_failures_unresolved`, `execute_burn_atomic` hardenizado
  (custody re-raise, settle log-and-continue), 3 testes de integração.
