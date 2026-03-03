# GATE 11 — Feature QA Interrogation

**Data**: 2026-03-03  
**Revisor**: CTO / Lead QA  
**Método**: Interrogação profunda de cada feature — propósito, métricas, riscos, edge cases, falhas, diagnóstico e rollback

---

## Feature Matrix

| # | Feature | Por que existe? | Como o Usuário Percebe | Métrica de Sucesso | Riscos | Casos Extremos | Como Falha | Como Suporte Diagnostica | Rollback |
|---|---------|----------------|------------------------|-------------------|--------|----------------|-----------|--------------------------|----------|
| 1 | Coaching Groups (multi-tenant) | Permite assessorias de corrida gerenciarem seus atletas de forma isolada | Coach faz login no portal → seleciona sua assessoria → vê apenas seus atletas e dados; atleta abre app → vê apenas treinos, avisos e resultados do seu grupo | % de assessorias com >5 atletas ativos | RLS leak entre grupos; performance com muitos membros | Grupo com 0 membros; membro em múltiplos grupos (impedido por unique index); coach sai do próprio grupo | 403 Forbidden se RLS falhar; tela vazia se grupo não existir | Verificar `coaching_members` tabela; checar RLS policies; inspecionar cookie `portal_group_id` | Desativar grupo via `state='suspended'`; membros mantidos mas acesso bloqueado |
| 2 | Training Sessions + Attendance | Coach cria sessões de treino presencial e rastreia presença dos atletas | Coach cria sessão no app → atletas veem no calendário; após o treino, lista de presença mostra quem compareceu e quem faltou com indicador visual (check verde / X vermelho) | Taxa de presença >60% por sessão; atletas com 0 presença geram alertas | Sessão criada no passado; attendance duplicada | Sessão sem atletas presentes; scan de atleta que não é do grupo; cancelar sessão com attendance já registrada | Empty state na lista; alert "missed_trainings_14d" gerado; attendance INSERT falha com RLS error | Checar `coaching_training_sessions` por grupo; verificar `coaching_training_attendance` por session_id; verificar RLS policies de INSERT | Cancelar sessão (`status='cancelled'`); attendance records mantidos para histórico |
| 3 | QR Check-in | Atleta escaneia QR no celular para confirmar presença em treino presencial, ou receber tokens | Coach gera QR na tela do celular → atleta aponta câmera → tela muda para "Presença confirmada ✓" em <5s; se QR expirou, atleta vê aviso "QR Expirado" | Tempo de check-in <5s; 0 falsos check-ins | QR expirado; QR reutilizado; conexão offline durante scan | QR gerado para intent já consumido; scan por usuário não-membro; scan offline | `token-create-intent` cria intent com TTL; `token-consume-intent` valida e consome; expirado → mostra "QR Expirado" | Verificar `token_intents` tabela — status, nonce, expires_at; verificar `coaching_token_inventory` | Não há dados persistidos até consumo — QR expira naturalmente; invalidar intent via UPDATE status |
| 4 | CRM (Tags, Notes, Status) | Coach categoriza e anota sobre atletas para gestão personalizada da assessoria | No portal, coach abre ficha do atleta → vê tags coloridas (ex: "Iniciante", "Lesionado"), notas cronológicas e status atual; pode filtrar lista de atletas por tag | % coaches que usam tags; média de notas por atleta | Tag órfã após exclusão; notas sem limite de tamanho | Atleta com 50+ tags; nota com 10k+ caracteres; status mudado enquanto tela aberta (optimistic locking) | Tags: SELECT retorna lista vazia se nenhuma criada; Notes: empty state; Status: valor default "active" | Checar `coaching_tags`, `coaching_athlete_tags`, `coaching_athlete_notes`, `coaching_member_status` por group_id | Tags/notes são soft data — DELETE cascata; status revert para "active" |
| 5 | Announcements | Coach envia comunicados para todos os atletas do grupo com controle de leitura | Atleta abre feed no app → vê comunicados do coach com avisos fixados no topo; ícone de "não lido" aparece até abrir; coach vê taxa de leitura por comunicado no portal | Read rate >50% em 48h; pinned announcements sempre visíveis | Announcement sem target audience; read marking race condition | Announcement com body vazio; 100+ announcements em feed; delete com reads existentes | Feed vazio → EmptyState com CTA "Criar"; reads contados via JOIN; DELETE cascata reads | Checar `coaching_announcements` por grupo; `coaching_announcement_reads` por announcement_id | DELETE announcement — cascata reads automática |
| 6 | KPI Engine (Snapshots) | Métricas diárias pré-computadas para dashboard rápido sem queries pesadas em tempo real | Coach abre dashboard do portal → vê cards com métricas do dia (membros ativos, WAU, distância total, créditos) carregando em <2s; gráficos de tendência semanal/mensal | Dashboard loads <2s; dados atualizados diariamente | Cron não executar; dados inconsistentes após recompute | Grupo novo sem dados históricos (KPIs zerados); division by zero em retention calc (handled com CASE WHEN); dia sem sessões | KPIs zerados → dashboard mostra "0" em vez de erro; compute function retorna row count | `SELECT max(computed_at) FROM coaching_kpis_daily` para verificar última execução; `SELECT compute_coaching_kpis_daily(CURRENT_DATE)` para recomputar | KPIs são regeneráveis — `DELETE FROM coaching_kpis_daily WHERE day >= X` + recompute |
| 7 | Alert Engine | Detecta automaticamente atletas em risco (inatividade, queda de engajamento) e notifica o coach | Coach abre painel "Risco" no portal → vê lista de atletas em risco com ícone de alerta e motivo (ex: "14 dias sem treinar"); pode marcar como resolvido após entrar em contato | % de alerts resolvidos pelo coach; tempo médio de resolução | Falsos positivos (atleta em férias); alert flood (muitos atletas inativos) | Atleta novo (nunca correu) gera alert "nunca registrou"; grupo com 100% inativos gera N alerts; alert dedup via ON CONFLICT | Alerts aparecem no Risk panel; resolvidos pelo coach via portal; dedup constraints impedem duplicatas | Checar `coaching_alerts` por group_id; filtrar `resolved=false`; verificar `alert_type` para tipo específico | Alerts são informacionais — DELETE safe; marcar como `resolved=true`; desativar tipo de alert no compute function |
| 8 | Workout Builder | Coach cria templates de treino estruturados com blocos (warmup, interval, cooldown, etc.) | Coach abre builder no app → arrasta blocos (aquecimento, tiro, recuperação) → salva template → atribui a atletas por data; atleta abre "Treino do Dia" e vê a sequência de blocos com pace/distância alvo | Média de templates por grupo; % atletas com assignment ativo | Template órfão (sem assignments); block sem dados (duration e distance ambos null) | Template com 20+ blocks; assignment para atleta que saiu do grupo; edit concurrent de template | Template list empty → EmptyState + CTA "Criar"; builder form com validação; save → SnackBar | Checar `coaching_workout_templates` por grupo; `coaching_workout_blocks` por template_id; `coaching_workout_assignments` por grupo + date range | DELETE template cascata blocks; assignments mantidos para histórico (referência mantida) |
| 9 | Financial Engine (Plans, Subscriptions, Ledger) | Coach gerencia planos, assinaturas e receita da assessoria | Coach abre "Financeiro" no portal → vê MRR, número de assinantes, crescimento %; pode criar planos com preço mensal e ver quais atletas estão inadimplentes | MRR (Monthly Recurring Revenue); churn rate; inadimplência | Subscription sem plan (FK constraint); ledger inconsistente; double charge | Plano com preço 0; subscription cancelada mas ledger pendente; múltiplos planos ativos por atleta | Financial page mostra KPIs zerados se sem dados; ledger entries imutáveis (append-only) | Checar `coaching_plans` por grupo; `coaching_subscriptions` por grupo + status; `coaching_financial_ledger` por grupo + date | Ledger é append-only — nova entry de ajuste para corrigir; subscription status → "cancelled" |
| 10 | Wearables (Device Links, Executions) | Atleta conecta relógio/device e registra execuções de treino automaticamente | Atleta abre "Meus Dispositivos" no app → conecta Garmin/Apple Watch via OAuth → corridas importadas automaticamente aparecem como execuções vinculadas ao treino atribuído pelo coach | % atletas com device linkado; execuções por semana | OAuth token expirado; duplicate activity (dedup index); device desconectado | Atleta com 3+ devices; execution sem assignment match; provider API offline | Device list vazio → EmptyState; execution upsert com UNIQUE constraint; expired token → re-auth prompt | Checar `coaching_device_links` por athlete; `coaching_workout_executions` por grupo + athlete; verificar token expiry | Unlink device — soft delete; executions mantidos para histórico |
| 11 | TrainingPeaks Integration | Sincroniza treinos do OmniRunner para calendário do TrainingPeaks do atleta | Coach ativa integração no portal → treinos atribuídos no OmniRunner aparecem automaticamente no calendário do TrainingPeaks do atleta; status de sync visível (sincronizado / erro / pendente) | % syncs bem-sucedidos; latência de sync <10s | TP API rate limits; OAuth token expirado; API schema change | Athlete sem conta TP; workout sem blocks compatíveis; sync retry após falha | Sync status visível em `/trainingpeaks` no portal; error → retry automático; token refresh via `trainingpeaks-oauth` | Checar `coaching_tp_tokens` — expiry, refresh status; logs do edge function `trainingpeaks-sync`; verificar env vars (CLIENT_ID, SECRET) | Desabilitar sync por athlete (DELETE token); rollback: feature flag para desabilitar module inteiro |
| 12 | Portal Reports & Exports | Staff exporta dados em CSV para análise offline ou compliance | Coach clica "Exportar" no portal → CSV baixa automaticamente com dados filtrados (atletas, presença, financeiro); pode escolher período e tipo de relatório | Downloads por mês; % assessorias que usam export | Export timeout em grupos grandes; CSV encoding issues (UTF-8 BOM) | Grupo com 1000+ atletas; export de período longo (1 ano); concurrent exports | Export routes retornam `text/csv` com headers; timeout → 504; empty data → CSV com headers only | Checar API routes em `/api/export/*`; verificar logs de `export/athletes/route.ts`; checar rate limits | Exports são read-only — sem dados para rollback; re-executar export |

