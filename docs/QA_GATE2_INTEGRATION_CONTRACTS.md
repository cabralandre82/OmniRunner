# GATE 2 — Integration Contracts

> Mapa completo de dependências Tela/Página → Backend para todo o produto.  
> Data: 2026-03-03

---

## Convenções

- **Loading:** estado enquanto dados carregam (shimmer, spinner, skeleton)
- **Empty:** estado quando query retorna 0 rows
- **Error:** estado quando query falha (network, 5xx, RLS)
- **Retry:** mecanismo de retry disponível (pull-to-refresh, botão, auto)
- **HTTP:** tratamento de status codes no portal (401→login, 403→no-access, 404→not-found, 409→conflict toast, 5xx→error page)

---

## App Flutter — Staff Screens

| Tela | Ação | Endpoint/RPC/Table | Request Schema | Response Schema | Loading | Empty | Error | Retry |
|------|------|--------------------|----------------|-----------------|---------|-------|-------|-------|
| StaffDashboardScreen | Load status | `coaching_members` SELECT WHERE user_id | `{user_id: string}` | `CoachingMemberEntity[]` | ShimmerLoading | "Nenhum grupo" + setup CTA | SnackBar error | Pull-to-refresh |
| StaffDashboardScreen | Load group name | `coaching_groups` SELECT WHERE id | `{group_id: string}` | `{name: string}` | ShimmerLoading | — | — | — |
| StaffDashboardScreen | Load wallet | `coaching_token_inventory` SELECT | `{group_id: string}` | `{available_tokens: int}` | ShimmerLoading | 0 | — | — |
| StaffDashboardScreen | Load disputes count | `clearing_settlements` SELECT WHERE status='pending' | `{group_id: string}` | `int count` | ShimmerLoading | 0 | — | — |
| StaffDashboardScreen | Load pending join requests | `coaching_members` SELECT WHERE role='pending' | `{group_id: string}` | `int count` | ShimmerLoading | 0 | — | — |
| StaffAthleteProfileScreen | Load profile | `profiles` SELECT + `sessions` SELECT + `athlete_verification` | `{user_id: string}` | Profile + stats | ShimmerLoading | — | SnackBar | Retry button |
| StaffCrmListScreen | Load CRM data | `coaching_member_status`, `coaching_athlete_tags`, `coaching_athlete_notes` | `{group_id: string}` | `CrmAthlete[]` | ShimmerLoading | "Nenhum atleta" | SnackBar | Pull-to-refresh |
| StaffCrmListScreen | Manage status | `manage_member_status` usecase → UPDATE coaching_member_status | `{user_id, group_id, status}` | `void` | Button loading | — | SnackBar error | — |
| StaffCrmListScreen | Manage tags | `manage_tags` usecase → INSERT/DELETE coaching_athlete_tags | `{athlete_user_id, group_id, tag_name}` | `void` | Button loading | — | SnackBar error | — |
| StaffCrmListScreen | Add note | `manage_notes` usecase → INSERT coaching_athlete_notes | `{athlete_user_id, group_id, note}` | `void` | Button loading | — | SnackBar error | — |
| StaffPerformanceScreen | Load KPIs | `kpi_daily_snapshots`, `sessions`, `coaching_members` | `{group_id: string}` | KPI metrics | ShimmerLoading | "Sem dados" | SnackBar | Pull-to-refresh |
| StaffRetentionDashboard | Load alerts + retention | `coaching_alerts`, `kpi_daily_snapshots` | `{group_id: string}` | Alert[] + KPIs | ShimmerLoading | "Sem alertas" | SnackBar | Pull-to-refresh |
| StaffWeeklyReport | Load report | `sessions`, `coaching_members`, `coin_ledger` agg | `{group_id, week}` | Report data | ShimmerLoading | "Sem atividade" | SnackBar | Retry |
| StaffSetupScreen | Create group | INSERT `coaching_groups` + `coaching_members` | `{name, user_id}` | `{group_id}` | Button loading | — | SnackBar | — |
| StaffJoinRequestsScreen | Load requests | `coaching_members` WHERE role='pending' | `{group_id: string}` | `Member[]` | ShimmerLoading | "Nenhum pedido" | SnackBar | Pull-to-refresh |
| StaffJoinRequestsScreen | Accept/Reject | UPDATE `coaching_members` SET role | `{member_id, role}` | `void` | Button loading | — | SnackBar | — |
| StaffQrHubScreen | Get emission capacity | `getEmissionCapacity` / `getBadgeCapacity` | `{group_id}` | `{available_tokens, available_badges}` | ShimmerLoading | — | SnackBar | Pull-to-refresh |
| StaffGenerateQrScreen | Create intent | `token-create-intent` edge fn | `{type, group_id, amount}` | `StaffQrPayload` | CircularProgress | — | SnackBar "Falha ao gerar" | Retry button |
| StaffScanQrScreen | Consume intent | `token-consume-intent` edge fn | `StaffQrPayload` | `void` | CircularProgress | — | SnackBar "QR inválido/expirado" | Scan again |
| StaffCreditsScreen | Load inventory | `coaching_token_inventory`, `coaching_badge_inventory` | `{group_id}` | Inventory | ShimmerLoading | "Sem créditos" | SnackBar | Pull-to-refresh |
| StaffDisputesScreen | Load disputes | `clearing_settlements` WHERE status IN (pending, disputed) | `{group_id}` | `Settlement[]` | ShimmerLoading | "Nenhuma disputa" | SnackBar | Pull-to-refresh |
| StaffWorkoutTemplatesScreen | Load templates | `coaching_workout_templates` SELECT | `{group_id}` | `WorkoutTemplate[]` | ShimmerLoading | "Nenhum template" | SnackBar | Pull-to-refresh |
| StaffWorkoutBuilderScreen | Load/Save template | SELECT/INSERT/UPDATE `coaching_workout_templates` + `coaching_workout_blocks` | Template + blocks | `void` | ShimmerLoading / button | — | SnackBar | — |
| StaffWorkoutAssignScreen | Assign workout | INSERT `coaching_workout_assignments` | `{template_id, athlete_user_id, group_id, scheduled_date}` | `{assignment_id}` | Button loading | — | SnackBar "Assinatura em atraso" | — |
| StaffTrainingListScreen | Load sessions | `coaching_training_sessions` SELECT | `{group_id}` | `TrainingSession[]` | ShimmerLoading | "Nenhuma sessão" | SnackBar | Pull-to-refresh |
| StaffTrainingCreateScreen | Create session | INSERT `coaching_training_sessions` | `{title, starts_at, location, group_id}` | `{session_id}` | Button loading | — | SnackBar | — |
| StaffTrainingDetailScreen | Load detail | `coaching_training_sessions` + `coaching_training_attendance` | `{session_id}` | Session + Attendance[] | ShimmerLoading | "Nenhum check-in" | SnackBar | Pull-to-refresh |
| StaffTrainingScanScreen | Scan attendance | `mark_attendance` usecase | `{session_id, token}` | `void` | CircularProgress | — | SnackBar "QR expirado" | Scan again |
| AnnouncementCreateScreen | Create announcement | INSERT `coaching_announcements` | `{title, body, group_id, pinned}` | `{id}` | Button loading | — | SnackBar | — |
| CoachingGroupsScreen | Load groups | `coaching_groups` + `coaching_members` | `{user_id}` | `Group[]` | ShimmerLoading | "Nenhum grupo" | SnackBar | Pull-to-refresh |
| CoachingGroupDetailsScreen | Load details | `coaching_groups` + `coaching_members` | `{group_id}` | Group + Member[] | ShimmerLoading | — | SnackBar | Pull-to-refresh |
| CoachingGroupDetailsScreen | Invite user | `invite_user_to_group` usecase | `{group_id, email}` | `void` | Button loading | — | SnackBar | — |
| CoachingGroupDetailsScreen | Remove member | `remove_coaching_member` usecase | `{member_id}` | `void` | Button loading | — | SnackBar | — |
| GroupMembersScreen | Load members | `coaching_members` SELECT | `{group_id}` | `Member[]` | ShimmerLoading | "Nenhum membro" | SnackBar | Pull-to-refresh |
| CoachInsightsScreen | Load insights | `coach_insights`, `kpi_daily_snapshots` | `{group_id}` | Insight[] | ShimmerLoading | "Sem insights" | SnackBar | Pull-to-refresh |

