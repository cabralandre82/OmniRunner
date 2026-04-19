# DBA — Bloat & Index Audit Runbook (L19)

> **Findings cobertos:** L19-02 (archive bloat), L19-03 (índices redundantes).
> **On-call:** platform-data-eng. **Severidade base:** P3 (degrad gradual);
> escalável a P2 se latência p95 de queries financeiras > 500ms por > 30min.

## 1. Quando acionar

Acionar este runbook quando QUALQUER um destes triggers acender:

| Trigger | Sinal | Severidade |
|---|---|---|
| Bloat em `coin_ledger` ou `sessions` > 30% dead tuples | `pg_stat_user_tables.n_dead_tup / n_live_tup > 0.30` | P2 |
| `fn_archive_old_ledger` ou `fn_archive_old_sessions` falhando há > 1 ciclo | `cron_run_state.last_status='failed'` | P2 |
| Latência p95 de `coin_ledger` queries > 500ms | Grafana `db.query.duration_ms` por `coin_ledger.*` | P2 |
| Novo índice redundante introduzido | `pg_indexes_redundant_pairs()` retorna > 0 rows | P3 |
| `coin_ledger_archive` crescendo descontrolado | `pg_total_relation_size('coin_ledger_archive') > 10GB` sem rotation | P3 |
| Disk pressure (Postgres data dir > 80%) | Cloud provider alarm | P1 |

## 2. Diagnóstico — bloat por table

```sql
-- Top 20 tabelas por dead-tuple ratio
SELECT
  schemaname || '.' || relname AS table_name,
  n_live_tup,
  n_dead_tup,
  ROUND(n_dead_tup::numeric / NULLIF(n_live_tup, 0), 3) AS dead_ratio,
  last_vacuum,
  last_autovacuum,
  pg_size_pretty(pg_total_relation_size(relid)) AS total_size
FROM pg_stat_user_tables
WHERE schemaname = 'public'
  AND n_live_tup > 1000
ORDER BY dead_ratio DESC NULLS LAST
LIMIT 20;
```

Critérios de leitura:

- `dead_ratio > 0.30` → bloat crítico, rodar `VACUUM` manual + investigar workload de DELETE.
- `last_autovacuum` antigo (> 7 dias) → autovacuum não está acompanhando; revisar `autovacuum_vacuum_scale_factor` na tabela.
- `total_size > 5GB` em tabela transacional → candidata a particionamento.

## 3. Diagnóstico — archive cron

```sql
-- Status da última execução do archive cron
SELECT name, started_at, finished_at, last_status, run_count, last_error,
       last_meta
  FROM public.cron_run_state
 WHERE name IN ('archive-old-sessions', 'archive-old-ledger', 'reconcile-wallets-daily')
 ORDER BY name;

-- Quantas partições mensais antigas ainda não foram detached
SELECT c.relname,
       pg_get_expr(c.relpartbound, c.oid)         AS partition_bound,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS size
  FROM pg_inherits i
  JOIN pg_class c   ON c.oid = i.inhrelid
  JOIN pg_class p   ON p.oid = i.inhparent
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE p.relname = 'coin_ledger'
   AND n.nspname = 'public'
   AND c.relname <> 'coin_ledger_default'
 ORDER BY c.relname;
```

Esperado em prod:

- Partições com `upper bound < (now - 12 months)` devem estar **ausentes** após `archive-old-ledger` rodar.
- `last_status='succeeded'` para todos os 3 jobs.
- Partições mensais devem ir crescendo conforme `coin_ledger_ensure_partition` é chamado mensalmente (cron `coin_ledger_ensure_partition_monthly @ 30 5 1 * *`).

## 4. Diagnóstico — índices redundantes

```sql
-- Helper criado em L19-03; retorna pares de índices duplicados.
SELECT * FROM public.pg_indexes_redundant_pairs();
```

Esperado: **0 rows**. Se retornar > 0:

1. Identificar a migration que introduziu o índice mais novo (`git log -S '<indexname>' supabase/migrations`).
2. Avaliar qual índice manter:
   - Manter o `UNIQUE` ou PK quando aplicável.
   - Manter o nome mais descritivo (`..._user_status` vs `..._user`).
3. Adicionar `DROP INDEX IF EXISTS public.<dup>;` na próxima migration de cleanup.
4. Acionar PR review com `@platform-data-eng`.

## 5. Mitigação — bloat alto em coin_ledger ou sessions

### Caso A — `coin_ledger` partitioned: bloat em partition viva

Bloat em partição mensal recente (não em retention archive):

```sql
-- Detecta a partição com bloat
SELECT relname, n_live_tup, n_dead_tup,
       ROUND(n_dead_tup::numeric / NULLIF(n_live_tup, 0), 3) AS dead_ratio
  FROM pg_stat_user_tables
 WHERE relname LIKE 'coin_ledger_p%'
 ORDER BY dead_ratio DESC NULLS LAST
 LIMIT 5;

-- Manual vacuum analyze na partição afetada
VACUUM (VERBOSE, ANALYZE) public.coin_ledger_p202604;
```

