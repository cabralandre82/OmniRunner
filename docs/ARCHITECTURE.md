# ARCHITECTURE.md — Arquitetura Técnica do Omni Runner

> **Atualizado:** 26/02/2026
> **Status:** Ativo — Pré-lançamento (QA em device real)
> **Código:** 458 arquivos Dart (lib/) · 55 arquivos de teste · ~116k linhas

---

## 1. STACK

| Camada | Tecnologia | Versão |
|---|---|---|
| UI / Framework | Flutter | 3.22+ |
| State Management | BLoC | 8.x |
| DI / Service Locator | get_it | latest |
| Persistência Local | Isar | 3.x |
| Mapas | MapLibre + MapTiler | 0.19+ |
| Backend | Supabase (PostgreSQL + Auth + Edge Functions + Storage) | 2.x |
| GPS | Geolocator + flutter_foreground_task | 11.x |
| Heart Rate | flutter_reactive_ble | latest |
| Health | health (HealthKit + Health Connect) | latest |
| Audio Coach | flutter_tts | latest |
| Crash Reporting | Sentry | latest |
| Auth | Google Sign-In + Supabase Auth | latest |
| Equality | Equatable | 2.x |
| Payments (Portal only) | Stripe (Next.js portal, never in app) | latest |

---

## 2. VISÃO GERAL DA ARQUITETURA

```
┌────────────────────────────────────────────────────────────────────┐
│                     FLUTTER APP (Mobile)                           │
│                                                                    │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐ │
│  │   Presentation   │  │     Domain       │  │      Data        │ │
│  │                  │  │                  │  │                  │ │
│  │  66 Screens      │  │  54 Entities     │  │  27 Repos (Isar) │ │
│  │  21 BLoCs        │  │  60 Use Cases    │  │  Datasources     │ │
│  │  Widgets         │  │  Failures        │  │  Mappers         │ │
│  └────────┬─────────┘  └────────▲─────────┘  └────────┬─────────┘ │
│           │                     │                      │           │
│           └─────────────────────┼──────────────────────┘           │
│                                 │                                  │
│                          DOMAIN É O CENTRO                         │
└───────────────────────────────┬─┬──────────────────────────────────┘
                                │ │
              ┌─────────────────┘ └────────────────┐
              ▼                                    ▼
┌──────────────────────┐              ┌──────────────────────┐
│   Supabase Backend   │              │    Portal B2B        │
│                      │              │    (Next.js)         │
│  PostgreSQL (RLS)    │              │                      │
│  41 Edge Functions   │              │  12 páginas          │
│  8 SQL Migrations    │              │  Stripe checkout     │
│  RPCs (SECURITY DEF) │              │  RBAC middleware     │
│  pg_cron schedules   │              │  SSR auth            │
└──────────────────────┘              └──────────────────────┘
```

---

## 3. ESTRUTURA DE DIRETÓRIOS

```
lib/
├── core/                          # Infraestrutura transversal
│   ├── analytics/                 # ProductEventTracker
│   ├── auth/                      # UserIdentityProvider
│   ├── config/                    # AppConfig (env vars)
│   ├── deep_links/                # Deep link handling
│   ├── errors/                    # CoachingFailures, etc.
│   ├── logging/                   # AppLogger → Sentry
│   ├── push/                      # NotificationRulesService
│   ├── sync/                      # AutoSyncManager
│   ├── tips/                      # FirstUseTips
│   └── utils/                     # Helpers genéricos
│
├── data/                          # Camada de dados (implementações)
│   ├── datasources/               # RemoteAuthDataSource, GPS, etc.
│   ├── mappers/                   # PositionMapper, PermissionMapper
│   ├── models/
│   │   ├── isar/                  # Isar collection models (*.g.dart)
│   │   └── proto/                 # Protobuf adapters
│   └── repositories_impl/        # 27 implementações concretas
│       ├── isar_*_repo.dart       # Persistência local (Isar)
│       ├── remote_*_repo.dart     # Supabase direto
│       ├── sync_repo.dart         # Sync offline-first
│       └── location_stream_repo.dart
│
├── domain/                        # Regras de negócio puras (Dart puro)
│   ├── entities/                  # 54 entities (imutáveis, Equatable)
│   ├── failures/                  # Sealed class hierarchy
│   ├── repositories/              # Contratos abstratos (interfaces)
│   ├── services/                  # Serviços de domínio
│   └── usecases/                  # 60 use cases
│       ├── coaching/              # Assessoria (CRUD, invite, remove)
│       ├── gamification/          # Desafios, challenges, wallet
│       ├── progression/           # XP, badges, missions, streaks
│       ├── social/                # Amigos, grupos sociais, eventos
│       └── (tracking)             # GPS, pace, distance, integrity
│
├── features/                      # Feature modules (mini clean arch)
│   ├── health_export/             # HealthKit / Health Connect
│   ├── integrations_export/       # GPX, TCX, FIT export
│   ├── parks/                     # Park detection, leaderboard, community
│   │   ├── data/                  # ParkDetectionService, parks_seed
│   │   ├── domain/                # ParkEntity, ParkLeaderboardEntry
│   │   └── presentation/          # ParkScreen, MyParksScreen
│   ├── strava/                    # Strava integration (sole data source)
│   ├── watch_bridge/              # WearOS / Apple Watch
│   └── wearables_ble/             # BLE heart rate monitors
│
├── presentation/
│   ├── blocs/                     # 21 BLoCs (Events + States)
│   ├── map/                       # MapLibre helpers
│   ├── screens/                   # 66 telas
│   └── widgets/                   # Componentes reutilizáveis
│
├── core/service_locator.dart      # get_it — único ponto de DI
└── main.dart                      # Entry point (Sentry + Supabase init)
```

