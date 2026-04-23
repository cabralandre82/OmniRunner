# Ledger Index Naming & Dedup Runbook

> **Audit ref:** L19-04 · **Owner:** dba · **Severity:** 🟠 High
> **Migration:** `supabase/migrations/20260421280000_l19_04_dedupe_ledger_indexes.sql`
> **Integration tests:** `tools/test_l19_04_duplicate_indexes.ts`
> **CI:** `npm run audit:duplicate-indexes` (wrapper sobre `fn_assert_no_duplicate_indexes`)

## 1. Modelo mental

Cada índice em `coin_ledger` custa:
- **~5–20 % de WAL** por INSERT (ledger tem ~800k inserts/dia em production alvo);
- **~15 % storage** extra na partição ativa;
- **autovacuum blocking** se a index page contention for alta;
- **tempo de rebuild** em cada partição nova de `coin_ledger_YYYY_MM`.

Então **índice duplicado ou redundante não é neutro**: ele degrada o caminho de escrita proporcionalmente a quantos houver. A convenção canônica pós-L19-04 é:

> **Um índice por combinação (key columns × predicate × include).**
> Variantes só são justificadas se adicionam enforcement único (`UNIQUE`), ou se o `WHERE` ou `INCLUDE` difere materialmente.

## 2. Convenção de nomes

Use o prefixo `idx_` seguido do **core da tabela** (sem os prefixos `coin_`, `clearing_`, `platform_`, `custody_` quando são redundantes com o contexto do schema `public`):

| ❌ Evite                         | ✅ Preferido               |
|----------------------------------|----------------------------|
| `idx_coin_ledger_user_created`   | `idx_ledger_user`          |
| `idx_coin_ledger_ref_reason`     | `idx_ledger_ref_reason`    |
| `idx_clearing_settlements_status`| `idx_clearing_status`      |
| `idx_platform_revenue_type`      | `idx_revenue_type`         |

Formato: `idx_<core>_<col1>[_<col2>][_<predicate_tag>]`.

Exemplos canônicos em `coin_ledger`:
- `idx_ledger_user` — `(user_id, created_at_ms DESC)`
- `idx_ledger_issuer` — `(issuer_group_id)`
- `idx_ledger_reason` — `(reason, created_at_ms DESC)` (L19-01)
- `idx_ledger_issue_snapshot` — `(user_id, issuer_group_id)` INCLUDE (delta_coins, clearing_fee_rate_pct_snapshot) WHERE `reason='institution_token_issue' AND issuer_group_id IS NOT NULL` (L03-02)

## 3. Como detectar duplicatas

### 3.1 Investigação ad-hoc

```sql
SELECT *
  FROM public.fn_find_duplicate_indexes('public', 'coin_ledger');
```

Retorna zero linhas quando não há duplicatas. Se retornar linhas, o envelope é:

| redundant_index | canonical_index | kind | reason |
|-----------------|-----------------|------|--------|
| `idx_ledger_user_v2` | `idx_ledger_user` | `exact_duplicate` | `mesmo key_sig='user_id:ASC|created_at_ms:DESC', include_sig='', predicate=''` |
| `idx_ledger_a` | `idx_ledger_a_b` | `prefix_overlap` | `key_sig de idx_ledger_a é prefixo de idx_ledger_a_b` |

### 3.2 Varredura global

```sql
SELECT *
  FROM public.fn_find_duplicate_indexes('public', NULL)
 ORDER BY tablename, redundant_index;
```

### 3.3 Assert (CI / self-tests)

```sql
SELECT public.fn_assert_no_duplicate_indexes(
  p_schemas => ARRAY['public']::text[],
  p_tables  => ARRAY['coin_ledger','clearing_settlements','custody_deposits',
                     'custody_withdrawals','platform_revenue','wallets']::text[]
);
```

Retorna `true` se tudo OK; raise `P0010` com lista detalhada se houver duplicatas. O CI job `npm run audit:duplicate-indexes` executa isso contra a base local e falha se regredir.

## 4. Cenários operacionais

### A — PR adiciona índice que `fn_find_duplicate_indexes` flagga

1. **Entender a justificativa**: leia o diff da migration. O contribuidor provavelmente queria resolver uma query lenta.
2. **Decidir entre 3 caminhos**:
   - **Merge** no canônico existente se as colunas são prefixo (ex.: adicionar `INCLUDE` ou estender `ORDER BY` ao invés de criar novo índice).
   - **Diferenciar via `WHERE`** se o caso de uso é um subset (ex.: `WHERE status='pending'`).
   - **Rejeitar** o novo índice se o canônico já cobre via `EXPLAIN ANALYZE`.
3. **Documentar** o racional no commit/PR para evitar futuros reverts.

