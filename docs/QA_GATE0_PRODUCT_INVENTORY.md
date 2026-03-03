# GATE 0 — Inventário Completo do Produto

> Gerado a partir de paths reais do repositório.  
> Data: 2026-03-03

---

## 1. Mapa de Telas — App Flutter

### Staff Screens

| Tela | Path | Objetivo | Dados |
|------|------|----------|-------|
| Staff Dashboard | `presentation/screens/staff_dashboard_screen.dart` | Hub principal staff — 6 cards (Atletas, Confirmações, Performance, Campeonatos, Créditos, Administração) | coaching_members, coaching_groups, coaching_token_inventory, clearing_settlements |
| Staff Athlete Profile | `presentation/screens/staff_athlete_profile_screen.dart` | Perfil individual do atleta com métricas e histórico | profiles, sessions, athlete_verification, coaching_member_status |
| Staff CRM List | `presentation/screens/staff_crm_list_screen.dart` | Lista CRM de atletas com tags, notas e status | coaching_member_status, coaching_athlete_tags, coaching_athlete_notes |
| Staff Performance | `presentation/screens/staff_performance_screen.dart` | KPIs de performance do grupo (WAU, distância, sessões) | sessions, coaching_members, kpi_daily_snapshots |
| Staff Retention Dashboard | `presentation/screens/staff_retention_dashboard_screen.dart` | Dashboard de retenção e risco de churn | coaching_alerts, coaching_member_status, kpi_daily_snapshots |
| Staff Weekly Report | `presentation/screens/staff_weekly_report_screen.dart` | Relatório semanal consolidado | sessions, coaching_members, coin_ledger |
| Staff Setup | `presentation/screens/staff_setup_screen.dart` | Configuração inicial da assessoria | coaching_groups, profiles |
| Staff Join Requests | `presentation/screens/staff_join_requests_screen.dart` | Gerenciar pedidos de ingresso | coaching_members (role=pending) |
| Staff QR Hub | `presentation/screens/staff_qr_hub_screen.dart` | Hub de emissão de QR codes (tokens + checkin) | token_intents, coaching_token_inventory |
| Staff Generate QR | `presentation/screens/staff_generate_qr_screen.dart` | Geração de QR code para distribuir OmniCoins | token_intents |
| Staff Scan QR | `presentation/screens/staff_scan_qr_screen.dart` | Escanear QR para consumir intents | token_intents |
| Staff Credits | `presentation/screens/staff_credits_screen.dart` | Inventário de créditos e informação de aquisição | coaching_token_inventory, coaching_badge_inventory |
| Staff Disputes | `presentation/screens/staff_disputes_screen.dart` | Gestão de disputas de clearing | clearing_settlements |
| Staff Challenge Invites | `presentation/screens/staff_challenge_invites_screen.dart` | Convidar grupo para desafios | challenges, challenge_participants |
| Staff Championship Templates | `presentation/screens/staff_championship_templates_screen.dart` | Gerenciar templates de campeonatos | championship_templates |
| Staff Championship Manage | `presentation/screens/staff_championship_manage_screen.dart` | Administrar campeonato ativo | championships, championship_participants |
| Staff Championship Invites | `presentation/screens/staff_championship_invites_screen.dart` | Enviar convites para campeonatos | championship_invites |
| Staff Workout Templates | `presentation/screens/staff_workout_templates_screen.dart` | Listar templates de treino | coaching_workout_templates |
| Staff Workout Builder | `presentation/screens/staff_workout_builder_screen.dart` | Criar/editar template de treino com blocos | coaching_workout_templates, coaching_workout_blocks |
| Staff Workout Assign | `presentation/screens/staff_workout_assign_screen.dart` | Atribuir treino a atleta(s) | coaching_workout_assignments, coaching_subscriptions |
| Staff Training List | `presentation/screens/staff_training_list_screen.dart` | Listar sessões de treino agendadas | coaching_training_sessions |
| Staff Training Create | `presentation/screens/staff_training_create_screen.dart` | Criar sessão de treino presencial | coaching_training_sessions |
| Staff Training Detail | `presentation/screens/staff_training_detail_screen.dart` | Detalhes da sessão + lista presença | coaching_training_sessions, coaching_training_attendance |
| Staff Training Scan | `presentation/screens/staff_training_scan_screen.dart` | Escanear QR de check-in de presença | coaching_training_attendance |
| Announcement Create | `presentation/screens/announcement_create_screen.dart` | Criar comunicado para o grupo | coaching_announcements |
| Coaching Groups | `presentation/screens/coaching_groups_screen.dart` | Lista de grupos de coaching do usuário | coaching_groups, coaching_members |
| Coaching Group Details | `presentation/screens/coaching_group_details_screen.dart` | Detalhes do grupo com membros | coaching_groups, coaching_members |
| Group Members | `presentation/screens/group_members_screen.dart` | Listar membros do grupo | coaching_members, profiles |
| Coach Insights | `presentation/screens/coach_insights_screen.dart` | Insights analíticos para o coach | coach_insights, kpi_daily_snapshots |