---

## 4. FLUXO DE AUTENTICAÇÃO E ONBOARDING

```
App Start
    │
    ▼
main.dart: SentryFlutter.init() → Supabase.initialize() → _bootstrap()
    │
    ▼
AuthGate
    ├─ Sem sessão → WelcomeScreen → LoginScreen (Google Sign-In)
    │
    ├─ Sessão sem perfil completo → complete-social-profile (EF)
    │
    ├─ Sessão sem role → OnboardingRoleScreen
    │   ├─ Atleta → JoinAssessoriaScreen (solicitar entrada)
    │   └─ Staff  → StaffSetupScreen (criar assessoria)
    │       ├─ PopScope intercepta back → sign-out → Welcome
    │       └─ Botão ← visual em todas as telas
    │
    ├─ Role = ATLETA → HomeScreen (4 tabs: Início, Hoje, Histórico, Mais)
    │
    └─ Role = ASSESSORIA_STAFF → HomeScreen (2 tabs: Início, Mais)
                                    └─ StaffDashboardScreen
```

---

## 5. STAFF DASHBOARD (Assessoria)

```
StaffDashboardScreen
    │
    ├─ Dados: query Supabase direto → sync coaching_groups + coaching_members → Isar
    │
    ├─ Cards:
    │   ├─ Atletas e Staff → CoachingGroupDetailsScreen (Supabase direto)
    │   │   └─ Lista membros + botão remover (fn_remove_member)
    │   │
    │   ├─ Solicitações → StaffJoinRequestsScreen
    │   │   └─ Aprovar/Rejeitar (fn_approve/reject_join_request)
    │   │   └─ Badge com contagem de pendentes
    │   │
    │   ├─ Confirmações → StaffDisputesScreen (clearing entre assessorias)
    │   │
    │   ├─ Performance → StaffPerformanceScreen
    │   │   └─ KPIs: atletas ativos, corridas, desafios, campeonatos
    │   │   └─ RLS: sessions_staff_read via staff_group_member_ids()
    │   │
    │   ├─ Campeonatos → StaffChampionshipTemplatesScreen
    │   │   └─ Criar modelo (5 seções: nome, formato, ranking, local, extras)
    │   │   └─ Usar modelo → agendar com date/time picker
    │   │
    │   ├─ Convites → StaffChampionshipInvitesScreen
    │   │
    │   ├─ Créditos → StaffCreditsScreen (saldo + portal "em breve")
    │   │
    │   ├─ Administração → StaffQrHubScreen (QR operations)
    │   │
    │   └─ Portal → SnackBar "em breve" (url não configurada)
    │
    └─ Retenção / Relatório Semanal (drill-down do Performance)
```

---

## 6. FLUXO DE ENTRADA EM ASSESSORIA