## App Flutter — Athlete Screens

| Tela | Ação | Endpoint/RPC/Table | Request Schema | Response Schema | Loading | Empty | Error | Retry |
|------|------|--------------------|----------------|-----------------|---------|-------|-------|-------|
| AthleteDashboardScreen | Load assessoria | `coaching_members` + `coaching_groups` | `{user_id}` | name, group_id | ShimmerLoading | "Sem assessoria" CTA | SnackBar | Pull-to-refresh |
| AthleteDashboardScreen | Load Strava status | `strava_tokens` SELECT | `{user_id}` | `bool` | — | — | — | — |
| AthleteWorkoutDayScreen | Load today assignments | `coaching_workout_assignments` + blocks | `{user_id, date}` | Assignment + blocks | ShimmerLoading | "Sem treino hoje" | SnackBar | Pull-to-refresh |
| AthleteLogExecutionScreen | Save execution | INSERT `coaching_workout_executions` | `{assignment_id, duration, distance, pace, hr, source='manual'}` | `{execution_id}` | Button loading | — | SnackBar | — |
| AthleteTrainingListScreen | Load sessions | `coaching_training_sessions` WHERE group_id | `{group_id}` | `Session[]` | ShimmerLoading | "Nenhuma sessão agendada" | SnackBar | Pull-to-refresh |
| AthleteAttendanceScreen | Load attendance | `coaching_training_attendance` WHERE athlete_user_id | `{user_id, group_id}` | `Attendance[]` | ShimmerLoading | "Nenhuma presença" | SnackBar | Pull-to-refresh |
| AthleteCheckinQrScreen | Scan & mark | `mark_attendance` usecase | `{session_id, token, athlete_user_id}` | `void` | CircularProgress | — | SnackBar "QR inválido/expirado/duplicado" | Scan again |
| AthleteDeviceLinkScreen | Load links | `coaching_device_links` SELECT | `{user_id, group_id}` | `DeviceLink[]` | ShimmerLoading | "Nenhum dispositivo" | SnackBar | Pull-to-refresh |
| AthleteDeviceLinkScreen | Link device | `link_device` usecase → INSERT coaching_device_links | `{provider, user_id, group_id}` | `void` | Button loading | — | SnackBar | — |
| AthleteDeviceLinkScreen | Unlink device | DELETE `coaching_device_links` | `{link_id}` | `void` | Button loading | — | SnackBar | — |
| AthleteMyEvolutionScreen | Load evolution | `athlete_baselines`, `athlete_trends` | `{user_id}` | Baseline + Trend[] | ShimmerLoading | "Sem dados suficientes" | SnackBar | Pull-to-refresh |
| AthleteMyStatusScreen | Load status | `athlete_verification`, `coin_ledger`, `coaching_member_status` | `{user_id}` | Status data | ShimmerLoading | — | SnackBar | Pull-to-refresh |
| AthleteVerificationScreen | Load verification | `athlete_verification` SELECT | `{user_id}` | Verification entity | ShimmerLoading | "Ainda calibrando" | SnackBar | Pull-to-refresh |
| AnnouncementFeedScreen | Load feed | `coaching_announcements` SELECT | `{group_id}` | `Announcement[]` | ShimmerLoading | "Nenhum comunicado" | SnackBar | Pull-to-refresh |
| AnnouncementDetailScreen | Load + mark read | SELECT + INSERT `coaching_announcement_reads` | `{announcement_id, user_id}` | Announcement + void | ShimmerLoading | — | SnackBar | Pull-to-refresh |
| MyAssessoriaScreen | Load assessoria info | `coaching_groups` + `coaching_members` | `{user_id}` | Group info | ShimmerLoading | "Sem assessoria" | SnackBar | Pull-to-refresh |
| JoinAssessoriaScreen | Search + join | `fn_search_coaching_groups` + `accept_coaching_invite` | `{search, invite_code}` | Groups[] / void | Button loading | "Nenhum resultado" | SnackBar | — |
| WalletScreen | Load wallet | `coin_ledger` SELECT + wallet agg | `{user_id}` | `LedgerEntry[]` + balance | ShimmerLoading | "Sem transações" | SnackBar | Pull-to-refresh |
| ChallengesListScreen | Load challenges | `challenge-list-mine` edge fn | `{user_id}` | `Challenge[]` | ShimmerLoading | "Sem desafios. Crie um!" | SnackBar | Pull-to-refresh |
| ChallengeCreateScreen | Create | `challenge-create` edge fn | `{type, goal, entry_fee, ...}` | `{challenge_id}` | Button loading | — | SnackBar | — |
| ChallengeDetailsScreen | Load details | `challenge-get` edge fn | `{challenge_id}` | Challenge + Participants | ShimmerLoading | — | SnackBar | Pull-to-refresh |
| ChallengeJoinScreen | Join | `challenge-join` edge fn | `{challenge_id}` | `void` | Button loading | — | SnackBar "Saldo insuficiente" | — |
| ProgressHubScreen | Load progress | `profile_progress`, `badges`, `missions` | `{user_id}` | Progress data | ShimmerLoading | — | SnackBar | Pull-to-refresh |
| ProgressionScreen | Load progression | `progression` SELECT | `{user_id}` | Level + XP | ShimmerLoading | — | SnackBar | Pull-to-refresh |
| BadgesScreen | Load badges | `badge_awards` + `badges` catalog | `{user_id}` | `Badge[]` | ShimmerLoading | "Nenhum badge" | SnackBar | Pull-to-refresh |
| MissionsScreen | Load missions | `missions` + `mission_progress` | `{user_id}` | Mission + progress | ShimmerLoading | "Sem missões ativas" | SnackBar | Pull-to-refresh |
| StreaksLeaderboardScreen | Load streaks | `leaderboard` SELECT | `{type='streaks'}` | `Entry[]` | ShimmerLoading | "Sem dados" | SnackBar | Pull-to-refresh |
| LeaderboardsScreen | Load leaderboards | `leaderboard` SELECT | `{type, period}` | `Entry[]` | ShimmerLoading | "Sem dados" | SnackBar | Pull-to-refresh |
| MatchmakingScreen | Find match | `matchmake` edge fn | `{user_id, criteria}` | `{opponent}` | CircularProgress | "Nenhum oponente disponível" | SnackBar | Retry |
| LeagueScreen | Load league | `league-list` edge fn | `{user_id}` | League + members | ShimmerLoading | "Sem liga ativa" | SnackBar | Pull-to-refresh |
| RunningDnaScreen | Load DNA | `running_dna` SELECT | `{user_id}` | DNA profile | ShimmerLoading | "Ainda calculando" | SnackBar | Pull-to-refresh |
| WrappedScreen | Load wrapped | `user_wrapped` SELECT | `{user_id, year}` | Wrapped data | ShimmerLoading | "Sem Wrapped" | SnackBar | — |

