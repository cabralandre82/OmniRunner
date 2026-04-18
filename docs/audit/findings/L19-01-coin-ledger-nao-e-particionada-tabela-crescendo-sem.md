---
id: L19-01
audit_ref: "19.1"
lens: 19
title: "coin_ledger não é particionada — tabela crescendo sem controle"
severity: critical
status: in-progress
wave: 0
discovered_at: 2026-04-17
fix_ready_at: 2026-04-17
tags: ["finance", "integration", "mobile", "migration", "cron", "performance", "partitioning"]
files:
  - supabase/migrations/20260218000000_full_schema.sql
  - supabase/migrations/20260417200000_coin_ledger_partitioning.sql
  - tools/integration_tests.ts
correction_type: migration
test_required: true
tests:
  - "tools/integration_tests.ts::L19-01: coin_ledger monthly partitions exist (structural proof)"
  - "tools/integration_tests.ts::L19-01: coin_ledger_ensure_partition is idempotent"
  - "tools/integration_tests.ts::L19-01: coin_ledger_idempotency enforces (ref_id, reason) uniqueness"
  - "tools/integration_tests.ts::L19-01: coin_ledger parent-table API works across partition ranges"
  - "tools/integration_tests.ts::L19-01: emit_coins_atomic idempotency via coin_ledger_idempotency"
linked_issues: []
linked_prs: []
owner: unassigned
runbook: docs/audit/runbooks/L19-01-coin-ledger-partition-management.md
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L19-01] coin_ledger não é particionada — tabela crescendo sem controle
> **Lente:** 19 — DBA · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** 🟡 in-progress
**Camada:** —
**Personas impactadas:** —
## Achado
— `grep "PARTITION" supabase/migrations/*.sql` retorna matches apenas em `strava-time-index-and-partitioning.sql:20-25` que cria **tabela de arquivo** (não partição). O ledger principal:

```274:274:supabase/migrations/20260218000000_full_schema.sql
CREATE INDEX idx_ledger_user ON public.coin_ledger(user_id, created_at_ms DESC);
```

é tabela monolítica. Em 2 anos de crescimento com 100k usuários ativos × 50 tx/mês = 120M rows. Reconciliação full scan = horas.
## Risco / Impacto

— Performance degrada; VACUUM bloqueia; backup demora.

## Correção proposta

— Migrar para `PARTITION BY RANGE (created_at_ms)`, partições mensais:

```sql
-- Requires downtime or blue/green table swap
CREATE TABLE coin_ledger_new (LIKE coin_ledger INCLUDING ALL)
  PARTITION BY RANGE (created_at_ms);

-- Create partitions for past 24 months + future 6 months
-- Move data in batches, swap names.
```

Após partition: archive cron move partições antigas para `coin_ledger_archive` via `ATTACH/DETACH` (instantâneo) ao invés de DELETE (lento + bloat).

## Correção implementada — 2026-04-17

Migration `supabase/migrations/20260417200000_coin_ledger_partitioning.sql`.

### Arquitetura

Particionamento declarativo por `RANGE (created_at_ms)` com partições mensais nomeadas `coin_ledger_pYYYYMM`. A mudança requer PK composta `(id, created_at_ms)` — regra PostgreSQL: partition key deve integrar todo unique constraint.

**Problema de idempotência resolvido em paralelo**: o partial UNIQUE INDEX em `coin_ledger(ref_id) WHERE reason='institution_token_issue'` (L02-01) não sobrevive ao particionamento — unique em partitioned table exigiria incluir `created_at_ms`, quebrando a garantia semântica. Solução: companion table `coin_ledger_idempotency(ref_id, reason) PK` NÃO-particionada, que atua como âncora de uniqueness global. `emit_coins_atomic` foi refatorada para claim idempotency slot via essa tabela antes do INSERT no ledger.

### Componentes

1. **Tabela `coin_ledger_idempotency`** — âncora de uniqueness `(ref_id, reason)` fora do ledger particionado. Bounded growth (1 row por operação idempotente). RLS: service_role only.