### B — Produção tem índice legacy que queremos remover

```sql
-- Prod seguro (concurrent, sem lock na tabela)
BEGIN;
SET lock_timeout = '2s';
DROP INDEX CONCURRENTLY IF EXISTS public.idx_coin_ledger_user_created;
COMMIT;
```

**NUNCA rode `DROP INDEX` em `coin_ledger` dentro de uma migration normal** — migrations rodam em transação, e `DROP INDEX CONCURRENTLY` não pode. Ou (a) crie uma pseudo-migration especial que roda fora de transação (Supabase CLI: `-- +migrate StatementBegin` etc.), ou (b) rode fora do pipeline de migration, documentando em `portal_audit_log` com `action='dba.index_drop'`.

Pós-drop, rode o `fn_find_duplicate_indexes` para confirmar convergência.

### C — Produção tem índice canônico faltando

Ex.: após restore de backup, `idx_ledger_user` pode estar ausente em uma partição específica.

1. Investigar:

```sql
SELECT indrelid::regclass AS partition, indexrelid::regclass AS idx, pg_get_indexdef(indexrelid)
  FROM pg_index
 WHERE indrelid::regclass::text LIKE 'coin_ledger_%'
   AND indrelid::regclass::text NOT LIKE '%default%'
   AND indrelid::regclass::text NOT LIKE '%_monolithic'
 ORDER BY indrelid::regclass::text;
```

2. Recriar **em partições locais, uma a uma** (não no partition root, que já propaga via `ON PARTITIONED TABLE` se L19-01 estiver ok):

```sql
-- Exemplo: faltou em coin_ledger_2026_04
CREATE INDEX CONCURRENTLY idx_ledger_user_on_202604
    ON public.coin_ledger_2026_04 (user_id, created_at_ms DESC);
```

3. Alinhar nome com o `ATTACH` automático (Postgres renomeia para o `idx_<parent>_<partition>` padrão).

### D — Adicionar novo índice financeiro

Antes do CREATE:

```sql
-- 1. Listar índices atuais da tabela alvo
\d+ public.<tabela>

-- 2. Rodar o detector
SELECT * FROM public.fn_find_duplicate_indexes('public', '<tabela>');
```

Depois do CREATE (em PR):

```sql
-- 3. Self-test: migrations novas devem incluir no DO block
DO $$
BEGIN
  PERFORM public.fn_assert_no_duplicate_indexes(
    p_schemas => ARRAY['public']::text[],
    p_tables  => ARRAY['<tabela>']::text[]
  );
END $$;
```

## 5. Tunáveis

- **`p_schemas`** em `fn_assert_no_duplicate_indexes` — só `public` é varrido no CI atual. Se você expandir para `auth`, `extensions`, certifique-se de que os esquemas não têm índices intencionalmente duplicados (ex.: Supabase Auth tem pares de índices em `auth.users` que não são redundantes, são partial-index duals).
- **Inclusão de `UNIQUE` e expression-based** — desativadas hoje. Se quiser cobertura para UNIQUE duplicates, adicione uma função irmã `fn_find_duplicate_unique_indexes` e uma política separada; não misture na primary.

## 6. Rollback

Segurança total:

```sql
DROP FUNCTION IF EXISTS public.fn_assert_no_duplicate_indexes(text[], text[]);
DROP FUNCTION IF EXISTS public.fn_find_duplicate_indexes(text, text);
-- Phantoms restauráveis via re-apply de 20260308000000 (se necessário)
```

O rollback não traz os phantoms de volta — o DROP IF EXISTS deles é idempotente e a decisão de manter não-drift é deliberada.

## 7. Observability signals

- `portal_audit_log` com `action='dba.index_drop'` + `metadata.index_name` / `metadata.table`.
- `npm run audit:duplicate-indexes` em CI — falha em `P0010` indica regressão.
- Alerta opcional: `pg_stat_user_indexes.idx_scan = 0` por 30 dias + tamanho > 100 MB → candidato a drop (não automático; requer sign-off DBA porque queries raras podem ter usado há semanas).

## 8. Referências cruzadas

- **L19-01** (`coin_ledger` particionada) — esta migration **pressupõe** que o partition swap já aconteceu quando os canônicos `idx_ledger_user/issuer/reason` foram recriados no partition root.
- **L19-08** (CHECK constraint naming) — convenção similar para constraints; próximo item do Batch C.
- **L03-02** (clearing fee freeze) — introduziu `idx_ledger_issue_snapshot` seguindo a convenção canônica.
- **L17-01** (withErrorHandler) — `P0010` propaga como 500 genérico; CI usa `fn_assert_*` e vê o erro estruturado diretamente.
