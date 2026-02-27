# MASTER_PLAN.md — Plano de Fases do Omni Runner

> **Atualizado:** 2026-02-26
> **Status:** Pre-launch — Auditoria final concluída (score 0.93)

---

## FASES DO PROJETO

| Phase | Nome | Descricao | Status |
|---|---|---|---|
| 00 | Planejamento Estrategico | Escopo, stack, governanca, congelamento | CONCLUIDA |
| 01 | Base do Projeto (Fundacao) | Flutter create, docs, estrutura de pastas, DI, Protobuf, Isar | CONCLUIDA |
| 02 | GPS Tracking (F1) | Captura GPS em tempo real, start/pause/stop | CONCLUIDA (removido — Strava-only) |
| 03 | Metricas (F2) | Calculo de distancia, pace, tempo a partir dos pontos GPS | CONCLUIDA |
| 04 | Persistencia (F3) | Salvar corridas no Isar, persistencia incremental offline | CONCLUIDA |
| 05 | Anti-Cheat (F6) | Validacao de velocidade, deteccao de teleporte, score | CONCLUIDA |
| 06 | Ghost Runner (F5) | Selecao de corrida anterior, comparacao em tempo real | CONCLUIDA (removido — Strava-only) |
| 07 | Mapa (F4) | Exibicao do trajeto pos-corrida com MapLibre | CONCLUIDA |
| 08 | Sync (F7) | Sincronizacao offline-first com Supabase | CONCLUIDA |
| 09 | Integracao | Fluxo completo, testes E2E, polish | CONCLUIDA |
| 10 | Build e Release | APK final, testes em device real, release | CONCLUIDA (v1.0.13) |
| 12 | Watch Apps | Apple Watch + WearOS standalone tracking, sync com phone | CONCLUIDA |
| 13 | Gamification Engine | Desafios 1v1/grupo/team, OmniCoins, rankings, auditoria (loja-safe) | CONCLUIDA |
| 14 | Integracoes Externas | Strava Import (OAuth2 + Webhook), Export FIT/GPX/TCX, HealthKit/Health Connect | CONCLUIDA |
| 15 | Social & Events | Amigos, grupos, leaderboards, eventos virtuais | CONCLUIDA |
| 16 | Assessoria Mode (Coaching Intelligence Engine) | Grupos de assessoria, rankings, análise de evolução, insights, dashboard staff | CONCLUIDA |
| 17 | Supabase Backend (Full Stack) | 60 migrations, 54 Edge Functions, RLS, RPCs, seed data, handoff doc | CONCLUIDA |
| 18 | Social Auth + Onboarding | Login social (Google/Apple/Facebook), onboarding 9 slides | CONCLUIDA |
| 19 | Assessoria Ecosystem Core (EPIC-07) | Tokens institucionais, clearing, campeonatos, coaching dashboard, liga | CONCLUIDA |
| 20 | Gamification (Progression Final) | XP, Níveis, Streaks, Goals semanais, badges (30), missions | CONCLUIDA |
| 21 | Monetização (Loja-Safe) | B2B SaaS portal, Stripe checkout, auto top-up, refunds, zero IAP | CONCLUIDA |
| 22 | Atleta Verificado & Monetization Gate | State machine DB, 4-layer server-side gate, auto eval, cron diário | CONCLUIDA |

---

## SPRINTS DA PHASE 01 (ATUAL)

| Sprint | Descricao | Status |
|---|---|---|
| 1.1 | Criar projeto Flutter | CONCLUIDA |
| 1.2 | Criar docs e arquivos de controle | EM ANDAMENTO |
| 1.3 | Estrutura de pastas Clean Architecture | TODO |
| 1.4 | Configurar dependencias (pubspec.yaml) | TODO |
| 1.5 | Configurar get_it (DI) | TODO |
| 1.6 | Configurar Protobuf + gerar entities base | TODO |
| 1.7 | Configurar Isar + primeiro schema | TODO |
| 1.8 | Primeiros testes unitarios (domain) | TODO |

---

## SPRINTS DA PHASE 13 — GAMIFICATION ENGINE (LOJA-SAFE)

| Sprint | Descricao | Status |
|---|---|---|
| 13.0.0 | Guardrails loja-safe: criar GAMIFICATION_POLICY.md + atualizar ARCHITECTURE.md e DECISIONS.md | CONCLUIDA |
| 13.0.1 | Domain: entidades Challenge, Rules, Participant, Wallet, LedgerEntry, ChallengeResult | CONCLUIDA |
| 13.0.2 | Domain: use cases (10) + repo interfaces (3) + GamificationFailure hierarchy | CONCLUIDA |
| 13.0.3 | Data: Isar models (4) + repo impls (3) + DB provider + DI registration | CONCLUIDA |
| 13.0.4 | Integração com Core: ChallengeRunBindingEntity + RewardSessionCoins + PostSessionChallengeDispatcher + 2 GamificationFailure subtypes | CONCLUIDA |
| 13.0.5 | Engine Avaliadora: ChallengeEvaluator (1v1 time/pace/distance, group, tiebreak earliestFinish) + 18 testes | CONCLUIDA |
| 13.0.6 | Liquidação Coins: LedgerService (entry fee, pool transfer, refund, never-negative, idempotency) + 19 testes | CONCLUIDA |
| 13.0.7 | UI Desafios: ChallengesBloc + WalletBloc + 4 screens (list, create, details, wallet) + DI | CONCLUIDA |
| 13.0.8 | QA Phase 12: termos proibidos, inconsistências (6), fraude (7 vetores), conformidade policy | CONCLUIDA |
| 13.1.0 | Especificação Progressão: PROGRESSION_SPEC.md (XP curva, badges, streaks, missões, temporadas) | CONCLUIDA |
| 13.1.1 | Entidades Progressão: ProfileProgressEntity, XpTransactionEntity, BadgeEntity, BadgeAwardEntity, MissionEntity, MissionProgressEntity, SeasonEntity, SeasonProgressEntity | CONCLUIDA |
| 13.1.2 | Use Cases Progressão: AwardXpForWorkout, EvaluateBadges, CreateDailyMissions, UpdateMissionProgress, ClaimRewards + 4 repo interfaces | CONCLUIDA |
| 13.1.3 | Persistência Progressão: 6 Isar models + 4 repo impls + DB provider + DI | CONCLUIDA |
| 13.1.4 | Integração com Corrida: PostSessionProgression orchestrator + wiring TrackingBloc (Award XP, Badges, Missions, ClaimRewards) + gamification dispatch + DI | CONCLUIDA |
| 13.1.5 | UI Progress: ProgressionBloc + BadgesBloc + MissionsBloc + 3 screens (progression, badges, missions) + DI | CONCLUIDA |
| 13.1.6 | QA Phase 13: termos proibidos, 7 inconsistências, 5 fraud vectors, DI audit | CONCLUIDA |
| 13.1.6-fix | QA Fix: serializar pipelines (FRAUD-01/02), LedgerReason badge/missionReward (INC-03), ordinal comment (INC-01), enum append-only rule (INC-02), MissionsScreen join defs (INC-05), CreateDailyMissions DI (INC-06), min distance 200m (FRAUD-03) | CONCLUIDA |
| 13.1.7 | Isar: BadgeDefinitionRecord, UserBadgeRecord + repos | TODO |
| 13.1.8 | Use Cases: UpdateStreak + StreakEntity persistence | TODO |
| 13.2.1 | (coberto por 13.1.4) Integrar RewardCoins no fluxo endWorkout() | CONCLUIDA |
| 13.2.2 | Streak detection (semanal + mensal) + reward | TODO |
| 13.2.3 | PR detection + reward | TODO |
| 13.3.1 | Rankings: domain + data layer (local) | TODO |
| 13.3.2 | Rankings: sync com Supabase (leaderboard remoto) | TODO |
| 13.4.1 | Anti-fraude: rate limiting (10 sessoes/dia), deduplicacao | TODO |
| 13.4.2 | Anti-fraude: audit log append-only | TODO |
| 13.5.1 | UI: tela de Coins + historico | TODO |
| 13.5.2 | UI: tela de desafios (criar, aceitar, ver progresso) | TODO |
| 13.5.3 | UI: tela de rankings | TODO |
| 13.5.4 | UI: loja cosmetica (badges, temas) | TODO |
| 13.6.1 | Testes unitarios: domain (entities + use cases) | TODO |
| 13.6.2 | Testes unitarios: data layer (repos) | TODO |
| 13.6.3 | Smoke tests: fluxo completo (correr → coins → desafio → ranking) | TODO |
| 13.7.0 | QA final + Definition of Done Phase 13 | TODO |

---

## SPRINTS DA PHASE 14 — INTEGRACOES EXTERNAS

| Sprint | Descricao | Status |
|---|---|---|
| 14.0.1 | Trava de contexto: definir escopo, criar PHASE_14_INTEGRATIONS.md | CONCLUIDA |
| 14.0.2 | Criar docs/API_KEYS_AND_SCOPES.md com politica de segredos | CONCLUIDA |
| 14.1.1 | Registrar app no Strava Developer Portal | TODO |
| 14.1.2 | Implementar OAuth2 Authorization Code + PKCE flow | TODO |
| 14.1.3 | Persistir tokens (access + refresh) com flutter_secure_storage | TODO |
| 14.1.4 | Implementar token refresh automatico | TODO |
| 14.1.5 | Criar UI de conexao/desconexao Strava em Settings | TODO |
| 14.1.6 | Testes unitarios do fluxo OAuth2 | TODO |
| 14.2.1 | Implementar gerador GPX 1.1 (GpxExporter) | TODO |
| 14.2.2 | Implementar gerador TCX (TcxExporter) | TODO |
| 14.2.3 | Implementar gerador FIT (FitExporter) — formato binario | TODO |
| 14.2.4 | Criar interface IWorkoutExporter e factory | TODO |
| 14.2.5 | Testes unitarios para cada formato | TODO |
| 14.3.1 | Implementar StravaUploadService (multipart POST) | CONCLUIDA |
| 14.3.2 | Polling de status do upload | CONCLUIDA |
| 14.3.3 | Integrar no fluxo de endWorkout() (auto-upload opt-in) | TODO |
| 14.3.4 | Upload manual via botao na tela de detalhes | TODO |
| 14.3.5 | Testes unitarios + mock HTTP | TODO |
| 14.3.6 | Smoke tests Phase 14 (37 tests, zero flakiness) | CONCLUIDA |
| 14.4.1 | Criar modelo PendingUpload no Isar | TODO |
| 14.4.2 | Implementar UploadQueueManager (enqueue, dequeue, retry) | TODO |
| 14.4.3 | Listener de conectividade para auto-sync | TODO |
| 14.4.4 | Exibir badge de uploads pendentes na UI | TODO |
| 14.4.5 | Testes unitarios da queue + retry | TODO |
| 14.4.6 | Bridge health export: IHealthExportService + controller + testes | CONCLUIDA |
| 14.5.1 | Implementar share sheet nativa (share_plus) | CONCLUIDA |
| 14.5.2 | Documentar fluxo Garmin/Outros (manual import) + UX copy | CONCLUIDA |
| 14.5.3 | Criar ExportScreen + HowToImportScreen (UI export + instrucoes) | CONCLUIDA |
| 14.5.4 | Adicionar botao de export na tela de detalhes (wiring) | TODO |
| 14.5.5 | Tela de Export History | TODO |
| 14.5.6 | Feedback visual: toast/snackbar | TODO |
| 14.6.0 | Definition of Done + Auditoria de riscos QA (50 criterios, 10 riscos) | CONCLUIDA |
| 14.6.1 | Validar GPX exportado em ferramentas externas | TODO |
| 14.6.2 | Validar FIT exportado em ferramentas externas | TODO |
| 14.6.3 | Validar TCX exportado em ferramentas externas | TODO |
| 14.6.4 | Testar upload Strava end-to-end | TODO |
| 14.6.5 | Revisao de privacidade | TODO |
| 14.6.6 | Atualizar CONTEXT_DUMP.md final da fase | TODO |

---

## SPRINTS DA PHASE 15 — Social & Events

| Sprint | Descricao | Status |
|---|---|---|
| 15.0.0 | Especificação Social: docs/SOCIAL_SPEC.md (amizade, grupos, leaderboards, eventos) | CONCLUIDA |
| 15.1.0 | Entidades domain: FriendshipEntity, GroupEntity, GroupGoalEntity, GroupMemberEntity, LeaderboardEntity, LeaderboardEntryEntity, EventEntity, EventParticipationEntity + 10 enums | CONCLUIDA |
| 15.2.0 | Use Cases social: 9 use cases (SendFriendInvite, AcceptFriend, BlockUser, CreateGroup, JoinGroup, LeaveGroup, JoinEvent, SubmitWorkoutToEvent, EvaluateEvent) + 3 repo interfaces + social_failures.dart | CONCLUIDA |
| 15.3.0 | Use Cases leaderboard: ComputeLeaderboard, GetLeaderboard, OptInLeaderboard | TODO |
| 15.3.0-isar | Persistência Isar: 4 model files (9 collections) + build_runner | CONCLUIDA |
| 15.6.0 | Persistência Isar: repo impls + DB provider update + DI | TODO |
| 15.7.0 | UI: 6 screens (Friends, Groups, GroupDetails, Leaderboards, Events, EventDetails) + 4 BLoCs + DI | CONCLUIDA |
| 15.8.0 | Integração TrackingBloc: post-session contribute to goals/events/leaderboards | TODO |
| 15.9.0 | QA Phase 15: termos proibidos, inconsistências, fraude, auditoria completa | CONCLUIDA |
| 15.9.0-fix | QA Fix: INC-01 FriendsScreen userId, FRAUD-01 dedup sessão evento, FRAUD-02 EvaluateEvent guard, INC-03 re-invite declined, FRAUD-03 EventRewards caps, INC-05 LeaderboardsBloc nowMs, INC-06/07 Isar composite indexes, INC-08 typo, FRAUD-04 JoinGroup left reuse, FRAUD-05 BlockUser blocker identity | CONCLUIDA |

---

## SPRINTS DA PHASE 16 — Assessoria Mode (Coaching Intelligence Engine)