## App Flutter — Shared/Social Screens

| Tela | Ação | Endpoint/RPC/Table | Request Schema | Response Schema | Loading | Empty | Error | Retry |
|------|------|--------------------|----------------|-----------------|---------|-------|-------|-------|
| LoginScreen | Sign in | Supabase Auth (email/google/apple) | `{email, password}` or OAuth | `AuthUser` | Button loading | — | SnackBar "Credenciais inválidas" | — |
| ProfileScreen | Load profile | `profiles` SELECT | `{user_id}` | `ProfileEntity` | ShimmerLoading | — | SnackBar | Pull-to-refresh |
| ProfileScreen | Update profile | `profiles` UPDATE | `ProfilePatch` | `ProfileEntity` | Button loading | — | SnackBar | — |
| FriendsScreen | Load friends | `friendships` SELECT | `{user_id}` | `Friend[]` | ShimmerLoading | "Sem amigos. Convide!" | SnackBar | Pull-to-refresh |
| FriendsScreen | Accept friend | `accept_friend` usecase | `{friendship_id}` | `void` | Button loading | — | SnackBar | — |
| HistoryScreen | Load history | `sessions` SELECT order by start_time_ms DESC | `{user_id, limit, offset}` | `Session[]` | ShimmerLoading | "Sem corridas" | SnackBar | Pagination + pull |
| SupportScreen | Load tickets | `support_tickets` SELECT | `{user_id}` | `Ticket[]` | ShimmerLoading | "Sem tickets" | SnackBar | Pull-to-refresh |
| SupportScreen | Create ticket | INSERT `support_tickets` | `{subject, message}` | `{ticket_id}` | Button loading | — | SnackBar | — |

