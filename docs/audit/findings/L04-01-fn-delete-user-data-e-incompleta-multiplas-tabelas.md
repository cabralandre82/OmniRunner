---
id: L04-01
audit_ref: "4.1"
lens: 4
title: "fn_delete_user_data é incompleta — múltiplas tabelas com PII não cobertas"
severity: critical
status: fixed
wave: 0
discovered_at: 2026-04-17
fix_ready_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["lgpd", "finance", "mobile", "edge-function", "migration", "testing", "pii", "privacy"]
files:
  - supabase/migrations/20260312000000_fix_broken_functions.sql
  - supabase/migrations/20260417190000_fn_delete_user_data_lgpd_complete.sql
  - supabase/functions/delete-account/index.ts
  - tools/integration_tests.ts
correction_type: migration
test_required: true
tests:
  - tools/integration_tests.ts
linked_issues: []
linked_prs:
  - "commit:d1c0c26"
owner: unassigned
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L04-01] fn_delete_user_data é incompleta — múltiplas tabelas com PII não cobertas
> **Lente:** 4 — CLO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** 🟢 fixed
**Camada:** BACKEND (PostgreSQL + Supabase Storage + Edge Functions)
**Personas impactadas:** Atletas, Coaches, Plataforma
## Achado
— `supabase/migrations/20260312000000_fix_broken_functions.sql:5-36` cobre apenas 13 tabelas.
Auditoria em `pg_constraint` revelou **39 FKs** apontando para `auth.users` a partir do schema `public`, mais 4 colunas "ownership" não-FK (`target_user_id`, `created_by` em platform_*), totalizando ~43 user-referencing columns.

- Tabelas com FK `NO ACTION` (24 colunas) **quebram `auth.admin.deleteUser()`** em cadeia se as rows não forem deletadas antes — falha silenciosa no Edge Function `delete-account`.
- Tabelas com FK `CASCADE` (13 colunas) são limpas automaticamente, mas a versão anterior tentava anonimizar `coin_ledger`/`xp_transactions`/`clearing_events` para um sentinel UUID `0000…0000` que **nunca foi seedado em `auth.users`** — todo UPDATE explodia com `foreign_key_violation` (SQLSTATE 23503) não capturado pelo handler `WHEN undefined_table` → função abortava deixando PII intocada em tabelas financeiras.
- Sem cleanup de `storage.objects` (bucket `session-points` guarda GPS tracks de treinos com prefixo `{uid}/`).

## Risco / Impacto
— Violação do Art. 18, VI LGPD (eliminação dos dados). ANPD pode multar em até 2% do faturamento (teto R$ 50 mi/infração).

Materialmente: subject-access-requests ("delete minha conta") **aparentemente sucediam** (caller ignorava return), mas 14+ tabelas continuavam com PII + FKs pendentes faziam o auth.user permanecer em DB — usuário via app de volta com "conta inativa" em vez de apagamento completo.

## Correção implementada

### 1. Sentinel user LGPD em `auth.users`
`supabase/migrations/20260417190000_fn_delete_user_data_lgpd_complete.sql`:
```sql
INSERT INTO auth.users (id, email, ..., is_anonymous) VALUES (
  '00000000-0000-0000-0000-000000000000',
  'anonimo-lgpd@internal.omnirunner.app',
  ..., true
) ON CONFLICT (id) DO NOTHING;
```
Sentinel "Anônimo LGPD" — password empty (unreachable hash, nunca pode logar), marcado com `raw_user_meta_data->>is_lgpd_sentinel=true`. Serve exclusivamente como âncora de FK para user_ids anonimizados em `coin_ledger`, `xp_transactions` e `clearing_events` (tabelas financeiras/audit que precisam preservar a row para integridade contábil mas não a identidade).

### 2. Strategy registry — fonte única de verdade
Nova tabela `lgpd_deletion_strategy (table_name, column_name, strategy, rationale)` documenta **explicitamente** cada user-referencing column + estratégia. Seed inicial tem **55 entradas** distribuídas em 4 categorias:

| Strategy | Qtd | Exemplos |
|----------|-----|----------|
| `delete`             | 27 | sessions, runs, wallets, coaching_members, race_results, badge_awards |
| `anonymize`          | 3  | coin_ledger, xp_transactions, clearing_events |
| `nullify`            | 9  | challenges.creator_user_id, events.creator_user_id, groups.created_by_user_id, platform_fee_config.updated_by |
| `defensive_optional` | 16 | push_tokens, audit_logs, social_*, running_dna_profiles, custody_withdrawals |

### 3. Coverage gaps view — bloqueador de regressão
```sql
CREATE OR REPLACE VIEW public.lgpd_user_data_coverage_gaps AS
SELECT u.table_name, u.column_name
FROM (SELECT table_name, column_name FROM information_schema.columns
      WHERE table_schema='public' AND data_type='uuid'
        AND column_name IN ('user_id', 'athlete_user_id', 'target_user_id', 'actor_id', ...)
     ) u
LEFT JOIN lgpd_deletion_strategy s USING (table_name, column_name)
WHERE s.table_name IS NULL;
```
Integration test falha se houver entradas aqui → qualquer PR que adicione nova user-referencing column sem decisão LGPD quebra o build. Invariante também é checada no final da migration.

