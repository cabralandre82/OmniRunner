# QA GATE 4 — Edge Cases Matrix

> Generated: 2026-03-03  
> Sources: migration SQL files in `supabase/migrations/`, edge functions in `supabase/functions/`, Dart client code in `omni_runner/lib/`

---

## Metodologia

Cada cenário foi verificado contra o SQL real das RPCs (SECURITY DEFINER) e as constraints das tabelas. Os status possíveis são:

| Ícone | Significado |
|-------|-------------|
| ✅ | Tratado corretamente no código/SQL |
| ⚠️ | Tratamento parcial — funciona mas poderia ser mais robusto |
| ❌ | Não tratado — risco de erro em produção |

---

## 1. Treinos (Workout Builder)

| Cenário | Estado Esperado | Tratamento Atual | Status |
|---------|----------------|-------------------|--------|
| Grupo sem templates | Lista vazia retornada, UI mostra empty state | RLS `staff_templates_select` retorna 0 rows; `fn_assign_workout` retorna `TEMPLATE_NOT_FOUND` se template_id inexistente | ✅ |
| Template sem blocos | Payload de export retorna `blocks: []` | `fn_generate_workout_payload` usa `coalesce(jsonb_agg(...), '[]'::jsonb)` — retorna array vazio | ✅ |
| Assignment sem execução | Assignment fica com `status = 'planned'` | Coluna `status` default `'planned'`; sem execução, nunca muda para `'completed'` — correto | ✅ |
| Execução parcial (dados nulos) | Execução salva com campos NULL | `fn_import_execution` aceita todos parâmetros como DEFAULT NULL; colunas `actual_duration_seconds`, `actual_distance_meters` etc. são nullable | ✅ |
| Treino cancelado (assignment deleted via template cascade) | Assignment removido se template é deletado | `coaching_workout_assignments.template_id` tem `ON DELETE CASCADE`; execuções com `assignment_id` ficam com `ON DELETE SET NULL` — dados preservados | ✅ |
| Sessão expirada (scheduled_date no passado) | Assignment permanece como `planned` (vira `missed` via batch?) | Sem mecanismo automático para marcar como `missed` — depende de lógica de aplicação futura | ⚠️ |
| Assign quando subscription está `late` | Bloqueado com erro `SUBSCRIPTION_LATE` | `fn_assign_workout` (BLOCO C) verifica `v_sub_status = 'late'` e retorna erro | ✅ |
| Assign quando subscription está `cancelled`/`paused` | Bloqueado com erro `SUBSCRIPTION_INACTIVE` | `fn_assign_workout` verifica `v_sub_status IN ('cancelled','paused')` | ✅ |
| Assign sem subscription (grupo sem planos) | Permitido | `fn_assign_workout` permite se `v_sub_status IS NULL` — "group may not use plans" | ✅ |
| Limite semanal de treinos atingido | Bloqueado com `WEEKLY_LIMIT_REACHED` | `fn_assign_workout` conta assignments na semana e compara com `max_workouts_per_week` do plano | ✅ |
| Assign duplicado (mesmo atleta, mesma data) | Upsert — atualiza template e incrementa version | `ON CONFLICT (athlete_user_id, scheduled_date) DO UPDATE SET template_id=..., version=version+1` | ✅ |

---

## 2. Presença (QR Check-in)

| Cenário | Estado Esperado | Tratamento Atual | Status |
|---------|----------------|-------------------|--------|
| QR expirado (`expires_at` ultrapassado) | Check-in rejeitado | `fn_issue_checkin_token` gera `expires_at` como epoch ms; **validação do expires_at é feita no cliente (Dart/Flutter)**, não na RPC `fn_mark_attendance` | ⚠️ |
| QR inválido (nonce corrompido) | Check-in rejeitado | `fn_mark_attendance` recebe `p_nonce` mas **não valida o nonce** — sem verificação criptográfica server-side; valida session_id e membership | ⚠️ |
| Atleta não pertence ao grupo | Rejeitado com `ATHLETE_NOT_IN_GROUP` | `fn_mark_attendance` verifica membership: `IF NOT EXISTS (SELECT 1 FROM coaching_members WHERE group_id=v_group_id AND user_id=p_athlete_user_id)` | ✅ |
| Duplicação (mesmo atleta, mesma sessão) | Idempotente — retorna `already_present` | `INSERT ... ON CONFLICT (session_id, athlete_user_id) DO NOTHING`; se conflict, retorna `{ok:true, status:'already_present'}` | ✅ |
| Sessão cancelada | Check-in rejeitado com `SESSION_CANCELLED` | `fn_mark_attendance`: `IF v_session.status = 'cancelled' THEN RETURN ...SESSION_CANCELLED` | ✅ |
| Sessão inexistente | Rejeitado com `SESSION_NOT_FOUND` | `fn_mark_attendance` verifica `IF v_session IS NULL` | ✅ |
| Chamador não é staff | Rejeitado com `NOT_STAFF` | `fn_mark_attendance` verifica caller role `IN ('admin_master','coach','assistant')` | ✅ |
| QR gerado por não-membro | Rejeitado com `NOT_IN_GROUP` | `fn_issue_checkin_token` verifica membership do caller | ✅ |