| Sprint | Descricao | Status |
|---|---|---|
| 16.0.1 | Entidades de assessoria: CoachingGroupEntity, CoachingMemberEntity (CoachingRole), CoachingInviteEntity (CoachingInviteStatus) | CONCLUIDA |
| 16.0.2 | Use Cases assessoria: 6 use cases (CreateCoachingGroup, InviteUserToGroup, AcceptCoachingInvite, RemoveCoachingMember, GetCoachingMembers, GetCoachingGroupDetails) + 3 repo interfaces + coaching_failures.dart | CONCLUIDA |
| 16.0.3 | Persistência Isar: 3 models (CoachingGroupRecord, CoachingMemberRecord, CoachingInviteRecord) + 3 repo impls + DB provider update + build_runner | CONCLUIDA |
| 16.0.4 | UI básica assessoria: 3 screens (CoachingGroups, CoachingGroupDetails, GroupMembers) + 2 BLoCs (CoachingGroupsBloc, CoachingGroupDetailsBloc) + DI (repos, use cases, BLoCs) | CONCLUIDA |
| 16.1.0 | Entidades de ranking: CoachingRankingMetric (4 métricas), CoachingRankingEntryEntity, CoachingGroupRankingEntity + CoachingRankingPeriod | CONCLUIDA |
| 16.1.1 | Ranking calculator: CoachingRankingCalculator (domain service, stateless, puro) + DTOs (RankableSession, AthleteSessionData) | CONCLUIDA |
| 16.1.2 | Persistência ranking: 2 Isar models (CoachingRankingRecord, CoachingRankingEntryRecord) + ICoachingRankingRepo + IsarCoachingRankingRepo + DB provider | CONCLUIDA |
| 16.1.3 | UI ranking assessoria: GroupRankingsScreen + CoachingRankingsBloc + filtros período/métrica + DI (ICoachingRankingRepo, CoachingRankingsBloc) | CONCLUIDA |
| 16.1.4 | Use case ComputeCoachingRanking (orquestra calculator + persiste snapshot) | TODO |
| 16.2.0 | Entidades analytics: EvolutionMetric (6 métricas), EvolutionPeriod, AthleteBaselineEntity, AthleteTrendEntity (TrendDirection) | CONCLUIDA |
| 16.2.1 | Baseline calculator: BaselineCalculator (domain service, stateless) + BaselineSession DTO | CONCLUIDA |
| 16.2.2 | Evolution analyzer: EvolutionAnalyzer (domain service, stateless) + PeriodDataPoint DTO | CONCLUIDA |
| 16.2.3 | Persistência analytics: 2 Isar models (AthleteBaselineRecord, AthleteTrendRecord) + 2 repo interfaces (IAthleteBaselineRepo, IAthleteTrendRepo) + 2 repo impls (IsarAthleteBaselineRepo, IsarAthleteTrendRepo) + DB provider | CONCLUIDA |
| 16.2.4 | UI evolução: 2 screens (AthleteEvolutionScreen, GroupEvolutionScreen) + 2 BLoCs (AthleteEvolutionBloc, GroupEvolutionBloc) + DI (repos + BLoCs) | CONCLUIDA |
| 16.3.0 | Entidades de eventos reais: RaceEventEntity (RaceEventMetric, RaceEventStatus), RaceParticipationEntity, RaceResultEntity | CONCLUIDA |
| 16.3.1 | Event detection: EventDetector (domain service, stateless) + DetectableSession DTO + RaceEventMatch DTO | CONCLUIDA |
| 16.3.2 | Event ranking: EventRankingCalculator (domain service, stateless) — ranking por métrica + distribuição de rewards | CONCLUIDA |
| 16.3.4 | UI eventos: group_events_screen + race_event_details_screen + 2 BLoCs (RaceEventsBloc, RaceEventDetailsBloc) + 3 repo interfaces (IRaceEventRepo, IRaceParticipationRepo, IRaceResultRepo) + DI | CONCLUIDA |
| 16.4.0 | Entidades de insights: CoachInsightEntity + InsightType enum + InsightPriority enum | CONCLUIDA |
| 16.4.1 | Insight generator: InsightGenerator (domain service, stateless) + AthleteActivitySummary DTO | CONCLUIDA |
| 16.4.2 | Persistência insights: CoachInsightRecord (Isar) + ICoachInsightRepo + IsarCoachInsightRepo + DB provider + DI | CONCLUIDA |
| 16.4.3 | UI insights: coach_insights_screen + CoachInsightsBloc + DI | CONCLUIDA |
| 16.4.4 | Contratos backend analytics: contracts/analytics_api.md (submitAnalyticsData, fetchGroupInsights, fetchEvolutionMetrics) | CONCLUIDA |
| 16.4.5 | Sincronização analytics: AnalyticsSyncService (submitAnalyticsData, fetchGroupInsights, fetchEvolutionMetrics) + DI | CONCLUIDA |
| 16.4.6 | Processamento remoto: Edge Function submit-analytics (TypeScript/Deno) + SQL migration (4 tabelas + RLS) | CONCLUIDA |
| 16.5.0 | UI: CoachingGroupScreen, AthleteListScreen, AthleteDetailScreen, CoachingDashboardScreen + BLoCs + DI | TODO |
| 16.6.0 | Integração TrackingBloc: post-session contribute to coaching analytics | TODO |
| 16.9.0 | QA Phase 16: auditoria completa (docs/QA_PHASE_16.md) — 1 PRIV, 4 FRAUD, 3 INC, 4 PERF, 12 PASS | CONCLUIDA |
| 16.9.0-fix | QA Fix: PRIV-01 RLS, FRAUD-01/02/03/04 Edge Function, INC-01/02/03 BLoC+DI, PERF-01/02/03/04 batch+pagination | CONCLUIDA |
| 16.10.0 | Roles migration: coach→adminMaster, assistant→assistente, athlete→atleta + professor; isStaff/canManage/canIssueTokens helpers; UI labels/colors; backward-compat ordinal + string mappers | CONCLUIDA |
| 16.10.1 | UX "Minha Assessoria": MyAssessoriaScreen + MyAssessoriaBloc + burn-warning modal + ISwitchAssessoriaRepo (stub+remote) + SwitchAssessoria use case + DI + more_screen nav | CONCLUIDA |
| 16.10.2 | Wallet UI com "Pendente": WalletEntity.pendingCoins + totalCoins getter; WalletRecord + mapper; LedgerReason cross-assessoria entries; BalanceCard 3-state (total/disponível/pendente) | CONCLUIDA |
| 16.10.3 | Telas staff QR: StaffQrPayload (nonce+expiry anti-replay); ITokenIntentRepo (stub+remote Edge Functions); StaffQrBloc; StaffQrHubScreen (isStaff gating) + StaffGenerateQrScreen (countdown) + StaffScanQrScreen (mobile_scanner); 3 ops: emitir/queimar token + ativar badge campeonato; DI + more_screen nav | CONCLUIDA |
| 16.99.0 | QA Phase 16/17: 18 testes — 9 backend curl (ISSUE/BURN/switch/cross-pending/clearing-confirm/dispute/expire/gating/anti-replay) + 6 frontend checklists (wallet 3-state, assessoria, staff QR hub/generate/scan, roles) + 3 global (termos proibidos, analyze, anti-replay) — docs/QA_PHASE_16_17.md | CONCLUIDA |

---

## SPRINTS DA PHASE 17 — Supabase Backend (Full Stack)

| Sprint | Descricao | Status |
|---|---|---|
| 17.0.1 | Análise dos 36 modelos Flutter → mapeamento SQL (32 tabelas core + 4 analytics) | CONCLUIDA |
| 17.0.2 | Migration 20260218_full_schema.sql: 32 tabelas, índices, RLS enable | CONCLUIDA |
| 17.0.3 | Migration 20260219_analytics_tables.sql: 4 tabelas analytics + RLS | CONCLUIDA |
| 17.0.4 | Migration 20260220_rpc_helpers.sql: 3 RPCs (increment_wallet_balance, increment_profile_progress, compute_leaderboard_global_weekly) | CONCLUIDA |
| 17.0.5 | Fix ordenação RLS: mover policies que referenciam tabelas ainda não criadas | CONCLUIDA |
| 17.1.1 | Edge Function verify-session (anti-cheat server-side) | CONCLUIDA |
| 17.1.2 | Edge Function evaluate-badges (gamificação server-side) | CONCLUIDA |
| 17.1.3 | Edge Function compute-leaderboard (materialização de rankings) | CONCLUIDA |
| 17.2.1 | Auth config: Google + Apple OAuth no config.toml | CONCLUIDA |
| 17.2.2 | Seed data: badge catalog (29 badges) + primeira temporada | CONCLUIDA |
| 17.3.1 | Handoff doc: SUPABASE_BACKEND_GUIDE.md (esquema, RLS, funções, integração) | CONCLUIDA |
| 17.3.2 | Credenciais reais no .env.dev (SUPABASE_URL, SUPABASE_ANON_KEY) | CONCLUIDA |
| 17.4.1 | Mock-first init: AppConfig.isSupabaseReady (runtime flag) + backendMode log | CONCLUIDA |
| 17.4.2 | Guards runtime: SyncService, UserIdentityProvider, AnalyticsSyncService usam isSupabaseReady | CONCLUIDA |
| 17.4.3 | Auth adapter pattern: IAuthDataSource + RemoteAuthDataSource + MockAuthDataSource + AuthRepository + AuthFailure + Auth Debug widget | CONCLUIDA |
| 17.4.4 | Primeira integração real DB: public.profiles com RLS — ProfileEntity, RemoteProfileDataSource, MockProfileDataSource, ProfileRepo, ProfileScreen + "Salvar nome" | CONCLUIDA |
| 17.4.5 | Auth Debug: botão "Copiar JWT" (debug build only) para teste end-to-end de Edge Functions | CONCLUIDA |
| 17.4.6 | Fix isar_flutter_libs: namespace AGP obrigatório no build.gradle do plugin local | CONCLUIDA |
| 17.4.7 | dependency_overrides: isar_flutter_libs apontando para cópia local patched | CONCLUIDA |
| 17.4.8 | Fix directive order: imports antes de declarações em watch_bridge_init.dart | CONCLUIDA |
| 17.4.9 | Fix AuthUser name conflict: alias `app` em remote_auth_datasource.dart | CONCLUIDA |
| 17.4.10 | Upgrade AGP 8.7.0 → 8.9.1 (Health Connect requer ≥ 8.9.1) | CONCLUIDA |
| 17.4.11 | Upgrade path_provider ^2.1.5 → path_provider_android 2.2.22 (remove PluginRegistry.Registrar) | CONCLUIDA |
| 17.4.12 | Upgrade maplibre_gl ^0.20.0 → ^0.25.0 (Flutter embedding v2 compativel) | CONCLUIDA |
| 17.4.13 | Upgrade shared_preferences ^2.2.3 → ^2.5.4 (embedding v2, Android 16) | CONCLUIDA |
| 17.4.14 | Upgrade url_launcher transitives (url_launcher_android 6.3.2 → 6.3.28, embedding v2) | CONCLUIDA |
| 17.4.15 | Rewrite PhoneWearListenerService.kt UTF-8 limpo + fix KDoc session/{id} | CONCLUIDA |
| 17.4.16 | Workaround JWT ES256 401: verify_jwt=false + manual auth.getUser() + ping mode em verify-session | CONCLUIDA |
| 17.4.17 | Mesmo workaround JWT ES256 aplicado em submit-analytics (verify_jwt=false + manual auth + ping mode) | CONCLUIDA |
| 17.4.18 | Mesmo workaround JWT ES256 aplicado em compute-leaderboard (verify_jwt=false + manual auth + ping mode) | CONCLUIDA |
| 17.4.19 | Mesmo workaround JWT ES256 aplicado em settle-challenge (verify_jwt=false + manual auth + ping mode) | CONCLUIDA |
| 17.4.20 | Mesmo workaround JWT ES256 aplicado em evaluate-badges (verify_jwt=false + manual auth + ping mode) | CONCLUIDA |
| 17.4.21 | Shared auth helper (_shared/auth.ts) + migrar verify-session para usar requireUser() | CONCLUIDA |
| 17.4.22 | Migrar submit-analytics para usar _shared/auth.ts requireUser() | CONCLUIDA |
| 17.4.23 | Migrar compute-leaderboard para usar _shared/auth.ts requireUser() | CONCLUIDA |
| 17.4.24 | Migrar settle-challenge para usar _shared/auth.ts requireUser() | CONCLUIDA |
| 17.4.25 | Migrar evaluate-badges para usar _shared/auth.ts requireUser() — todas 5 functions migradas | CONCLUIDA |
| 17.4.26 | Ping Backend DEV ONLY: botao "Ping verify-session" no Auth Debug card (E2E App→Auth→Edge Function) | CONCLUIDA |
| 17.4.27 | Ping Backend DEV ONLY: botao "Ping submit-analytics" no Auth Debug card | CONCLUIDA |
| 17.4.28 | Ping Backend DEV ONLY: botao "Ping compute-leaderboard" no Auth Debug card | CONCLUIDA |
| 17.4.29 | Hardening: shared http.ts (jsonOk/jsonErr), requestId, top-level try/catch em 5 Edge Functions | CONCLUIDA |
| 17.4.30 | Rate limit por usuario via Postgres RPC em 5 Edge Functions | CONCLUIDA |
| 17.4.31 | Observabilidade minima: structured logs (request_id, fn, user_id, status, duration_ms) em 5 Edge Functions | CONCLUIDA |
| 17.4.32 | Fix obs: refatorar 5 Edge Functions para try/finally — logs sempre executam | CONCLUIDA |
| 17.4.33 | Hardening: validacao de entrada com shared validate.ts (requireJson/requireFields) em 5 Edge Functions | CONCLUIDA |
| 17.4.34 | Hardening: validacao obrigatoria de inputs (requireFields) — submit-analytics exige event_name, settle-challenge exige challenge_id, evaluate-badges exige user_id | CONCLUIDA |
| 17.4.35 | Producao: CORS + preflight (OPTIONS 204) + CORS headers em todas as respostas via shared cors.ts + http.ts | CONCLUIDA |
| 17.4.36 | Fix: rate limit nao disparava — db client sem persistSession:false + fail-open trocado por 503 RATE_LIMIT_UNAVAILABLE | CONCLUIDA |
| 17.4.37 | Hardening: sanitizar erros de DB via classifyError — mensagens internas do Postgres nunca vazam para o client | CONCLUIDA |
| 17.4.38 | Schema v1: runs + RLS hardening + seed | REVERTIDA — instrucao cancelada pelo usuario |
| 17.5.0 | Expandir roles coaching_members (coach→admin_master, assistant→assistente, athlete→atleta) + professor; migration + 5 RLS policies | CONCLUIDA |
| 17.5.1 | Enforce: atleta pertence a 1 assessoria + profiles.active_coaching_group_id (FK + partial unique index) | CONCLUIDA |
| 17.5.2 | RPC fn_switch_assessoria (burn coins + switch group + membership) + coin_ledger reason expansion | CONCLUIDA |
| 17.6.0 | coaching_token_inventory + token_intents (OPEN/CONSUMED/EXPIRED/CANCELED) + RLS staff/target | CONCLUIDA |
| 17.6.1 | Edge Functions token-create-intent + token-consume-intent + coin_ledger reason expansion + inventory RPCs | CONCLUIDA |
| 17.7.0 | Pending coins para prêmios cross-assessoria: wallets.pending_coins + RPCs + settle-challenge cross detection | CONCLUIDA |
| 17.8.0 | Clearing semanal: clearing_weeks/cases/items/events tables + clearing-confirm-sent + clearing-confirm-received + clearing-open-dispute Edge Functions | CONCLUIDA |
| 17.9.0 | Championships: templates + championships + invites + participants + badges tables + champ-create/invite/activate-badge/list/participant-list Edge Functions | CONCLUIDA |
| 17.10.0 | QA: aplicar migrations em projeto real, validar RLS, testar Edge Functions | TODO |
| 17.6.0 | Atualizar docs (MASTER_PLAN + CONTEXT_DUMP) | CONCLUIDA |

---

## PHASE 18 — Social Auth + Onboarding