```
Atleta busca assessoria (nome, código, QR)
    │
    ▼
JoinAssessoriaScreen → fn_request_join(p_group_id)
    │
    ├─ already_member → onComplete()
    ├─ already_requested → dialog "Aguardando aprovação"
    └─ requested → dialog "Solicitação enviada!"
                      │
                      ▼
          coaching_join_requests (status: pending)
                      │
                      ▼
Staff abre StaffJoinRequestsScreen
    │
    ├─ Aprovar → fn_approve_join_request
    │   └─ Cria coaching_member (role: atleta)
    │   └─ Atualiza profiles.active_coaching_group_id
    │
    └─ Rejeitar → fn_reject_join_request
        └─ Status → rejected

Remoção de membro (staff):
    CoachingGroupDetailsScreen → fn_remove_member
    └─ Limpa active_coaching_group_id do removido
```

---

## 7. ATIVIDADE (Strava como Fonte Única)

> **Decisão de produto (Sprint 25.0.0):** O app NÃO faz tracking GPS próprio.
> O atleta corre com qualquer relógio/app compatível com Strava.
> Dados fluem do Strava para o Omni Runner via API + webhook.

```
Strava Connect Flow
    │
    ├─ OAuth2 → StravaConnectController.handleCallback(code)
    │   ├─ exchangeCode → StravaConnected (tokens)
    │   ├─ _syncTokensToServer → strava_connections table
    │   └─ importStravaHistory (fire-and-forget)
    │       └─ getAthleteActivities(last 20)
    │           └─ filter type=Run/VirtualRun
    │               └─ upsert → strava_activity_history table
    │
    ├─ Webhook (push) ou poll → nova atividade detectada
    │   ├─ Download activity via API
    │   ├─ verify-session (anti-cheat)
    │   ├─ AwardXpForWorkout (cap 1000 XP/dia)
    │   ├─ EvaluateBadges → award XP por tier
    │   ├─ UpdateMissionProgress
    │   ├─ PostSessionChallengeDispatcher
    │   └─ ParkDetectionService.detectPark(lat, lng)
    │       └─ Se detectado → insert park_activities
    │
    └─ TodayScreen exibe recap, comparação, diário

Tracking GPS legado (TrackingScreen/TrackingBloc) permanece no código mas
NÃO é acessível pela navegação. Será removido em sprint futuro de cleanup.
```

### 7.1 Park Detection
```
ParkDetectionService
    │
    ├─ detectPark(lat, lng)
    │   └─ Ray-casting point-in-polygon para cada ParkEntity
    │       └─ Retorna ParkEntity? (primeiro match)
    │
    └─ findNearby(lat, lng, radiusM)
        └─ Haversine distance < radiusM ao center de cada park
            └─ Retorna List<ParkEntity>
```

---

## 8. SUPABASE BACKEND

### 8.1 Tabelas Principais

| Domínio | Tabelas |
|---------|---------|
| Auth/Profile | `profiles`, `auth.users` |
| Coaching | `coaching_groups`, `coaching_members`, `coaching_invites`, `coaching_join_requests` |
| Tracking | `sessions`, `session_points` |
| Challenges | `challenges`, `challenge_participants`, `challenge_results` |
| Championships | `championships`, `championship_templates`, `championship_participants`, `championship_invitations` |
| Wallet | `wallets`, `coin_ledger`, `coaching_token_inventory`, `token_intents` |
| Clearing | `clearing_weeks`, `clearing_cases`, `clearing_case_items`, `clearing_case_events` |
| Billing | `billing_customers`, `billing_products`, `billing_purchases`, `billing_events`, `billing_refund_requests`, `billing_auto_topup_settings` |
| Social | `groups`, `group_members`, `friendships`, `events`, `event_participants` |
| Progression | `badges`, `badge_awards`, `missions`, `mission_progress`, `xp_transactions`, `profile_progress` |
| Verification | `athlete_verification` |
| Strava | `strava_connections`, `strava_activity_history` |
| Parks | `park_activities`, `park_leaderboard`, `park_segments` |
| Notifications | `notification_log` |

### 8.2 RPC Functions (SECURITY DEFINER)