### Athlete Screens

| Tela | Path | Objetivo | Dados |
|------|------|----------|-------|
| Athlete Dashboard | `presentation/screens/athlete_dashboard_screen.dart` | Hub principal atleta — 6 cards (Desafios, Assessoria, Progresso, Créditos, Campeonatos, Convidar) | coaching_members, challenges, wallet |
| Athlete Workout Day | `presentation/screens/athlete_workout_day_screen.dart` | Treino do dia com blocos detalhados | coaching_workout_assignments, coaching_workout_blocks |
| Athlete Log Execution | `presentation/screens/athlete_log_execution_screen.dart` | Registrar execução manual de treino | coaching_workout_executions |
| Athlete Training List | `presentation/screens/athlete_training_list_screen.dart` | Listar sessões de treino disponíveis | coaching_training_sessions |
| Athlete Attendance | `presentation/screens/athlete_attendance_screen.dart` | Histórico de presenças | coaching_training_attendance |
| Athlete Checkin QR | `presentation/screens/athlete_checkin_qr_screen.dart` | Escanear QR para registrar presença | coaching_training_attendance |
| Athlete Device Link | `presentation/screens/athlete_device_link_screen.dart` | Vincular/desvincular wearables e TrainingPeaks | coaching_device_links |
| Athlete My Evolution | `presentation/screens/athlete_my_evolution_screen.dart` | Evolução pessoal ao longo do tempo | sessions, athlete_baselines, athlete_trends |
| Athlete Evolution | `presentation/screens/athlete_evolution_screen.dart` | Detalhamento de métricas de evolução | sessions, progression |
| Athlete My Status | `presentation/screens/athlete_my_status_screen.dart` | Status atual (verificação, coins, assessoria) | athlete_verification, wallet, coaching_member_status |
| Athlete Verification | `presentation/screens/athlete_verification_screen.dart` | Status de verificação do atleta | athlete_verification |
| Athlete Championships | `presentation/screens/athlete_championships_screen.dart` | Listar campeonatos disponíveis | championships |
| Athlete Championship Ranking | `presentation/screens/athlete_championship_ranking_screen.dart` | Ranking de um campeonato | championship_participants |
| Announcement Feed | `presentation/screens/announcement_feed_screen.dart` | Feed de comunicados do grupo | coaching_announcements |
| Announcement Detail | `presentation/screens/announcement_detail_screen.dart` | Detalhe do comunicado + marcar como lido | coaching_announcements, coaching_announcement_reads |
| My Assessoria | `presentation/screens/my_assessoria_screen.dart` | Informações da assessoria do atleta | coaching_groups, coaching_members |
| Assessoria Feed | `presentation/screens/assessoria_feed_screen.dart` | Feed público da assessoria | assessoria_feed |
| Join Assessoria | `presentation/screens/join_assessoria_screen.dart` | Buscar e solicitar ingresso em assessoria | coaching_groups |
| Partner Assessorias | `presentation/screens/partner_assessorias_screen.dart` | Assessorias parceiras | coaching_groups |
| Wallet | `presentation/screens/wallet_screen.dart` | Saldo e histórico de OmniCoins | coin_ledger, wallet |
| Challenges List | `presentation/screens/challenges_list_screen.dart` | Listar desafios ativos | challenges |
| Challenge Create | `presentation/screens/challenge_create_screen.dart` | Criar novo desafio | challenges |
| Challenge Details | `presentation/screens/challenge_details_screen.dart` | Detalhes e progresso do desafio | challenges, challenge_participants |
| Challenge Invite | `presentation/screens/challenge_invite_screen.dart` | Convidar amigos para desafio | challenges, friendships |
| Challenge Join | `presentation/screens/challenge_join_screen.dart` | Aceitar convite de desafio | challenges |
| Challenge Result | `presentation/screens/challenge_result_screen.dart` | Resultado final do desafio | challenge_results |
| Matchmaking | `presentation/screens/matchmaking_screen.dart` | Encontrar oponente para desafio | profiles, matchmaking |
| Progress Hub | `presentation/screens/progress_hub_screen.dart` | Hub de evolução (streaks, badges, XP) | profile_progress, badges, missions |
| Progression | `presentation/screens/progression_screen.dart` | Detalhes de progressão (nível, XP) | progression |
| Personal Evolution | `presentation/screens/personal_evolution_screen.dart` | Evolução pessoal com gráficos | athlete_baselines, athlete_trends |
| Streaks Leaderboard | `presentation/screens/streaks_leaderboard_screen.dart` | Ranking de streaks | leaderboard |
| Leaderboards | `presentation/screens/leaderboards_screen.dart` | Leaderboards gerais | leaderboard |
| Badges | `presentation/screens/badges_screen.dart` | Coleção de badges do atleta | badge_awards, badges |
| Missions | `presentation/screens/missions_screen.dart` | Missões diárias e semanais | missions, mission_progress |
| Running DNA | `presentation/screens/running_dna_screen.dart` | Perfil genético de corrida | running_dna |
| Wrapped | `presentation/screens/wrapped_screen.dart` | Resumo anual estilo Spotify Wrapped | user_wrapped |
| League | `presentation/screens/league_screen.dart` | Liga de competição | league_members, league_snapshots |