| Sprint | Descricao | Status |
|---|---|---|
| 18.1.0 | Habilitar Login Social no Supabase (Google + Apple) — configuração Dashboard apenas, sem código Flutter | CONCLUIDA |
| 18.1.1 | Definir callback/redirect do app (deep link): registrar scheme `omnirunner://` em AndroidManifest + Info.plist + documentar em DECISIONS + SOCIAL_AUTH_SETUP | CONCLUIDA |
| 18.1.2 | Contract de Auth: profiles.onboarding_state (NEW/ROLE_SELECTED/READY) + user_role (ATLETA/ASSESSORIA_STAFF) + created_via (ANON/EMAIL/OAUTH_GOOGLE/OAUTH_APPLE/OTHER) + handle_new_user trigger update | CONCLUIDA |
| 18.2.0 | Edge Function: complete-social-profile (idempotent upsert profile + created_via auto-detect + rate limit + obs) | CONCLUIDA |
| 18.2.1 | Edge Function: set-user-role (ATLETA/ASSESSORIA_STAFF) — guards NEW/ROLE_SELECTED, denies READY, advances to ROLE_SELECTED | CONCLUIDA |
| 18.3.0 | Flutter: google_sign_in + sign_in_with_apple + signInWithIdToken — IAuthDataSource social methods, RemoteAuthDataSource (native SDK → signInWithIdToken), MockAuthDataSource stubs, AuthRepository social wrappers, AuthSocialCancelled failure, complete-social-profile call (unawaited) | CONCLUIDA |
| 18.3.1 | Session Guard Global + Routing por Estado: AuthGate (session→login/onboarding/home), LoginScreen (Google+Apple), OnboardingRoleScreen (ATLETA/ASSESSORIA_STAFF→set-user-role→READY), ProfileEntity + OnboardingState enum, main.dart entry point | CONCLUIDA |
| 18.4.0 | Tela "O que é o Omni Runner" (WelcomeScreen): 4 bullets value prop + CTA COMEÇAR → LoginScreen; AuthGate welcome destination | CONCLUIDA |
| 18.4.1 | Tela Login Social (Google + Apple): LoginScreen polished — OutlinedButton Google, FilledButton Apple (iOS), inline error com ícone, loading spinner, sem email/senha, sem role | CONCLUIDA |
| 18.4.2 | Tela "Escolher Papel": OnboardingRoleScreen rewrite — select+confirm pattern (Radio), animated border, spinner no botão, sem termos técnicos, calls set-user-role → READY | CONCLUIDA |
| 18.5.0 | Escolher Assessoria (JoinAssessoriaScreen): busca por nome (fn_search_coaching_groups RPC), QR scanner, código manual, convites pendentes, pular; AuthGate joinAssessoria destination; OnboardingRoleScreen ATLETA→ROLE_SELECTED (não READY); fn_switch_assessoria para join; set READY on join/skip | CONCLUIDA |
| 18.5.1 | Dashboard Atleta "para dummies": AthleteDashboardScreen 4 cards (Meus desafios, Minha assessoria, Meu progresso, Meus créditos), empty state assessoria, HomeScreen tabs reorganized (Início/Correr/Histórico/Mais — Progress tab removida) | CONCLUIDA |
| 18.6.0 | Staff Setup (StaffSetupScreen): "Criar assessoria" (fn_create_assessoria RPC → admin_master + active_coaching_group_id) vs "Entrar como professor" (fn_join_as_professor RPC → search/QR/code); AuthGate staffSetup destination; OnboardingRoleScreen: both roles stay ROLE_SELECTED | CONCLUIDA |
| 18.6.1 | Dashboard Assessoria "para dummies": StaffDashboardScreen 4 cards (Atletas, Campeonatos, Créditos, Administração), alert "Prêmios pendentes de liberação", HomeScreen role-aware (AuthGate passa userRole → tab 0 dinâmico) | CONCLUIDA |
| 18.7.0 | Roteamento Final: auditoria da máquina de estados (NEW→ROLE_SELECTED→READY + papel), forward-only sem loops, READY terminal (409 ONBOARDING_LOCKED), trigger handle_new_user garante profile, dashboard por papel (AuthGate→HomeScreen userRole), DECISAO 041 | CONCLUIDA |
| 18.7.1 | Empty States "para dummies": ChallengesListScreen CTA "Criar desafio" (FilledButton.icon), WalletScreen empty history "Peça ao professor para distribuir OmniCoins", MyAssessoriaScreen CTA "Entrar em uma assessoria" (→ JoinAssessoriaScreen) | CONCLUIDA |
| 18.99.0 | QA Phase 18: 65 testes — Auth (7), Onboarding (16), Guards (11), UX Empty States (7), Termos Proibidos (14), Static Analysis (4), Edge Functions (2), SQL RPCs (4); QA-FIX-01 "clearing"→"confirmado entre assessorias"; docs/QA_PHASE_18.md | CONCLUIDA |
| 18.8.0 | Onboarding polish: nome, avatar | TODO |

---

## PHASE 19 — OAuth Avançado + Assessoria Ecosystem Core

> **Status:** EM ANDAMENTO

### OAuth Avançado

| Sprint | Descricao | Status |
|---|---|---|
| 19.1.0 | Configurar apps TikTok e Instagram (consoles externos): TikTok Login Kit (sandbox) + Instagram Basic Display via Facebook Developers (dev mode); Redirect URI unificada; DECISAO 042 (custom provider via Edge Function); SOCIAL_AUTH_SETUP.md §8-12 | CONCLUIDA |
| 19.1.1 | Registrar providers no Supabase: Facebook/Instagram via `auth.external.facebook` (nativo); TikTok requer Edge Function customizada (não suportado nativamente); config.toml + .env.example + SUPABASE_BACKEND_GUIDE atualizado | CONCLUIDA |
| 19.1.2 | Integrar TikTok e Instagram no AuthService: `signInWithInstagram()` via `signInWithOAuth(facebook)`; `signInWithTikTok()` via Edge Function `validate-social-login`; IAuthDataSource + RemoteAuth + MockAuth + AuthRepository + LoginScreen com 4 botões | CONCLUIDA |
| 19.2.0 | Deep Links Universais: Android App Links + iOS Universal Links para `https://omnirunner.app/invite/{code}`; `app_links` package; `DeepLinkHandler` singleton; `AuthGate` + `JoinAssessoriaScreen` wiring; `.well-known` templates; UNIVERSAL_LINKS_SETUP.md | CONCLUIDA |
| 19.2.1 | Invite Links Persistentes: `invite_code` + `invite_enabled` em coaching_groups; `fn_generate_invite_code` + `fn_lookup_group_by_invite_code` RPCs; `fn_create_assessoria` retorna invite_link; entity/Isar/repo atualizados; JoinAssessoriaScreen aceita invite codes | CONCLUIDA |
| 19.2.2 | QR Code para Invite Links: `InviteQrScreen` com QR persistente do invite_link; `share_plus` (copiar/compartilhar); acesso via StaffQrHubScreen + CoachingGroupDetailsScreen; QR abre app via Universal/App Links | CONCLUIDA |
| 19.3.0 | Auto Join via Invite Link: `DeepLinkHandler` persiste invite code em SharedPreferences; `AuthGate` auto-join com dialog de confirmação para READY users; pending code sobrevive OAuth redirect; QR scanner aceita invite URLs | CONCLUIDA |
| 19.3.1 | Estado de Invite Pendente: fix cold-start race condition (auto-persist em `_handle()`); auto-advance WelcomeScreen→Login quando invite chega; banner "Você recebeu um convite!" no LoginScreen; `consumePendingInvite` após auto-join | CONCLUIDA |
| 19.4.0 | Revisar Textos do App: audit completo de UI contra GAMIFICATION_POLICY.md; tradução PT-BR de more_screen; substituição de "Token"→"OmniCoins", "Taxa"→"Inscrição", "nonce"→"código de uso único"; 0 termos proibidos; linguagem simples e consistente | CONCLUIDA |
| 19.4.1 | Tooltips de Primeira Utilização: `FirstUseTips` (SharedPreferences) + `TipBanner` widget reutilizável com animação; tips em AthleteDashboard (boas-vindas + assessoria), ChallengesListScreen (como desafiar), StaffDashboard (boas-vindas + campeonatos); dismiss-once | CONCLUIDA |
| 19.5.0 | Edge Function: validate-social-login (TikTok code exchange — custom OAuth) | TODO |
| 19.6.0 | Migration: profiles.created_via expansion (OAUTH_FACEBOOK, OAUTH_TIKTOK) | TODO |
| 19.99.0 | Testes End-to-End Phase 19: 97 testes (OAuth 4 providers, Deep Links, Invite Persistence, Auto-Join, QR Invites, Onboarding regression, UX Polish, Static Analysis, Backend RPCs/Edge Functions); 97 PASS / 0 FAIL; QA_PHASE_19.md | CONCLUIDA |

### Assessoria Ecosystem Core (EPIC-07)

> **Origem:** DECISAO 038 — Introdução do Ecossistema de Assessorias como Núcleo do Produto

### Objetivo

Transformar o Omni Runner de um aplicativo centrado no usuário individual para um ecossistema institucional centrado em Assessorias esportivas.

### Princípios de Implementação

- Nenhuma funcionalidade existente pode ser quebrada
- Todo o desenvolvimento deve ser incremental, compatível com o modelo atual e isolado por domínio

### Dependências Críticas

- Module C depende de Module A + B
- Module D depende de Module C
- Module E depende de Module D
- Module F depende de Module A
- Module G depende de pipeline analytics existente (Phase 16)

### Critérios de Conclusão

- Assessorias conseguirem operar completamente dentro do app
- Tokens funcionarem com lastro institucional
- Desafios inter-assessorias funcionarem
- Clearing semanal estiver operacional
- Campeonatos institucionais puderem ser criados e executados

### Riscos

- Complexidade de domínio elevada
- Necessidade de UX extremamente clara
- Impacto significativo no modelo de dados
- Alto número de novas entidades

### MODULE A — Institutional Core Domain

| Sprint | Descricao | Status |
|---|---|---|
| 18.A.1 | Entidades domain: InstitutionEntity, InstitutionStaffEntity, InstitutionMembershipEntity + enums (InstitutionStatus, StaffRole, MembershipStatus) | TODO |
| 18.A.2 | Use Cases: CreateInstitution, ApproveInstitution, AddStaff, RemoveStaff, RequestMembership, ApproveMembership + repo interfaces + InstitutionFailure hierarchy | TODO |
| 18.A.3 | Persistência: Supabase tables (institutions, institution_staff, institution_memberships) + RLS policies + migrations | TODO |
| 18.A.4 | UI: InstitutionDashboardScreen, StaffManagementScreen, MembershipRequestsScreen + BLoCs + DI | TODO |

### MODULE B — User Institutional Binding

| Sprint | Descricao | Status |
|---|---|---|
| 18.B.1 | Entidade: campo active_institution_id no ProfileEntity + InstitutionBindingEntity | TODO |
| 18.B.2 | Use Cases: BindToInstitution, UnbindFromInstitution, SwitchInstitution (com regras de queima de tokens) | TODO |
| 18.B.3 | Persistência: migration para active_institution_id em profiles + RLS update | TODO |
| 18.B.4 | UI: InstitutionSelectionScreen, SwitchInstitutionConfirmationDialog + warnings de queima | TODO |

### MODULE C — Institutional Token Economy

| Sprint | Descricao | Status |
|---|---|---|
| 18.C.1 | Entidades: InstitutionTokenInventoryEntity, InstitutionalWalletEntity + token lifecycle state machine | TODO |
| 18.C.2 | Use Cases: PurchaseTokens (plataforma→assessoria), DistributeTokens (assessoria→atleta), BurnTokens + ledger institucional | TODO |
| 18.C.3 | Persistência: Supabase tables + institution_origin_id em coins + clearing constraints + migrations | TODO |
| 18.C.4 | UI: InstitutionWalletScreen, TokenDistributionScreen, TokenLedgerScreen + BLoCs + DI | TODO |

### MODULE D — Cross-Institution Challenges

| Sprint | Descricao | Status |
|---|---|---|
| 18.D.1 | Entidades: CrossInstitutionChallengeEntity + stake institucional + pending clearing state | TODO |
| 18.D.2 | Use Cases: CreateCrossChallenge, SettleCrossChallenge (tokens→assessoria vencedora) + ajustes no settle-challenge Edge Function | TODO |
| 18.D.3 | Persistência: migrations + RLS para cross-institution challenges | TODO |
| 18.D.4 | UI: CrossChallengeScreen + ajustes em ChallengeDetailsScreen + DI | TODO |

### MODULE E — Inter-Institution Clearing System

| Sprint | Descricao | Status |
|---|---|---|
| 18.E.1 | Entidades: InterInstitutionSettlementEntity + SettlementStatus enum + ClearingPeriod | TODO |
| 18.E.2 | Use Cases: CreateSettlement, ConfirmSettlement (dupla confirmação), DisputeSettlement, ResolveDispute + Edge Function clearing-weekly | TODO |
| 18.E.3 | Persistência: inter_institution_settlements table + migrations + RLS | TODO |
| 18.E.4 | UI: ClearingDashboardScreen, SettlementDetailsScreen, DisputeResolutionScreen + BLoCs + DI | TODO |

### MODULE F — Championships System

| Sprint | Descricao | Status |
|---|---|---|
| 18.F.1 | Entidades: ChampionshipEntity (ChampionshipStatus, ChampionshipType), ChampionshipParticipantEntity, ChampionshipRankingEntity | TODO |
| 18.F.2 | Use Cases: CreateChampionship, InviteInstitution, AcceptChampionshipInvite, SubmitChampionshipResult, ComputeChampionshipRanking | TODO |
| 18.F.3 | Persistência: championships, championship_participants tables + badge temporário + migrations + RLS | TODO |
| 18.F.4 | UI: ChampionshipsListScreen, ChampionshipDetailsScreen, ChampionshipRankingScreen, CreateChampionshipScreen + BLoCs + DI | TODO |

### MODULE G — Coaching Intelligence Dashboard

| Sprint | Descricao | Status |
|---|---|---|
| 18.G.1 | Dashboard: CoachingOverviewScreen (KPIs institucionais, atletas ativos, sessões/semana, evolução média) | TODO |
| 18.G.2 | Performance tracking: AthletePerformanceScreen (métricas individuais, baseline comparison, trends) | TODO |
| 18.G.3 | Insights automáticos: integração InsightGenerator com dados institucionais + alertas para coach | TODO |
| 18.G.4 | Gestão de atletas: AthleteManagementScreen (bulk actions, notas, classificação por nível) + BLoCs + DI | TODO |

### MODULE H — Gamification Alignment

| Sprint | Descricao | Status |
|---|---|---|
| 18.H.1 | Leaderboards institucionais: InstitutionLeaderboardEntity + rankings por assessoria + rankings inter-assessorias | TODO |
| 18.H.2 | Badges institucionais: InstitutionBadgeEntity + badges criados pela assessoria + badges de campeonato | TODO |
| 18.H.3 | Progressão esportiva: ajustar XP/badges para priorizar evolução real sobre gamificação casual | TODO |
| 18.H.4 | Rankings inter-assessorias: GlobalInstitutionRankingEntity + Edge Function compute-institution-ranking | TODO |

---

## PHASE 20 — Gamification (Progression Final)

> **Status:** EM ANDAMENTO