---

## Portal Next.js Pages

| Página | Ação | Endpoint/RPC/Table | Request Schema | Response Schema | Loading | Empty | Error | HTTP Codes |
|--------|------|--------------------|----------------|-----------------|---------|-------|-------|------------|
| `/dashboard` | Load KPIs | coaching_token_inventory, coaching_members, sessions, challenges, athlete_verification | `{group_id}` via cookie | DashboardData | `loading.tsx` skeleton | N/A (always shows 0) | fetchError → red banner | 401→login, 403→no-access |
| `/athletes` | Load athletes | coaching_members, profiles, athlete_verification, sessions | `{group_id}` | `Athlete[]` | `loading.tsx` | "Nenhum atleta" | fetchError → red banner | 401, 403 |
| `/athletes` | Distribute coins | POST `/api/distribute-coins` | `{user_id, amount, group_id}` | `{ok, new_balance}` | Button spinner | — | Toast error | 400 bad req, 403, 409 insufficient |
| `/custody` | Load custody | custody_accounts, custody_deposits, custody_withdrawals, coin_ledger, clearing_settlements | `{group_id}` | Account + tx lists | `loading.tsx` skeleton | "Sem transações" | Error banner | 401, 403 |
| `/custody` | Deposit | POST `/api/custody` | `{amount, group_id}` | `{deposit_id}` | Button spinner | — | Toast error | 400, 403 |
| `/custody` | Withdraw | POST `/api/custody/withdraw` | `{amount, group_id}` | `{withdrawal_id}` | Button spinner | — | Toast error | 400, 403, 409 |
| `/clearing` | Load settlements | clearing_settlements, clearing_events, coaching_groups | `{group_id}` | Settlements + events | Inline | "Nenhuma compensação" | Error banner | 401, 403 |
| `/clearing` | Confirm received | `clearing-confirm-received` | `{settlement_id}` | `void` | Button | — | Toast | 400, 403, 409 |
| `/swap` | Load offers | swap_orders, custody_accounts, platform_fee_config | `{group_id}` | Offers + balance | Inline | "Sem ofertas abertas" | Error banner | 401, 403 |
| `/swap` | Create/Accept/Cancel | POST/PATCH/DELETE `/api/swap` | `{action, ...params}` | `void` | Button spinner | — | Toast error | 400, 403, 409 |
| `/fx` | Load FX data | custody_accounts, fx_rates | `{group_id}` | Balance + rates | Inline | — | Error banner | 401, 403 |
| `/fx` | Withdraw | POST `/api/custody/withdraw` | `{amount, currency}` | `void` | Button | — | Toast | 400, 403 |
| `/badges` | Load badges | coaching_badge_inventory, billing_products, billing_customers | `{group_id}` | Inventory + products | Inline | "Sem badges" | Error banner | 401, 403 |
| `/audit` | Load audit trail | clearing_events, clearing_settlements, coaching_groups | `{group_id}` | Events + settlements | Inline | "Sem eventos" | Error banner | 401, 403 |
| `/distributions` | Load distributions | coin_ledger, coaching_members, coaching_token_inventory | `{group_id}` | LedgerEntry[] + balance | `loading.tsx` | "Sem distribuições" | Error banner | 401, 403 |
| `/verification` | Load athletes | athlete_verification, profiles, coaching_members | `{group_id}` | AthleteRow[] | `loading.tsx` | "Nenhum atleta" | Error banner | 401, 403 |
| `/verification` | Reevaluate | POST `/api/verification/evaluate` | `{user_id, group_id}` | `{new_status}` | Button spinner | — | Toast error | 400, 403, 404 |
| `/engagement` | Load engagement | sessions, coaching_members, challenges, kpi_daily_snapshots | `{group_id, period}` | Engagement data | `loading.tsx` | "Sem atividade" | Error banner | 401, 403 |
| `/attendance` | Load sessions + attendance | coaching_training_sessions, coaching_training_attendance | `{group_id, from, to}` | Session[] + counts | Inline | "Nenhuma sessão" | Error banner | 401, 403 |
| `/attendance/[id]` | Load session detail | coaching_training_attendance + profiles | `{session_id}` | Attendance[] | Inline | "Nenhum check-in" | Error banner | 401, 403, 404 |
| `/attendance-analytics` | Load analytics | coaching_training_attendance agg + coaching_training_sessions | `{group_id, period}` | Analytics data | `loading.tsx` | "Sem dados" | Error banner | 401, 403 |
| `/crm` | Load CRM | coaching_member_status, coaching_athlete_tags, coaching_athlete_notes, coaching_alerts | `{group_id, ?tag, ?status, ?search}` | CrmAthlete[] | `loading.tsx` | "Nenhum atleta" | Error banner | 401, 403 |
| `/crm/at-risk` | Load at-risk | coaching_alerts, coaching_member_status | `{group_id}` | AlertedAthletes[] | Inline | "Sem atletas em risco" | Error banner | 401, 403 |
| `/crm/[userId]` | Load profile + notes | coaching_athlete_notes, coaching_member_status, coaching_athlete_tags | `{user_id, group_id}` | Profile + notes | Inline | "Sem notas" | Error banner | 401, 403, 404 |
| `/crm/[userId]` | Add note | POST `/api/crm/notes` | `{user_id, group_id, note}` | `void` | Button spinner | — | Toast error | 400, 403 |
| `/crm/[userId]` | Manage tags | POST/DELETE `/api/crm/tags` | `{user_id, group_id, tag_name}` | `void` | Button spinner | — | Toast error | 400, 403 |
| `/announcements` | Load announcements | coaching_announcements, coaching_announcement_reads, coaching_members | `{group_id}` | AnnouncementRow[] | `loading.tsx` | "Nenhum comunicado" | Error banner | 401, 403 |
| `/announcements` | Create | POST `/api/announcements` | `{title, body, group_id, pinned}` | `{id}` | Button spinner | — | Toast error | 400, 403 |
| `/announcements/[id]` | Load detail | coaching_announcements + reads + profiles | `{announcement_id}` | Detail + readers | Inline | — | Error banner | 401, 403, 404 |
| `/announcements/[id]/edit` | Update | PATCH `/api/announcements/[id]` | `{title, body, pinned}` | `void` | Button spinner | — | Toast | 400, 403, 404 |
| `/communications` | — | — | — | — | — | — | — | — |
| `/risk` | Load alerts | coaching_alerts, profiles, coaching_member_status | `{group_id}` | AlertRow[] | `loading.tsx` | "Sem alertas ativos" | Error banner | 401, 403 |
| `/risk` | Resolve alert | UPDATE coaching_alerts SET resolved=true | `{alert_id}` | `void` | Button | — | Toast | 400, 403 |
| `/risk` | Export | GET `/api/export/alerts` | `{from, to}` | CSV | — | — | Toast | 400, 403 |
| `/exports` | Export athletes | GET `/api/export/athletes` | `{from, to}` | CSV download | — | — | Toast error | 401, 403 |
| `/exports` | Export attendance | GET `/api/export/attendance` | `{from, to}` | CSV download | — | — | Toast error | 401, 403 |
| `/exports` | Export engagement | GET `/api/export/engagement` | `{from, to}` | CSV download | — | — | Toast error | 401, 403 |
| `/exports` | Export CRM | GET `/api/export/crm` | `{from, to}` | CSV download | — | — | Toast error | 401, 403 |
| `/exports` | Export alerts | GET `/api/export/alerts` | `{from, to}` | CSV download | — | — | Toast error | 401, 403 |
| `/exports` | Export announcements | GET `/api/export/announcements` | `{from, to}` | CSV download | — | — | Toast error | 401, 403 |
| `/exports` | Export financial | GET `/api/export/financial` | `{from, to}` | CSV download | — | — | Toast error | 401, 403 |
| `/workouts` | Load templates | coaching_workout_templates + blocks count | `{group_id}` | WorkoutTemplate[] | `loading.tsx` | "Nenhum template" | Error banner | 401, 403 |
| `/workouts/analytics` | Load analytics | coaching_workout_executions agg | `{group_id}` | Analytics data | `loading.tsx` | "Sem execuções" | Error banner | 401, 403 |
| `/workouts/assignments` | Load assignments | coaching_workout_assignments | `{group_id}` | Assignment[] | Inline | "Sem atribuições" | Error banner | 401, 403 |
| `/trainingpeaks` | Load TP status | coaching_device_links + fn_tp_sync_status RPC | `{group_id}` | Links + SyncStatus[] | `loading.tsx` | "Nenhum atleta vinculou TP" | Error banner | 401, 403 |
| `/financial` | Load financial KPIs | coaching_financial_ledger, coaching_subscriptions | `{group_id}` | FinancialKpis | `loading.tsx` | "Sem movimentação" | Error banner | 401, 403 |
| `/financial/plans` | Load plans | coaching_plans | `{group_id}` | Plan[] | Inline | "Sem planos" | Error banner | 401, 403 |
| `/financial/subscriptions` | Load subs | coaching_subscriptions | `{group_id}` | Subscription[] | Inline | "Sem assinaturas" | Error banner | 401, 403 |
| `/executions` | Load executions | coaching_workout_executions + profiles + templates | `{group_id}` | Execution[] | Inline | "Sem execuções" | Error banner | 401, 403 |
| `/credits` | Load products | coaching_token_inventory, billing_products | `{group_id}` | Inventory + products | `loading.tsx` | "Sem produtos" | Error banner | 401, 403 |
| `/credits` | Buy | POST `/api/checkout` | `{product_id, group_id, gateway}` | `{checkout_url}` | Button spinner | — | Toast | 400, 403 |
| `/billing` | Load billing | billing_* | `{group_id}` | Billing data | `loading.tsx` | — | Error banner | 401, 403 |
| `/settings` | Load team + config | coaching_members, billing_products, auto_topup_settings, coaching_branding, billing_customers | `{group_id}` | Settings data | `loading.tsx` | "Equipe vazia" | Error banner | 401, 403 |
| `/settings` | Invite team member | POST `/api/team/invite` | `{email, role, group_id}` | `void` | Button spinner | — | Toast error | 400 "já existe", 403, 409 |
| `/settings` | Remove team member | POST `/api/team/remove` | `{member_id}` | `void` | Button spinner | — | Toast error | 400, 403 |
| `/settings` | Save auto-topup | POST `/api/auto-topup` | `{enabled, threshold, product_id, max_per_month}` | `void` | Button spinner | — | Toast | 400, 403 |
| `/settings` | Save branding | POST `/api/branding` | `{primary_color, sidebar_bg, logo_url, ...}` | `void` | Button spinner | — | Toast | 400, 403 |
| `/settings` | Save gateway | POST `/api/gateway-preference` | `{gateway: 'stripe'\|'mercadopago'}` | `void` | Button spinner | — | Toast | 400, 403 |
| `/select-group` | Load groups | coaching_members + coaching_groups | `{user_id}` | Group[] | Spinner | "Sem acesso a grupos" → no-access | Error banner | 401 |
| `/select-group` | Select group | Set cookies `portal_group_id`, `portal_role` | `{group_id}` | redirect to /dashboard | — | — | — | — |

