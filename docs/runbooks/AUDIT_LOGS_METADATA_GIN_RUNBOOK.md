## `audit_logs.metadata` GIN index runbook (L19-06)

**Status**: active · **Owner**: Platform / DBA / SRE · **Updated**: 2026-04-21

---

### 1. Problema

`public.audit_logs` armazena telemetria estruturada em `metadata jsonb` com
padrões frequentes de lookup:

```sql
SELECT * FROM audit_logs WHERE metadata @> '{"request_id":"..."}';
SELECT * FROM audit_logs WHERE metadata @> '{"session_id":"..."}';
SELECT * FROM audit_logs WHERE metadata @> '{"correlation_id":"..."}';
SELECT * FROM audit_logs WHERE metadata @> '{"group_id":"..."}';
```

Sem índice, essas queries fazem **Seq Scan** sobre toda a tabela. Para uma
tabela de audit ativa (milhões de linhas/mês), uma lookup por `request_id`
passa de ~200 ms (OLAP) ou timeouts no portal admin.

---

### 2. Solução

Índice GIN com operador `jsonb_path_ops`:

```sql
CREATE INDEX CONCURRENTLY idx_audit_logs_metadata_gin
  ON public.audit_logs USING GIN (metadata jsonb_path_ops);
```

**Por que `jsonb_path_ops` e não `jsonb_ops`?**

| Operator class | Operadores suportados | Tamanho | Escolha |
|---|---|---|---|
| `jsonb_ops` (default) | `@>`, `?`, `?|`, `?&`, `@?`, `@@` | ~100% | Mantenha se precisar de `?` (existence) em queries de produção |
| `jsonb_path_ops` | Só `@>`, `@?`, `@@` | ~70% | Escolhido — só usamos `@>` |

As queries canônicas do sistema (documentadas acima) **só usam `@>`**.
Se uma nova query pedir `metadata ? 'key'`, adicione um índice secundário
`jsonb_ops` em vez de migrar o GIN existente.

---

### 3. Aplicação em produção

A migração `20260421300000_l19_06_audit_logs_metadata_gin.sql` é **defensiva**:
só cria o índice se `public.audit_logs` existir e tiver coluna `metadata jsonb`.
Além disso, ela usa `CREATE INDEX IF NOT EXISTS` (NÃO CONCURRENTLY) porque o
DSL de migration roda dentro de uma transação.

Para bases com >10M linhas onde um AccessExclusive lock durante
`CREATE INDEX` é inaceitável, o playbook CONCURRENTLY deve rodar **fora** do
pipeline:

```sql
-- 1. Setar lock_timeout curto para falhar rápido se houver bloqueio
SET lock_timeout = '5s';

-- 2. Criar o índice CONCURRENTLY (não pode estar em BEGIN/COMMIT)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_audit_logs_metadata_gin
  ON public.audit_logs USING GIN (metadata jsonb_path_ops);

-- 3. Validar
SELECT * FROM pg_indexes
 WHERE schemaname='public'
   AND indexname='idx_audit_logs_metadata_gin';

-- 4. Adicionar comentário (pode rodar dentro de transação)
COMMENT ON INDEX public.idx_audit_logs_metadata_gin IS
  'L19-06: GIN jsonb_path_ops para lookups audit_logs.metadata @> filter.';
```

Se `CREATE INDEX CONCURRENTLY` falhar (ex.: deadlock, cancel), deixa um
índice `INVALID` que precisa ser dropado:

```sql
SELECT c.relname, i.indisvalid
  FROM pg_index i JOIN pg_class c ON c.oid=i.indexrelid
 WHERE c.relname='idx_audit_logs_metadata_gin';
-- Se indisvalid = false:
DROP INDEX CONCURRENTLY public.idx_audit_logs_metadata_gin;
-- Então recria do passo 2.
```

---

### 4. Detecção / CI

Dois helpers SECURITY DEFINER (execute só para service_role):

#### `public.fn_audit_logs_has_metadata_gin()`
Retorna `TRUE` se o índice esperado está registrado (nome exato
`idx_audit_logs_metadata_gin` em `public.audit_logs` com access method `gin`).

#### `public.fn_audit_logs_assert_metadata_gin()`
Wrapper que:
1. Retorna `true` se `public.audit_logs` não existe (no-op em sandboxes).
2. Retorna `true` se a tabela existe mas não tem coluna `metadata jsonb`.
3. Retorna `true` se ambas existem E o índice está presente.
4. Raises **P0010** com HINT se a tabela + coluna existem mas o índice falta.

CI script: `npm run audit:audit-logs-gin`.

```bash
npm run audit:audit-logs-gin
# L19-06: checking public.audit_logs GIN index on metadata…
#   public.audit_logs: OK (GIN index on metadata present)
# OK — audit_logs metadata GIN index is present.
```

---

### 5. Query patterns canônicos

Use `@>` (containment) para selection:

```sql
-- Por request_id
SELECT * FROM audit_logs
 WHERE metadata @> jsonb_build_object('request_id', $1)
 ORDER BY created_at DESC
 LIMIT 100;

-- Por multiple keys (AND)
SELECT * FROM audit_logs
 WHERE metadata @> jsonb_build_object('group_id', $1, 'action_kind', 'custody.deposit')
 ORDER BY created_at DESC;
```

**Anti-patterns** que NÃO usam o índice:

```sql
-- ❌ existence com ? — jsonb_path_ops não suporta
SELECT * FROM audit_logs WHERE metadata ? 'request_id';

-- ❌ path accessor operator — precisa de expression index separado
SELECT * FROM audit_logs WHERE metadata->>'request_id' = '...';
-- Para este padrão, prefira:
SELECT * FROM audit_logs WHERE metadata @> jsonb_build_object('request_id', '...');

-- ❌ LIKE em path accessor — sempre seq scan
SELECT * FROM audit_logs WHERE metadata->>'user_agent' LIKE 'Mozilla/%';
```

---

### 6. Interação com L08-08 (Wave 2)

L08-08 converterá `audit_logs` em tabela particionada por `created_at` (rolling
retention + pruning). Quando aquele trabalho chegar, o GIN precisará ser
recriado:

1. Por partição (ou LOCAL): `CREATE INDEX ... ON audit_logs_2026_04 USING GIN …`.
2. Ou no parent com `ON ONLY` + `CREATE INDEX … ON audit_logs_YYYY_MM …
   ATTACH PARTITION`.

Consulte a migração de partitioning quando ela for criada e ajuste o CI
correspondente.

---

### 7. Observabilidade

Para medir impacto pós-deploy:

```sql
SELECT indexrelname, idx_scan, idx_tup_read, idx_tup_fetch
  FROM pg_stat_user_indexes
 WHERE indexrelname = 'idx_audit_logs_metadata_gin';
```

Espera-se:
- Semana 1: 10-50% das queries de audit_logs atingem o índice
- Semana 4: 80%+ (queries legacy com `metadata->>'x'` ainda existirão)

Se `idx_scan` permanecer 0 depois de 2 semanas, investigar:
- Caller ainda usa `metadata->>'x' = 'y'`? Substitua por `@>`.
- Planner subestima seletividade? `VACUUM ANALYZE audit_logs;`.

---

### 8. Referências

- Finding: `docs/audit/findings/L19-06-jsonb-em-audit-logs-metadata-sem-indice-gin.md`
- Migração: `supabase/migrations/20260421300000_l19_06_audit_logs_metadata_gin.sql`
- CI: `tools/audit/check-audit-logs-gin.ts`
- Testes: `tools/test_l19_06_audit_logs_metadata_gin.ts`
- L08-08 (Wave 2): audit_logs retention + partitioning