| Sprint | Descricao | Status |
|---|---|---|
| 20.1.0 | Travar Modelo de Progressão (Docs): DECISAO 044 (4 pilares: XP, Nível, Streak, Goals semanais); microcopy UX "para dummies" em PT-BR; integração com assessorias e campeonatos; ARCHITECTURE.md §8 Progression System; compliance GAMIFICATION_POLICY.md verificado; sem código | CONCLUIDA |
| 20.1.1 | Backend: profile_progress +level/streak_best/freeze_earned_at_streak; weekly_goals table (metric/target/status/xp); v_user_progression view (xp/level/streak/xp_to_next); v_weekly_progress view (sessions aggregated by ISO week); increment_profile_progress updated to recompute level; fn_update_streak RPC (freeze logic); fn_generate_weekly_goal RPC (baseline 4w, factor 1.0/1.1); fn_check_weekly_goal RPC (auto-complete +40 XP); RLS own+staff read | CONCLUIDA |
| 20.1.2 | Edge Function: calculate-progression (idempotente por run); sessions.progression_applied flag; fn_mark_progression_applied RPC (atomic mark+fetch +is_verified field para distinguir "already applied" vs "not verified"); fn_get_daily_session_xp + fn_count_daily_sessions (caps); XP breakdown (base 20 + dist + dur + HR); daily caps 1000 XP + 10 sessions; streak + weekly goal check integrado; outer catch logs error detail; config.toml registrado | CONCLUIDA |
| 20.1.3 | UI: Progresso do Atleta — ProgressionScreen redesenhada com 3 blocos (Nível+XP com barra, Streak com recorde+proteção, Meta Semanal com progresso %); WeeklyGoalEntity criada; ProfileProgressEntity +streakBest; Isar model+repo atualizado; ProgressionBloc busca weekly_goals via Supabase; empty-state "corra para começar"; TipBanner progressionHowTo; progress_hub_screen traduzido PT-BR; "Season XP" → "XP da temporada", "Streak" → "Sequência" nos labels | CONCLUIDA |
| 20.2.0 | Catálogo de Badges Automáticos (Docs): DECISAO 045 — 24 badges em 7 categorias (Primeiros Passos, Distância, Frequência, Streak, Velocidade, Social, Especial); 3 novos criteria_types (weekly_distance, challenge_won, championship_completed); badges de overtraining removidos; streak máx 14 dias global; linguagem PT-BR saudável; sem código | CONCLUIDA |
| 20.2.1 | Backend: Expandir evaluate-badges — migration 6 novos badges; seed.sql atualizado; Edge Function +4 criteria_types (weekly_distance via v_weekly_progress, challenge_won, championship_completed, personal_record_pace server-side); fetch paralelo de weekly progress, challenge wins, champ completions, best pace; EvalContext expandido; dailyStreak usa MAX(current, best) | CONCLUIDA |
| 20.2.2 | UI: Tela de Badges (Coleção + Recentes) — redesign BadgesScreen com seção "Desbloqueadas recentemente" (horizontal scroll, top 6), "Coleção" (ListTile com "Como ganhar" visível), detail bottom sheet com "Como ganhar" box, TipBanner badgesHowTo, empty states motivacionais | CONCLUIDA |
| 20.3.0 | Backend: Leaderboards v2 (Global/Assessoria/Campeonato) — migration 20260227_leaderboard_v2.sql: expand scope CHECK (+assessoria, +championship), +coaching_group_id/championship_id FK columns, RLS v2 (scope-aware read + service_role write), 3 RPCs (compute_leaderboard_global composite, compute_leaderboard_assessoria composite, compute_leaderboard_championship per-metric); Edge Function compute-leaderboard reescrita para 3 scopes + validação de membro/participante + período weekly/monthly | CONCLUIDA |
| 20.3.1 | UI: Rankings com Tabs e Filtros Simples — LeaderboardsScreen com TabBar (Assessoria/Campeonato/Global), filtro Semana/Mês (FilterChip), dropdown de campeonato, LeaderboardsBloc fetchando Supabase real, highlight do usuário atual (tag "Você"), ScoringExplanation card, TipBanner rankingsHowTo, empty states contextuais por tab; LeaderboardEntity +assessoria/championship scopes +composite metric; progress_hub_screen imports limpos | CONCLUIDA |
| 20.4.0 | UX do Desafio: Criar/Aceitar/Agendar — ChallengeCreateScreen com 2 modos claros (Agora: chips 5/10/30min/1h/24h + Agendado: date/time picker + duração 1/3/7/14/30 dias); regras de validação visíveis; ChallengeDetailsScreen com card Accept/Decline para convidados, card "Como funciona" sempre visível, tag "Você", results com OmniCoins; ChallengesListScreen +mode tag (Imediato/Agendado), "C"→"OmniCoins"; "Taxa"→"Inscrição" | CONCLUIDA |
| 20.4.1 | Race Mode: Ghost Runner visível e motivador — ChallengeGhostProvider (polling opponent progress_value a cada 15s, stale detection 2min); ChallengeGhostOverlay (progresso relativo "X m à frente/atrás", barras de progresso dual, indicador offline com tooltip, borda pulsante); SetChallengeContext event + TrackingActive +challengeId/opponentUserId/opponentName/targetM; TrackingScreen integração condicional da overlay; GhostVoiceTrigger/GhostComparisonCard/GhostPickerSheet traduzidos PT-BR; privacidade preservada (sem GPS do oponente, apenas distância agregada) | CONCLUIDA |
| 20.4.2 | Pós-corrida do Desafio: Resultado claro + próxima ação — ChallengeResultScreen com HeroSection (troféu/outcome, headline contextual "Você venceu!"/"Boa tentativa!"/etc), classificação com rank+nome+valor+OmniCoins, RewardCard ("Recompensa liberada"/"Recompensa pendente"), CTAs (Desafiar novamente → ChallengeCreateScreen, Ver ranking → LeaderboardsScreen, Compartilhar → placeholder); ChallengeSessionBanner no RunSummaryScreen (banner teal com "Ver resultado do desafio"); ChallengeDetailsScreen +botão "Ver resultado completo"; TrackingScreen passa challengeId ao RunSummaryScreen; RunSummaryScreen traduzido PT-BR | CONCLUIDA |
| 20.5.0 | Feed da Assessoria (social leve) — migration assessoria_feed table (7 event_types, JSONB payload, RLS member-only, fn_get_assessoria_feed RPC paginado max 50); FeedItemEntity + FeedEventType enum; AssessoriaFeedBloc (load/loadMore/refresh, paginação cursor-based); AssessoriaFeedScreen (pull-to-refresh, infinite scroll, tiles com ícone+cor+descrição contextual por tipo, "há X min" relativo, empty state motivacional); ProgressHubScreen +tile "Feed da Assessoria" com fetch async de active_coaching_group_id; sem feed global; sem exposição cross-grupo | CONCLUIDA |
| 20.5.1 | Replays/Highlights (mínimo viável) — ReplayAnalyzer use case (km splits com pace, sprint final detection via sliding window últimos 40%, SprintHighlight + KmSplit + ReplayData models); RunReplayScreen (polyline animada 12s com head dot, sprint highlight layer laranja no mapa, splits table com pace bars + star no melhor km, sprint card com bolt icon, play/pause); SummaryMetricsPanel +replayPoints + botão "Replay da corrida" (≥10 pontos); RunSummaryScreen e RunDetailsScreen passam pontos ao replay; labels PT-BR completos; nenhum dado sensível armazenado | CONCLUIDA |
| 20.6.0 | UX: Corrida invalidada (explicar de forma clara e amigável) — InvalidatedRunCard (flags→razões amigáveis PT-BR, sem acusações, CTAs: Tentar novamente/Enviar para revisão/Ver dicas de GPS); GpsTipsSheet bottom sheet (6 dicas práticas com ícones); RunSummaryScreen+RunDetailsScreen substituem integrity card antigo; TrackingScreen banner traduzido "GPS instável — pode afetar a validação"; chips SYNCED/UNVERIFIED/flags traduzidos PT-BR | CONCLUIDA |
| 20.6.1 | UX: Disputa do Desafio (para staff/atleta) — DisputeStatusCard (5 fases: pendingClearing/sentConfirmed/disputed/cleared/expired, textos empáticos PT-BR, prazo countdown, OmniCoins amount, sem "plataforma decide"); StaffDisputesScreen (lista de clearing_cases com ações: confirmar envio/recebimento, abrir revisão com dialog de confirmação, status visual por caso, empty/error states); ChallengeDetailsScreen +_ClearingInfo async lookup; StaffDashboardScreen +card "Confirmações" com badge de casos pendentes em vez do placeholder Campeonatos; Supabase queries RLS-safe | CONCLUIDA |
| 20.6.2 | Use Case: GenerateWeeklyGoal (baseline 4 semanas, fator 1.0×/1.1×, auto-check) + CheckWeeklyGoal | TODO |
| 20.6.3 | Persistência Goals: Isar WeeklyGoalRecord + repo impl + DB provider + DI | TODO |
| 20.6.4 | UI Goals: WeeklyGoalCard na home (barra de progresso + mensagem) + GoalHistoryScreen | TODO |
| 20.7.0 | Integração pós-sessão: wiring AwardXp + EvaluateBadges + UpdateStreak + CheckWeeklyGoal no pipeline | TODO |
| 20.8.0 | Microcopy final: implementar mensagens UX em todas as telas de progressão (conforme DECISAO 044 §3) | TODO |
| 20.99.0 | QA Phase 20: testes E2E progressão + goals + microcopy + termos proibidos — 72 testes / 72 PASS / 0 FAIL; 7 correções de termos proibidos (saldo→Seus OmniCoins, carteira→removido, Token→OmniCoins); scan completo §5 GAMIFICATION_POLICY; flutter analyze 0 errors; docs/QA_PHASE_20.md gerado | CONCLUIDA |

---

### PHASE 21 — Monetização (Loja-Safe)

> **Status:** EM ANDAMENTO

| Sprint | Descricao | Status |
|---|---|---|
| 21.1.0 | Formalizar Modelo Loja-Safe nos Docs — DECISAO 046 (B2B SaaS: créditos digitais para assessorias, venda externa, zero IAP, zero valor monetário no app); ARCHITECTURE.md §9 Monetization Model (fluxo, invariantes M1–M7, componentes existentes); terminologia proibida expandida (comprar/preço/R$/fatura/plano/upgrade); declarações App Review preparadas | CONCLUIDA |
| 21.1.1 | Tabela de Licenciamento de Créditos (B2B) — institution_credit_purchases (append-only, zero valores monetários, FK coaching_groups); fn_credit_institution RPC (atomic: audit row + inventory increment, SECURITY DEFINER); RLS admin_master read-only; SUPABASE_BACKEND_GUIDE.md atualizado (mapa, SQL files, RLS matrix) | CONCLUIDA |
| 21.1.2 | Tela de Aquisição de Créditos (Sem Pagamento no App) — StaffCreditsScreen (inventário assessoria via coaching_token_inventory, histórico via institution_credit_purchases, CTA "Entre em contato" sem referência a pagamento); StaffDashboardScreen card Créditos redireciona para nova tela; zero termos proibidos; compliance GAMIFICATION_POLICY + DECISAO 046 | CONCLUIDA |
| 21.2.0 | Dashboard de Performance da Assessoria — StaffPerformanceScreen com 4 KPIs (atletas ativos/total, corridas semanais+km, desafios realizados/vitórias, campeonatos participações/concluídos) + top 5 atletas da semana; dados reais via Supabase (coaching_members, sessions, challenge_participants, championship_participants); card "Performance" no StaffDashboardScreen (grid agora com 5 cards); pull-to-refresh + empty/error states; zero termos proibidos | CONCLUIDA |
| 21.2.1 | Relatórios Semanais para Assessoria — StaffWeeklyReportScreen com navegação prev/next week; 3 seções: resumo semanal (corridas, distância, ativos/total, média por atleta), progresso médio (XP, nível, sequência via v_user_progression), ranking interno (todos atletas por distância + corridas + pace); botão "Ver relatório semanal" no StaffPerformanceScreen; dados Supabase reais (coaching_members, sessions, v_user_progression); zero termos proibidos | CONCLUIDA |
| 21.3.0 | Sistema de Convites de Amigos — InviteFriendsScreen (link pessoal + QR + share nativo via share_plus); link formato `https://omnirunner.app/refer/{userId}`; DeepLinkHandler +ReferralAction para /refer/ path; AthleteDashboardScreen +card "Convidar amigos" (grid 5 cards); MoreScreen "Amigos" Coming Soon substituído por tile funcional; card "Como funciona?" com 3 passos; zero termos proibidos | CONCLUIDA |
| 21.3.1 | Mostrar Streaks dos Amigos/Assessoria — StreaksLeaderboardScreen com 2 seções: "Em sequência agora" (atletas com streak ≥1, fire tiles com dias + recorde) e "Ranking de consistência" (todos atletas por streak_best desc + streak ativa); dados via coaching_members + v_user_progression; highlight "você"; fallback sem assessoria; ProgressHubScreen +tile "Sequências" + _Target.streaks; zero termos proibidos | CONCLUIDA |
| 21.3.2 | Templates de Campeonatos Recorrentes — StaffChampionshipTemplatesScreen (lista modelos salvos, criar novo modelo com nome/descrição/métrica/duração/badge/máx participantes, lançar campeonato a partir de modelo via champ-create Edge Function com date picker); StaffDashboardScreen +card "Campeonatos" (grid agora com 6 cards); TipBanner campeonatos atualizado; DB: championship_templates já existente (migration 20260222); zero termos proibidos | CONCLUIDA |
| 21.4.0 | Tracking de Eventos de Produto — migration product_events (append-only, RLS user+staff); ProductEventTracker service (track fire-and-forget + trackOnce com dedup); ProductEvents constantes (onboarding_completed, first_challenge_created, first_championship_launched, flow_abandoned); instrumentação: JoinAssessoriaScreen (3 paths: join/invite/skip), StaffSetupScreen (2 paths: create/join), ChallengeCreateScreen (first challenge + abandonment), StaffChampionshipTemplatesScreen (first championship); service_locator registrado; zero termos proibidos | CONCLUIDA |
| 21.4.1 | Dashboards de Retenção — StaffRetentionDashboardScreen com 3 seções: DAU/WAU gauge (ativos hoje/semana/total com % de engajamento), gráfico de atividade semanal (barras 4 semanas com atletas ativos), tabela de retenção semanal (ativos/retornantes/taxa % com cores semáforo + tag "atual"), insight card automático (trending up/down/flat com recomendações); dados via sessions + coaching_members (RLS-safe); StaffPerformanceScreen +botão "Retenção" ao lado de "Relatório"; zero termos proibidos | CONCLUIDA |
| 21.5.0 | Infraestrutura de Push Notifications — migration device_tokens (user_id+token+platform, RLS own CRUD, UNIQUE user_id+token); Edge Function send-push (service-role only, FCM HTTP v1 API, OAuth2 JWT signing com service account, envio por user_ids, limpeza automática de tokens stale NOT_FOUND/UNREGISTERED, config Android priority+channel + iOS sound+badge); PushNotificationService Flutter (requestPermission, getToken+upsert, onTokenRefresh, foreground handler, background handler @pragma vm:entry-point, clearTokens on sign-out); firebase_core+firebase_messaging no pubspec.yaml; Firebase.initializeApp() no bootstrap; service_locator registrado; config.toml send-push registrado; zero termos proibidos | CONCLUIDA |
| 21.5.1 | Regras de Notificação Inteligentes — migration notification_log (dedup guard: user_id+rule+context_id+sent_at, RLS select own, service-role write); Edge Function notify-rules (service-role only, avalia 3 regras: challenge_received busca invited em challenge_participants e notifica convidados, streak_at_risk verifica v_user_progression streak>=3 sem sessão hoje, championship_starting busca campeonatos iniciando em 24h e notifica participants enrolled/active; dedup 12h via notification_log; dispatch via send-push interno); NotificationRulesService Flutter (fire-and-forget, notifyChallengeReceived + notifyChampionshipStarting + evaluateAll); wired em challenge_create_screen (após ChallengeCreated) e staff_championship_templates_screen (após champ-create); service_locator registrado; config.toml notify-rules registrado; zero termos proibidos | CONCLUIDA |
| 21.99.0 | Testes End-to-End — phase_21_e2e_smoke_test.dart com 44 testes em 10 grupos validando 5 pilares: (1) Créditos — data model, formatação, inventory math; (2) Relatórios — mondayOf, week labels, ranking sort by distance desc, pace formatting, avg per athlete; (3) Convites virais — referral link format HTTPS omnirunner.app/refer/{userId}, share text compliance; (4) Analytics — event names snake_case, unicidade, "first_" prefix convention; (5) Notificações — dedup guard 12h window (same user+rule+context blocked, different combos pass), 3 regras server-side (streak_at_risk cron-only), push body compliance; + retention computation (4 weeks, returning = intersection, 100% when all active); compliance scan: zero termos proibidos em todas as strings user-facing; todos 44 testes passando; modelo sustentável validado, crescimento operacional pronto | CONCLUIDA |

---

### Billing Portal (EPIC-10)