### Shared / Auth / Social Screens

| Tela | Path | Objetivo | Dados |
|------|------|----------|-------|
| Home | `presentation/screens/home_screen.dart` | Shell de navegação principal (tabs) | — |
| Today | `presentation/screens/today_screen.dart` | Tela do dia com resumo | sessions, missions |
| More | `presentation/screens/more_screen.dart` | Hub secundário (social, config, integrações) | — |
| Login | `presentation/screens/login_screen.dart` | Tela de login (email/social) | auth |
| Auth Gate | `presentation/screens/auth_gate.dart` | Redirecionamento baseado em estado de auth | auth |
| Welcome | `presentation/screens/welcome_screen.dart` | Boas-vindas / primeiro acesso | — |
| Onboarding Role | `presentation/screens/onboarding_role_screen.dart` | Selecionar papel (atleta/staff) | profiles |
| Onboarding Tour | `presentation/screens/onboarding_tour_screen.dart` | Tour interativo das funcionalidades | — |
| Profile | `presentation/screens/profile_screen.dart` | Perfil do usuário | profiles |
| Settings | `presentation/screens/settings_screen.dart` | Configurações do app | preferences |
| How It Works | `presentation/screens/how_it_works_screen.dart` | Explicação do sistema | — |
| Friends | `presentation/screens/friends_screen.dart` | Lista de amigos | friendships |
| Friend Profile | `presentation/screens/friend_profile_screen.dart` | Perfil de amigo | profiles, sessions |
| Friends Activity Feed | `presentation/screens/friends_activity_feed_screen.dart` | Feed de atividades dos amigos | feed_items |
| Invite Friends | `presentation/screens/invite_friends_screen.dart` | Compartilhar link de convite | invite_codes |
| Invite QR | `presentation/screens/invite_qr_screen.dart` | QR code de convite | invite_codes |
| History | `presentation/screens/history_screen.dart` | Histórico de corridas | sessions |
| Run Details | `presentation/screens/run_details_screen.dart` | Detalhes de uma corrida | sessions, location_points |
| Run Summary | `presentation/screens/run_summary_screen.dart` | Resumo pós-corrida | sessions |
| Run Replay | `presentation/screens/run_replay_screen.dart` | Replay animado da corrida | sessions, location_points |
| Map | `presentation/screens/map_screen.dart` | Mapa de corrida ao vivo | location_points |
| Recovery | `presentation/screens/recovery_screen.dart` | Recuperar sessão interrompida | sessions |
| Events | `presentation/screens/events_screen.dart` | Eventos do grupo social | events |
| Event Details | `presentation/screens/event_details_screen.dart` | Detalhes de evento | events, event_participations |
| Race Event Details | `presentation/screens/race_event_details_screen.dart` | Detalhes de evento de corrida | race_events |
| Groups | `presentation/screens/groups_screen.dart` | Grupos sociais | groups |
| Group Details | `presentation/screens/group_details_screen.dart` | Detalhes do grupo social | groups, group_members |
| Group Events | `presentation/screens/group_events_screen.dart` | Eventos do grupo | events |
| Group Evolution | `presentation/screens/group_evolution_screen.dart` | Evolução do grupo | sessions (group) |
| Group Rankings | `presentation/screens/group_rankings_screen.dart` | Rankings do grupo | leaderboard |
| Support | `presentation/screens/support_screen.dart` | Tela de suporte | support_tickets |
| Support Ticket | `presentation/screens/support_ticket_screen.dart` | Detalhes do ticket de suporte | support_tickets |
| Diagnostics | `presentation/screens/diagnostics_screen.dart` | Diagnósticos técnicos (GPS, BLE, perms) | — |
| Park | `features/parks/presentation/park_screen.dart` | Detalhes do parque de corrida | parks, park_activities |

**Total: ~100 telas**

---

## 2. Mapa de Páginas — Portal Next.js

