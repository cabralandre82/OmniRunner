---
id: L04-04
audit_ref: "4.4"
lens: 4
title: "Dados de saúde/biométricos (dados sensíveis, LGPD Art. 11) sem proteção reforçada"
severity: critical
status: in-progress
wave: 0
discovered_at: 2026-04-17
tags: ["lgpd", "rls", "gps", "mobile", "migration", "testing"]
files:
  - supabase/migrations/20260417230000_sensitive_health_data_protection.sql
  - portal/src/lib/sensitive-access.ts
  - portal/src/app/api/ai/athlete-briefing/route.ts
  - portal/src/app/(portal)/athletes/[id]/page.tsx
  - tools/integration_tests.ts
correction_type: process
test_required: true
tests:
  - tools/integration_tests.ts::"L04-04 ·*"
linked_issues: []
linked_prs: []
owner: unassigned
runbook: docs/audit/runbooks/L04-04-sensitive-health-access.md
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: "RPCs fn_can_read_athlete_health / fn_log_sensitive_access / fn_read_athlete_health_snapshot entregues; service_role clients no Portal refatorados para `ensureCoachHealthAccess` antes de acessar sessions/runs/baselines/trends."
---
# [L04-04] Dados de saúde/biométricos (dados sensíveis, LGPD Art. 11) sem proteção reforçada
> **Lente:** 4 — CLO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** 🟡 in-progress
**Camada:** Banco + Portal (service_role clients) + Edge Functions
**Personas impactadas:** Atleta, Coach, Assistente, Admin Master
## Achado
- `sessions`, `runs`, `athlete_baselines`, `athlete_trends`, `coaching_athlete_kpis_daily`, `running_dna_profiles`, `support_tickets` armazenam dados pessoais sensíveis (LGPD Art. 11):
  - Frequência cardíaca média/max
  - Pace / cadência / ritmo (indicador de condicionamento físico)
  - Trajetórias GPS (localização precisa)
  - Lesões / queixas em `support_tickets`
  - VO₂ máx, limiar de lactato, recovery heart rate
- Antes desta correção **não existia**:
  - Registro explícito de quais colunas são sensíveis (catalogação)
  - Log de acesso cross-user a dados sensíveis (auditabilidade)
  - Gate de consent `coach_data_share` antes de leituras feitas por coaches / assistentes
  - Path de acesso único para callers que usam `service_role` (bypass de RLS)

## Risco / Impacto
Vazamento de dados de saúde = enforcement agravado LGPD Art. 52 + possível ação coletiva (atletas profissionais / amadores de visibilidade). Sem log de acesso, não é possível comprovar quem leu o quê — requisito do Art. 37 (registro de operações).

## Correção aplicada

Arquivo: `supabase/migrations/20260417230000_sensitive_health_data_protection.sql`.

### 1. Registry de colunas sensíveis
`public.sensitive_health_columns (table_name, column_name, category, legal_basis, rationale)` — categoriza cada coluna em `health | biometric | location | physical_perf` com base legal (Art. 7 execução de contrato, Art. 11 § 2º I execução de contrato sobre dado sensível para finalidade esportiva). Popular via `INSERT ... WHERE to_regclass(...) IS NOT NULL` para tolerar tabelas opcionais.

### 2. Log append-only
`public.sensitive_data_access_log (actor_id, subject_id, resource, action, request_id, ip, user_agent, row_count, denied, denial_reason, accessed_at)` com:
- RLS habilitada (ninguém escreve direto; apenas `SECURITY DEFINER` RPCs).
- Trigger `BEFORE UPDATE/DELETE` bloqueando mutações (append-only).
- Registrada em `lgpd_deletion_strategy` com `action='anonymize'` para `actor_id`/`subject_id` → preserva trilha pós-erasure.