---

## Portal API Routes — Error Contract

| Route | 401 Unauthenticated | 403 Forbidden | 400 Bad Request | 404 Not Found | 409 Conflict | 500 Server Error |
|-------|---------------------|---------------|-----------------|---------------|--------------|------------------|
| `/api/distribute-coins` | "Not authenticated" | "Staff role required" | "Missing amount/user_id" | — | "Insufficient tokens" | "Internal error" |
| `/api/team/invite` | "Not authenticated" | "Admin role required" | "Invalid email" | — | "Already a member" | "Internal error" |
| `/api/team/remove` | "Not authenticated" | "Admin role required" | "Missing member_id" | "Member not found" | — | "Internal error" |
| `/api/verification/evaluate` | "Not authenticated" | "Staff role required" | "Missing user_id" | "Athlete not found" | — | "Internal error" |
| `/api/announcements` | "Not authenticated" | "Staff role required" | "Missing title/body" | — | — | "Internal error" |
| `/api/crm/notes` | "Not authenticated" | "Staff role required" | "Missing note/user_id" | — | — | "Internal error" |
| `/api/crm/tags` | "Not authenticated" | "Staff role required" | "Missing tag_name" | — | — | "Internal error" |
| `/api/clearing` | "Not authenticated" | "Staff role required" | — | — | "Already settled" | "Internal error" |
| `/api/swap` | "Not authenticated" | "Admin role required" | "Invalid params" | — | "Already accepted" | "Internal error" |
| `/api/checkout` | "Not authenticated" | "Admin role required" | "Invalid product" | — | — | "Internal error" |
| `/api/branding` | "Not authenticated" | "Admin role required" | "Invalid color format" | — | — | "Internal error" |
| `/api/auto-topup` | "Not authenticated" | "Admin role required" | "Invalid threshold" | — | — | "Internal error" |
| `/api/custody` | "Not authenticated" | "Admin role required" | "Invalid amount" | — | — | "Internal error" |
| `/api/custody/withdraw` | "Not authenticated" | "Admin role required" | "Invalid amount" | — | "Insufficient balance" | "Internal error" |
| `/api/export/*` | "Not authenticated" | "Staff role required" | — | — | — | "Internal error" |
| `/api/gateway-preference` | "Not authenticated" | "Admin role required" | "Invalid gateway" | — | — | "Internal error" |