| Função | Propósito |
|--------|-----------|
| `fn_create_assessoria` | Cria coaching_group + membership admin_master |
| `fn_switch_assessoria` | Troca assessoria (queima coins, cria membership) |
| `fn_request_join` | Atleta solicita entrada (cria join request pendente) |
| `fn_approve_join_request` | Staff aprova (cria membership) |
| `fn_reject_join_request` | Staff rejeita |
| `fn_remove_member` | Staff remove membro (limpa profile) |
| `fn_search_coaching_groups` | Busca assessorias por nome |
| `fn_lookup_group_by_invite_code` | Busca por código de convite |
| `fn_join_as_professor` | Staff entra como professor |
| `fn_fulfill_purchase` | Processa compra (atomic credit allocation) |
| `release_pending_to_balance` | Clearing: libera pendentes → disponível |
| `check_daily_token_usage` | Rate limit de tokens |
| `increment_wallet_balance` | Atualiza saldo atomicamente |
| `eval_athlete_verification` | Avalia e transiciona estado de verificação do atleta (SECURITY DEFINER) |
| `get_verification_state` | Retorna estado + checklist booleans + contagens + thresholds para o app (SECURITY DEFINER STABLE) |
| `is_user_verified` | Helper: retorna true se atleta é VERIFIED (SECURITY DEFINER) |
| `user_coaching_group_ids()` | Helper RLS (retorna group_ids do caller) |
| `user_social_group_ids()` | Helper RLS (social groups) |
| `is_group_admin_or_mod()` | Helper RLS (social admin check) |
| `staff_group_member_ids()` | Helper RLS (member IDs para staff leitura) |

### 8.3 Edge Functions (41)

| Categoria | Funções |
|-----------|---------|
| Auth | `set-user-role`, `complete-social-profile` |
| Challenges | `challenge-create`, `challenge-join`, `challenge-get`, `challenge-list-mine`, `challenge-invite-group`, `challenge-accept-group-invite`, `settle-challenge` |
| Championships | `champ-create`, `champ-open`, `champ-list`, `champ-enroll`, `champ-invite`, `champ-accept-invite`, `champ-lifecycle`, `champ-update-progress`, `champ-participant-list`, `champ-activate-badge` |
| Tokens | `token-create-intent`, `token-consume-intent` |
| Wallet/Billing | `create-checkout-session`, `create-portal-session`, `list-purchases`, `webhook-payments`, `process-refund`, `auto-topup-check`, `auto-topup-cron` |
| Clearing | `clearing-confirm-sent`, `clearing-confirm-received`, `clearing-open-dispute`, `clearing-cron` |
| Progression | `calculate-progression`, `evaluate-badges`, `compute-leaderboard` |
| Verification | `eval-athlete-verification`, `verify-session`, `eval-verification-cron` |
| Analytics | `submit-analytics` |
| Notifications | `notify-rules`, `send-push` |
| Lifecycle | `lifecycle-cron` |

### 8.4 RLS Strategy

- **coaching_members**: `group_id IN (SELECT user_coaching_group_ids())` — SECURITY DEFINER evita recursão
- **sessions**: `user_id = auth.uid()` + `sessions_staff_read` (via `staff_group_member_ids()`)
- **challenge_participants**: own read + staff read
- **championship_templates**: INSERT/UPDATE/DELETE para admin_master/professor
- **coaching_join_requests**: own read (atleta) + group staff read + staff update
- **clearing_cases**: staff de ambos os grupos

---

## 9. CONVENCÕES DE UNIDADES (FIXAS)

| Grandeza | Tipo | Unidade Interna | Formatação UI |
|---|---|---|---|
| Distância | double | metros | km (ex: 5.23 km) |
| Tempo | int64 | milissegundos | HH:MM:SS |
| Pace | double | segundos por km | min:sec/km (ex: 5:30/km) |
| Coordenadas | double | graus decimais (WGS84) | — |
| Velocidade | double | metros por segundo | km/h (apenas UI) |
| Coins/Tokens | int | unidades | "X OmniCoins" |

Conversão para unidades de exibição acontece APENAS na presentation layer.

---

## 10. ERROR HANDLING

```
Hierarquia (sealed classes):
  Failure
  ├── GpsFailure (noPermission, timeout, unavailable)
  ├── StorageFailure (readError, writeError, full)
  ├── SyncFailure (noConnection, serverError, timeout)
  ├── ValidationFailure (invalidPace, invalidDistance, suspectedCheat)
  ├── IntegrationFailure (auth, upload, export)
  ├── HealthExportFailure (permission, availability)
  ├── GamificationFailure (unverifiedSession, dailyLimitReached, challengeExpired)
  └── CoachingFailure (groupNotFound, notMember, insufficientRole, cannotRemoveAdmin)

Logging: AppLogger → Sentry.captureException()
Retry: 3x exponential backoff em chamadas críticas (auth, create assessoria)
```

---

## 11. FEATURES MAP