### 3. RPCs de acesso
- `fn_can_read_athlete_health(p_athlete_id)` — verifica self OR coach/assistente/admin_master com consent `coach_data_share` válido em `v_user_consent_status`.
- `fn_log_sensitive_access(...)` — grava entrada em `sensitive_data_access_log`.
- `fn_read_athlete_health_snapshot(...)` — accessor canônico que **não lança exceção em denial** (retorna `{ error: 'NOT_AUTHORIZED', denial_reason }`) para preservar o log mesmo em acesso bloqueado.

### 4. RLS endurecida (consent-gated)
Políticas antigas (`*_staff_read`, `baselines_read`, `trends_read`) removidas. Novas policies exigem:
- Self access: `user_id = auth.uid()` (atleta sempre lê o próprio dado, independente de consent).
- Cross-user: `fn_can_read_athlete_health(user_id)` — que internamente exige consent `coach_data_share` ativo.

### 5. Auto-grant + backfill
- Trigger `_auto_grant_coach_data_share` em `coaching_members` emite `consent_event(type='coach_data_share', status='granted', source='system', base='execucao_contrato')` ao inserir um atleta, documentando a base legal.
- Bloco `DO $$` faz backfill equivalente para relacionamentos `coaching_members` pré-existentes (`source='backfill'`).
- Check constraint `consent_events_source_check` estendido para aceitar `'system'` e `'backfill'`.

### 6. Detector de drift
`public.v_sensitive_health_coverage_gaps` sinaliza `missing_table` / `missing_column` / `rls_disabled` quando o registry aponta para colunas que deixem de existir ou tabelas com RLS desabilitada. Integrado a `tools/integration_tests.ts`.

### 7. Refactor dos callers (service_role)
Novo helper `portal/src/lib/sensitive-access.ts::ensureCoachHealthAccess` encapsula:
1. RPC `fn_can_read_athlete_health` (no contexto do usuário autenticado);
2. RPC `fn_log_sensitive_access` (audit, inclusive em denial);
3. Retorno estruturado `SensitiveReadOutcome` que o caller traduz em HTTP 403.

Integrado em:
- `portal/src/app/api/ai/athlete-briefing/route.ts` (briefing AI → lê `sessions`).
- `portal/src/app/(portal)/athletes/[id]/page.tsx` (perfil do atleta → agregados de `sessions`).

Outros callers service_role em `portal/src/app/(portal)/dashboard/page.tsx`, `.../engagement/page.tsx`, `.../api/staff-alerts/route.ts` fazem agregação sobre **o próprio grupo do coach** — consent `coach_data_share` é auto-granted pelo trigger em `coaching_members`, e nenhum dado per-athlete bruto é retornado ao cliente. Mesmo assim foram sinalizados no runbook para futura auditoria bulk-access.

## Teste de regressão
13 testes em `tools/integration_tests.ts`:
1. Registry populado com categorias corretas.
2. `v_sensitive_health_coverage_gaps` limpo para tabelas base.
3. `fn_can_read_athlete_health` — self → true.
4. Coach bloqueado após revogação de consent.
5. Coach autorizado com consent granted.
6. Coach de outro grupo sempre bloqueado.
7. `fn_read_athlete_health_snapshot` retorna payload `NOT_AUTHORIZED` + loga denial.
8. `fn_read_athlete_health_snapshot` sucesso loga acesso + retorna snapshot JSON.
9. RLS `athlete_baselines` — 0 linhas sem consent, 1 linha com consent.
10. RLS `athlete_baselines` — atleta sempre vê o próprio baseline.
11. Trigger `_auto_grant_coach_data_share` emite `consent_event` ao inserir em `coaching_members`.
12. `sensitive_data_access_log` é append-only (UPDATE bloqueado).
13. `sensitive_data_access_log.actor_id`/`subject_id` registrados para anonimização em `lgpd_deletion_strategy`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[4.4]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 4 — CLO, item 4.4).
- `2026-04-17` — Correção aplicada: registry + log append-only + RPCs consent-gated + RLS reforçada + auto-grant/backfill + refactor service_role callers + 13 testes.
