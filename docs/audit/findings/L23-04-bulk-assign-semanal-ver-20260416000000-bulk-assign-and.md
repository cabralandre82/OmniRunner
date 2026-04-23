---
id: L23-04
audit_ref: "23.4"
lens: 23
title: "Bulk assign semanal (ver 20260416000000_bulk_assign_and_week_templates.sql) sem rollback"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["migration", "coach", "rollback", "sql", "rpc"]
files:
  - supabase/migrations/20260421730000_l23_04_bulk_assign_rollback.sql
  - tools/audit/check-bulk-assign-rollback.ts
correction_type: rpc
test_required: true
tests:
  - tools/audit/check-bulk-assign-rollback.ts
linked_issues: []
linked_prs: []
owner: coach-tooling
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Migration aditiva, retrocompatível:

  1. Nova tabela `public.bulk_assign_batches` registra cada lote
     com `actor_id`, `group_id`, `description`, `items_count`,
     `undo_ttl_minutes` (1–1440, default 60), `created_at`,
     `undone_at`, `undone_by`, `undo_reason`. CHECK garante
     consistência de (undone_at, undone_by).
  2. Colunas opcionais `bulk_batch_id` em `plan_workout_releases`
     e `training_plan_weeks`, indexadas parcialmente (WHERE IS NOT
     NULL para evitar overhead em linhas legacy).
  3. RPCs `SECURITY DEFINER`, `search_path=public,pg_temp`,
     REVOKE PUBLIC + GRANT EXECUTE TO authenticated:

     - `fn_bulk_assign_batch_open(group_id, actor_id, description,
       ttl_minutes)` — cria batch; role gate coach/admin_master.
     - `fn_bulk_assign_batch_attach(batch_id, release_ids[],
       week_ids[])` — anexa releases criados por
       `fn_bulk_assign_week` ao batch; group_id boundary defense.
     - `fn_bulk_assign_batch_undo(batch_id, actor_id, reason)` —
       desfaz atomicamente: cancela plan_workout_releases,
       cancela training_plan_weeks, escreve workout_change_log
       com change_type='bulk_assign_undone', atualiza batch
       com undone_at/by/reason. Retorna jsonb com counts.
     - `fn_bulk_assign_batch_summary(batch_id)` — read-only jsonb
       com `can_undo`, `already_undone`, `undo_deadline`; UI usa
       para habilitar/desabilitar botão "Desfazer".

  Gates do undo:
  - P0001 INVALID_INPUT: batch_id ou actor_id null.
  - P0002 BATCH_NOT_FOUND: batch inexistente.
  - P0003 BATCH_ALREADY_UNDONE: idempotência.
  - P0005 UNDO_WINDOW_EXPIRED: TTL excedido (default 60 min).
  - P0010 UNAUTHORIZED: actor não é coach/admin_master do grupo
    nem platform_admin, OU actor ≠ batch.actor_id (sem escalação
    por platform_admin).

  RLS em `bulk_assign_batches`: leitura permitida a staff do grupo
  (admin_master, coach, assistant); DML direto bloqueado (só via
  RPC).

  OmniCoin: nenhuma função toca coin_ledger/wallets (L04-07-OK).

  CI guard `audit:bulk-assign-rollback` (~70 asserts) valida
  schema, RLS, SECURITY DEFINER em todas as 4 RPCs, REVOKE/GRANT,
  códigos de erro canônicos (P0001/P0002/P0003/P0005/P0010), TTL
  bounds, author-only gate, group boundary em attach, ausência
  de INSERT em coin_ledger, self-test runtime.

  Integração com coach tooling: UI chama
  `fn_bulk_assign_batch_open` → `fn_bulk_assign_week` (cria
  releases, existente) → `fn_bulk_assign_batch_attach` com os IDs
  retornados. Se coach clicar "Desfazer último lote", chama
  `fn_bulk_assign_batch_summary` para validar TTL, depois
  `fn_bulk_assign_batch_undo`.
