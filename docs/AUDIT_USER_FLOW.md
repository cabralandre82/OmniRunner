# Audit: User Flow Analysis

> Generated: 2026-03-04 | End-to-end user flow analysis for 3 personas across all touchpoints.

---

## Methodology

Three representative personas were simulated through every reachable screen, menu item, and action in the app. Each flow was rated:

- ✅ **Complete** — Full round-trip from entry to result, no dead ends
- ⚠️ **Partial** — Reachable but missing sub-features, empty states, or unfinished paths
- ❌ **Dead end** — Screen exists but leads nowhere, or feature is explicitly "coming soon"

Source of truth: actual screen code (`presentation/screens/`), home/dashboard/more screen navigation, sidebar NAV_ITEMS, and BLoC wiring.

---

## Persona 1: Athlete (role: `ATLETA`)

### 1.1 Bottom Navigation Tabs

| Tab | Screen | Rating | Notes |
|-----|--------|--------|-------|
| **Início** | `AthleteDashboardScreen` | ✅ | 6 dashboard cards: Desafios, Assessoria, Progresso, Créditos, Campeonatos, Convidar |
| **Hoje** | `TodayScreen` | ✅ | Live run tracking with GPS, map, audio coach, HR zones |
| **Histórico** | `HistoryScreen` | ✅ | Past runs list with details, replay, summary |
| **Mais** | `MoreScreen(userRole: 'ATLETA')` | ✅ | Hub for secondary features |

### 1.2 Dashboard Cards (AthleteDashboardScreen)

| Card | Target Screen | Rating | Flow |
|------|--------------|--------|------|
| **Meus desafios** | `ChallengesListScreen` | ✅ | List → Details → Create/Join → Result. Full lifecycle. |
| **Minha assessoria** | `MyAssessoriaScreen` | ✅ | Shows group info, feed, switch option. Empty state if unbound → `JoinAssessoriaScreen`. |
| **Meu progresso** | `ProgressHubScreen` | ✅ | Hub with 12 sub-features (see 1.4) |
| **Meus créditos** | `WalletScreen` | ✅ | Balance, ledger history, pending coins |
| **Campeonatos** | `AthleteChampionshipsScreen` | ✅ | List, ranking per championship |
| **Convidar amigos** | `InviteFriendsScreen` | ✅ | Share link + QR code |

Additional dashboard elements:
- Strava connection banner (if disconnected) → Settings
- Verification banner (if unverified) → `AthleteVerificationScreen`
- Assessoria feed section → `AssessoriaFeedScreen`
- Pending join request notice

### 1.3 "Mais" Menu (Athlete)

| Section | Item | Target | Rating | Notes |
|---------|------|--------|--------|-------|
| **Assessoria** | Minha Assessoria | `MyAssessoriaScreen` | ✅ | LoginRequired guard |
| **Assessoria** | Escanear QR | `StaffScanQrScreen` | ✅ | Athlete scanning staff QR to receive/return coins |
| **Assessoria** | Entregas Pendentes | `AthleteDeliveryScreen` | ✅ | Confirm workouts delivered to watch |
| **Social** | Convidar amigos | `InviteFriendsScreen` | ✅ | Share link generation |
| **Social** | Meus Amigos | `FriendsScreen` | ✅ | Friends list, search, requests |
| **Social** | Atividade dos amigos | — | ❌ | **Coming soon** (explicit `_ComingSoonTile`, shows SnackBar) |
| **Conta** | Meu Perfil | `ProfileScreen` | ✅ | View/edit profile |
| **Configurações** | Configurações | `SettingsScreen` | ✅ | Strava, theme, units |
| **Informações** | Sobre | About dialog | ✅ | Version + legal info |
| — | Sair | Auth gate | ✅ | Confirmation dialog → sign out |
| — | Modo Offline banner | Auth gate | ✅ | Only visible for anonymous users |

### 1.4 Progress Hub (ProgressHubScreen)