| Sprint | Descrição | Status |
|--------|-----------|--------|
| 30.1.0 | Sincronização absoluta + DECISAO 047: stack do portal = Next.js 14+ (App Router) + TypeScript + Tailwind + shadcn/ui + Supabase Auth SSR + Vercel; pasta `portal/` sibling de `omni_runner/`; domínio `portal.omnirunner.app`; escopo read-mostly (créditos, atletas, relatórios, solicitação); zero tabelas novas; RLS existente; roadmap 30.1–30.7+ definido | CONCLUIDA |
| 30.1.1 | DECISAO 048 — Auth Model staff-only: acesso restrito a admin_master/professor/assistente (atleta NUNCA acessa); group_id via query coaching_members (não profiles.active_coaching_group_id); group picker para staff multi-grupo; RLS 100% reutilizado (zero policies novas); matriz de permissões 13 rotas × 3 roles; middleware flow 5 etapas (session→membership→group→role→render); API Routes server-side com service_role para relatórios de engajamento (sessions cross-user); institution_credit_purchases exclusivo admin_master (enforced by RLS); zero tabelas novas | CONCLUIDA |
| 30.2.0 | Backend billing tables — migration 20260221_billing_portal_tables.sql: 4 tabelas (billing_customers PK=group_id com legal_name/tax_id/email/address; billing_products catalog credits_amount+price_cents+currency+is_active; billing_purchases lifecycle pending→paid→fulfilled\|cancelled com FK product_id+group_id+fulfilled_credit_id→institution_credit_purchases; billing_events append-only audit log 6 event types); RLS: billing_customers/purchases/events = admin_master only, billing_products = any staff; fn_fulfill_purchase RPC (SECURITY DEFINER, paid→fulfilled + fn_credit_institution atomic); 3 indexes; SUPABASE_BACKEND_GUIDE.md atualizado (mapa+RLS matrix+migrations) | CONCLUIDA |
| 30.3.0 | Seed billing_products — 5 pacotes em seed.sql (Starter 500/R$75, Básico 1500/R$199, Profissional 5000/R$599, Premium 15000/R$1499, Enterprise 50000/R$3999); price_cents em centavos BRL; IDs estáveis bp_*; ON CONFLICT DO NOTHING (idempotente); padrão consistente com badge catalog seed; nunca exposto no app mobile | CONCLUIDA |

---

### Payments (EPIC-11)

| Sprint | Descrição | Status |
|--------|-----------|--------|
| 31.1.0 | DECISAO 049 — Gateway de pagamento: Stripe como provider único (Pix + boleto + cartão via Stripe BR); Stripe Checkout (hosted page, zero PCI scope); webhooks checkout.session.completed/expired + charge.refunded/dispute; mapeamento completo Stripe → billing_purchases lifecycle; env vars STRIPE_SECRET_KEY + PUBLISHABLE + WEBHOOK_SECRET; fluxo 5 etapas (checkout session → redirect → payment → webhook → fn_fulfill_purchase); dual-provider rejeitado (complexidade não justifica 0,3% economia Pix); revisão futura se volume >R$50k/mês; zero impacto no app mobile (G8) | CONCLUIDA |
| 31.2.0 | Edge Function create-checkout-session — POST recebe product_id+group_id; auth via requireUser (JWT manual); rate limit 10/60s; verifica admin_master via coaching_members; lookup billing_products (is_active); cria billing_purchases (pending) + billing_events (created); inicializa Stripe SDK (esm.sh/stripe@14); cria Stripe Checkout Session (payment_method_types: card+boleto+pix para BRL; metadata: purchase_id+group_id+product_id+request_id; success/cancel URLs portal; expires_at 30min); atualiza payment_reference com session.id; retorna {purchase_id, checkout_url, session_id}; config.toml registrado; .env.example atualizado (STRIPE_SECRET_KEY, PORTAL_URL); SUPABASE_BACKEND_GUIDE atualizado (deploy + env vars); segue 100% padrão _shared (auth/http/cors/rate_limit/obs/validate/errors) | CONCLUIDA |
| 31.3.0 | Edge Function webhook-payments (idempotente) — migration 20260221_billing_webhook_dedup.sql (billing_events.stripe_event_id TEXT + UNIQUE partial index); 3 camadas de idempotência: L1=billing_events stripe_event_id UNIQUE, L2=conditional UPDATE WHERE status='pending', L3=fn_fulfill_purchase FOR UPDATE lock; Stripe signature verification (constructEventAsync + SubtleCryptoProvider); 6 eventos: checkout.session.completed (pending→paid→fulfilled via fn_fulfill_purchase), async_payment_succeeded (boleto), async_payment_failed (→cancelled), expired (→cancelled), charge.refunded (log), charge.dispute.created (log); resolvePaymentMethod via PI expand latest_charge; sem JWT auth (server-to-server); sem rate limit (Stripe-controlled); service-role DB client; retorna 200 para todos eventos processados (evita retry); logs seguros (nunca loga body/headers, só request_id+event_type+error_code) | CONCLUIDA |
| 31.4.0 | Edge Function list-purchases — POST recebe group_id + filtros opcionais (status, limit, offset); auth via requireUser (JWT manual); rate limit 60/60s; verifica admin_master via coaching_members; query billing_purchases por group_id com paginação (default 50, max 200) + count exact; summary computado: total_purchases, total_credits_fulfilled, total_price_cents_fulfilled, breakdown by_status (count+credits+price_cents); retorna {purchases, count, limit, offset, summary}; segue padrão champ-list; config.toml registrado; SUPABASE_BACKEND_GUIDE deploy atualizado | CONCLUIDA |

---

### Portal UI (EPIC-12)

| Sprint | Descrição | Status |
|--------|-----------|--------|
| 32.1.0 | Bootstrap portal web — Next.js 14 (App Router) + TypeScript + Tailwind CSS em `portal/` (sibling de omni_runner/); Supabase Auth SSR (@supabase/ssr + @supabase/supabase-js) com 3 client helpers (server/client/middleware); middleware.ts implementa DECISAO 048 flow 5 etapas (session→membership→group→role→render); login page (email/senha); no-access page; select-group page (multi-grupo); portal layout com sidebar (nav role-aware: 6 rotas, filtro por role) + header (group name + trocar grupo + sign out); route group (portal) com 6 skeleton pages (dashboard/credits/billing/athletes/engagement/settings); role-based route protection (admin_only + admin_professor routes); auth callback API route; .env.local.example; tsc --noEmit ✓; next lint ✓; next build ✓ (15/15 pages) | CONCLUIDA |
| 32.2.0 | Login staff + guard de sessão — fix 3 bugs do 32.1.0: (1) select-group agora usa Server Action setPortalGroup para cookies httpOnly (antes era document.cookie sem httpOnly), (2) sign-out/switch-group via Server Actions signOut+clearPortalGroup com cookies().delete() server-side (antes document.cookie falhava em limpar httpOnly), (3) header convertido de client component para server component com forms; no-access page detecta se usuário é atleta (coaching_members role check) e mostra mensagem específica "Sua conta está vinculada como atleta... Use o app"; dashboard com dados reais via Server Component: coaching_token_inventory (créditos disponíveis), coaching_members count (atletas), billing_purchases (compras fulfilled + total créditos, admin_master only); quick-links admin_master (Comprar Créditos/Ver Estoque/Ver Atletas); lib/actions.ts centraliza 3 server actions (setPortalGroup, clearPortalGroup, signOut); tsc ✓; lint ✓; build 15/15 ✓ | CONCLUIDA |
| 32.3.0 | Tela Créditos (pacotes + comprar) — credits/page.tsx Server Component lista billing_products (is_active=true, sort_order ASC) com saldo atual (coaching_token_inventory.available_tokens); cards com nome/descrição/preço (formatBRL)/custo por OmniCoin; BuyButton client component chama POST /api/checkout que proxeia create-checkout-session Edge Function (JWT forward + group_id cookie); redirect para checkout_url Stripe; billing/success e billing/cancelled pages para retorno pós-checkout; permissão de compra somente para admin_master (outros roles veem mensagem informativa); tsc ✓; build 17/17 ✓ | CONCLUIDA |
| 32.4.0 | Tela Compras & Recibos — billing/page.tsx Server Component lista billing_purchases (group_id, desc created_at, limit 50) com tabela: data, créditos, valor (BRL), método de pagamento (Cartão/Pix/Boleto), status badge (Pendente/Pago/Concluído/Cancelado), link "Ver recibo" (invoice_url → Stripe receipt); summary cards (total compras, total pago, créditos adquiridos); status breakdown badges; estado vazio com link para /credits; webhook-payments atualizado para capturar receipt_url do Stripe charge e gravar em billing_purchases.invoice_url; tsc ✓; build 17/17 ✓ | CONCLUIDA |
| 32.5.0 | Tela Equipe (convites staff) — settings/page.tsx Server Component lista coaching_members staff (admin_master, professor, assistente, coach, assistant) com tabela: nome, função (badge colorido), desde (data), ação remover; InviteForm client component (email + role selector professor/assistente) chama POST /api/team/invite; RemoveButton client component chama POST /api/team/remove com confirmação; API routes usam service-role key para bypass RLS; invite busca user por email via auth.admin.listUsers(), verifica duplicata, insere coaching_members; remove bloqueia auto-remoção e remoção de admin_master; sidebar renomeada "Configurações" → "Equipe"; supabase/service.ts helper criado; .env.local.example atualizado com SUPABASE_SERVICE_ROLE_KEY; tsc ✓; build 20/20 ✓ | CONCLUIDA |

### App Mobile Link (EPIC-13)

| Passo | Descrição | Status |
|-------|-----------|--------|
| 33.1.0 | App mobile: botão "Portal de Assessorias" abre browser externo — AppConfig.portalUrl (PORTAL_URL env, default portal.omnirunner.app); staff_dashboard_screen: card "Portal" (7o card) com icon open_in_browser_rounded abre url_launcher LaunchMode.externalApplication; staff_credits_screen: _ContactCta substituída por _PortalCta com FilledButton "Abrir Portal de Assessorias" que abre browser externo; nunca abre checkout/payment dentro do app; zero referências a preço/pagamento no app; loja-safe (Apple 3.1.1 + Google Play Billing); flutter analyze 0 erros novos ✓ | CONCLUIDA |
| 33.2.0 | Medição: eventos de billing no analytics — 6 event types no product_events: billing_checkout_started (create-checkout-session), billing_payment_confirmed (webhook paid), billing_payment_failed (webhook async_payment_failed), billing_checkout_expired (webhook expired), billing_checkout_returned (portal success/cancelled pages), billing_credits_viewed + billing_purchases_viewed (portal page loads); backend: trackBillingAnalytics helper no webhook (resolve requested_by de billing_purchases, fire-and-forget); portal: lib/analytics.ts trackBillingEvent helper (Server Component, fire-and-forget); tsc ✓; build 20/20 ✓ | CONCLUIDA |

### QA Billing (EPIC-14)

| Passo | Descrição | Status |
|-------|-----------|--------|
| 34.99.0 | QA end-to-end billing — 94 checks across 5 areas: create-checkout-session (20/20), webhook→inventory (30/30), portal reflects balance (19/19), app reflects balance (10/10), no price in app (15/15); code audit: 0 refs to price_cents/billing_products/billing_purchases in app lib/; RLS audit: billing tables staff/admin-only, athletes blocked; idempotency 3-layer verified (L1 unique index, L2 conditional UPDATE, L3 FOR UPDATE lock); loja-safe: Apple 3.1.1 + Google Play Billing compliant; QA_PHASE_34.md written | CONCLUIDA |

### Auto Top-Up (EPIC-15)

