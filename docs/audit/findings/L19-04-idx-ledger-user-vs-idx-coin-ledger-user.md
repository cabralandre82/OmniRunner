---
id: L19-04
audit_ref: "19.4"
lens: 19
title: "idx_ledger_user vs idx_coin_ledger_user_created — evoluções sem limpeza"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
tags: ["finance", "migration", "performance", "reliability"]
files:
  - "supabase/migrations/20260421280000_l19_04_dedupe_ledger_indexes.sql"
  - "tools/test_l19_04_duplicate_indexes.ts"
  - "tools/audit/check-duplicate-indexes.ts"
  - "docs/runbooks/LEDGER_INDEX_NAMING_RUNBOOK.md"
correction_type: migration
test_required: true
tests:
  - "tools/test_l19_04_duplicate_indexes.ts"
linked_issues: []
linked_prs: ["d5bcc54"]
owner: dba
runbook: "docs/runbooks/LEDGER_INDEX_NAMING_RUNBOOK.md"
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L19-04] idx_ledger_user vs idx_coin_ledger_user_created — evoluções sem limpeza
> **Lente:** 19 — DBA · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fixed
**Camada:** db
**Personas impactadas:** DBA, SRE

## Achado
— Migration 2026-02-18 cria `idx_ledger_user`; migration 2026-03-08 cria `idx_coin_ledger_user_created`. Nomenclatura inconsistente; provavelmente ambos persistem.

## Correção proposta

— Migration `CREATE INDEX CONCURRENTLY idx_X; DROP INDEX CONCURRENTLY idx_Y;` para trocar sem lock.

## Correção aplicada

Após investigar o estado real em ambiente local (post-L19-01 partition swap), verificou-se que `DROP TABLE coin_ledger_monolithic CASCADE` já havia derrubado `idx_coin_ledger_user_created`. Mas o problema sistêmico — **ausência de detector de duplicatas e convenção de naming frouxa** — permanecia. O fix entrega uma solução em 5 camadas:

1. **`public.fn_find_duplicate_indexes(p_schema text, p_table text) RETURNS TABLE(schemaname, tablename, redundant_index, canonical_index, kind, reason)`** STABLE SECURITY DEFINER — detecta dois tipos de redundância em índices btree plain (não UNIQUE, não PK, não expression-based):
   - `exact_duplicate`: mesmo key_sig + mesmo INCLUDE + mesmo WHERE predicate. Canônico = lex menor.
   - `prefix_overlap`: key_sig de A é prefixo estrito do key_sig de B, com INCLUDE e WHERE iguais. A é redundante vs B.

2. **`public.fn_assert_no_duplicate_indexes(p_schemas text[], p_tables text[]) RETURNS boolean`** STABLE SECURITY DEFINER — wrapper que RAISE `P0010` com lista detalhada se houver duplicatas nos escopo fornecido. Validação NULL (22023). Usado em CI + self-tests de migrations futuras.

3. **DROP IF EXISTS defensivo** dos 4 phantoms conhecidos (`idx_coin_ledger_user_created`, `idx_coin_ledger_ref_reason`, `idx_ledger_user_monolithic`, `idx_ledger_issuer_monolithic`) — idempotente em envs limpos; elimina drift em envs que aplicaram 20260308 sem o L19-01 swap completo.

4. **CI tool** `tools/audit/check-duplicate-indexes.ts` + `npm run audit:duplicate-indexes` — invoca o assert em 16 tabelas financeiras críticas (`coin_ledger`, `coin_ledger_idempotency`, `clearing_settlements`, `clearing_events`, `custody_deposits`, `custody_withdrawals`, `custody_accounts`, `platform_revenue`, `billing_purchases`, `billing_auto_topup_settings`, `wallets`, `xp_transactions`, `sessions`, `audit_logs`, `portal_audit_log`, `notification_log`). Exit 1 se regredir.

5. **Self-test DO-block** valida 4 fases em-place: (a) ambas funções registradas com SECURITY DEFINER, (b) `coin_ledger` limpo → 0 duplicatas, (c) fabricação sintética em schema temp `l19_04_test` + detecção de 1 prefix_overlap, (d) assert wrapper raise P0010 com duplicatas (cleanup com DROP SCHEMA CASCADE).

6. **Integration tests** `tools/test_l19_04_duplicate_indexes.ts` (14 cases docker-exec): schema/DDL (STABLE + SECURITY DEFINER + service_role EXECUTE / anon NÃO + phantoms ausentes), behaviour (coin_ledger limpo 0 dups + prefix_overlap + exact_duplicate com canônico lex menor + UNIQUE/PK ignorados + WHERE/INCLUDE diferentes NÃO flaggados + exact match com WHERE+INCLUDE idênticos), argument validation (NULL schemas → 22023, duplicatas → P0010, tables[] scope filtra). 14/14 verdes.

7. **Runbook canônico** `docs/runbooks/LEDGER_INDEX_NAMING_RUNBOOK.md` (~200 linhas, 8 seções):
   - Modelo mental (cada índice custa 5-20% WAL + 15% storage + autovacuum blocking).
   - Convenção de nomes `idx_<core>_<cols>[_<predicate_tag>]` com tabela de ❌ vs ✅.
   - Como detectar (ad-hoc, varredura global, CI assert).
   - Cenários operacionais: PR adiciona índice flaggado (merge vs diferenciar vs rejeitar), remover legacy em prod (DROP INDEX CONCURRENTLY fora de migration normal), índice canônico faltando pós-restore, adicionar novo índice (checklist antes/depois).
   - Tunáveis (`p_schemas` scope, UNIQUE/expression-based opt-out por design).
   - Rollback (DROP FUNCTION seguros; phantoms NÃO restaurados).
   - Observability (portal_audit_log `action='dba.index_drop'`, `npm run audit:duplicate-indexes` em CI, candidatos a drop via `pg_stat_user_indexes.idx_scan=0`).
   - Cross-refs L19-01/08 + L03-02 + L17-01.

### Impacto
- **Antes**: um contribuidor adicionando `idx_coin_ledger_X` sobre `(user_id, created_at)` passaria review — `idx_ledger_user` com semântica idêntica já existia, mas o nome diferente mascarava. Cada duplicata cobra 5-20% WAL em toda INSERT contra `coin_ledger` (~800k/dia no alvo).
- **Depois**: o CI barra em PR-time. Self-test da própria migration falha em re-apply se alguma regressão ocorrer. Convenção documentada para os próximos contribuidores. Detector reusável para qualquer tabela, não só ledger.

### Escopo deliberadamente excluído
- **CREATE INDEX CONCURRENTLY** — não é possível dentro de uma migration transacional. O runbook §4.B documenta o fluxo manual de remoção em prod.
- **Análise de `pg_stat_user_indexes` para indexes nunca usados** — L19-07 (DBA tuning, deferido) cobrirá isso com decisões per-index baseadas em telemetria real.
- **Naming enforcement via regex em migrations** — decisão de naming convention fica em runbook humano, não em lint automático, porque a convenção é prescritiva (pode evoluir) e falsos positivos criariam fricção maior que benefício.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[19.4]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 19 — DBA, item 19.4).
- `2026-04-21` — Correção aplicada (`d5bcc54`): `fn_find_duplicate_indexes` + `fn_assert_no_duplicate_indexes` + DROP phantoms + CI `audit:duplicate-indexes` + 14 tests + runbook.