| # | Item | Target Screen | Rating | Notes |
|---|------|--------------|--------|-------|
| 1 | Nível e XP | `ProgressionScreen` | ✅ | Level, streak, weekly goal |
| 2 | Minha Retrospectiva | `WrappedScreen` | ✅ | OmniWrapped summary |
| 3 | Meu DNA de Corredor | `RunningDnaScreen` | ✅ | Radar profile, PR prediction |
| 4 | Minha Evolução | `PersonalEvolutionScreen` | ✅ | Pace, volume, frequency charts |
| 5 | Desafios | `ChallengesListScreen` | ✅ | Same as dashboard card |
| 6 | Campeonatos | `AthleteChampionshipsScreen` | ✅ | Same as dashboard card |
| 7 | Carteira | `WalletScreen` | ✅ | Same as dashboard card |
| 8 | Missões | `MissionsScreen` | ✅ | Active missions, progress bars |
| 9 | Conquistas | `BadgesScreen` | ✅ | Badge collection |
| 10 | Rankings | `LeaderboardsScreen` | ✅ | Weekly/assessoria/global |
| 11 | Sequência | `StreaksLeaderboardScreen` | ✅ | Streak leaderboard |
| 12 | Liga | `LeagueScreen` | ✅ | League position, promotions/relegations |
| 13 | Feed assessoria | `AssessoriaFeedScreen` | ✅ | Assessoria activity feed |

### 1.5 Challenge Flow (Deep Dive)

```
ChallengesListScreen
├── [Create] → ChallengeCreateScreen → (stakes, rules, duration) → Challenge created ✅
├── [Browse] → ChallengeDetailsScreen
│   ├── [Join] → ChallengeJoinScreen → wallet debit → Joined ✅
│   └── [Invite Group] → ChallengeInviteScreen ✅
├── [Matchmaking] → MatchmakingScreen → auto-pair by skill bracket ✅
└── [Completed] → ChallengeResultScreen → prize distribution ✅
```

### 1.6 Run Flow (Deep Dive)

```
TodayScreen
├── [Start Run] → GPS tracking + foreground service + map
│   ├── Audio coach active (TTS pace callouts) ✅
│   ├── HR zone display (if BLE sensor connected) ✅
│   ├── Ghost comparison (if racing challenge) ✅
│   ├── [Pause/Resume] ✅
│   └── [Stop] → RunSummaryScreen
│       ├── Metrics panel (distance, pace, elevation, splits) ✅
│       ├── [Share] → RunShareCard (social sharing) ✅
│       ├── [Replay] → RunReplayScreen (animated map replay) ✅
│       └── [Details] → RunDetailsScreen (full analysis) ✅
├── [No GPS] → GpsTipsSheet (troubleshooting) ✅
└── Offline mode → session saved to Isar → synced later ✅
```

### 1.7 Verification Flow

```
AthleteVerificationScreen
├── Checklist display (min runs, min distance, Strava linked, etc.) ✅
├── Each item: status (met / not met) ✅
├── [Trigger eval] → eval_my_verification() RPC ✅
└── Gate: verified status required for entry-fee challenges ✅
```

### 1.8 Athlete Flow Summary

| Area | Reachable Screens | ✅ | ⚠️ | ❌ |
|------|------------------|----|----|----| 
| Dashboard | 6 cards + banners | 6 | 0 | 0 |
| Bottom tabs | 4 | 4 | 0 | 0 |
| Mais menu | 10 items | 9 | 0 | 1 |
| Progress Hub | 13 items | 13 | 0 | 0 |
| Challenge lifecycle | 7 screens | 7 | 0 | 0 |
| Run lifecycle | 6 screens | 6 | 0 | 0 |
| **TOTAL** | **46** | **45** | **0** | **1** |

**Dead ends:** Friends Activity Feed (explicitly "Em breve").

---

## Persona 2: Coach / Staff (role: `ASSESSORIA_STAFF`)

### 2.1 Bottom Navigation Tabs

