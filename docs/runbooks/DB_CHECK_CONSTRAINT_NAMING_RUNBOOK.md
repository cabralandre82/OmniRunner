## DB CHECK constraint naming runbook (L19-08)

**Status**: active · **Owner**: Platform / DB · **Updated**: 2026-04-21

Este runbook define a convenção de nomes para `CHECK` constraints em tabelas
do schema `public` e documenta como detectar, renomear, e prevenir regressões.

---

### 1. Problema

Até 2026-04, tabelas financeiras tinham nomes de CHECK inconsistentes:

- Postgres auto-generate → `<table>_<col>_check` (ex.: `custody_accounts_total_deposited_usd_check`).
- Constraints ad-hoc com prefixo → `chk_peg_1_to_1` (na migration 20260227000000).
- Constraints ad-hoc **sem** prefixo → `different_groups`, `swap_different_groups`,
  `coin_ledger_reason_length_guard`, `coin_ledger_reason_pii_guard`.

O último grupo causava:

- Mensagens de erro feias no frontend (`ERROR: new row violates check constraint "different_groups"`).
- Dificuldade de grep/audit — o nome não dá nenhuma pista de que tabela ou
  regra a constraint implementa.
- Colisão futura potencial — `different_groups` é muito genérico.

---

### 2. Convenção (forward-only)

A partir de 2026-04-21, **duas** formas são aceitas:

| Padrão | Quando usar | Exemplo |
|---|---|---|
| (A) `<table>_<col>_check` | Postgres default, gerado automaticamente quando a CHECK é declarada inline numa column `x int CHECK (x > 0)` | `custody_accounts_total_deposited_usd_check` |
| (B) `chk_<table>_<rule>` | Constraints ad-hoc, declaradas via `ALTER TABLE … ADD CONSTRAINT … CHECK (…)` ou que envolvem múltiplas colunas | `chk_clearing_settlements_distinct_groups`, `chk_coin_ledger_reason_pii_guard` |

**Qualquer outro nome é rejeitado** pelo CI `audit:constraint-naming`.

Boas práticas para o segmento `<rule>` no padrão (B):

- Use snake_case curto e descritivo.
- Para constraints entre colunas, descreva a invariante (`distinct_groups`, `peg_1_to_1`, `amount_positive`).
- Para guards (PII, LGPD), use sufixo `_guard` (`reason_pii_guard`, `reason_length_guard`).
- Não inclua o nome da schema; o prefixo da tabela já desambigua.

---

### 3. Detecção de violações

Duas SQL functions (migração `20260421290000_l19_08_check_constraint_naming.sql`):

#### `public.fn_find_nonstandard_check_constraints(p_schema text DEFAULT 'public', p_table text DEFAULT NULL)`

Retorna uma tabela com CHECK constraints cujo nome não se encaixa em nenhum
dos dois padrões:

```sql
SELECT * FROM public.fn_find_nonstandard_check_constraints('public');
-- schemaname | tablename | constraint_name | suggested_name | definition
```

#### `public.fn_assert_check_constraints_standardized(p_schemas text[], p_tables text[])`

Wrapper que levanta `P0010` com a lista de violações se a função anterior
retornar alguma linha. Usado em CI e em self-tests.

```sql
PERFORM public.fn_assert_check_constraints_standardized(
  p_schemas => ARRAY['public']::text[],
  p_tables  => ARRAY['coin_ledger', 'clearing_settlements']::text[]
);
-- retorna true, ou raises P0010 com HINT.
```

Ambas são `SECURITY DEFINER` com `EXECUTE` só para `service_role`.

---

### 4. Renomeando uma constraint

1. Identifique violações:

    ```bash
    npm run audit:constraint-naming
    ```

    (Falha se qualquer tabela do escopo tiver constraint fora da convenção.)

2. Para cada violação, use `suggested_name` como ponto de partida ou escolha
   um nome melhor no formato `chk_<table>_<rule>`.

3. Faça o rename numa migration forward-only dedicada:

    ```sql
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM pg_constraint con
        JOIN pg_class c ON c.oid = con.conrelid
        WHERE c.relname = '<table>'
          AND con.conname = '<old_name>'
      ) AND NOT EXISTS (
        SELECT 1 FROM pg_constraint con
        JOIN pg_class c ON c.oid = con.conrelid
        WHERE c.relname = '<table>'
          AND con.conname = '<new_name>'
      ) THEN
        ALTER TABLE public.<table>
          RENAME CONSTRAINT <old_name> TO <new_name>;
      END IF;
    END $$;
    ```

    O padrão idempotente (duplo `IF EXISTS … AND NOT EXISTS`) garante
    replay-safe mesmo que a migração já tenha rodado.

4. Atualize quaisquer referências por nome (testes, logs estruturados,
   `COMMENT ON CONSTRAINT`, docs).

---

### 5. Por que não renomeamos todas as auto-geradas?

Investigação de 2026-04-21 mostrou ~25 migrations referenciando nomes no
formato `<table>_<col>_check` em blocos `DROP CONSTRAINT IF EXISTS` (ex.:
`20260303100000`, `20260227400000`, `20260316000000`). Renomear em bloco
quebraria o replay histórico.

A convenção aceita **tanto** o padrão auto-generated (A) **quanto** o
`chk_` explícito (B) exatamente para evitar esse custo. O nome auto-generated
do Postgres **é** informativo (`<table>_<col>_check` já diz a que tabela e
a que column pertence), e é o padrão moderno do Postgres.

---

### 6. CI / Integração

- `npm run audit:constraint-naming` — falha se qualquer tabela do scope
  financeiro tiver CHECK fora da convenção.
- O scope é o mesmo de `audit:duplicate-indexes` (L19-04): `coin_ledger`,
  `clearing_settlements`, `custody_accounts`, `platform_revenue`, etc.
- Para estender: edite `SCOPE` em `tools/audit/check-constraint-naming.ts`.

Self-test da migration: cria uma tabela temporária com CHECK não-conforme,
verifica detecção, verifica raise P0010, e dropa o schema temp.

---

### 7. FAQ

**P: Posso usar um nome em inglês? Português?**
R: Sim — só respeite o padrão `chk_<table>_<snake_case_rule>`. Ambos os
idiomas são aceitos; prefira consistência com o resto do schema da tabela.

**P: Uma constraint que envolve 3 colunas — como nomear?**
R: `chk_<table>_<regra>`, onde `<regra>` descreve a invariante semântica
(ex.: `chk_settlement_amounts_sum_to_total`).

**P: Posso mudar uma constraint existente sem renomear?**
R: Sim, `DROP CONSTRAINT … ADD CONSTRAINT …` mantém o nome original
(que pode estar ou não em conformidade). Se estiver fora, renomeie.

---

### 8. Referências

- Finding: `docs/audit/findings/L19-08-*.md`
- Migração: `supabase/migrations/20260421290000_l19_08_check_constraint_naming.sql`
- CI: `tools/audit/check-constraint-naming.ts`
- Testes: `tools/test_l19_08_check_constraint_naming.ts`
- Runbook relacionado: `docs/runbooks/LEDGER_INDEX_NAMING_RUNBOOK.md` (L19-04)