---

## 3. CRM (Tags, Notas, Status)

| Cenário | Estado Esperado | Tratamento Atual | Status |
|---------|----------------|-------------------|--------|
| Grupo sem tags | Lista vazia | RLS `tags_staff_read` retorna 0 rows; UI deve tratar empty state | ✅ |
| Nota vazia (body vazio) | Rejeitada | `coaching_athlete_notes.note` tem `CHECK (length(trim(note)) >= 1)` — constraint rejeita vazio | ✅ |
| Tag duplicada (mesmo nome no grupo) | Rejeitada | `UNIQUE (group_id, name)` constraint em `coaching_tags` | ✅ |
| Status inexistente passado para `fn_upsert_member_status` | RPC executa mas DB rejeita | `coaching_member_status.status` tem `CHECK (status IN ('active','paused','injured','inactive','trial'))` — constraint cuida; RPC **não** valida o valor antes do INSERT | ⚠️ |
| Atleta removido do grupo — tags/notas/status órfãos | Dados órfãos ficam no banco | `coaching_athlete_tags`, `coaching_athlete_notes`, `coaching_member_status` **não** têm FK para `coaching_members` — quando membro é removido via `fn_remove_member` (DELETE coaching_members), os dados CRM permanecem | ⚠️ |
| Tag atribuída a atleta que já saiu | Tag persiste mas fica invisível (RLS filtra) | RLS exige membership, então staff de outro grupo não vê; dados permanecem para caso o atleta volte | ✅ |
| `fn_upsert_member_status` para user não membro | Rejeitado com `USER_NOT_IN_GROUP` | RPC verifica `IF NOT EXISTS (SELECT 1 FROM coaching_members WHERE group_id=p_group_id AND user_id=p_user_id)` | ✅ |

---

## 4. Anúncios (Comunicação)

| Cenário | Estado Esperado | Tratamento Atual | Status |
|---------|----------------|-------------------|--------|
| Grupo sem anúncios | Lista vazia | RLS `announcements_member_read` retorna 0 rows | ✅ |
| Leitura duplicada (mesmo user, mesmo anúncio) | Idempotente | `fn_mark_announcement_read`: `INSERT ... ON CONFLICT (announcement_id, user_id) DO NOTHING` | ✅ |
| Anúncio deletado após leitura | Reads removidas via cascade | `coaching_announcement_reads.announcement_id` tem `ON DELETE CASCADE` | ✅ |
| `fn_mark_announcement_read` por não-membro | Rejeitado com `NOT_IN_GROUP` | RPC verifica membership antes do INSERT | ✅ |
| `fn_announcement_read_stats` por não-staff | Rejeitado com `NOT_STAFF` | RPC verifica role `IN ('admin_master','coach','assistant')` | ✅ |
| Stats com 0 membros (divisão por zero) | `read_rate` retorna 0 | `CASE WHEN v_total > 0 THEN round(...) ELSE 0 END` | ✅ |
| Anúncio inexistente passado para read/stats | Rejeitado com `ANNOUNCEMENT_NOT_FOUND` | Ambas RPCs verificam `IF v_group_id IS NULL` após SELECT | ✅ |

---

## 5. Financeiro (Engine Financeiro)

| Cenário | Estado Esperado | Tratamento Atual | Status |
|---------|----------------|-------------------|--------|
| Grupo sem planos | Nenhum plano listado; subscriptions impossíveis | RLS `staff_plans_select`/`athlete_plans_select` retorna 0 rows | ✅ |
| Subscription inexistente para `fn_update_subscription_status` | Rejeitado com `SUBSCRIPTION_NOT_FOUND` | RPC verifica `IF v_group_id IS NULL` após SELECT | ✅ |
| Status `late` → bloqueio de assign | Assign bloqueado | `fn_assign_workout` (BLOCO C) retorna `SUBSCRIPTION_LATE` | ✅ |
| Status `paused`/`cancelled` → bloqueio | Assign bloqueado | `fn_assign_workout` retorna `SUBSCRIPTION_INACTIVE` | ✅ |
| Ledger vazio (sem lançamentos) | Relatório mostra R$0 | KPI compute usa `coalesce(sum(l.amount)..., 0)` — retorna 0 | ✅ |
| Período sem dados financeiros | revenue_month = 0 | Compute query usa `coalesce(..., 0)` | ✅ |
| `fn_create_ledger_entry` com `amount <= 0` | Rejeitado com `INVALID_AMOUNT` | RPC valida `IF p_amount IS NULL OR p_amount <= 0` | ✅ |
| `fn_create_ledger_entry` com tipo inválido | Rejeitado com `INVALID_TYPE` | RPC valida `IF p_type NOT IN ('revenue','expense')` | ✅ |
| `fn_update_subscription_status` com status inválido | Rejeitado com `INVALID_STATUS` | RPC valida `IF p_new_status NOT IN ('active','late','paused','cancelled')` | ✅ |
| Currency null | Não há coluna currency | `coaching_financial_ledger` usa `amount numeric(12,2)` sem coluna de moeda — assume moeda única | ⚠️ |
| Subscription duplicada (mesmo atleta, mesmo grupo) | Rejeitada | `UNIQUE (athlete_user_id, group_id)` em `coaching_subscriptions` | ✅ |