| Passo | Descrição | Status |
|-------|-----------|--------|
| 35.1.0 | Formalizar regras de recarga automática — DECISAO 050: auto top-up opt-in por grupo; threshold configurável (10–10.000, default 50); admin escolhe pacote fixo de billing_products; max 3 recargas/mês (config 1–10); cooldown 24h entre recargas; card-only (off-session PaymentIntent); 3DS falha gracefully; tabela billing_auto_topup_config; fluxo: debit → threshold check → PaymentIntent.create → webhook → fn_fulfill_purchase; desligar imediato via toggle; 8 invariantes (AT-1..AT-8); roadmap 35.2–35.6 definido | CONCLUIDA |
| 35.1.1 | Migration: billing_auto_topup_settings — CREATE TABLE com group_id PK (FK coaching_groups CASCADE), enabled (default false), threshold_tokens (10–10000, default 50), product_id (FK billing_products), max_per_month (1–10, default 3), last_triggered_at (nullable TIMESTAMPTZ); RLS: 3 policies admin_master only (SELECT, UPDATE, INSERT via coaching_members role check); no DELETE policy (disable via enabled=false); comments on all columns; BEGIN/COMMIT transaction | CONCLUIDA |
| 35.1.2 | Edge Function: auto-topup-check — POST (service-role only, no user JWT); receives { group_id } after token debit; decision tree: (1) load billing_auto_topup_settings, (2) check available_tokens < threshold, (3) count monthly auto_topup purchases < max_per_month, (4) 24h cooldown via last_triggered_at, (5) verify billing_customers.stripe_customer_id + stripe_default_pm, (6) load billing_products; creates billing_purchase (source='auto_topup') + Stripe PaymentIntent off-session confirm=true; on Stripe error: cancel purchase + log; on success: update payment_reference + last_triggered_at; inline fulfillment if PI succeeds immediately (fn_fulfill_purchase RPC); analytics billing_auto_topup_triggered; migration adds stripe_customer_id/stripe_default_pm to billing_customers + source column to billing_purchases (AT-6); config.toml registered | CONCLUIDA |
| 35.1.3 | Cron Scheduler: auto-topup-cron — Edge Function wrapper que itera sobre todos os grupos com auto top-up enabled e chama auto-topup-check para cada um; pg_cron schedule '0 * * * *' (a cada hora) via pg_net HTTP POST; fn_invoke_auto_topup_cron helper PL/pgSQL (SECURITY DEFINER) lê app.supabase_url + app.service_role_key do database settings; 200ms delay entre chamadas para rate-limiting; analytics billing_auto_topup_cron_run (groups_checked, groups_triggered, duration_ms); migration habilita pg_cron + pg_net; config.toml registrado | CONCLUIDA |
| 35.2.0 | Customer Billing Portal — Edge Function create-portal-session (cria Stripe Customer Portal session; auto-provisiona Stripe Customer se não existe; grava stripe_customer_id em billing_customers); API routes: /api/billing-portal (proxy JWT→EF) + /api/auto-topup (upsert billing_auto_topup_settings, admin_master only); settings/page.tsx reestruturada com 3 seções: (1) Stripe Portal — botão "Gerenciar Pagamentos e Faturas" abre portal Stripe hospedado para ver invoices e atualizar cartão, (2) Auto Top-Up — toggle on/off instantâneo + form configurável (threshold 10–10000, pacote, max/mês 1–10) com summary visual, (3) Equipe (existente); sidebar aberta para todos os roles (admin vê billing+equipe, staff vê equipe); AutoTopupForm client component com switch toggle + campos + save; PortalButton client component com redirect; tsc ✓; lint ✓; build 20/20 ✓ | CONCLUIDA |
| 35.2.1 | Tela "Gerenciar Cobrança" — botão "Gerenciar Cobrança" adicionado à página de Faturamento (/billing) ao lado do título, com ícone external-link; ManageBillingButton client component reutiliza /api/billing-portal para abrir Stripe Customer Portal em redirect; botão na settings page unificado com mesmo label "Gerenciar Cobrança"; header do billing page reestruturado com flex layout (título esquerda, botão direita); tsc ✓; lint ✓; build 20/20 ✓ | CONCLUIDA |
| 35.3.0 | Documentar Política de Refunds — DECISAO 051: elegibilidade por cenário (duplicada 30d, acidental 7d, parcial 7d, consumido=não); impacto nos créditos (débito proporcional obrigatório, RF-1 saldo nunca negativo, RF-3 refund sem débito proibido); aprovação: admin solicita → plataforma verifica consumo/prazo → Stripe Refund → webhook debita inventário; status 'refunded' em billing_purchases (migration futura); max 3 refunds/grupo/mês; self-service futuro; tratamento de disputas via Stripe Dashboard; reembolso parcial com floor(credits*ratio) | CONCLUIDA |
| 35.3.1 | Migration: billing_refund_requests — CREATE TABLE com id UUID PK, purchase_id (FK billing_purchases CASCADE), group_id (FK coaching_groups CASCADE), status ('requested'/'approved'/'processed'/'rejected'), reason (TEXT min 3), refund_type ('full'/'partial'), amount_cents (nullable, partial only), credits_to_debit (calculated), requested_by (FK auth.users), reviewed_by (nullable), review_notes, requested_at, reviewed_at, processed_at; UNIQUE partial index previne duplicatas abertas (purchase_id WHERE status IN requested/approved); RLS: admin_master SELECT + INSERT (requested_by=auth.uid()), mutations service_role; ALTER billing_purchases status CHECK → inclui 'refunded'; ALTER billing_events event_type CHECK → inclui 'refund_requested'; BEGIN/COMMIT | CONCLUIDA |
| 35.3.2 | Refund Processor — Edge Function process-refund (service-role only); recebe { refund_request_id }; valida status='approved' + purchase status='fulfilled' + payment_reference presente; calcula credits_to_debit (full=credits_amount, partial=floor ratio); verifica inventory >= credits (RF-1); chama stripe.refunds.create (full ou partial amount); debita coaching_token_inventory via decrement_token_inventory RPC; atualiza billing_purchases.status→'refunded' (full) ou mantém 'fulfilled' (partial); atualiza refund_request.status→'processed' + processed_at; insere billing_events (refunded) com metadata completa; analytics billing_refund_processed; tratamento de falha Stripe (502) e falha de débito (500 + critical log para reconciliação manual); config.toml registrado | CONCLUIDA |
| 35.4.0 | Limites Operacionais — DECISAO 052: consolidação de todos os limites do sistema em 7 categorias: (1) créditos emitidos/dia: 5.000 tokens/grupo/dia staff, 100.000/intent, auto top-up 3/mês+24h cooldown; (2) resgates/dia: 5.000 burns/grupo/dia, 500/atleta/dia, 10 sessões Coins/dia, XP 1.000+500/dia; (3) desafios simultâneos: 5 ativos/atleta, 10 pendentes, 20 criados/dia, 3 campeonatos ativos/grupo, 200 participantes/campeonato; (4) billing: checkout 10/min, portal 10/min, 1 refund aberto/purchase, 3 refunds/grupo/mês, R$50k max/compra; (5) API rate limits: 14 Edge Functions com limites de 10-60 req/60s; (6) storage: 500 membros/grupo, 300 atletas, 20 staff, 50 events/purchase; (7) enforcement 5 níveis (DB constraint→RLS→rate limit→business logic→monitoring); roadmap de 7 limites não implementados com prioridade | CONCLUIDA |
| 35.4.1 | Migration: billing_limits — CREATE TABLE com group_id UUID PK (FK coaching_groups CASCADE), daily_token_limit INT DEFAULT 5000 CHECK(100–100000), daily_redemption_limit INT DEFAULT 5000 CHECK(100–100000), created_at, updated_at; RLS: staff SELECT, admin_master UPDATE, insert/delete service_role only; RPC get_billing_limits(group_id) retorna limites efetivos com fallback para defaults; RPC check_daily_token_usage(group_id, type) conta SUM(amount) de token_intents do dia UTC e retorna capacidade restante; ambas SECURITY DEFINER STABLE | CONCLUIDA |
| 35.4.2 | Aplicar limites nas Edge Functions — (1) token-create-intent: check_daily_token_usage RPC antes do INSERT para ISSUE_TO_ATHLETE e BURN_FROM_ATHLETE, retorna 429 DAILY_LIMIT_EXCEEDED com capacidade restante; (2) token-consume-intent: mesmo check + per-athlete daily burn cap 500 via query token_intents CONSUMED do dia, retorna 429 ATHLETE_DAILY_BURN_LIMIT; (3) settle-challenge: stake distribution guard MAX_COINS_PER_CHALLENGE=10000, challenges que excedem são expiradas com log; (4) champ-create: MAX_ACTIVE_CHAMPS=3 por grupo (draft+active), retorna 429 CHAMPIONSHIP_LIMIT; (5) DB triggers: fn_enforce_challenge_limits (max 20 challenges/dia/user) + fn_enforce_participant_limits (max 5 accepted + max 10 pending por atleta); migration 20260221_challenge_limits.sql | CONCLUIDA |
| 35.5.1 | Gateway de Pagamento Preferido — cada assessoria agora escolhe seu gateway padrão (MercadoPago ou Stripe) nas Configurações do portal; migration: billing_customers.preferred_gateway (TEXT, default 'mercadopago', CHECK IN); API route /api/gateway-preference (GET/POST, admin_master only, auto-provisiona billing_customers se necessário); GatewaySelector component com cards visuais lado a lado mostrando prós e contras de cada gateway; BuyButton atualizado: botão principal usa gateway preferido com estilo contextual (azul MP / roxo Stripe), botão secundário permite usar o gateway alternativo; credits/page.tsx busca preferred_gateway via service client; fluxo completo: Settings → escolhe → salva → Credits → botão reflete escolha → checkout usa gateway correto | CONCLUIDA |
| 35.5.0 | Recarga Automática Híbrida — auto-topup-check agora suporta modo híbrido: (1) Com Stripe configurado (stripe_customer_id + stripe_default_pm): cobrança automática off-session via PaymentIntent (comportamento original); (2) Sem Stripe: envia notificação push para admin_master via notify-rules (regra low_credits_alert) avisando que créditos estão baixos e sugerindo compra manual pelo portal (MercadoPago); Stripe é agora opcional (não bloqueia startup se STRIPE_SECRET_KEY ausente); cooldown 24h aplicado nos dois caminhos; UI do portal atualizada: seção Stripe Customer Portal só aparece se há stripe_customer_id; summary do AutoTopupForm mostra texto contextual (cobrança automática vs notificação push); toggle description adaptado; novo return reason 'no_payment_method_notified' com campo notified:boolean | CONCLUIDA |
| 35.99.0 | QA end-to-end Phase 35 — Validação completa: (1) Auto top-up: billing_auto_topup_settings schema OK, threshold/max_per_month CHECK constraints OK, RLS admin_master only OK, auto-topup-check decision tree (6 skip reasons + trigger path) OK, idempotency via cooldown+monthly cap OK, Stripe PaymentIntent off-session OK, graceful cancel on Stripe error OK, inline fulfillment OK, auto-topup-cron hourly sweep OK, pg_cron+pg_net integration OK; (2) Billing portal: create-portal-session admin_master auth OK, auto-provision Stripe Customer OK, rate limit 10/min OK, portal-button+manage-billing-button UX OK, API routes proxy correctly OK; (3) Refunds: billing_refund_requests lifecycle (requested→approved→processed/rejected) OK, UNIQUE partial index prevents duplicates OK, RLS admin_master SELECT+INSERT OK, process-refund validates status chain (approved→fulfilled→payment_reference) OK, RF-1 inventory check OK, Stripe refunds.create (full/partial) OK, atomic debit via decrement_token_inventory OK, billing_events audit trail OK, critical error handling (502 Stripe/500 debit) OK; (4) Limits: billing_limits table with CHECK constraints OK, get_billing_limits fallback defaults OK, check_daily_token_usage RPC OK, token-create-intent daily limit check OK, token-consume-intent group+athlete burn limits OK, settle-challenge stake cap 10k OK, champ-create 3 active cap OK, DB triggers (20 challenges/day, 5 active, 10 pending) OK; (5) Cross-cutting: config.toml 7 Phase 35 functions registered OK, billing_purchases.source column OK, billing_purchases.status includes 'refunded' OK, billing_events.event_type includes 'refund_requested'+'refunded' OK, stripe_customer_id+stripe_default_pm columns OK, all portal UI components present OK, API routes functional OK, analytics events tracked OK. Zero issues found. | CONCLUIDA |

---

---

### PHASE 90 — QA Pré-Lançamento: Desafios e Campeonatos

> **Status:** EM ANDAMENTO (TODOs operacionais restantes)

| Sprint | Descrição | Status |
|---|---|---|
| 90.1.0 | Auditoria E2E: fluxos de Desafios (1v1, Group, Team vs Team) + Campeonatos (multi-assessoria) | CONCLUIDA |
| 90.1.1 | Fix 18 problemas originais (P0-01 a P2-01): sync Isar↔Supabase, lifecycle backend, UI staff invites, labels, limits | CONCLUIDA |
| 90.2.0 | Confidence check: 4 problemas adicionais (schema mismatches, wrong group source, Isar query gap, non-exhaustive switch) | CONCLUIDA |
| 90.3.0 | Eliminar 4 riscos residuais: lifecycle-cron (pg_cron), notify-rules +2 handlers + auth fix, completed challenges na lista, 5 testes teamVsTeam | CONCLUIDA |
| 90.3.1 | Fix colateral: doc comment evaluator (time=higher wins), 2 testes pré-existentes corrigidos, Set→List no Isar | CONCLUIDA |
| 90.4.0 | Configurar pg_cron — 4 cron jobs recriados com URL e service_role_key hardcoded (ALTER DATABASE SET bloqueado no Supabase hosted): lifecycle-cron (*/5min), clearing-cron (seg 03:00), auto-topup-cron (hora em hora), eval-verification-cron (03:00 diário). Todos usando extensions.http → Edge Functions. | CONCLUIDA |
| 90.4.1 | Verificar send-push EF deployado + notification_log table com RLS — send-push ACTIVE (v5), notification_log migration aplicada com RLS (select own) | CONCLUIDA |
| 90.4.2 | TODO: Teste de integração com Supabase real (challenge lifecycle completo) | TODO |
| 90.4.3 | TODO: Monitorar logs lifecycle-cron nas primeiras 24h pós-deploy | TODO |

**Resultado:** 22 problemas corrigidos, 46/46 testes passando, 0 erros flutter analyze, confiança 96%.

---

### PHASE 97 — QA Wallet/Ledger/Clearing

> **Status:** EM ANDAMENTO

| Sprint | Descrição | Status |
|---|---|---|
| 97.1.0 | Auditoria Wallet/Ledger (fonte da verdade): wallet, intents QR, burning, troca de assessoria + queima | CONCLUIDA |
| 97.1.0-fix | Fix W-01: coin_ledger_reason_check +team reasons; Fix W-02: fn_switch_assessoria burn pending_coins | CONCLUIDA |
| 97.2.0 | Clearing entre assessorias (sem moderacao da plataforma): Fix C-01 settle-challenge cross-assessoria -> pending; Fix C-02 clearing-cron agrega pending em clearing_cases semanais; Fix C-03 expira cases vencidos; Fix C-04 team_vs_team intra-assessoria (coluna `team` em participants, scoring por team nao group_id); scan termos dinheiro OK; pending tokens bloqueados OK; 23/23 testes; 0 erros analyze | CONCLUIDA |
| 97.3.0 | Dispute UX (amigavel, sem acusacao): Fix D-01 DISPUTED guidance para staff; Fix D-02 EXPIRED guidance para staff; Fix D-03 "Desqualificado" -> "Nao elegivel"; Fix D-04 challenge_result_screen team filtering por `team` (intra-assessoria); icone DISPUTED report->rate_review; DisputeStatusCard tom neutro; 0 erros analyze | CONCLUIDA |

---

### PHASE 98 — Billing B2B (Portal) + Mercado Pago/Stripe

> **Status:** EM ANDAMENTO

| Sprint | Descrição | Status |
|---|---|---|
| 98.1.0 | Auditoria: portal existe? gateway? webhook? auto top-up? Tudo existe e completo. | CONCLUIDA |
| 98.2.0 | Plano de criacao do portal: N/A — portal ja existe (Next.js 14, 11 paginas, RBAC, Stripe) | CONCLUIDA (N/A) |
| 98.3.0 | Loja-safe checklist: 0 precos no app, 0 IAP, 0 termos monetarios, 0 deps billing, portal abre browser externo. Compliance OK. | CONCLUIDA |

---

---

### PHASE 99 — Deploy Config (Pre-APK)

> **Status:** CONCLUIDA

| Sprint | Descrição | Status |
|---|---|---|
| 99.1.0 | Revisão completa do app: 0 errors, 913/913 testes, 65 telas, 40 EFs, 38 migrations. Confiança: 76% (code) / 92% (com config) | CONCLUIDA |
| 99.2.0 | Firebase: projeto criado, google-services.json com SHA-1, Google Sign-In habilitado, Gradle plugin adicionado (condicional) | CONCLUIDA |
| 99.2.1 | GoogleSignIn hardened: serverClientId via GOOGLE_WEB_CLIENT_ID (--dart-define) | CONCLUIDA |
| 99.2.2 | .env.dev: Supabase URL+Key, MapTiler, Sentry, Google Web Client ID — tudo preenchido | CONCLUIDA |
| 99.2.3 | Google OAuth configurado no Supabase Dashboard (Client ID + Secret) | CONCLUIDA |
| 99.3.0 | Backend deploy: 38 migrations aplicadas (reordenadas por dependência), 40 Edge Functions deployadas | CONCLUIDA |
| 99.3.1 | Fix: championship_tables partial index now() → composite index (IMMUTABLE) | CONCLUIDA |
| 99.4.0 | Script preflight_check.sh: valida todas as dependências antes do build. ALL CHECKS PASSED. | CONCLUIDA |
| 99.5.0 | Git commit (898 files, 161.658 lines) + push to github.com/cabralandre82/OmniRunner (master) | CONCLUIDA |
| 99.6.0 | Build APK release: keystore gerado, `flutter build apk --flavor prod --release`, APK 121MB assinado | CONCLUIDA |

---

### PHASE 100 — QA Device Testing (Hotfix v1.0.1)

> **Status:** EM ANDAMENTO

