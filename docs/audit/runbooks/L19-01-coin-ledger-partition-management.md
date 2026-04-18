# Runbook: gestão de partições de `coin_ledger`

> **Finding:** [L19-01](../findings/L19-01-coin-ledger-nao-e-particionada-tabela-crescendo-sem.md)
> **Migration:** `supabase/migrations/20260417200000_coin_ledger_partitioning.sql`

## Arquitetura

`public.coin_ledger` é particionada por `RANGE (created_at_ms)` com partições mensais nomeadas `coin_ledger_pYYYYMM`. Partições seed: 2024-01 a 2028-12. Catchall: `coin_ledger_default`.

Idempotência de emissões financeiras é âncorada em `public.coin_ledger_idempotency` (tabela não-particionada, PK `(ref_id, reason)`).

## Tarefas operacionais

### 1. Garantir partição futura existe

Chamada mensal via `pg_cron` (se instalado) ou via CD pipeline. Idempotente.

```sql
SELECT public.coin_ledger_ensure_partition((CURRENT_DATE + INTERVAL '2 months')::date);
```

Criar partição específica:

```sql
SELECT public.coin_ledger_ensure_partition('2029-01-01'::date);
```

Retorna o nome da partição (`coin_ledger_p202901`). Se já existir, retorna o nome existente sem erro.

### 2. Checar partições existentes

```sql
SELECT c.relname AS partition,
       pg_get_expr(c.relpartbound, c.oid) AS range
FROM pg_inherits i
JOIN pg_class c ON c.oid = i.inhrelid
JOIN pg_class p ON p.oid = i.inhparent
WHERE p.relname = 'coin_ledger'
ORDER BY c.relname;
```

### 3. Inspecionar dados órfãos em DEFAULT

Se rows caíram em `coin_ledger_default` (fora do range 2024-2028), significa que uma partição futura está em falta ou há dados sintéticos com `created_at_ms` inválido.

```sql
SELECT count(*) AS orphan_rows,
       min(created_at_ms)::timestamp AT TIME ZONE 'UTC' AS earliest,
       max(created_at_ms)::timestamp AT TIME ZONE 'UTC' AS latest
FROM public.coin_ledger_default;
```

Para mover rows órfãs para uma partição apropriada:

```sql
-- 1. Criar a partição faltante
SELECT public.coin_ledger_ensure_partition('2029-03-01');

-- 2. Mover rows (declarative partitioning cuida do roteamento)
--    NOTA: DEFAULT partition deve ser detached antes de INSERT no parent,
--    caso contrário PG rejeita por overlap.
ALTER TABLE public.coin_ledger DETACH PARTITION public.coin_ledger_default;
INSERT INTO public.coin_ledger SELECT * FROM public.coin_ledger_default
  WHERE created_at_ms >= <start_ms> AND created_at_ms < <end_ms>;
DELETE FROM public.coin_ledger_default
  WHERE created_at_ms >= <start_ms> AND created_at_ms < <end_ms>;
ALTER TABLE public.coin_ledger ATTACH PARTITION public.coin_ledger_default DEFAULT;
```

### 4. Arquivar partição antiga

Política padrão sugerida: **24 meses online, 36+ meses em archive**.

```sql
-- DETACH instantâneo — partição vira tabela standalone
SELECT public.coin_ledger_detach_old_partition('2024-01-01'::date);
-- retorna 'coin_ledger_p202401' ou NULL se não existir
```

Após DETACH, a partição é uma tabela normal. Operador decide:

- **Mover para schema archive** (recomendado para compliance/LGPD):
  ```sql
  ALTER TABLE public.coin_ledger_p202401 SET SCHEMA coin_ledger_archive;
  ```
  (Criar schema antes: `CREATE SCHEMA IF NOT EXISTS coin_ledger_archive;`)

- **Backup + DROP** (se além da retenção regulatória):
  ```sql
  -- pg_dump --table=coin_ledger_p202401 > archive/coin_ledger_p202401.sql
  DROP TABLE public.coin_ledger_p202401;
  ```

### 5. Agendamento `pg_cron` manual

Se `pg_cron` foi instalado após a migration, rode:

```sql
SELECT cron.schedule(
  'coin_ledger_ensure_partition_monthly',
  '0 3 1 * *',
  $$SELECT public.coin_ledger_ensure_partition((CURRENT_DATE + INTERVAL '2 months')::date);$$
);
```

## Alertas / SLO

- **Orphan rows em DEFAULT** — alerta se `count(*)` em `coin_ledger_default` > 0 por mais de 24h.
- **Partition age** — alerta se partição seed mais recente estiver a <1 mês de expirar (helper não foi chamado).
- **Idempotency table bloat** — alerta se `coin_ledger_idempotency` > 10M rows (rodar GC: `DELETE FROM coin_ledger_idempotency WHERE created_at < now() - interval '1 year';`).

## Troubleshooting

**Sintoma**: `INSERT INTO coin_ledger` falha com `no partition of relation "coin_ledger" found for row`.
**Causa**: `created_at_ms` fora de range das partições E `coin_ledger_default` foi detached.
**Fix**: `ALTER TABLE public.coin_ledger ATTACH PARTITION public.coin_ledger_default DEFAULT;` ou criar partição específica via `coin_ledger_ensure_partition(...)`.

**Sintoma**: `emit_coins_atomic` retorna `was_idempotent=true` quando não deveria.
**Causa**: Row órfã em `coin_ledger_idempotency` de uma chamada anterior.
**Fix**: Inspecionar via `SELECT * FROM coin_ledger_idempotency WHERE ref_id = '<ref>'`. Se o `ledger_id` não existe em `coin_ledger`, deletar o idempotency row.

**Sintoma**: Migration re-aplicada falha com "relation already exists".
**Causa**: Migration abortou no meio (raro — DO block é atomic).
**Fix**: Inspecionar estado: se `coin_ledger_monolithic` ainda existe mas `coin_ledger` não, é possível recuperar via RENAME. Contactar DBA antes de qualquer ação.