| Página | Rota | Objetivo | Dados |
|--------|------|----------|-------|
| Dashboard | `/dashboard` | KPIs: créditos, atletas, WAU, distância, challenges, gráficos | coaching_token_inventory, coaching_members, sessions, challenges |
| Atletas | `/athletes` | Lista de atletas com status verificação, distância, sessões | coaching_members, profiles, athlete_verification, sessions |
| Custódia | `/custody` | Conta de custódia: depósitos, saques, saldo, settlements | custody_accounts, custody_deposits, custody_withdrawals, coin_ledger, clearing_settlements |
| Compensações | `/clearing` | Recebíveis e pagáveis de clearing entre assessorias | clearing_settlements, clearing_events, coaching_groups |
| Swap de Lastro | `/swap` | Mercado de swap de lastro entre assessorias | swap_orders, custody_accounts, platform_fee_config |
| Conversão Cambial | `/fx` | Simulador de conversão + saques | custody_accounts, fx_rates |
| Badges | `/badges` | Inventário de badges, compra, ativações | coaching_badge_inventory, billing_products, billing_customers |
| Auditoria | `/audit` | Trail de clearing events e settlements | clearing_events, clearing_settlements, coaching_groups |
| Distribuições | `/distributions` | Histórico de distribuição de OmniCoins | coin_ledger, coaching_members, coaching_token_inventory |
| Verificação | `/verification` | Status de verificação de todos atletas + reavaliar | athlete_verification, profiles, coaching_members |
| Engajamento | `/engagement` | Métricas de engajamento: WAU, distância, challenges, KPIs diários | sessions, coaching_members, challenges, kpi_daily_snapshots |
| Presença | `/attendance` | Sessões de treino + check-ins por sessão | coaching_training_sessions, coaching_training_attendance |
| Presença (detalhe) | `/attendance/[id]` | Check-ins individuais de uma sessão | coaching_training_attendance, profiles |
| Análise Presença | `/attendance-analytics` | Analytics de presença: frequência, tendência, top atletas | coaching_training_attendance, coaching_training_sessions |
| CRM Atletas | `/crm` | Lista CRM com filtros por tag/status, contagem alertas | coaching_member_status, coaching_athlete_tags, coaching_athlete_notes, coaching_alerts |
| CRM At-Risk | `/crm/at-risk` | Atletas em risco (filtro pré-aplicado) | coaching_alerts, coaching_member_status |
| CRM Perfil | `/crm/[userId]` | Ficha individual com notas e histórico | coaching_athlete_notes, coaching_member_status, coaching_athlete_tags |
| Mural | `/announcements` | Lista de comunicados com taxa de leitura | coaching_announcements, coaching_announcement_reads |
| Mural Detalhe | `/announcements/[id]` | Detalhe do comunicado + quem leu | coaching_announcements, coaching_announcement_reads |
| Mural Editar | `/announcements/[id]/edit` | Editar comunicado | coaching_announcements |
| Comunicação | `/communications` | Canal de comunicação direta | — |
| Alertas/Risco | `/risk` | Alertas de churn, inatividade, milestones | coaching_alerts, coaching_member_status, profiles |
| Exports | `/exports` | Exportar dados em CSV (atletas, presença, engajamento, CRM, alertas, financeiro, mural) | Múltiplas tabelas |
| Treinos | `/workouts` | Templates de treino do grupo | coaching_workout_templates, coaching_workout_blocks |
| Análise Treinos | `/workouts/analytics` | Analytics de execução de treinos | coaching_workout_executions, coaching_workout_assignments |
| Assignments | `/workouts/assignments` | Atribuições ativas de treinos | coaching_workout_assignments |
| TrainingPeaks | `/trainingpeaks` | Atletas vinculados + status sync TP | coaching_device_links, tp_sync_status |
| Financeiro | `/financial` | Dashboard financeiro: receita, assinantes, crescimento | coaching_financial_ledger, coaching_subscriptions |
| Planos | `/financial/plans` | Gestão de planos financeiros | coaching_plans |
| Assinaturas | `/financial/subscriptions` | Lista de assinaturas ativas/atrasadas | coaching_subscriptions |
| Execuções | `/executions` | Histórico de execuções de treino | coaching_workout_executions, coaching_workout_assignments |
| Créditos (legacy) | `/credits` | Compra de créditos (legacy, redirect se flag off) | coaching_token_inventory, billing_products |
| Billing | `/billing` | Gestão de plano billing da assessoria | billing |
| Configurações | `/settings` | Equipe, auto-topup, gateway, branding, invite | coaching_members, billing_products, auto_topup_settings, coaching_branding, billing_customers |
| Selecionar Grupo | `/select-group` | Selecionar assessoria ativa | coaching_members, coaching_groups |
| No Access | `/no-access` | Tela de acesso negado | — |
| Platform Admin | `/platform/*` | Painel administrativo plataforma (assessorias, fees, produtos, reembolsos, suporte, liga, feature flags, invariants) | platform_* tables |

**Total: ~35 páginas**

---

## 3. API Routes