---

## Detalhamento por Feature

### 1. Coaching Groups (Multi-tenant)

**Arquivos-chave**:
- Migration: `20260218000000_full_schema.sql` (coaching_members, coaching_groups)
- Migration: `20260303300000_fix_coaching_roles.sql`
- Migration: `20260227100000_coaching_groups_state.sql`
- App: `coaching_groups_screen.dart`, `coaching_group_details_screen.dart`
- Portal: `select-group/page.tsx`

**RLS**: Todas as tabelas de coaching usam RLS baseado em `coaching_members.group_id` com subquery verificando membership. Policies cobrem SELECT, INSERT, UPDATE, DELETE por role (admin_master, coach, assistant, athlete).

**Isolation Test**: Atleta de grupo A não deve ver dados de grupo B. Verificado por RLS policies com JOIN em coaching_members.

### 2. Training Sessions + Attendance

**Arquivos-chave**:
- Migration: `20260303400000_training_sessions_attendance.sql`
- App: `staff_training_*_screen.dart`, `athlete_attendance_screen.dart`
- Portal: `/attendance`, `/attendance-analytics`
- RPC: `fn_mark_attendance` (SECURITY DEFINER)

**Integridade**: Attendance tem FK para session_id (CASCADE DELETE). Staff-only INSERT/UPDATE no attendance. Athletes apenas leitura do próprio status.