| Sprint | Descrição | Status |
|---|---|---|
| 100.1.0 | Fix 3 bugs críticos encontrados em teste no device: auth flow, login modal, mapa+crash | CONCLUIDA |
| 100.1.1 | Fix env files: `.env.dev`/`.env.prod` movidos para `omni_runner/` (Flutter não encontrava no parent dir) | CONCLUIDA |
| 100.1.2 | Preflight script atualizado: busca env local primeiro, fallback p/ parent dir com warning | CONCLUIDA |
| 100.2.0 | Build APK v1.0.1: `flutter build apk --flavor prod --release --dart-define-from-file=.env.dev`, 121MB | CONCLUIDA |
| 100.2.1 | Build APK v1.0.2: google-services.json atualizado com SHA-1 do release keystore (Google Sign-In fix) | CONCLUIDA |
| 100.3.0 | Teste no device v1.0.2: Google Sign-In funciona, mas 2 novos bugs Sentry | CONCLUIDA |
| 100.3.1 | Fix FGS crash: `foregroundServiceType` mudado de `location\|connectedDevice` → `location` (BLE opcional) | CONCLUIDA |
| 100.3.2 | Fix RLS recursion: `coaching_members_group_read` policy self-reference → fn `SECURITY DEFINER` | CONCLUIDA |
| 100.3.3 | Build APK v1.0.3: ambos os fixes aplicados | CONCLUIDA |
| 100.4.0 | Teste no device v1.0.3: FGS OK, corrida inicia sem crash, mas distância 0m e timer com gaps | CONCLUIDA |
| 100.4.1 | Fix `_accumDist` stuck: `_prevPt` nunca avançava se 1o ponto tinha accuracy ruim → distância sempre 0 | CONCLUIDA |
| 100.4.2 | `maxAccuracyMeters` relaxado de 15m → 25m (FilterLocationPoints + AccumulateDistance) | CONCLUIDA |
| 100.4.3 | `TimerTick` event periódico 1s: UI atualiza a cada segundo (timer suave sem gaps) | CONCLUIDA |
| 100.4.4 | Elapsed time via wall-clock (`DateTime.now()`) em vez de GPS timestamp | CONCLUIDA |
| 100.4.5 | Build APK v1.0.4: todos os fixes de tracking aplicados | CONCLUIDA |
| 100.4.6 | Fix HistoryScreen: reload ao trocar aba via `isVisible` + `didUpdateWidget` | CONCLUIDA |
| 100.5.0 | Teste no device v1.0.4: distância, timer, pace OK. Novos bugs: logout, "Sequências" naming, group_members RLS | CONCLUIDA |
| 100.5.1 | Fix logout: `signOut()` agora faz `GoogleSignIn().signOut()` antes de `_auth.signOut()` — limpa cache Google | CONCLUIDA |
| 100.5.2 | Rename "Sequências"→"Consistência" + textos atualizados na `StreaksLeaderboardScreen` e `ProgressHubScreen` | CONCLUIDA |
| 100.5.3 | Fix RLS recursion `group_members_read`: fn `SECURITY DEFINER` `user_social_group_ids()` | CONCLUIDA |
| 100.5.4 | Fix assessoria creation: `await _completeSocialProfile()` + retry 3x em chamadas críticas | CONCLUIDA |
| 100.5.5 | Fix back navigation: `PopScope` + `onBack` callback nas telas de onboarding (sign-out → welcome) | CONCLUIDA |
| 100.5.6 | Build APK v1.0.5: logout + naming + RLS + retry + back nav | CONCLUIDA |
| 100.5.7 | Fix `fn_create_assessoria`: `created_at_ms` faltando no INSERT (NOT NULL constraint) — fix no banco via Management API | CONCLUIDA |
| 100.6.0 | Fix staff UX: HomeScreen role-aware (sem Correr/Histórico p/ staff), StaffDashboard query Supabase direto, MoreScreen role-aware | CONCLUIDA |
| 100.6.1 | Build APK v1.0.6: staff dashboard fix + role-aware tabs + menu cleanup | CONCLUIDA |
| 100.7.0 | Fix UX staff dashboard: "Atletas"→"Atletas e Staff", "Desafios" subtitle, Portal "em breve", championship template flow simplificado (sem "Sessões", RadioListTile com descrições, Corrida única, duração personalizada), RLS INSERT/UPDATE/DELETE championship_templates, Portal CTA "em breve" em StaffCreditsScreen | CONCLUIDA |
| 100.7.1 | Build APK v1.0.7: UX fixes + championship flow + RLS fix | CONCLUIDA |
| 100.8.0 | Fix role string mismatch (`'athlete'`→`'atleta'`) em 4 telas (Performance, Retention, Streaks, Weekly Report); remover "Desafios" do dashboard staff (desafios são entre atletas); member count no card "Atletas e Staff"; re-sync Supabase→Isar ao abrir Atletas | CONCLUIDA |
| 100.8.1 | Build APK v1.0.8: role fix + desafios removal + member count + sync | CONCLUIDA |
| 100.9.0 | BUG-24: Fluxo de entrada em assessoria sem aprovação — novo fluxo com tabela `coaching_join_requests`, RPCs de solicitação/aprovação/rejeição, UI de solicitar entrada e tela de aprovação no dashboard staff | CONCLUIDA |
| 100.9.1 | Build APK v1.0.9: fluxo de aprovação de entrada em assessoria | CONCLUIDA |
| 100.10.0 | FEATURE: Remoção de membros — RPC `fn_remove_member` + UI na tela "Atletas e Staff" com ícone remover, dialog de confirmação, re-sync pós-remoção | CONCLUIDA |
| 100.10.1 | Build APK v1.0.10: remoção de membros | CONCLUIDA |
| 100.11.0 | BUG-25 Performance RLS (staff não via sessions atletas); BUG-26 Atletas e Staff reescrita (Supabase direto, sem Isar); campeonatos redesenhados (5 seções, formato visual, local, resumo) | CONCLUIDA |
| 100.11.1 | Build APK v1.0.11 | CONCLUIDA |
| 100.12.0 | BUG-28/29/30/31: Performance resilience, championship draft 404, member count refresh, join request email column | CONCLUIDA |
| 100.12.1 | Build APK v1.0.12 | CONCLUIDA |
| 100.13.0 | BUG-32: MyAssessoriaBloc Isar stale → Supabase direto; BUG-33: HistoryScreen Isar-only → pull Supabase + merge | CONCLUIDA |
| 100.13.1 | Build APK v1.0.13 | CONCLUIDA |
| 100.14.0 | BUG-34/35: isSynced hardcoded false em _toRecord + syncOne skip sem markSynced | CONCLUIDA |
| 100.14.1 | Build APK v1.0.14 | CONCLUIDA |
| 100.15.0 | IMP-01: Remover team_vs_team de desafios + IMP-02: Warmup 5min no modo "Agora" | CONCLUIDA |
| 100.15.1 | Deploy EF challenge-join com warmup | CONCLUIDA |
| 100.15.2 | IMP-03: Janela de aceite para grupo (5/10/20/30 min) + migration + EFs | CONCLUIDA |
| 100.15.3 | Build APK v1.0.15 | CONCLUIDA |
| 100.16.0 | BUG-36: Histórico sem replay/mapa nas corridas 2+ — RunDetailsScreen só lia pontos do Isar local (vazio para sessions puxadas do Supabase); fix: download pontos do Storage bucket `session-points`, parse JSON, cache Isar, fallback Brasília | CONCLUIDA |
| 100.16.1 | IMP-04: Cancelamento de campeonato — EF `champ-cancel` (draft/open/active→cancelled, withdraw participants, revoke pending invites); botão "Cancelar campeonato" com confirmação no ManageScreen; info card prazo de aceite de convites (antes do start_at); config.toml registrado | CONCLUIDA |
| 100.16.2 | BUG-37: Emitir/Recolher OmniCoins e Badge Bad Request — `RemoteTokenIntentRepo` não enviava `nonce` nem `expires_at_iso`; corrigido key `id`→`intent_id` | CONCLUIDA |
| 100.16.3 | Teste no device v1.0.16 | TODO |

---

## PHASE 22 — Atleta Verificado & Monetization Gate

> **Status:** EM ANDAMENTO
> **Origem:** Regra de produto congelada — stake>0 exige VERIFIED; stake=0 sempre liberado; ZERO override admin.

| Sprint | Descrição | Status |
|---|---|---|
| 22.0.0 | Inventário & Mapa de Encaixe (Sprint 0) — leitura dos 5 docs-lei, busca no repo, identificação de arquivos-alvo para todas as sprints | CONCLUIDA |
| 22.1.0 | Schema: tabela `athlete_verification` (state machine UNVERIFIED→CALIBRATING→MONITORED→VERIFIED→DOWNGRADED); RPC `eval_athlete_verification` (SECURITY DEFINER); helper `is_user_verified`; RLS own-read-only; trigger auto-create; backfill; DECISAO 053 | CONCLUIDA |
| 22.1.1 | Checklist automático: RPC `get_verification_state()` (read-only, checklist booleans + contagens + thresholds); EF `eval-athlete-verification` (idempotente, user_id do JWT); thresholds finalizados (N=7, trust=80); scoring recalibrado (5pts/session); error codes padronizados; config.toml registrado | CONCLUIDA |
| 22.2.0 | Monetization gate (3 camadas): DB triggers `trg_challenges_verified_stake_gate` + `trg_participants_verified_join_gate` (impossível burlar); RLS INSERT policy atualizada; EFs `challenge-create` + `challenge-join` com validação `ATHLETE_NOT_VERIFIED`; migration `20260224000003` | CONCLUIDA |
| 22.2.1 | Integrity flags: dicionário oficial `_shared/integrity_flags.ts` (7 critical + 4 quality); verify-session EF reescrita com flags oficiais + 3 novos checks (NO_MOTION_PATTERN, BACKGROUND_GPS_GAP, TIME_SKEW); InvalidatedRunCard atualizado; schema sessions confirmado | CONCLUIDA |
| 22.3.0 | Evaluation trigger: `verify-session` EF chama `eval_athlete_verification` RPC pós-verdict (fire-and-forget); `SyncRepo._syncOne()` chama `verify-session` EF pós-upsert; `eval-verification-cron` EF (pg_cron 03:00 UTC) reavalia CALIBRATING/MONITORED/DOWNGRADED + users com flags recentes; migration `20260224000004`; config.toml registrado | CONCLUIDA |
| 22.4.0 | Flutter UX completa: `AthleteVerificationEntity` + `VerificationBloc` (load + eval) + `AthleteVerificationScreen` (status badge, progress bar, checklist com contagem regressiva, stats, botão reavaliar); `verification_gate.dart` modal sheet reutilizável; `ChallengeCreateScreen` intercepta stake>0 pré-submit; `ChallengeDetailsScreen._AcceptDeclineCard` intercepta join stake>0; server continua como autoridade final | CONCLUIDA |
| 22.5.0 | Portal Next.js: página `/verification` (observabilidade read-only, KPIs, tabela atletas com status/trust/flags/corridas); botão "Reavaliar" (admin_master/professor) chama `eval_athlete_verification` RPC via API route; sidebar atualizado; ZERO override | CONCLUIDA |
| 22.6.0 | Testes & Provas: `scripts/test_verification_gate.sh` (12 testes curl: stake=0 ok, stake>0 bloqueado UNVERIFIED, VERIFIED libera, DOWNGRADED bloqueia, service_role INSERT bloqueado por trigger, UPDATE 0→100 bloqueado, RLS bloqueia UPDATE direto); `scripts/TEST_PLAN_FLUTTER.md` (12 test cases manuais: tela verificação, gate create, gate join, fluxos completos, matriz de cobertura 4 camadas) | CONCLUIDA |
| 22.7.0 | Consistência settle-challenge: stake>0 settle verifica VERIFIED de cada participante; quem perdeu status recebe apenas coins-base (sem pool); log `pool_forfeited`; ZERO override; caps + proteções existentes mantidos | CONCLUIDA |
| 23.0.0 | Matchmaking: `challenge_queue` table + `fn_try_match` RPC atômico + `fn_compute_skill_bracket` + `fn_expire_queue_entries` cron (5min) + EF `matchmake` (queue/cancel/poll) + Flutter `MatchmakingScreen` (setup→searching→matched→error) + integração `ChallengesListScreen` ("Encontrar Oponente") + monetization gate no matchmake + skill brackets (beginner/intermediate/advanced/elite por pace) | CONCLUIDA |
| 23.1.0 | C-3 Gate Assessoria Obrigatória: EFs (`challenge-create`, `challenge-join`, `matchmake`) query `coaching_members` → `NO_ASSESSORIA` 403; Flutter `AssessoriaRequiredSheet` bloqueia Desafios/Campeonatos no dashboard; `DECISAO 063` | CONCLUIDA |
| 23.1.1 | C-6 Push notification ao aceitar desafio: regra `challenge_accepted` no `notify-rules` + disparo fire-and-forget no `challenge-join`; FCM secrets (`FCM_PROJECT_ID`, `FCM_SERVICE_ACCOUNT`) configurados; pipeline `join→notify-rules→send-push→FCM→device` | CONCLUIDA |
| 23.1.2 | S-2 Push notification para staff ao receber solicitação de entrada: regra `join_request_received` no `notify-rules` + `NotificationRulesService.notifyJoinRequestReceived()` + disparo no `JoinAssessoriaScreen` após `fn_request_join` | CONCLUIDA |
| 23.2.0 | F-3 Gráficos de evolução pessoal: `PersonalEvolutionScreen` com 3 charts (pace line, volume bar, frequência bar) + PRs via `fl_chart`; dados de sessions agregados por ISO week (12 semanas); integrado no ProgressHub | CONCLUIDA |
| 23.2.1 | F-4 Feed de atividades dos amigos: RPC `fn_friends_activity_feed` (SECURITY DEFINER, join friendships+sessions+profiles); `FriendsActivityFeedScreen` com cards (avatar, métricas, tempo relativo); paginação 30/vez; integrado no menu Mais | CONCLUIDA |
| 23.2.2 | F-2 Compartilhamento social pós-corrida: `RunShareCard` (gradiente, métricas hero, badge verificada); captura PNG via RepaintBoundary; share sheet nativo via share_plus; botão no RunSummaryScreen | CONCLUIDA |
| 23.3.0 | C-4 Deep link + Portal web: Portal Next.js deployado em `omnirunner.app` (Vercel + Cloudflare DNS). Landing pages `/challenge/[id]` e `/invite/[code]` (auto-redirect 3s + badges store + OG metadata). Android App Links (`assetlinks.json` SHA256). iOS Universal Links (`apple-app-site-association`, TEAM_ID placeholder). Middleware atualizado (rotas públicas). Env vars configuradas na Vercel. | CONCLUIDA |
| 23.4.0 | W-6 Integração Strava funcional: Conta developer criada (Client ID 205793). Credenciais em `.env.dev`. `StravaCallbackAction` no DeepLinkHandler + handler no AuthGate. Seção "Integrações" no Settings com tile Conectar/Desconectar. Auto-upload FIT fire-and-forget no SyncRepo após sync. Toda infraestrutura OAuth/upload/polling já existia. | CONCLUIDA |
| 23.5.0 | Strava Webhook Import — Corridas do relógio contam para desafios: Migration `20260225200000_strava_import.sql` (source, strava_activity_id, device_name em sessions + tabela strava_connections); Edge Function `strava-webhook` (recebe eventos Strava, busca atividade + GPS streams, anti-cheat 8 flags, cria session source='strava', vincula a desafios ativos); Edge Function `strava-register-webhook` (setup one-time); OAuth scope atualizado para `activity:read_all,activity:write`; tokens sincronizados server-side em strava_connections; UI: badge STRAVA no histórico, tela de conexão explica uso com relógio; Isar/Entity atualizados com source/deviceName; webhook registrado (ID 332234) | CONCLUIDA |
| 23.9.0 | QA Phase 23 + update docs finais | TODO |

**Bugs corrigidos (100.1.0):**

| # | Bug | Causa raiz | Fix |
|---|---|---|---|
| BUG-01 | App vai direto pra Home sem tela de login | `RemoteAuthDataSource.init()` fazia `signInAnonymously()` auto, criando sessão anônima → AuthGate via sessão e mandava pra home | Removido auto-anonymous sign-in; sem sessão → AuthGate mostra Welcome→Login |
| BUG-02 | Botão "Criar conta" no modal fecha e nada acontece | `AuthGate._resolve()` routeava anonymous → home; botão levava a AuthGate que re-routeava pra home | Anonymous → welcome (não home); fluxo Welcome→Login→Onboarding→Home funciona |
| BUG-03a | Mapa mostra São Paulo (user em Brasília) | Coordenadas hardcoded `-23.5505, -46.6333` (SP) em `tracking_screen.dart` e `map_screen.dart` | Fallback → Brasília (`-15.7975, -47.8919`) + `getLastKnownPosition()` p/ posição real do user |
| BUG-03b | Crash ao clicar "Iniciar corrida" | `on Exception catch` no TrackingBloc não captura `Error` nativo (foreground service, geolocator) | `catch` (Object) em start/stop/close do tracking — erros nativos não derrubam o app |

**Bugs corrigidos (100.3.x — v1.0.2/v1.0.3):**

| # | Bug | Causa raiz | Fix |
|---|---|---|---|
| BUG-04 | Google Sign-In `DEVELOPER_ERROR (10)` | `google-services.json` só tinha SHA-1 do debug keystore; release SHA-1 não registrado no Firebase | Adicionado release SHA-1 no Firebase, baixado novo `google-services.json` |
| BUG-05 | Crash `SecurityException` FGS `connectedDevice` | `foregroundServiceType="location\|connectedDevice"` exige BLE permission runtime Android 14+; BLE é opcional | Removido `connectedDevice` do `foregroundServiceType`, mantido apenas `location` |
| BUG-06 | `PostgrestException: infinite recursion` coaching_members | RLS policy `coaching_members_group_read` self-reference → loop infinito | Fn `SECURITY DEFINER` `user_coaching_group_ids()` bypassa RLS |

**Bugs corrigidos (100.4.x — v1.0.4):**

| # | Bug | Causa raiz | Fix |
|---|---|---|---|
| BUG-07 | Distância sempre 0m (64 pts GPS registrados) | `_accumDist`: se 1o ponto GPS tinha accuracy > 15m, `_prevPt` nunca avançava → filter sempre rejeitava, `f.length < 2` → 0m | `_prevPt = f.last` quando filter aceita ao menos 1 ponto; accuracy relaxada 15→25m |
| BUG-08 | Timer com gaps (09:41 → 09:46) | UI só atualizava ao receber ponto GPS; elapsed calculado por GPS timestamp | `TimerTick` periódico 1s + elapsed via `DateTime.now()` (wall-clock) |
| BUG-09 | Corrida demora minutos para aparecer no Histórico | `HistoryScreen` usa `IndexedStack` → `initState` roda 1x na criação; trocar aba não recarrega | `isVisible` prop + `didUpdateWidget` recarrega ao entrar na aba |