---

## Edge Functions — Auth Contract

| Function | Auth Required | Role Required | group_id Validated | Rate Limited |
|----------|--------------|---------------|-------------------|-------------|
| `token-create-intent` | Yes | admin_master, coach | Yes (membership check) | Yes |
| `token-consume-intent` | Yes | Any (athlete or staff) | Yes (intent.group_id match) | Yes |
| `challenge-create` | Yes | Any | No (user-scoped) | Yes |
| `challenge-join` | Yes | Any | No | Yes |
| `clearing-cron` | Service role (cron) | — | All groups | No |
| `lifecycle-cron` | Service role (cron) | — | All groups | No |
| `trainingpeaks-sync` | Service role / user | — | Yes | Yes |
| `eval-athlete-verification` | Yes | Staff | Yes | Yes |
| `matchmake` | Yes | Any | No | Yes |
| `send-push` | Service role | — | — | No |
| `webhook-payments` | Webhook signature | — | — | No |
| `webhook-mercadopago` | Webhook signature | — | — | No |

---

## 5. Cobertura de Paginação

| Página/Tela | Query | Paginação | Método |
|-------------|-------|-----------|--------|
| Portal: /crm | coaching_members | `.range(0, 99)` | Server-side offset |
| Portal: /announcements | coaching_announcements | `.range(0, 49)` | Server-side offset |
| Portal: /workouts | coaching_workout_templates | `.range(0, 49)` | Server-side offset |
| Portal: /risk | coaching_alerts | `.limit(100)` | Fixed limit |
| Portal: /executions | coaching_workout_executions | `.limit(200)` | Fixed limit |
| Portal: /distributions | distributions | `.limit(200)` | Fixed limit |
| Portal: /athletes | coaching_members | Sem paginação | ⚠️ TODO |
| Portal: /attendance | coaching_training_attendance | Sem paginação | ⚠️ TODO |
| App: CRM List | coaching_members | `LoadMoreCrmAthletes` event | Infinite scroll |
| App: Training List | coaching_training_sessions | `.limit(50)` | Fixed limit |
| App: Announcements | coaching_announcements | `.limit(50)` | Fixed limit |
| App: History | sessions | `{limit, offset}` | Cursor |

## 6. Tratamento HTTP 429

| Componente | Proteção | Implementação |
|------------|----------|---------------|
| Flutter App | Client-side rate limiter | `lib/core/utils/rate_limiter.dart` — sliding window, 10 calls/min |
| Portal API | Nenhum rate-limit dedicado | Depende de Supabase platform limits |
| Edge Functions | obs.ts logging | Não implementa 429 server-side |
| Resposta UI (429) | Flutter: "Muitas requisições, aguarde" SnackBar | Portal: não tratado explicitamente |