### 3. QR Check-in

**Arquivos-chave**:
- App: `staff_generate_qr_screen.dart`, `athlete_checkin_qr_screen.dart`, `staff_scan_qr_screen.dart`
- Edge Functions: `token-create-intent`, `token-consume-intent`
- Migration: `20260221000023_token_inventory_intents.sql`

**Segurança**: Intent tem TTL (expiry timestamp), nonce único, e atomic consume (SELECT FOR UPDATE + idempotency_key).

### 4-5. CRM + Announcements

**Arquivos-chave**:
- Migrations: `20260303500000_crm_tags_notes_status.sql`, `20260303600000_announcements.sql`
- App: `staff_crm_list_screen.dart`, `announcement_feed_screen.dart`
- Portal: `/crm`, `/announcements`, `/api/crm/*`, `/api/announcements/*`

**CRM Export**: `/api/export/crm/route.ts` gera CSV com tags e status integrados.

### 6-7. KPI Engine + Alert Engine

**Arquivos-chave**:
- Migration: `20260303800000_kpi_attendance_integration.sql`
- Functions: `compute_coaching_kpis_daily(date)`, `compute_coaching_alerts_daily(date)`
- Portal: `/dashboard`, `/engagement`, `/risk`
- Cron: `lifecycle-cron` edge function