---

## 6. Wearables (Device Links + Executions)

| Cenário | Estado Esperado | Tratamento Atual | Status |
|---------|----------------|-------------------|--------|
| Token expirado (access_token TP/Garmin) | Push falha, sync_status = 'failed' | `trainingpeaks-sync` edge fn: se TP API retorna erro, marca `sync_status='failed'` com mensagem | ✅ |
| Provider indisponível (API offline) | Push falha gracefully | Edge fn: `catch(err)` marca `sync_status='failed'` com `err.message` | ✅ |
| Payload inválido (`fn_generate_workout_payload` com assignment inexistente) | Retorna `ASSIGNMENT_NOT_FOUND` | RPC verifica `IF v_assignment IS NULL` | ✅ |
| Import duplicado (mesma provider_activity_id) | `ON CONFLICT DO NOTHING`, retorna `DUPLICATE` | `fn_import_execution`: `ON CONFLICT (athlete_user_id, provider_activity_id) WHERE provider_activity_id IS NOT NULL DO NOTHING`; se `v_exec_id IS NULL`, retorna `{ok:true, code:'DUPLICATE'}` | ✅ |
| Device link removido durante sync | Push falha com "No access token" | `trainingpeaks-sync`: verifica `if (!accessToken)` e marca `failed` | ✅ |
| `fn_import_execution` sem assignment (manual) | Resolve group_id do membership | RPC faz fallback: `SELECT cm.group_id FROM coaching_members WHERE user_id=v_uid AND role='athlete' LIMIT 1` | ✅ |
| Device link duplicado (mesmo atleta, mesmo provider) | Upsert | `UNIQUE (athlete_user_id, provider)` em `coaching_device_links`; OAuth callback usa `upsert` com `onConflict` | ✅ |
| Atleta sem grupo tentando import | Rejeitado com `NO_GROUP` | `fn_import_execution`: se nenhum `coaching_members` row, retorna `NO_GROUP` | ✅ |

---

## 7. TrainingPeaks (Integração TP)

| Cenário | Estado Esperado | Tratamento Atual | Status |
|---------|----------------|-------------------|--------|
| TP não vinculado | Push rejeitado com `TP_NOT_LINKED` | `fn_push_to_trainingpeaks`: verifica device_link com `provider='trainingpeaks'`; se NULL, retorna erro | ✅ |
| Sync falhado (API error) | sync_status = 'failed' com error_message | `trainingpeaks-sync` edge fn salva `error_message: 'TP API {status}: {body}'` | ✅ |
| Workout já pushed (re-push) | Upsert — reseta para 'pending' | `fn_push_to_trainingpeaks`: `ON CONFLICT (assignment_id, athlete_user_id) DO UPDATE SET sync_status='pending', error_message=NULL` | ✅ |
| Token expirado no TP | Push falha; refresh disponível | `trainingpeaks-oauth` edge fn tem action `refresh` que troca refresh_token por novo access_token; **mas** `trainingpeaks-sync` não faz refresh automático antes do push | ⚠️ |
| Assignment deletado durante sync | FK cascade remove tp_sync row | `coaching_tp_sync.assignment_id` tem `ON DELETE CASCADE` | ✅ |
| Pull sem TP links no grupo | Retorna `{imported: 0}` | `trainingpeaks-sync` action `pull`: verifica `if (!links?.length)` | ✅ |
| Pull com workout sem CompletedDate | Workout ignorado | `if (!tw.CompletedDate || !tw.TotalTimePlanned) continue` | ✅ |

---

## 8. KPIs / Alerts (Analytics)