| Rota | Método | Objetivo |
|------|--------|----------|
| `/api/health` | GET | Health check do portal |
| `/api/auth/callback` | GET | Callback OAuth Supabase |
| `/api/announcements` | POST | Criar comunicado |
| `/api/announcements/[id]` | PATCH/DELETE | Editar/deletar comunicado |
| `/api/auto-topup` | GET/POST | Ler/salvar configuração auto-topup |
| `/api/billing-portal` | POST | Criar sessão Stripe Customer Portal |
| `/api/branding` | GET/POST | Ler/salvar branding do grupo |
| `/api/checkout` | POST | Criar sessão de checkout Stripe/MercadoPago |
| `/api/clearing` | GET/POST | Listar/confirmar settlements |
| `/api/crm/notes` | POST | Adicionar nota CRM a atleta |
| `/api/crm/tags` | POST/DELETE | Gerenciar tags CRM |
| `/api/custody` | GET/POST | Operações de custódia |
| `/api/custody/webhook` | POST | Webhook de depósitos |
| `/api/custody/withdraw` | POST | Solicitar saque |
| `/api/distribute-coins` | POST | Distribuir OmniCoins para atleta |
| `/api/export/athletes` | GET | Exportar atletas CSV |
| `/api/export/attendance` | GET | Exportar presença CSV |
| `/api/export/engagement` | GET | Exportar engajamento CSV |
| `/api/export/crm` | GET | Exportar CRM CSV |
| `/api/export/alerts` | GET | Exportar alertas CSV |
| `/api/export/announcements` | GET | Exportar mural CSV |
| `/api/export/financial` | GET | Exportar financeiro CSV |
| `/api/gateway-preference` | GET/POST | Ler/salvar gateway preferido |
| `/api/platform/assessorias` | GET/POST/PATCH | CRUD assessorias (platform admin) |
| `/api/platform/fees` | GET/PATCH | Gerenciar taxas da plataforma |
| `/api/platform/products` | GET/POST/PATCH | Gerenciar produtos billing |
| `/api/platform/refunds` | GET/POST | Gerenciar reembolsos |
| `/api/platform/support` | GET/PATCH | Tickets de suporte |
| `/api/platform/liga` | GET/POST | Gerenciar ligas |
| `/api/platform/feature-flags` | GET/POST | Feature flags |
| `/api/platform/invariants` | GET | Verificar invariantes |
| `/api/platform/invariants/enforce` | POST | Forçar correção de invariantes |
| `/api/swap` | GET/POST/PATCH/DELETE | CRUD de swap orders |
| `/api/team/invite` | POST | Convidar membro para equipe |
| `/api/team/remove` | POST | Remover membro da equipe |
| `/api/verification/evaluate` | POST | Reavaliar verificação de atleta |

**Total: 36 rotas API**

---

## 4. Edge Functions

| Função | Objetivo |
|--------|----------|
| `auto-topup-check` | Verificar se grupo precisa auto-topup |
| `auto-topup-cron` | Cron job de auto-topup |
| `calculate-progression` | Calcular progressão de nível/XP |
| `challenge-accept-group-invite` | Aceitar convite de desafio de grupo |
| `challenge-create` | Criar desafio |
| `challenge-get` | Buscar detalhes de desafio |
| `challenge-invite-group` | Convidar grupo para desafio |
| `challenge-join` | Entrar em desafio |
| `challenge-list-mine` | Listar desafios do usuário |
| `champ-accept-invite` | Aceitar convite de campeonato |
| `champ-activate-badge` | Ativar badge em campeonato |
| `champ-cancel` | Cancelar campeonato |
| `champ-create` | Criar campeonato |
| `champ-enroll` | Inscrever em campeonato |
| `champ-invite` | Convidar para campeonato |
| `champ-lifecycle` | Lifecycle de campeonatos (start/end) |
| `champ-list` | Listar campeonatos |
| `champ-open` | Abrir campeonato para inscrições |
| `champ-participant-list` | Listar participantes de campeonato |
| `champ-update-progress` | Atualizar progresso no campeonato |
| `clearing-confirm-received` | Confirmar recebimento de settlement |
| `clearing-confirm-sent` | Confirmar envio de settlement |
| `clearing-cron` | Cron de clearing automático |
| `clearing-open-dispute` | Abrir disputa de clearing |
| `complete-social-profile` | Completar perfil social |
| `compute-leaderboard` | Calcular rankings do leaderboard |
| `create-checkout-mercadopago` | Criar checkout MercadoPago |
| `create-checkout-session` | Criar sessão de checkout Stripe |
| `create-portal-session` | Criar sessão portal Stripe |
| `delete-account` | Deletar conta do usuário |
| `eval-athlete-verification` | Avaliar verificação de atleta |
| `eval-verification-cron` | Cron de verificação automática |
| `evaluate-badges` | Avaliar e conceder badges |
| `generate-running-dna` | Gerar perfil de running DNA |
| `generate-wrapped` | Gerar resumo anual (Wrapped) |
| `league-list` | Listar ligas |
| `league-snapshot` | Snapshot de liga |
| `lifecycle-cron` | Cron de lifecycle genérico (challenges, sessions) |
| `list-purchases` | Listar compras |
| `matchmake` | Encontrar oponente para desafio |
| `notify-rules` | Processar regras de notificação |
| `process-refund` | Processar reembolso |
| `reconcile-wallets-cron` | Cron de reconciliação de wallets |
| `send-push` | Enviar push notification |
| `set-user-role` | Definir papel do usuário |
| `settle-challenge` | Liquidar desafio finalizado |
| `strava-register-webhook` | Registrar webhook Strava |
| `strava-webhook` | Receber atividades Strava |
| `submit-analytics` | Submeter eventos de analytics |
| `token-consume-intent` | Consumir intent de token (QR scan) |
| `token-create-intent` | Criar intent de token (QR generate) |
| `trainingpeaks-oauth` | OAuth flow TrainingPeaks |
| `trainingpeaks-sync` | Sincronizar treinos com TrainingPeaks |
| `validate-social-login` | Validar login social (Google/Apple) |
| `verify-session` | Verificar integridade de sessão |
| `webhook-mercadopago` | Webhook de pagamentos MercadoPago |
| `webhook-payments` | Webhook de pagamentos Stripe |