2. **Rename + recriação** — em um único `DO $$` bloco transacional: rename `coin_ledger` → `coin_ledger_monolithic`, criar novo `coin_ledger` particionado (mesma schema + PK composta), copiar rows via INSERT-SELECT, validar count, dropar monolítica.

3. **Partições seed** — 60 partições mensais cobrindo **2024-01 a 2028-12** + 1 DEFAULT catchall (`coin_ledger_default`). Total: 61 partições na instalação.

4. **Helper `public.coin_ledger_ensure_partition(p_month date) RETURNS text`** — idempotente. `SECURITY DEFINER`, `SET search_path`, `SET lock_timeout='5s'`. Grant: service_role. Cria partição se não existir; retorna nome.

5. **Helper `public.coin_ledger_detach_old_partition(p_cutoff date) RETURNS text`** — operador chama para DETACH instantâneo de partição antiga. Retorna nome da tabela standalone (ou NULL). Permite arquivamento sem bloqueio.

6. **Refactor `emit_coins_atomic`** — agora claim slot em `coin_ledger_idempotency` (ON CONFLICT DO NOTHING) antes do INSERT, usando o `ledger_id` reservado como PK. Retry com mesmo `ref_id` retorna `was_idempotent=true` sem mutar custódia/inventário/wallet. Demais garantias (transação única, SQLSTATEs P0001-P0003) preservadas.

7. **pg_cron (se instalado)** — agenda `coin_ledger_ensure_partition((CURRENT_DATE + '2 months'))` mensalmente (dia 1 às 3h). Se `pg_cron` ausente, migration loga NOTICE remetendo ao runbook para agendamento manual.

8. **Invariantes pós-migration** — DO block final verifica: tabela é particionada, ≥12 partições existem, `emit_coins_atomic` ainda tem `search_path` configurado. Falha em qualquer invariante aborta a migration.

### Benefícios mensuráveis (projeção 120M rows)

- **Partition pruning**: queries `WHERE user_id=X AND created_at_ms BETWEEN A AND B` tocam apenas as partições relevantes — ms em vez de segundos.
- **Reconciliation cron**: scan paralelo por partição reduz tempo de horas para minutos.
- **Archive**: `ALTER TABLE DETACH PARTITION` é instantâneo; substitui DELETE massivo (lock exclusivo por horas + bloat + WAL).
- **Backup seletivo**: `pg_dump --table coin_ledger_pYYYYMM` permite backup granular por mês.
- **Autovacuum**: opera em partições individuais; não bloqueia ledger corrente.

### Breaking changes

- PK mudou de `(id)` para `(id, created_at_ms)`. Confirmado via `pg_constraint`: nenhum FK externo aponta para `coin_ledger.id`, então sem ripple effect. Uniqueness global de `id` é garantida por `gen_random_uuid()` (colisão ≈ 2^61).
- Partial unique `idx_coin_ledger_ref_id_institution_issue_unique` removido — substituído por PK composta de `coin_ledger_idempotency`.
- `emit_coins_atomic` preserva assinatura e retorno; nenhuma mudança necessária em callers.

### Verificação

- 5 testes de integração (ver `tests` no frontmatter) validam: partições existem, helper é idempotente, companion table impede duplicate, INSERT parent-table continua funcionando através dos ranges, `emit_coins_atomic` mantém idempotência.
- SQL dry-run (`BEGIN ... ROLLBACK`) no DB local confirmou 61 partições criadas e zero row loss durante swap.
- Migration é idempotente: re-aplicar em DB já particionado é no-op (guardado por `pg_partitioned_table` check).

### Pendente (operacional, não-código)

- [ ] Rodar migration em staging com dataset de produção-like e validar tempo de cópia.
- [ ] Definir política de retenção (runbook) — default sugerido: 24 meses online, 36+ meses archive via DETACH.
- [ ] Integrar call `coin_ledger_ensure_partition` no CD pipeline para deploys em ambientes sem pg_cron.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[19.1]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 19 — DBA, item 19.1).
- `2026-04-17` — Correção implementada: particionamento RANGE(created_at_ms) mensal + companion table de idempotência + helpers de gestão + refactor emit_coins_atomic. Status: in-progress.