| Feature | Camada | Tecnologia | Status |
|---|---|---|---|
| F1 — GPS Tracking | data (Geolocator) + domain (use cases) | Location stream + filter + accumulate | ✅ |
| F2 — Métricas | domain (use cases puros) | Pace, distance, elevation, HR zones | ✅ |
| F3 — Persistência offline | data (Isar) | Sessions, points, entities | ✅ |
| F4 — Mapa ao vivo | presentation (MapLibre) | Camera follow + auto-bearing | ✅ |
| F5 — Ghost Runner | domain + presentation | Interpolação + hysteresis + voz | ✅ |
| F6 — Anti-cheat | domain (3 detectors) | Speed, teleport, vehicle (via steps) | ✅ |
| F7 — Sync offline-first | data (SyncRepo) + core (AutoSyncManager) | Auto-retry on connectivity | ✅ |
| F8 — Exportação | features/ | GPX, TCX, FIT, Strava, HealthKit, Health Connect | ✅ |
| F9 — Gamificação | domain + data | Coins, challenges (1v1, group, team), streaks | ✅ |
| F10 — Progressão | domain + EFs | XP, levels, badges (30), missions, goals | ✅ |
| F11 — Social | domain + data | Amigos, grupos, eventos, leaderboards | ✅ |
| F12 — Assessoria | domain + data + EFs | Coaching groups, members, tokens, QR | ✅ |
| F13 — Campeonatos | domain + EFs | Templates, scheduling, invite, lifecycle | ✅ |
| F14 — Clearing | EFs + pg_cron | Compensação semanal inter-assessoria | ✅ |
| F15 — Billing B2B | Portal (Next.js) + Stripe | Checkout, webhook, auto top-up, refund | ✅ |
| F16 — Wearables BLE | features/ | HR monitors (Garmin, Polar, etc.) | ✅ |
| F17 — Audio Coach | domain + data | TTS, priority queue, voice triggers | ✅ |
| F18 — Crash Reporting | core (Sentry) | SentryFlutter.init + AppLogger hook | ✅ |
| F19 — Join Request Flow | data + EFs | Solicitação → aprovação/rejeição | ✅ |
| F20 — Member Management | data + EFs | Remover membros, role-based access | ✅ |
| F21 — Strava-Only Data Source | features/strava | OAuth2, history import, activity webhook | ✅ |
| F22 — Today Tab ("Hoje") | presentation/screens/today_screen | Streak, CTA, recap, comparison, journal | ✅ |
| F23 — Parks & Leaderboards | features/parks | Detection, tiers, community, segments | ✅ |
| F24 — Park Matchmaking | presentation/screens/matchmaking_screen | Preferred park auto-detect, priority match | ✅ |

---

## 12. BOUNDED CONTEXTS

### 12.1 Tracking Context
Captura GPS em tempo real, anti-cheat, métricas, ghost runner, auto-pause, foreground service.

### 12.2 Coaching Context (Assessoria)
Assessorias, membros (admin_master/professor/assistente/atleta), join requests com aprovação, remoção de membros, convites, QR operations, tokens/OmniCoins.

### 12.3 Challenge Context
Desafios 1v1, grupo e team vs team. Sempre entre atletas. Assessorias não participam de desafios — apenas distribuem tokens.

### 12.4 Championship Context
Campeonatos criados por assessorias. Modelos reutilizáveis. Corrida única ou período. Métricas: distância, tempo, pace, elevação. Lifecycle automático via pg_cron.

### 12.5 Wallet / Clearing Context
OmniCoins (gamificação, nunca monetário). Ledger append-only. Clearing semanal inter-assessoria. Disputas amigáveis sem moderação da plataforma.

### 12.6 Progression Context
XP, níveis (N^1.5), badges (30 tipos, 4 tiers), missions diárias, streaks (diário/semanal/mensal), goals semanais. Pertence ao atleta, não à assessoria.

### 12.7 Social Context
Amigos, grupos sociais, eventos, rankings, leaderboards.

### 12.8 Billing Context (Portal only)
Next.js portal. Stripe (card/pix/boleto). Auto top-up. Refund. Nunca no app mobile.

### 12.9 Parks Context
Detecção de parque via GPS (ray-casting polygon), leaderboards multi-tier (Rei/Elite/Destaque/Pelotão/Frequentador), 6 categorias de ranking (pace/distância/frequência/streak/evolução/maior corrida), comunidade por parque ("Quem corre aqui"), segmentos com recordes, matchmaking por parque preferido, shadow racing (futuro). Seed inicial com 10 parques brasileiros. Entities: `ParkEntity`, `ParkLeaderboardEntry`, `ParkActivityEntity`, `ParkSegmentEntity`. UI: `ParkScreen` (tabs: Ranking/Comunidade/Segmentos), `MyParksScreen`.