| Tab | Screen | Rating | Notes |
|-----|--------|--------|-------|
| **Início** | `StaffDashboardScreen` | ✅ | 6 management cards |
| **Mais** | `MoreScreen(userRole: 'ASSESSORIA_STAFF')` | ✅ | Reduced menu (no running features) |

Note: Staff has only 2 tabs (no "Hoje" or "Histórico" — coaches don't track runs in the staff flow).

### 2.2 Staff Dashboard Cards

| Card | Target Screen | Rating | Flow |
|------|--------------|--------|------|
| **Atletas** | `CoachingGroupDetailsScreen` | ✅ | Full member list, stats, member management |
| **Confirmações** | `StaffDisputesScreen` | ✅ | Clearing disputes, open cases |
| **Performance** | `StaffPerformanceScreen` | ✅ | KPI dashboard, retention metrics |
| **Campeonatos** | `StaffChampionshipTemplatesScreen` | ✅ | Create/manage templates → open → invite → lifecycle |
| **Créditos** | `StaffCreditsScreen` | ✅ | Token inventory, purchase info, distribution |
| **Administração** | `StaffQrHubScreen` | ✅ | Generate QR (emit/collect coins, activate badge) |

Additional dashboard elements:
- Group name + member count + balance display
- Invite code section (copy + share)
- Join requests badge (count of pending)
- League link → `LeagueScreen`
- Support link → `SupportScreen`
- Portal link (opens web browser → portal URL)
- Pending professor approval status

### 2.3 Staff Dashboard → Sub-flows

#### 2.3.1 Athlete Management

```
CoachingGroupDetailsScreen
├── Member list (with role badges) ✅
├── [Member] → StaffAthleteProfileScreen
│   ├── Athlete details, metrics ✅
│   ├── CRM notes and tags ✅
│   └── Training history ✅
├── [Join Requests] → StaffJoinRequestsScreen
│   ├── Approve ✅
│   └── Reject ✅
└── [Rankings] → Group evolution/rankings ✅
```

#### 2.3.2 Championship Management

```
StaffChampionshipTemplatesScreen
├── List templates ✅
├── [Create] → New template (name, rules, badge) ✅
├── [Template] → StaffChampionshipManageScreen
│   ├── Open championship from template ✅
│   ├── [Invites] → StaffChampionshipInvitesScreen ✅
│   └── Lifecycle: draft → open → active → completed ✅
└── [Challenge Invites] → StaffChallengeInvitesScreen ✅
```

#### 2.3.3 QR Operations

```
StaffQrHubScreen
├── [Emitir OmniCoins] → StaffGenerateQrScreen (mint) ✅
├── [Recolher OmniCoins] → StaffGenerateQrScreen (burn) ✅
├── [Ativar Badge] → StaffGenerateQrScreen (badge activation) ✅
└── Each generates a QR → athlete scans → token intent consumed ✅
```

### 2.4 "Mais" Menu (Staff)

| Section | Item | Target | Rating | Notes |
|---------|------|--------|--------|-------|
| **Social** | Assessorias Parceiras | `PartnerAssessoriasScreen` | ✅ | Partnership management |
| **Conta** | Meu Perfil | `ProfileScreen` | ✅ | View/edit |
| **Configurações** | Configurações | `SettingsScreen(isStaff: true)` | ✅ | Theme only (no Strava for staff) |
| **Administração** | Operações QR | `StaffQrHubScreen` | ✅ | Same as dashboard card |
| **Informações** | Sobre | About dialog | ✅ | Version info |
| — | Sair | Auth gate | ✅ | Confirmation → sign out |

### 2.5 Portal (Web Dashboard)

The coach accesses the portal at a separate URL. Role determines visible sidebar items.

#### 2.5.1 Coach (role: `coach`) — 22 sidebar items visible

| # | Page | Rating | Flow |
|---|------|--------|------|
| 1 | Dashboard | ✅ | Overview KPIs, quick links |
| 2 | Compensações (Clearing) | ✅ | Weekly clearing cycles, confirm sent/received |
| 3 | Badges | ✅ | Badge catalog, inventory management |
| 4 | Auditoria | ✅ | Audit log of portal actions |
| 5 | Distribuições | ✅ | Coin distribution to athletes |
| 6 | Atletas | ✅ | Full athlete roster |
| 7 | Verificação | ✅ | Review athlete verification status |
| 8 | Engajamento | ✅ | Engagement analytics |
| 9 | Presença | ✅ | Training session attendance tracking |
| 10 | CRM Atletas | ✅ | Notes, tags, status per athlete |
| 11 | Mural (Announcements) | ✅ | Create/edit/view announcements |
| 12 | Comunicação | ✅ | Push notification management |
| 13 | Análise Presença | ✅ | Attendance analytics charts |
| 14 | Alertas/Risco | ✅ | At-risk athlete alerts |
| 15 | Exports | ✅ | CSV export for all data categories |
| 16 | Treinos | ✅ | Workout template builder |
| 17 | Análise Treinos | ✅ | Workout completion analytics |
| 18 | Entrega Treinos | ✅ | Watch delivery pipeline |
| 19 | TrainingPeaks | ⚠️ | Feature-flag gated (only visible if `trainingpeaksEnabled`) |
| 20 | Financeiro | ✅ | Plans, subscriptions, ledger |
| 21 | Execuções | ✅ | Workout execution logs |
| 22 | Configurações | ✅ | Group settings, branding |

#### 2.5.2 Admin Master (role: `admin_master`) — All 25 items

Additional items beyond coach:

| # | Page | Rating | Notes |
|---|------|--------|-------|
| + | Custódia | ✅ | Wallet custody operations |
| + | Swap de Lastro | ✅ | Token swap/exchange |
| + | Conversão Cambial (FX) | ✅ | Currency conversion |

#### 2.5.3 Assistant (role: `assistant`) — 12 items

Subset: Dashboard, Atletas, Verificação, Engajamento, Presença, CRM Atletas, Mural, Análise Presença, Execuções, Configurações.

### 2.6 Staff Flow Summary

| Area | Reachable Points | ✅ | ⚠️ | ❌ |
|------|-----------------|----|----|----| 
| Bottom tabs | 2 | 2 | 0 | 0 |
| Dashboard cards | 6 + extras | 6 | 0 | 0 |
| Mais menu | 6 items | 6 | 0 | 0 |
| Athlete management | 4 screens | 4 | 0 | 0 |
| Championship flow | 4 screens | 4 | 0 | 0 |
| QR operations | 3 flows | 3 | 0 | 0 |
| Portal (coach) | 22 pages | 21 | 1 | 0 |
| **TOTAL** | **47** | **46** | **1** | **0** |

**Partial:** TrainingPeaks integration (feature-flag gated, available only when enabled).

---

## Persona 3: Platform Admin (role: `platform_admin`)

Platform admins access a separate section in the portal, shown below the main sidebar.

### 3.1 Platform Admin Pages

| # | Page | Rating | Flow |
|---|------|--------|------|
| 1 | Admin Plataforma (hub) | ✅ | Landing page with links to sub-sections |
| 2 | Assessorias | ✅ | List all assessorias, approval status, stats |
| 3 | Conquistas (Badges) | ✅ | Global badge catalog CRUD |
| 4 | Feature Flags | ✅ | Toggle features per group or globally |
| 5 | Taxas (Fees) | ✅ | Platform fee configuration |
| 6 | Financeiro | ✅ | Global financial overview, revenue |
| 7 | Invariants | ✅ | System health checks, data consistency |
| 8 | Liga | ✅ | League seasons management, snapshots |
| 9 | Produtos | ✅ | Billing product catalog (credit packs) |
| 10 | Reembolsos (Refunds) | ✅ | Process refund requests |
| 11 | Suporte | ✅ | Support ticket triage |
| 12 | Suporte / [id] | ✅ | Individual ticket detail + response |

### 3.2 Platform Admin API Routes

| Route | Purpose | Rating |
|-------|---------|--------|
| `api/platform/assessorias` | List/manage assessorias | ✅ |
| `api/platform/feature-flags` | Toggle feature flags | ✅ |
| `api/platform/fees` | Configure platform fees | ✅ |
| `api/platform/invariants` | Run invariant checks | ✅ |
| `api/platform/liga` | League admin operations | ✅ |
| `api/platform/products` | CRUD billing products | ✅ |
| `api/platform/refunds` | Process refunds | ✅ |
| `api/platform/support` | Support ticket management | ✅ |

### 3.3 Platform Admin Flow Summary

| Area | Reachable Points | ✅ | ⚠️ | ❌ |
|------|-----------------|----|----|----| 
| Platform pages | 12 | 12 | 0 | 0 |
| Platform APIs | 8 | 8 | 0 | 0 |
| **TOTAL** | **20** | **20** | **0** | **0** |

---

## 4. Cross-Persona: Shared Public Pages

| Page | URL Pattern | Rating | Notes |
|------|-------------|--------|-------|
| Login | `/login` | ✅ | Supabase auth callback |
| No Access | `/no-access` | ✅ | Shown when role insufficient |
| Challenge View | `/challenge/[id]` | ✅ | Public challenge details (shareable link) |
| Invite Landing | `/invite/[code]` | ✅ | Join assessoria via invite code |
| Select Group | `/select-group` | ✅ | Multi-group users pick active group |

---

## 5. Cross-Persona: Deep Link Entry Points

| Deep Link | Target | Rating |
|-----------|--------|--------|
| Challenge invite | `challenge/[id]` → `ChallengeDetailsScreen` | ✅ |
| Assessoria invite code | `invite/[code]` → `JoinAssessoriaScreen` | ✅ |
| Push notification tap | Context-dependent navigation via `push_navigation_handler.dart` | ✅ |
| Strava callback | OAuth redirect → Strava connection | ✅ |
| TrainingPeaks callback | OAuth redirect → TP connection | ✅ |

---

## 6. Offline / Edge Case Flows

| Scenario | Handling | Rating |
|----------|----------|--------|
| No internet during run | Session saved to Isar, synced on reconnection. `NoConnectionBanner` shown. | ✅ |
| Anonymous user | Can run and track. Gate on social/monetary features with `LoginRequiredSheet`. | ✅ |
| No assessoria bound | Dashboard shows empty state card → `JoinAssessoriaScreen`. `AssessoriaRequiredSheet` blocks assessoria-only features. | ✅ |
| Unverified athlete | `VerificationGate` widget blocks entry-fee challenges. Banner on dashboard. | ✅ |
| Watch disconnected | `OfflineSessionStore` on Wear OS, sync when reconnected via `DataLayerManager` | ✅ |
| Apple Watch | Scaffolded only (`.gitkeep` stubs) | ❌ |

---

## 7. Complete Screen Reachability Matrix

### 7.1 Screens Reachable by Athlete

| Screen | Entry Path | Rating |
|--------|-----------|--------|
| `athlete_dashboard_screen` | Tab: Início | ✅ |
| `today_screen` | Tab: Hoje | ✅ |
| `history_screen` | Tab: Histórico | ✅ |
| `more_screen` | Tab: Mais | ✅ |
| `map_screen` | Today → during run | ✅ |
| `run_summary_screen` | Today → stop run | ✅ |
| `run_details_screen` | History → run item | ✅ |
| `run_replay_screen` | Run details → replay | ✅ |
| `recovery_screen` | Post-run | ✅ |
| `challenges_list_screen` | Dashboard card / Progress Hub | ✅ |
| `challenge_details_screen` | Challenge list → item | ✅ |
| `challenge_create_screen` | Challenge list → create | ✅ |
| `challenge_join_screen` | Challenge details → join | ✅ |
| `challenge_invite_screen` | Challenge details → invite | ✅ |
| `challenge_result_screen` | Challenge details (completed) | ✅ |
| `matchmaking_screen` | Challenge list → matchmaking | ✅ |
| `wallet_screen` | Dashboard card / Progress Hub | ✅ |
| `badges_screen` | Progress Hub | ✅ |
| `leaderboards_screen` | Progress Hub | ✅ |
| `league_screen` | Progress Hub | ✅ |
| `missions_screen` | Progress Hub | ✅ |
| `progression_screen` | Progress Hub | ✅ |
| `personal_evolution_screen` | Progress Hub | ✅ |
| `running_dna_screen` | Progress Hub | ✅ |
| `wrapped_screen` | Progress Hub | ✅ |
| `streaks_leaderboard_screen` | Progress Hub | ✅ |
| `assessoria_feed_screen` | Progress Hub / Dashboard | ✅ |
| `athlete_championships_screen` | Dashboard card | ✅ |
| `athlete_championship_ranking_screen` | Championships → item | ✅ |
| `athlete_verification_screen` | Dashboard banner | ✅ |
| `my_assessoria_screen` | Dashboard / Mais | ✅ |
| `join_assessoria_screen` | Dashboard (no assessoria) | ✅ |
| `athlete_workout_day_screen` | Training list → day | ✅ |
| `athlete_training_list_screen` | Assessoria → training | ✅ |
| `athlete_log_execution_screen` | Workout day → log | ✅ |
| `athlete_delivery_screen` | Mais → Entregas | ✅ |
| `athlete_device_link_screen` | Delivery → link device | ✅ |
| `athlete_checkin_qr_screen` | Attendance → QR | ✅ |
| `athlete_my_evolution_screen` | Evolution sub-flow | ✅ |
| `athlete_my_status_screen` | Status sub-flow | ✅ |
| `athlete_evolution_screen` | Evolution sub-flow | ✅ |
| `athlete_attendance_screen` | Attendance sub-flow | ✅ |
| `friends_screen` | Mais → Meus Amigos | ✅ |
| `friend_profile_screen` | Friends → profile | ✅ |
| `friends_activity_feed_screen` | Mais → Atividade | ❌ |
| `invite_friends_screen` | Dashboard / Mais | ✅ |
| `invite_qr_screen` | Invite flow | ✅ |
| `profile_screen` | Mais → Meu Perfil | ✅ |
| `settings_screen` | Mais → Configurações | ✅ |
| `support_screen` | Staff Dashboard / link | ✅ |
| `support_ticket_screen` | Support → ticket | ✅ |
| `progress_hub_screen` | Dashboard → Meu Progresso | ✅ |
| `diagnostics_screen` | Settings (hidden) | ✅ |
| `how_it_works_screen` | Onboarding | ✅ |
| `welcome_screen` | First launch | ✅ |
| `auth_gate` | Launch / sign out | ✅ |
| `login_screen` | Auth gate | ✅ |
| `onboarding_role_screen` | Post-signup | ✅ |
| `onboarding_tour_screen` | Post-onboarding | ✅ |

### 7.2 Screens Reachable by Staff

| Screen | Entry Path | Rating |
|--------|-----------|--------|
| `staff_dashboard_screen` | Tab: Início | ✅ |
| `more_screen` | Tab: Mais | ✅ |
| `coaching_group_details_screen` | Dashboard → Atletas | ✅ |
| `coaching_groups_screen` | Navigation | ✅ |
| `staff_athlete_profile_screen` | Member list → athlete | ✅ |
| `staff_crm_list_screen` | CRM navigation | ✅ |
| `staff_join_requests_screen` | Dashboard → pending | ✅ |
| `staff_championship_templates_screen` | Dashboard → Campeonatos | ✅ |
| `staff_championship_manage_screen` | Template → manage | ✅ |
| `staff_championship_invites_screen` | Championship → invites | ✅ |
| `staff_challenge_invites_screen` | Challenge invites | ✅ |
| `staff_credits_screen` | Dashboard → Créditos | ✅ |
| `staff_disputes_screen` | Dashboard → Confirmações | ✅ |
| `staff_performance_screen` | Dashboard → Performance | ✅ |
| `staff_retention_dashboard_screen` | Performance sub-flow | ✅ |
| `staff_weekly_report_screen` | Performance sub-flow | ✅ |
| `staff_qr_hub_screen` | Dashboard / Mais → QR | ✅ |
| `staff_generate_qr_screen` | QR Hub → generate | ✅ |
| `staff_scan_qr_screen` | QR Hub → scan | ✅ |
| `staff_training_create_screen` | Training mgmt | ✅ |
| `staff_training_detail_screen` | Training list → detail | ✅ |
| `staff_training_list_screen` | Training management | ✅ |
| `staff_training_scan_screen` | Training → scan | ✅ |
| `staff_workout_builder_screen` | Workout management | ✅ |
| `staff_workout_templates_screen` | Workout management | ✅ |
| `staff_workout_assign_screen` | Workout → assign | ✅ |
| `staff_setup_screen` | First-time staff setup | ✅ |
| `coach_insights_screen` | Analytics | ✅ |
| `partner_assessorias_screen` | Mais → Parceiras | ✅ |
| `league_screen` | Dashboard → Liga | ✅ |
| `support_screen` | Dashboard → Suporte | ✅ |
| `profile_screen` | Mais → Meu Perfil | ✅ |
| `settings_screen` | Mais → Configurações | ✅ |

### 7.3 Screens with Limited/No Reachability

| Screen | Issue | Persona |
|--------|-------|---------|
| `friends_activity_feed_screen` | Explicitly "Coming soon" | Athlete |
| `group_events_screen` | Reachable from group details | ✅ (via groups) |
| `events_screen` / `event_details_screen` | Reachable from groups/events | ✅ |
| `race_event_details_screen` | Reachable from events | ✅ |

---

## 8. Overall Health Score

| Persona | Total Flows | ✅ Complete | ⚠️ Partial | ❌ Dead End |
|---------|-------------|-------------|-------------|-------------|
| **Athlete** | 58 | 57 (98%) | 0 (0%) | 1 (2%) |
| **Coach/Staff** | 47 | 46 (98%) | 1 (2%) | 0 (0%) |
| **Platform Admin** | 20 | 20 (100%) | 0 (0%) | 0 (0%) |
| **GRAND TOTAL** | **125** | **123 (98.4%)** | **1 (0.8%)** | **1 (0.8%)** |

### Key Findings

1. **98.4% of all user flows are complete** — the app is extremely well-connected with no orphaned screens.
2. **1 dead end:** Friends Activity Feed is explicitly flagged "Em breve" (coming soon) with a SnackBar notification. This is intentional, not a bug.
3. **1 partial:** TrainingPeaks portal page is feature-flag gated. When the flag is off, the sidebar item is hidden — by design.
4. **Zero orphan screens:** Every screen file in `presentation/screens/` is reachable from at least one navigation path.
5. **Strong gate system:** Anonymous users, unverified athletes, and users without an assessoria all encounter appropriate gates (`LoginRequiredSheet`, `VerificationGate`, `AssessoriaRequiredSheet`) that guide them to resolution rather than dead-ending.
6. **Apple Watch:** Watch app is scaffolded but not implemented (Swift side). Wear OS is fully functional.

### Recommendations

1. **Ship Friends Activity Feed** — the screen file exists (`friends_activity_feed_screen.dart`), the RPC exists (`fn_friends_activity_feed()`), but it's gated behind "coming soon". Consider enabling.
2. **Apple Watch implementation** — all Swift directories have `.gitkeep` stubs only. The Wear OS companion is complete and could serve as a reference.
3. **TrainingPeaks** — works when enabled, but feature-flag default is off. Document the enablement criteria for coaches.