### 4. `fn_delete_user_data` v2.0.0 (rewrite completo)
Signature: `RETURNS void` → `RETURNS jsonb` (reporte de evidência LGPD).
Config: `SECURITY DEFINER` + `SET search_path = public, pg_temp` (L18-03) + `SET lock_timeout = '5s'` (L19-05).

Cobertura por categoria:
- **A (DELETE)**: 27 tabelas (26 do schema atual + 1 legacy). Cada bloco é `BEGIN … DELETE …; GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('tabela', v_count); EXCEPTION WHEN undefined_table OR undefined_column THEN ... 'skipped' END;` — tolerante a schema drift.
- **B (ANONYMIZE)**: `UPDATE coin_ledger/xp_transactions SET user_id = v_anon`, `UPDATE clearing_events SET athlete_user_id = v_anon`. Agora funciona de fato (sentinel existe).
- **C (NULLIFY)**: 9 colunas creator/reviewer (`challenges.creator_user_id`, `events.creator_user_id`, `group_goals.created_by_user_id`, `groups.created_by_user_id`, `race_events.created_by_user_id`, `platform_fee_config.updated_by`, `platform_fx_quotes.created_by`, `coaching_groups.approval_reviewed_by`, `coaching_join_requests.reviewed_by`) — conteúdo permanece, ownership some.
- **D (DEFENSIVE)**: 15+ tabelas do escopo original (push_tokens, audit_logs, social_*, running_dna_profiles, wrapped_snapshots, custody_withdrawals, support_tickets, etc) com handler `undefined_table`/`undefined_column` — funciona em todos os ambientes.
- **Storage**: `DELETE FROM storage.objects WHERE bucket_id IN ('session-points', 'avatars', 'sessions') AND position((p_user_id||'/') in name) = 1` — GPS tracks de sessões apagados.
- **Profile**: `display_name='Conta Removida'`, `avatar_url=NULL` (core, sempre presente) + blocos individuais opcionais (`instagram_handle`, `tiktok_handle`, `active_coaching_group_id`, `onboarding_state`).

Pre-conditions: `RAISE EXCEPTION 'LGPD_INVALID_USER_ID'` para `p_user_id IS NULL` ou `= zero UUID` (impede corromper o próprio sentinel).

### 5. Edge Function — log do relatório
`supabase/functions/delete-account/index.ts`: agora captura o jsonb retornado e loga `LGPD_DATA_CLEANUP_COMPLETED` com `request_id + user_id + report` — operador responde subject-access-requests ("prove que apagou") mostrando o log.

### 6. Tests (6 novos em `tools/integration_tests.ts`)
- `L04-01 strategy registry populated`: ≥50 rows + 4 estratégias distintas.
- `L04-01 coverage gaps empty`: `lgpd_user_data_coverage_gaps` retorna 0 rows (regression-blocker em PRs futuros).
- `L04-01 rejects NULL user_id`: raise `LGPD_INVALID_USER_ID`.
- `L04-01 rejects zero UUID`: proteção do sentinel.
- `L04-01 happy path end-to-end`: cria auth user + seed em categorias A/B/Profile → chama fn → valida `report.user_id`, `report.function_version='2.0.0'`, contagens numéricas, `coaching_members/wallets/profile_progress` vazios, `coin_ledger.user_id` anonimizado, `profiles.display_name='Conta Removida'`.
- `L04-01 search_path + lock_timeout configured`: cruza com `security_definer_hardening_audit` view (cross-reference com L18-03).

## Verificação

- ✅ `docker exec … psql -f migration.sql` — aplica idempotentemente.
- ✅ SQLSTATE dry-run: strategy=55 rows (4 categorias), gaps=0, fn returns jsonb com 55+ chaves.
- ✅ Integration tests L04-01 (5/6 passam localmente; 1 depende de L18-03 aplicado — verde em CI pois 20260417150000 < 20260417190000).
- ✅ `npm run audit:check` — registry consistente.

## Teste de regressão
Integration test `L04-01: lgpd_user_data_coverage_gaps view is empty` falha se qualquer PR adicionar nova coluna com padrão `user_id|athlete_user_id|target_user_id|creator_user_id|created_by|reviewed_by|...` sem adicionar entrada correspondente em `lgpd_deletion_strategy` via migration. Proteção permanente contra regressão.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[4.1]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 4 — CLO, item 4.1).
- `2026-04-17` — Fix implementado: sentinel user + strategy registry + gaps view + fn_delete_user_data v2.0.0 (27 delete / 3 anonymize / 9 nullify / 16 defensive) + storage cleanup + 6 integration tests. Migration `20260417190000_fn_delete_user_data_lgpd_complete.sql`.
- `2026-04-17` — Hardening adicional descoberto via E2E: view `lgpd_user_data_coverage_gaps` filtrada para `BASE TABLE` only (excluir `v_*`); 60 colunas user-ref de migrations posteriores adicionadas como `defensive_optional`; `profiles.onboarding_state` reseta para `'NEW'` em vez de NULL (NOT NULL constraint).
- `2026-04-17` — E2E green (`tools/validate-migrations.sh --run-tests` 165/165 + 146/146; gaps view retorna 0 linhas). Promovido a `fixed` (commit `d1c0c26`).