**Total: 57 edge functions**

---

## 5. Mapa de Funcionalidades

| Feature | Descrição | Quem Usa | Dado Tocado | Resultado |
|---------|-----------|----------|-------------|-----------|
| Coaching Groups (multi-tenant) | Estrutura multi-tenant que isola cada assessoria | Admin, Coach, Assistant | coaching_groups, coaching_members | Isolamento de dados por group_id |
| Training Sessions + QR Attendance (OS-01) | Agendamento de treinos presenciais com check-in via QR code | Staff cria, Atleta faz check-in | coaching_training_sessions, coaching_training_attendance | Presença registrada com QR |
| CRM: Tags, Notes, Status (OS-02) | Gestão de relacionamento com atletas via tags, notas e status | Staff gerencia | coaching_member_status, coaching_athlete_tags, coaching_athlete_notes | Ficha do atleta enriquecida |
| Announcements + Read Receipts (OS-03) | Mural de comunicados com rastreio de quem leu | Staff publica, Atleta lê | coaching_announcements, coaching_announcement_reads | Comunicação com taxa de leitura |
| Portal Reports + Exports (OS-04) | Dashboards analíticos e exportação CSV multi-tipo | Staff visualiza/exporta | Múltiplas | CSVs e dashboards analíticos |
| KPI/Alert Engine (OS-05) | Motor de KPIs diários e alertas automáticos de risco/churn | Sistema gera, Staff visualiza | kpi_daily_snapshots, coaching_alerts | Alertas de risco/churn automáticos |
| Workout Builder (BLOCO A) | Construtor de templates de treino com blocos estruturados | Staff cria templates+blocos, Atleta visualiza | coaching_workout_templates, coaching_workout_blocks, coaching_workout_assignments | Treinos estruturados com blocos |
| Financial Engine (BLOCO B) | Motor financeiro: planos, assinaturas e ledger da assessoria | Staff gerencia planos, Atleta assina | coaching_plans, coaching_subscriptions, coaching_financial_ledger | Controle financeiro da assessoria |
| Workout-Financial Integration (BLOCO C) | Gate que bloqueia atribuição de treino se assinatura atrasada | Sistema valida | coaching_subscriptions ↔ coaching_workout_assignments | Bloqueio de assignment se assinatura atrasada |
| Wearables + TrainingPeaks (BLOCO D) | Integração com wearables e TrainingPeaks para import de execuções | Atleta vincula, Staff sincroniza | coaching_device_links, coaching_workout_executions | Import de execuções de wearables |
| Advanced Analytics (BLOCO E) | Analytics avançadas de engajamento com snapshots diários | Staff visualiza | kpi_daily_snapshots, analytics_* | Análises avançadas de engajamento |
| Token Economy (OmniCoins) | Economia de tokens: distribuição via QR, saldo, histórico | Staff distribui, Atleta recebe | coin_ledger, coaching_token_inventory | Gamificação com moeda interna |
| Clearing & Settlement | Compensação automática de saldos entre assessorias | Sistema automático | clearing_events, clearing_settlements | Compensação inter-assessoria |
| Custody & Swap | Conta de custódia e mercado de swap de lastro | Admin gerencia | custody_accounts, swap_orders | Gestão de lastro financeiro |
| Challenges | Desafios 1v1 ou em grupo com aposta de OmniCoins | Atleta cria/participa | challenges, challenge_participants | Desafios entre atletas |
| Championships | Campeonatos estruturados com convites, inscrição e ranking | Staff cria, Atleta participa | championships, championship_participants | Competições estruturadas |
| Athlete Verification | Verificação automática de integridade GPS de sessões | Sistema automático, Staff revisa | athlete_verification | Verificação de integridade GPS |
| Badges & Missions | Sistema de conquistas (badges) e missões diárias/semanais | Sistema automático | badges, badge_awards, missions, mission_progress | Gamificação progressiva |
| Progression & XP | Sistema de níveis e pontos de experiência por atividade | Sistema automático | progression, xp_transactions | Níveis e pontos de experiência |
| Leaderboards & Leagues | Rankings competitivos semanais/mensais e ligas por nível | Atleta compete | leaderboard, league_members | Rankings competitivos |
| Social (Friends, Groups, Events) | Rede social: amigos, grupos de corrida e eventos presenciais | Atleta interage | friendships, groups, events | Rede social de corredores |
| Running DNA & Wrapped | Perfil genético de corrida e resumo anual estilo Spotify | Sistema gera | running_dna, user_wrapped | Perfil personalizado |
| Strava Integration | Importação automática de atividades do Strava via webhook | Atleta vincula | strava_tokens, sessions | Import automático de atividades |
| Billing (Stripe + MercadoPago) | Monetização via Stripe e MercadoPago para compra de créditos | Admin compra créditos | billing_products, billing_purchases, billing_customers | Monetização da plataforma |
| Platform Admin | Painel central da plataforma: assessorias, fees, suporte, flags | Platform Admin | platform_* | Gestão centralizada da plataforma |