---
# [L23-04] Bulk assign semanal (ver 20260416000000_bulk_assign_and_week_templates.sql) sem rollback
> **Lente:** 23 — Treinador · **Severidade:** 🔴 Critical · **Onda:** 1 · **Status:** ✅ fixed
**Camada:** Backend / Coach tooling
**Personas impactadas:** Coach (massa de 300 atletas), Atleta (recebendo workout errado), Assistente (precisa desfazer sem pedir admin)

## Achado
`fn_bulk_assign_week` (migration 20260416000000) cria dezenas de `plan_workout_releases` + uma `training_plan_weeks` por atleta. Se coach erra e atribui o pacote errado para 300 atletas, não há rollback atômico — teria que deletar manualmente linha por linha.

## Risco / Impacto
- Atletas recebem workout errado durante janela de correção manual (minutos ou horas);
- Push notifications já foram disparadas → caos;
- Coach perde confiança na ferramenta e volta para spreadsheet manual.

## Correção aplicada

Migration aditiva e retrocompatível introduzindo **batch tracking + TTL-gated atomic undo**:

### 1. Schema (`bulk_assign_batches`)
Registro por lote com actor, descrição, items_count, undo_ttl_minutes (1–1440, default 60), undone_at/by/reason. Colunas opcionais `bulk_batch_id` em `plan_workout_releases` e `training_plan_weeks`, indexadas parcialmente. Não quebra schemas existentes.

### 2. RPCs
- `fn_bulk_assign_batch_open` — abre batch, role gate coach/admin_master.
- `fn_bulk_assign_batch_attach` — anexa releases criados ao batch, defensa de group boundary.
- `fn_bulk_assign_batch_undo` — cancela atomicamente (releases + weeks), escreve audit log, marca batch como undone.
- `fn_bulk_assign_batch_summary` — read-only info para UI decidir se botão "Desfazer" está disponível.

### 3. Gates
- P0001 INVALID_INPUT (null/ttl fora de bounds)
- P0002 BATCH_NOT_FOUND
- P0003 BATCH_ALREADY_UNDONE (idempotente)
- P0005 UNDO_WINDOW_EXPIRED (TTL default 60 min)
- P0010 UNAUTHORIZED (role/author gates)

### 4. Segurança
- `SECURITY DEFINER` + `search_path = public, pg_temp` em todas as 4 RPCs.
- REVOKE PUBLIC, GRANT EXECUTE to authenticated.
- RLS em `bulk_assign_batches`: staff read, no direct DML.
- Author-only undo (platform_admin bypass para suporte).
- **Nenhuma função toca `coin_ledger`/`wallets`** — L04-07-OK reforçando política L22-02.

### 5. CI guard
`tools/audit/check-bulk-assign-rollback.ts` com ~70 asserts valida toda a superfície (schema, RLS, RPCs, gates, grants, audit trail, OmniCoin non-interference, self-test).

### 6. Integração coach tooling
UI chama `fn_bulk_assign_batch_open` → `fn_bulk_assign_week` (já existia) → `fn_bulk_assign_batch_attach` com os IDs retornados. Botão "Desfazer último lote" usa `summary` + `undo`.

## Teste de regressão
- `npm run audit:bulk-assign-rollback` — ~70 asserts.
- Smoke test: abrir batch, atribuir 3 semanas, undo, validar que releases ficam `cancelled` e batch fica `undone_at IS NOT NULL`.
- TTL: ajustar `created_at` para >60 min atrás, undo deve falhar com P0005.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[23.4]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 23 — Treinador, item 23.4).
- `2026-04-21` — Fixed via migration aditiva `20260421730000_l23_04_bulk_assign_rollback.sql` (tabela `bulk_assign_batches`, colunas `bulk_batch_id` em releases/weeks, 4 RPCs SECURITY DEFINER, RLS, self-test) + CI guard `audit:bulk-assign-rollback`. Backward-compatible: `fn_bulk_assign_week` existente continua funcionando; novos lotes são opt-in por coach tooling chamando `fn_bulk_assign_batch_open` antes.