### 12.10 Verification Context (Atleta Verificado)
State machine de verificação de atleta (`athlete_verification` table). UNVERIFIED→CALIBRATING→MONITORED→VERIFIED→DOWNGRADED. Gate de monetização: stake>0 exige VERIFIED. Trust score (0..100) computado server-side. ZERO override admin. Avaliação via RPC SECURITY DEFINER `eval_athlete_verification` (thresholds: N=7, trust>=80). Leitura via RPC `get_verification_state` (checklist booleans + contagens). EF `eval-athlete-verification` (POST, JWT, idempotente). RLS: own-read-only. Enforcement: 4 camadas — Flutter UX gate (verification_gate.dart modal) + EF validation + RLS INSERT policy + DB triggers (`trg_challenges_verified_stake_gate`, `trg_participants_verified_join_gate`) que bloqueiam mesmo service_role. Flutter: `AthleteVerificationEntity`, `VerificationBloc` (load/eval), `AthleteVerificationScreen` (status+progress+checklist), gate integrado em `ChallengeCreateScreen._submit()` e `ChallengeDetailsScreen._AcceptDeclineCard._onAccept()`. Reavaliação automática: event-driven (SyncRepo→verify-session→eval RPC fire-and-forget) + cron diário (`eval-verification-cron` EF via pg_cron 03:00 UTC, batch 100 candidatos).

---

## 13. MONETIZATION MODEL (Loja-Safe)

O modelo de receita é **B2B SaaS** (plataforma → assessoria). O app **nunca processa pagamento** e **nunca mostra valores monetários**.

| Invariante | Verificação |
|------------|-------------|
| App NUNCA mostra preços R$/USD | 0 ocorrências em lib/ |
| App NUNCA processa pagamento | Zero payment SDK, zero IAP |
| App NUNCA menciona dinheiro/saque | Vocabulário controlado |
| OmniCoins ≠ valor monetário | GAMIFICATION_POLICY §2 |
| Checkout vive no portal web (browser externo) | `launchUrl(mode: externalApplication)` |

---

## 14. BUILD & DEPLOY

| Item | Valor |
|------|-------|
| Build flavor | `prod` (prod keystore), `dev` (debug) |
| Env vars | `--dart-define-from-file=.env.dev` |
| Keystore | `omnirunner-release.keystore` |
| APK atual | `v1.0.13` (127 MB) |
| Supabase | 42 Edge Functions + 11 migrations |
| Portal | `portal/` (Next.js 14, não deployado ainda) |
| CI/CD | Manual (flutter build apk) |
| Min Android SDK | 21 (Android 5.0) |
| Target SDK | 36 |

---

## 15. DATA FLOW PATTERNS

### Padrão 1: Supabase Direto (preferido para staff)
Staff dashboard, performance, atletas, solicitações → query Supabase direto.
Sem BLoC intermediário. Pull-to-refresh.

### Padrão 2: Supabase-first + Isar Cache (para atleta)
MyAssessoriaBloc, HistoryScreen → query Supabase primeiro, merge no Isar.
Garante dados frescos após aprovações server-side ou troca de conta.
Fallback silencioso para Isar quando offline.

### Padrão 2b: Isar Cache + BLoC (tracking ativo)
Tracking, wallet, challenges → Isar local como cache principal.
BLoC lê do Isar. SyncRepo sincroniza com Supabase.
AutoSyncManager retenta ao restaurar conectividade.

### Padrão 3: Edge Function (operações transacionais)
Criar desafio, settle challenge, criar campeonato, checkout.
SECURITY DEFINER + validações server-side.

---

## 16. TESTES

| Tipo | Quantidade | Diretório |
|------|-----------|-----------|
| Unit tests | 55 arquivos | `test/` |
| Cobertura | GPS, pace, distance, filter, ghost, auto-pause, integrity, badges, challenges | — |
| Smoke tests | Synthetic run E2E | `test/smoke/` |
| Testes manuais | QA em device real (v1.0.0 → v1.0.13, 33 bugs corrigidos) | — |

---

*Documento atualizado em 26/02/2026 — Sprint 25.0.0 (Strava-Only + Parks)*