### Caso B — `sessions` bloat (não particionada)

Sessions usa chunked DELETE; bloat ocasional é esperado mas reclamado por autovacuum (scale_factor 0.05). Se autovacuum não está acompanhando:

```sql
-- Manual VACUUM (concurrent-safe; não bloqueia leituras)
VACUUM (VERBOSE, ANALYZE) public.sessions;

-- Se bloat for severo (> 50%), VACUUM FULL exige lock exclusivo;
-- usar fora de horário comercial (3-5 AM UTC) e com janela de manutenção:
-- VACUUM FULL public.sessions;
```

**Tracking task**: se bloat de sessions reaparecer mensalmente, escalar para particionar `sessions` por `start_time_ms` (mirror do trabalho L19-01 em `coin_ledger`). Wave 2 candidate.

## 6. Mitigação — archive cron falhando

### Sintoma: `cron_run_state.last_status='failed'` para `archive-old-ledger`

```sql
-- Inspeciona último erro
SELECT name, last_error, last_meta, finished_at
  FROM public.cron_run_state
 WHERE name = 'archive-old-ledger';
```

Casos típicos:

- **`lock_not_available` em DETACH PARTITION**: outra transação segura lock na partição. Identificar e cancelar:

  ```sql
  SELECT pid, usename, state, query, age(now(), query_start) AS dur
    FROM pg_stat_activity
   WHERE query LIKE '%coin_ledger_p%'
     AND state <> 'idle'
   ORDER BY query_start ASC;
  -- Cancelar com SELECT pg_cancel_backend(<pid>); se segura.
  ```

  Próximo ciclo do cron retentará automaticamente.

- **`unparseable bound`**: notificação de uma partição com formato de bound inesperado (e.g. partição manual criada fora do helper `coin_ledger_ensure_partition`). Renomear ou ajustar a partição manualmente.

### Sintoma: `cron_run_state.last_status='failed'` para `archive-old-sessions`

Causa mais provável: schema drift entre `sessions` e `sessions_archive`. Diagnóstico:

```sql
-- Comparar colunas das duas tabelas
SELECT column_name FROM information_schema.columns
  WHERE table_schema='public' AND table_name='sessions'
EXCEPT
SELECT column_name FROM information_schema.columns
  WHERE table_schema='public' AND table_name='sessions_archive';
```

Se retornar colunas, criar migration `ALTER TABLE sessions_archive ADD COLUMN IF NOT EXISTS <col> ...` espelhando o tipo/default de `sessions`. O test `sessions_archive schema is a superset of sessions` em `tools/test_l19_dba_health.ts` deveria pegar isso em CI antes de chegar em prod.

## 7. Mitigação — disk pressure

Se `pg_total_relation_size('coin_ledger_archive') > 50GB`:

1. Confirmar política de retenção do produto (legal/finance: tipicamente 7 anos para audit trail).
2. Se rows > 7 anos: bulk-export + DROP partition equivalente em `coin_ledger_archive`. Não há archiving automático do archive (by design — operator decisão).
3. Considerar mover `coin_ledger_archive` para tablespace separado (cold storage SSD/HDD).

Se `pg_total_relation_size('coin_ledger') > 50GB`:

1. Verificar se cron de archive está rodando (`SELECT * FROM cron.job WHERE jobname LIKE 'archive%'`).
2. Conferir que autovacuum não está starvado (ver §2).
3. Forçar archive manualmente:

   ```sql
   SELECT public.fn_archive_old_ledger();
   ```

## 8. Pós-mitigação — checklist

- [ ] `pg_indexes_redundant_pairs()` retorna 0 rows.
- [ ] `cron_run_state` para `archive-old-*` mostra `last_status='succeeded'`.
- [ ] `pg_stat_user_tables.n_dead_tup` para `coin_ledger`/`sessions` ≤ 30% de `n_live_tup`.
- [ ] Tests `tools/test_l19_dba_health.ts` passam.
- [ ] Postmortem se bloat alcançou trigger P2 (latência > 500ms).
- [ ] Se nova migration introduzida, rodar `tools/audit/verify.ts`.

## 9. Métricas / dashboard

Painel sugerido (Grafana):

- `pg_stat_user_tables.n_dead_tup / n_live_tup` por tabela (top 10).
- `pg_total_relation_size` série temporal para `coin_ledger`, `coin_ledger_archive`, `sessions`, `sessions_archive`.
- `cron_run_state` heatmap por `name × last_status`.
- Alert: `pg_indexes_redundant_pairs() > 0` (run via cron weekly Slack notification).

## 10. Referências

- Migrations: `supabase/migrations/20260419110000_l19_archive_via_partition_detach.sql`, `20260419110001_l19_drop_redundant_indexes.sql`.
- Findings: `docs/audit/findings/L19-02-*.md`, `L19-03-*.md`.
- L19-01 (partitioning) context: `docs/audit/parts/19-dba.md` âncora `[19.1]`.
- Tests: `tools/test_l19_dba_health.ts`.