---

## 6. Matriz Clique → Ação

| Tela/Página | Botão/CTA | RPC/Tabela | Side Effect | Feedback UI |
|-------------|-----------|------------|-------------|-------------|
| Staff Dashboard | Card "Atletas" | coaching_members | Navigate to group details | — |
| Staff Dashboard | Card "Administração" | — | Navigate to QR Hub | — |
| Staff QR Hub | "Gerar QR" | `token-create-intent` | Cria intent + mostra QR | QR code exibido |
| Staff QR Hub | "Escanear QR" | `token-consume-intent` | Consome intent, credita coins | SnackBar sucesso/erro |
| Staff Training Create | "Criar Sessão" | INSERT coaching_training_sessions | Sessão criada | Navigate to detail |
| Staff Training Detail | "Gerar QR Presença" | `issue_checkin_token` | Token + QR gerado | QR exibido |
| Staff Workout Builder | "Salvar Template" | INSERT coaching_workout_templates + blocks | Template salvo | SnackBar + pop |
| Staff Workout Assign | "Atribuir" | INSERT coaching_workout_assignments | Treino atribuído (validação de assinatura) | SnackBar |
| Announcement Create | "Publicar" | POST `/api/announcements` | Comunicado criado | Navigate to feed |
| Coaching Group Details | "Convidar" | `invite_user_to_group` | Membro convidado | SnackBar |
| Coaching Group Details | "Remover" | `remove_coaching_member` | Membro removido | SnackBar |
| Athlete Dashboard | Card "Desafios" | challenges | Navigate to challenges list | — |
| Athlete Dashboard | Card "Assessoria" | coaching_members | Navigate to my assessoria | — |
| Athlete Checkin QR | Scan QR | `mark_attendance` | Presença registrada | SnackBar sucesso |
| Athlete Workout Day | "Registrar Execução" | INSERT coaching_workout_executions | Execução manual salva | Navigate to summary |
| Athlete Device Link | "Vincular" | INSERT coaching_device_links | Device vinculado | SnackBar |
| Announcement Detail | (auto) | INSERT coaching_announcement_reads | Leitura registrada | — |
| Challenge Create | "Criar" | `challenge-create` | Desafio criado | Navigate to details |
| Challenge Details | "Participar" | `challenge-join` | Entrada no desafio | SnackBar |
| Portal Dashboard | — (auto) | coaching_token_inventory, sessions | KPIs exibidos | Loading → Cards |
| Portal Athletes | "Distribuir" | POST `/api/distribute-coins` | Coins distribuídos | Toast sucesso |
| Portal Verification | "Reavaliar" | POST `/api/verification/evaluate` | Verificação recalculada | Toast |
| Portal Settings | "Convidar" | POST `/api/team/invite` | Staff convidado | Toast |
| Portal Settings | "Remover" | POST `/api/team/remove` | Staff removido | Toast |
| Portal Settings | "Salvar Branding" | POST `/api/branding` | Logo + cores salvos | Toast |
| Portal Settings | "Salvar Auto-Topup" | POST `/api/auto-topup` | Configuração salva | Toast |
| Portal Clearing | "Confirmar Recebido" | `clearing-confirm-received` | Settlement confirmed | Toast |
| Portal Swap | "Criar Oferta" | POST `/api/swap` | Swap order criada | Toast |
| Portal Swap | "Aceitar Oferta" | PATCH `/api/swap` | Swap executado | Toast |
| Portal CRM | Link → Perfil | coaching_athlete_notes | Navigate to athlete detail | — |
| Portal CRM Perfil | "Adicionar Nota" | POST `/api/crm/notes` | Nota criada | Refresh |
| Portal CRM Perfil | "Adicionar Tag" | POST `/api/crm/tags` | Tag associada | Refresh |
| Portal Risk | "Resolver" | UPDATE coaching_alerts | Alerta marcado resolvido | Toast |
| Portal Exports | "Exportar CSV" | GET `/api/export/*` | Download CSV | Browser download |
| Portal Announcements | "Novo Comunicado" | POST `/api/announcements` | Comunicado criado | Redirect |
| Portal Financial | Link → Planos | coaching_plans | Navigate to plans page | — |
| Portal Financial | Link → Assinaturas | coaching_subscriptions | Navigate to subscriptions | — |
| Portal Credits | "Comprar" | POST `/api/checkout` | Sessão checkout criada | Redirect to Stripe/MP |
| Portal Custody | "Depositar" | POST `/api/custody` | Depósito iniciado | Toast |
| Portal Custody | "Sacar" | POST `/api/custody/withdraw` | Saque solicitado | Toast |
| Staff Championship Templates | "Criar Template" | INSERT championship_templates | Template de campeonato criado | SnackBar + navigate |
| Staff Championship Manage | "Abrir Inscrições" | `champ-open` edge fn | Campeonato aberto para inscrições | SnackBar |
| Staff Championship Manage | "Cancelar Campeonato" | `champ-cancel` edge fn | Campeonato cancelado | Dialog confirm + SnackBar |
| Staff Championship Invites | "Enviar Convite" | `champ-invite` edge fn | Convite enviado para grupo | SnackBar |
| Athlete Championships | "Inscrever-se" | `champ-enroll` edge fn | Atleta inscrito no campeonato | SnackBar + navigate to ranking |
| Athlete Championship Ranking | — (auto) | `champ-participant-list` edge fn | Ranking renderizado | ShimmerLoading → list |
| Challenge Create | "Criar Desafio" | `challenge-create` edge fn | Desafio criado com entry_fee | Navigate to details |
| Challenge Details | "Participar" | `challenge-join` edge fn | Entrada no desafio (coins debitados) | SnackBar |
| Challenge Invite | "Convidar" | `challenge-invite-group` edge fn | Convite enviado para grupo | SnackBar |
| Challenge Result | — (auto) | `settle-challenge` edge fn | Resultado exibido | Loading → resultado |
| Friends | "Adicionar Amigo" | INSERT friendships | Solicitação enviada | SnackBar |
| Friends | "Aceitar" | UPDATE friendships SET status='accepted' | Amizade confirmada | SnackBar + refresh |
| Friend Profile | "Desafiar" | Navigate to `challenge_create_screen` | — | Navigate |
| Groups | "Criar Grupo" | INSERT groups | Grupo social criado | Navigate to group details |
| Group Details | "Entrar" | INSERT group_members | Ingresso no grupo | SnackBar |
| Group Events | "Criar Evento" | INSERT events | Evento social criado | Navigate to event detail |
| Event Details | "Participar" | INSERT event_participations | Participação confirmada | SnackBar |
| Badges | "Ativar Badge" | `champ-activate-badge` edge fn | Badge ativado no campeonato | SnackBar |
| Missions | "Ver Detalhe" | SELECT mission_progress | — | Navigate to mission detail |
| League | — (auto) | `league-list` edge fn | Liga carregada | ShimmerLoading → list |
| Streaks Leaderboard | — (auto) | SELECT leaderboard WHERE type='streaks' | Ranking exibido | ShimmerLoading → list |
| Leaderboards | Trocar aba (semanal/mensal) | SELECT leaderboard WHERE period=X | Ranking atualizado | Tab switch + loading |
| Settings | "Salvar" | UPDATE profiles/preferences | Preferências salvas | SnackBar |
| Onboarding Role | "Sou Atleta" / "Sou Coach" | UPDATE profiles SET role | Role definido | Navigate to tour |
| Onboarding Tour | "Concluir" | UPDATE profiles SET onboarding_complete=true | Tour finalizado | Navigate to home |
| Support | "Abrir Ticket" | INSERT support_tickets | Ticket criado | Navigate to ticket detail |
| Support Ticket | "Enviar Mensagem" | INSERT support_ticket_messages | Mensagem enviada | Refresh chat |
| Invite Friends | "Compartilhar" | share_plus package | Link de convite enviado | System share sheet |
| Invite QR | — (auto) | invite_codes | QR exibido | QR renderizado |

---

**SQL Migrations: 89 arquivos** em `supabase/migrations/`  
**Isar Collections: 26 modelos** (cache local offline)  
**BLoCs: 32 blocs** em `presentation/blocs/`  
**Domain Entities: 68 entidades** em `domain/entities/`  
**Domain Use Cases: ~60 use cases** em `domain/usecases/`  
**Data Repositories: 47 repositórios** em `data/repositories_impl/`