**Bugs corrigidos (100.5.x — v1.0.5):**

| # | Bug | Causa raiz | Fix |
|---|---|---|---|
| BUG-10 | Logout não volta pra login social (auto-login com conta anterior) | `signOut()` só limpava sessão Supabase; Google Sign-In mantinha credential em cache → auto-seleção | `GoogleSignIn().signOut()` antes de `_auth.signOut()` — limpa cache Google |
| BUG-11 | "Sequências" naming confuso em Meu Progresso | Título "Sequências" / "quem está em sequência" sem contexto claro | Renomeado para "Consistência" / "Ranking de dias consecutivos correndo" |
| BUG-12 | Rankings: `infinite recursion` em `group_members` | `group_members_read` policy self-reference (mesma causa do BUG-06 com `coaching_members`) | Fn `SECURITY DEFINER` `user_social_group_ids()` + `is_group_admin_or_mod()` |
| BUG-13 | Criar assessoria falha: `ClientException: connection abort` | `_completeSocialProfile()` era `unawaited` → podia falhar silently; sem retry em chamadas de rede críticas | `await` + retry 3x com backoff em `_completeSocialProfile`, `set-user-role`, `fn_create_assessoria` |
| BUG-14 | Botão voltar fecha o app nas telas de onboarding | Telas renderizadas inline no `AuthGate` sem `Navigator.push` → back popa o AuthGate (raiz) → app fecha | `PopScope` + callback `onBack` (sign-out → welcome) nas 3 telas de onboarding + botão ← visual |
| BUG-15 | Criar assessoria sempre falha (NOT NULL constraint) | `fn_create_assessoria` não incluía `created_at_ms` no INSERT; coluna `NOT NULL` sem default | Adicionado `created_at_ms` ao INSERT da função (fix no banco, sem novo APK) |
| BUG-16 | Dashboard staff: botões não funcionam, tabs de atleta visíveis | `StaffDashboardScreen` lia do Isar (cache local vazio); `HomeScreen` mostrava Correr/Histórico p/ staff; `MoreScreen` mostrava itens de atleta p/ staff | Dashboard agora consulta Supabase direto; HomeScreen role-aware (2 tabs staff / 4 tabs atleta); MoreScreen filtra itens por role |
| BUG-17 | Tela "Atletas" crash: `CoachingGroupNotFound` | `GetCoachingGroupDetails` lia do Isar (vazio); dados do Supabase não eram sincronizados localmente | Dashboard agora sincroniza grupo + todos membros do Supabase → Isar após fetch. Auditoria dos 9 botões: apenas "Atletas" usava Isar; demais 8 usam Supabase direto |
| BUG-18 | "Atletas" e "Desafios" labels confusos no dashboard staff | "Atletas" não mostrava que admin aparece na lista; "Desafios" subtitle "Convites de equipe" vago | "Atletas" → "Atletas e Staff" / "Ver e gerenciar membros"; "Desafios" subtitle → "Convites de outras assessorias" |
| BUG-19 | "Erro ao salvar modelo" nos templates de campeonato | Tabela `championship_templates` só tinha RLS SELECT — INSERT/UPDATE/DELETE bloqueados | Migration com 3 novas policies (INSERT/UPDATE/DELETE) para admin_master/professor |
| BUG-20 | Fluxo campeonato confuso (métrica, duração, "Sessões") | Métricas com "Sessões" sem explicação; duração só chips fixos (7/14/30/60/90 dias); sem opção de corrida única | Removido "Sessões"; RadioListTile com descrições (ex: "Quem correr mais km"); duração: Corrida única (1d) / 1 semana / 2 semanas / 1 mês / Personalizado |
| BUG-21 | Botão "Portal" e "Abrir Portal de Assessorias" não faziam nada | URL `portal.omnirunner.app` não configurada; `canLaunchUrl` falhava silenciosamente | Dashboard Portal: SnackBar "em breve"; Credits `_PortalCta`: card informativo "está sendo desenvolvido" |
| BUG-22 | Performance mostra "0 de 2 membros" mas só tem 1 atleta | Role string mismatch: código filtrava por `'athlete'` (inglês) mas DB armazena `'atleta'` (português, desde migration 16.10.0) | Corrigido em 4 telas: `staff_performance_screen`, `staff_retention_dashboard_screen`, `streaks_leaderboard_screen`, `staff_weekly_report_screen`. Contagem agora mostra apenas atletas (não staff) |
| BUG-23 | "Desafios" no dashboard staff — conceito errado | Card "Desafios" mostrava convites de "team vs team entre assessorias", mas desafios são SEMPRE entre atletas, não assessorias | Card removido do dashboard staff. Assessorias não participam de desafios — apenas distribuem OmniCoins e gerenciam atletas |
| BUG-24 | Atletas entram na assessoria sem aprovação | `fn_switch_assessoria` adicionava atleta direto como membro | Fluxo de solicitação: `fn_request_join` → `fn_approve/reject_join_request`. Tabela `coaching_join_requests`, tela de solicitações, badge com pendentes |
| BUG-25 | Performance "não foi possível carregar dados" | RLS impedia staff de ler sessions/challenges dos atletas | `staff_group_member_ids()` SECURITY DEFINER + policies `sessions_staff_read` e `challenge_parts_staff_read` |
| BUG-26 | "Atletas e Staff" mostra 2 mas só exibe 1 | BLoC→Isar cache local incompleto | Reescrita para query Supabase direto, sem BLoC/Isar |
| BUG-27 | Solicitação não chega na assessoria | Atleta já era membro do fluxo antigo | Não é bug — `fn_request_join` retorna `already_member` |
| BUG-28 | Performance screen crash silencioso | Catch-all comia exceções | Per-section try-catch com logging |
| BUG-29 | "Erro ao carregar campeonato" (404) | EF `champ-participant-list` excluía "draft" | EF redeployado com "draft"; manage screen resiliente |
| BUG-30 | Contagem de membros não atualiza após remoção | Dashboard não recarregava ao voltar | `.then((_) => _loadStatus())` |
| BUG-31 | Solicitação falha: "column email does not exist" | `fn_request_join` referenciava `email` em `profiles` (não existe) | RPC recriado com `COALESCE(display_name, 'Atleta')` |
| BUG-32 | Atleta aprovado mas "Minha Assessoria" vazia | `MyAssessoriaBloc` lia do Isar local (cache nunca atualizado após aprovação) | BLoC reescrito para query Supabase direto + sync Isar |
| BUG-33 | Corrida sumiu do histórico (visível no Performance) | `HistoryScreen` lia apenas do Isar; troca de conta perdia sessions | Pull últimas 30 sessions do Supabase → merge Isar antes de exibir |
| BUG-34 | Session do Supabase fica "PENDENTE" eternamente | `_toRecord()` hardcodeava `isSynced = false` | `..isSynced = entity.isSynced` |
| BUG-35 | Sync não marca sessions sem pontos locais | `_syncOne()` retornava null sem `markSynced()` | `markSynced()` antes do return |
| IMP-01 | Desafio team_vs_team não faz sentido (desafios são entre atletas) | Opção "Equipe" presente na criação | Removido segmento, simplificado `_submit()` |
| IMP-02 | Desafio 1v1 "Agora" inicia instantaneamente (injusto) | `starts_at_ms = nowMs` no aceite | `starts_at_ms = nowMs + 5min` (warmup), countdown visual |
| IMP-03 | Grupo: todos aceitam ao mesmo tempo, janela configurável | Grupo ativava com 2 aceites (como 1v1) | Janela de aceite (5/10/20/30 min) + ativa só quando todos aceitarem |
| BUG-36 | Histórico: só 1a corrida tem replay/mapa correto | `RunDetailsScreen._loadPoints()` só lia pontos do Isar local; sessions puxadas do Supabase não tinham pontos locais → mapa sem polyline, posição fallback SP, sem replay | Download pontos do Supabase Storage (`session-points/{uid}/{sid}.json`), parse JSON → `LocationPointEntity`, cache no Isar; fallback Brasília |
| IMP-04 | Staff não consegue cancelar campeonato | Não existia funcionalidade de cancelamento — sem EF, sem botão na UI | EF `champ-cancel` (draft/open/active → cancelled, withdraw participants, revoke invites); botão "Cancelar campeonato" com dialog de confirmação; info card "aceitar convite antes do início" |
| BUG-37 | Emitir/Recolher OmniCoins e Badge de campeonato: Bad Request | `RemoteTokenIntentRepo.createIntent()` não enviava `nonce` nem `expires_at_iso` (campos obrigatórios do EF `token-create-intent`); também lia `data['id']` mas EF retorna `data['intent_id']` | Gerar `nonce` (UUID v4) e `expires_at_iso` (now+5min) no client antes de enviar; corrigir key `id` → `intent_id` na resposta |

---

## REGRA

Cada Phase so inicia quando a anterior esta CONCLUIDA.
Cada Sprint so inicia quando a anterior esta CONCLUIDA.
Sem pular. Sem paralelizar.

---

### Portal: Login Social (Google/Apple)  ✅ CONCLUIDA

Staff que se registrou no app com Google ou Apple agora pode logar no portal web (`omnirunner.app`) com o mesmo método. Implementado OAuth com PKCE flow no Next.js, cookie handling correto no Route Handler de callback, e configurações no Google Cloud Console e Supabase Auth.

---

### Sprint 24.0.0 — CORREÇÃO DE BUGS DO AUDIT (P0-P3)  ✅ CONCLUIDA

14 correções aplicadas cobrindo bugs críticos (mock mode, LGPD, QR staff leak, rate limit) e melhorias de UX (onboarding, pull-to-refresh, logout visível, pending coins, invite warning, verification dashboard).

Ver `AUDIT_REPORT.md` seção 17 para lista completa.

---

### Billing: Checkout MercadoPago + Stripe  ✅ CONCLUIDA

Compra de créditos OmniCoins pelo portal agora funcional. MercadoPago como gateway primário (Pix, cartão, boleto). Stripe como alternativa. Seed de 5 pacotes de créditos. Webhook handlers para ambos gateways. Fluxo testado end-to-end: checkout → pagamento → créditos alocados automaticamente.

---

### Sprint 25.0.0 — Strava-Only Strategy + Aba "Hoje" + Parks Feature  🔧 EM PROGRESSO

**Decisão de produto:** O app deixa de ter tracking GPS próprio. O atleta corre com qualquer relógio/app e todos os dados fluem pelo Strava. A aba "Correr" (mapa + botão iniciar) foi substituída pela aba **"Hoje"** — um briefing diário de gamificação.

**Strava como fonte única de dados:**
- `activity:read_all` scope fornece GPS, HR, pace, elapsed/moving time — tudo que o anti-cheat precisa
- Webhook via `strava_connections` importa atividades automaticamente
- Ao conectar, últimas 20 corridas são importadas para calibrar o nível do atleta (`strava_activity_history`)
- Nike Run Club / adidas Running / outros não têm API pública — atletas que usam esses apps podem sincronizá-los ao Strava
- Arquitetura extensível para novos provedores no futuro

**Aba "Hoje" (TodayScreen):**
- Streak banner (sequência de dias, recorde, freeze, marcos com XP)
- CTA "Bora Correr" (abre Strava via deep link `strava://`)
- Run Recap Card (última corrida com métricas, fonte, badges)
- Comparação com corrida anterior (% mais rápido/lento)
- Botão Compartilhar (PNG via share sheet)
- Diário de corrida (anotação + humor)
- Quick Stats (nível, XP, corridas na semana, km total)
- Park check-in (detecção automática de parque via GPS polygon)

**Parks Feature (features/parks/):**
- Detecção de parque por GPS (ray-casting point-in-polygon)
- 10 parques brasileiros seedados (Ibirapuera, Aterro, Barigui, etc.)
- "Rei do Parque" — leaderboard multi-tier (👑 Rei / ⭐ Elite / 🏅 Destaque / 🎯 Pelotão / 🏃 Frequentador)
- 6 categorias (Pace, Distância, Frequência, Sequência, Evolução, Maior corrida)
- Comunidade por parque ("Quem corre aqui")
- Detecção de corridas sociais (overlap de horário)
- Shadow Racing (ghost de outro atleta no mesmo parque)
- Segmentos com recordes (KOM-style)
- Matchmaking por parque (prioriza oponentes do mesmo parque)

**Matchmaking melhorado:**
- Explicação "Como funciona?" no setup
- TipBanner na lista de desafios explicando matchmaking
- Aviso de Strava não conectado (challenges + matchmaking)

**Platform Approval de Assessorias (DECISAO 061):**
- `coaching_groups.approval_status` (pending_approval/approved/rejected/suspended)
- `profiles.platform_role` ('admin') para o dono da plataforma
- RPCs: `fn_platform_approve/reject/suspend_assessoria` (SECURITY DEFINER)
- Portal: `/platform/assessorias` com dashboard de aprovação
- Flutter: tela de status de aprovação no `StaffDashboardScreen`
- `fn_search_coaching_groups` e `fn_lookup_group_by_invite_code` filtram apenas `approved`

**Navegação:** Início | **Hoje** | Histórico | Mais (antes: Início | Correr | Histórico | Mais)

**Tabelas Supabase necessárias:**
- `strava_activity_history` (user_id, strava_activity_id, distance_m, moving_time_s, average_heartrate, summary_polyline, ...)
- `park_activities` (user_id, park_id, distance_m, start_time, display_name, ...)
- `park_leaderboard` (park_id, user_id, category, rank, value, period, display_name)
- `park_segments` (id, park_id, name, length_m, record_holder_name, record_pace_sec_per_km)

**Arquivos criados (13):**
- `lib/presentation/screens/today_screen.dart`
- `lib/features/parks/domain/park_entity.dart`
- `lib/features/parks/data/park_detection_service.dart`
- `lib/features/parks/data/parks_seed.dart`
- `lib/features/parks/presentation/park_screen.dart`
- `lib/features/parks/presentation/my_parks_screen.dart`
- `supabase/migrations/20260226110000_platform_approval_assessorias.sql`
- `portal/src/app/platform/layout.tsx`
- `portal/src/app/platform/assessorias/page.tsx`
- `portal/src/app/platform/assessorias/actions.tsx`
- `portal/src/app/api/platform/assessorias/route.ts`
- `portal/src/lib/supabase/admin.ts`

**Arquivos modificados (14+):**
- `lib/presentation/screens/home_screen.dart` (TrackingScreen → TodayScreen, ícone "Hoje")
- `lib/presentation/screens/athlete_dashboard_screen.dart` (+card Parques)
- `lib/presentation/screens/challenges_list_screen.dart` (Strava banner + matchmaking tip)
- `lib/presentation/screens/matchmaking_screen.dart` (Strava check + park preference + "Como funciona")
- `lib/features/strava/data/strava_http_client.dart` (+getAthleteActivities)
- `lib/features/strava/presentation/strava_connect_controller.dart` (+importStravaHistory, +httpClient)
- `lib/core/service_locator.dart` (+httpClient no controller)
- `lib/core/tips/first_use_tips.dart` (+matchmakingHowTo, +stravaConnect)
- `portal/src/middleware.ts` (+platform admin bypass)
- `portal/src/components/sidebar.tsx` (+link admin plataforma)
- `portal/src/app/(portal)/layout.tsx` (+redirect platform admin)
- `portal/src/app/select-group/page.tsx` (+redirect platform admin)
- `portal/src/app/no-access/page.tsx` (+redirect platform admin)

---

*Documento gerado na Sprint 1.2 — Atualizado em 26/02/2026 (DECISAO 061)*