| Cenário | Estado Esperado | Tratamento Atual | Status |
|---------|----------------|-------------------|--------|
| Primeiro dia sem snapshots (dia 1) | KPIs com valores 0/null | Compute usa `LEFT JOIN LATERAL` com `coalesce(..., 0)` para todos; `_kpi_sessions` temp table retorna vazio | ✅ |
| D-1 ausente (gap no histórico) | Compute para qualquer dia funciona independente | Cada chamada é autocontida — calcula tudo do zero para `p_day`. Sem dependência de D-1 | ✅ |
| Compute 3x no mesmo dia (idempotência) | Mesmos dados, sem duplicação | `INSERT ... ON CONFLICT (group_id, day) DO UPDATE SET ...` para KPIs; `ON CONFLICT (group_id, user_id, day, alert_type) DO NOTHING` para alerts | ✅ |
| Grupo sem membros | KPIs com zeros | `coalesce(mem.total_members, 0)` etc. Handles gracefully | ✅ |
| Grupo sem sessões de corrida | sessions_today=0, dau=0 | Temp table `_kpi_sessions` vazia → all LEFT JOINs return NULL → coalesce to 0 | ✅ |
| attendance_rate com 0 sessões (divisão por zero) | NULL | `CASE WHEN coalesce(att.training_sessions_7d,0)=0 OR coalesce(mem.total_athletes,0)=0 THEN NULL` | ✅ |
| compute_coaching_alerts_daily sem athlete_kpis | 0 alerts gerados | JOINs com `coaching_athlete_kpis_daily` simplesmente não retornam rows | ✅ |
| Alert dedup constraints presentes | Confirmado | `uq_kpis_group_day`, `uq_athlete_kpis_group_user_day`, `uq_alert_dedup` — verified in `20260303300001_alert_dedup_constraints.sql` | ✅ |

---

## 9. Portal (Dashboard Staff)

| Cenário | Estado Esperado | Tratamento Atual | Status |
|---------|----------------|-------------------|--------|
| Período sem dados nos gráficos | Gráfico mostra série vazia ou mensagem | KPI queries retornam 0 rows para período; frontend deve tratar empty state | ⚠️ |
| Filtros vazios (sem atletas correspondendo) | Lista vazia | Queries filtram via WHERE; 0 resultados é válido | ✅ |
| Export CSV vazio (sem dados) | CSV com apenas header | Implementação em `portal/src/app/api/export/athletes/route.ts` — retorna CSV header mesmo sem dados | ✅ |
| Paginação última página (offset > total) | Lista vazia | Queries com OFFSET/LIMIT retornam 0 rows quando offset excede | ✅ |
| Usuário sem grupo ativo | Redirecionado para seleção | Middleware verifica `active_coaching_group_id`; se null, redireciona para `/select-group` | ✅ |

---

## Resumo Geral

| Módulo | Total Cenários | ✅ | ⚠️ | ❌ |
|--------|---------------|-----|-----|-----|
| Treinos | 11 | 10 | 1 | 0 |
| Presença | 8 | 6 | 2 | 0 |
| CRM | 7 | 5 | 2 | 0 |
| Anúncios | 7 | 7 | 0 | 0 |
| Financeiro | 11 | 10 | 1 | 0 |
| Wearables | 8 | 8 | 0 | 0 |
| TrainingPeaks | 7 | 6 | 1 | 0 |
| KPIs/Alerts | 8 | 8 | 0 | 0 |
| Portal | 5 | 4 | 1 | 0 |
| **TOTAL** | **72** | **64** | **8** | **0** |

### Itens ⚠️ — Ações recomendadas

1. **Treinos — sessão expirada**: Implementar cron ou compute que marca assignments passados como `missed` automaticamente.
2. **Presença — QR expirado**: Validação de `expires_at` é only client-side. Recomendação: validar `expires_at` dentro de `fn_mark_attendance` server-side.
3. **Presença — QR nonce**: `fn_mark_attendance` recebe `p_nonce` mas não valida. Risco baixo (session_id+membership já validam), mas nonce deveria ser checado para evitar replay fora da janela.
4. **CRM — status inexistente**: `fn_upsert_member_status` não valida o valor antes do INSERT — depende da CHECK constraint que gera erro genérico. Recomendação: validar na RPC e retornar mensagem amigável.
5. **CRM — dados órfãos pós-remoção**: Quando atleta é removido via `fn_remove_member`, tags/notas/status permanecem. Considerar cleanup cascade ou soft-delete.
6. **Financeiro — currency**: Sem coluna de moeda. OK para MVP single-currency, mas documentar limitação.
7. **TrainingPeaks — auto-refresh**: `trainingpeaks-sync` push não faz refresh automático de token expirado. Recomendação: tentar refresh antes de marcar como failed.
8. **Portal — período vazio**: Frontend deve ter empty state para gráficos sem dados no período selecionado.