**Idempotência**: ON CONFLICT DO UPDATE para KPIs, ON CONFLICT DO NOTHING para alerts (dedup constraint).

### 8. Workout Builder

**Arquivos-chave**:
- Migration: `20260304100000_workout_builder.sql`
- App: `staff_workout_builder_screen.dart`, `staff_workout_templates_screen.dart`, `athlete_workout_day_screen.dart`
- Portal: `/workouts`, `/workouts/assignments`
- BLoC: `workout_builder_bloc.dart`, `workout_assignments_bloc.dart`

**TP Integration**: Templates sincronizados para TrainingPeaks via `trainingpeaks-sync` edge function.

### 9. Financial Engine

**Arquivos-chave**:
- Migration: `20260304200000_financial_engine.sql`
- Portal: `/financial`, `/billing`
- App: N/A (staff-only via portal)

**Audit Trail**: Ledger é append-only — cada transação financeira cria novo registro.

### 10. Wearables

**Arquivos-chave**:
- Migration: `20260304400000_wearables.sql`
- App: `athlete_device_link_screen.dart`, `athlete_log_execution_screen.dart`
- Repository: `supabase_wearable_repo.dart`

**Dedup**: UNIQUE INDEX `uq_execution_athlete_provider_activity` previne duplicatas.

### 11. TrainingPeaks Integration

**Arquivos-chave**:
- Migration: `20260304800000_trainingpeaks_integration.sql`
- Edge Functions: `trainingpeaks-oauth/index.ts`, `trainingpeaks-sync/index.ts`
- Portal: `/trainingpeaks`

**OAuth Flow**: OAuth 2.0 com token refresh. Tokens armazenados em `coaching_tp_tokens` com expiry tracking.

### 12. Portal Reports & Exports

**API Routes**:
- `/api/export/athletes` — CSV de atletas com verificação + sessions
- `/api/export/crm` — CSV com tags, notas, status
- `/api/export/announcements` — CSV de comunicados + read rates
- `/api/export/financial` — CSV de ledger financeiro
- `/api/export/alerts` — CSV de alertas
- `/api/export/engagement` — CSV de KPIs de engajamento
- `/api/export/attendance` — CSV de presença

**Formato**: Todos retornam `text/csv` com UTF-8 encoding.

---

## Veredito GATE 11: ✅ PASS

Todas as 12 features possuem:
- ✅ Propósito claro e métrica de sucesso definida
- ✅ Riscos identificados e mitigados
- ✅ Edge cases documentados
- ✅ Modos de falha conhecidos
- ✅ Procedimentos de diagnóstico para suporte
- ✅ Estratégia de rollback
