# Audit: Feature Map

> Generated: 2026-03-04 | Complete feature inventory mapped to code, DB, and API surfaces.

---

## Legend

- **Entry Point:** Where the user first accesses the feature
- **Screens:** Flutter screens involved (mobile app)
- **Portal Pages:** Next.js pages involved (web dashboard)
- **Edge Functions:** Supabase Edge Functions invoked
- **RPCs:** Postgres functions called directly from client
- **Tables:** Primary database tables used
- **RLS:** Whether Row-Level Security policies are active

---

## 1. Core

### 1.1 Authentication & Onboarding

| Aspect | Detail |
|--------|--------|
| Entry Point | `auth_gate.dart`, `login_screen.dart` |
| Screens | `auth_gate`, `login_screen`, `onboarding_role_screen`, `onboarding_tour_screen`, `welcome_screen` |
| Portal Pages | `login/page.tsx`, `no-access/page.tsx`, `select-group/page.tsx` |
| Edge Functions | `validate-social-login`, `set-user-role`, `verify-session` |
| RPCs | `handle_new_user()`, `handle_new_user_gamification()` |
| Tables | `profiles`, `profile_progress`, `wallets` |
| Auth Methods | Google Sign-In, Apple Sign-In, anonymous mode |
| RLS | Yes |

### 1.2 User Profile

| Aspect | Detail |
|--------|--------|
| Entry Point | More > Meu Perfil |
| Screens | `profile_screen` |
| Edge Functions | `complete-social-profile`, `delete-account` |
| RPCs | `fn_search_users()` |
| Tables | `profiles` |
| RLS | Yes |

### 1.3 Push Notifications

| Aspect | Detail |
|--------|--------|
| Entry Point | Background/passive |
| Implementation | `core/push/push_navigation_handler.dart` |
| Edge Functions | `send-push`, `notify-rules` |
| Tables | `device_tokens`, `notification_log` |
| RLS | Yes |

### 1.4 Settings

| Aspect | Detail |
|--------|--------|
| Entry Point | More > Configurações |
| Screens | `settings_screen` |
| Portal Pages | `(portal)/settings/page.tsx` |
| Features | Theme (light/dark), units, Strava connection, language |
| RLS | N/A (local preferences + profile row) |

---

## 2. Running

### 2.1 Live Run Tracking

| Aspect | Detail |
|--------|--------|
| Entry Point | Bottom tab "Hoje" (athlete) |
| Screens | `today_screen`, `map_screen`, `run_summary_screen`, `run_details_screen`, `run_replay_screen` |
| Datasources | `geolocator_location_stream`, `foreground_task_config`, `health_platform_service`, `audio_coach_service` |
| BLoCs | `tracking` |
| Tables | `sessions`, `sessions_archive` |
| Features | GPS tracking, audio coach (TTS), heart rate zones, pace alerts, ghost racing |
| Offline | Sessions stored in Isar, synced when online |
| RLS | Yes |

### 2.2 Run History

| Aspect | Detail |
|--------|--------|
| Entry Point | Bottom tab "Histórico" (athlete) |
| Screens | `history_screen`, `run_details_screen`, `run_replay_screen` |
| Tables | `sessions`, `sessions_archive` |
| RLS | Yes |

### 2.3 Parks & Segments

| Aspect | Detail |
|--------|--------|
| Entry Point | Athlete Dashboard > Parks section |
| Screens | `my_parks_screen` (feature module) |
| RPCs | `fn_refresh_park_leaderboard()`, `backfill_park_activities()` |
| Tables | `parks`, `park_activities`, `park_segments`, `park_leaderboard` |
| Features | Auto-detect park from GPS, park leaderboard, segment records |
| RLS | Yes |

### 2.4 Recovery

| Aspect | Detail |
|--------|--------|
| Entry Point | Post-run flow |
| Screens | `recovery_screen` |
| RLS | N/A |

---

## 3. Coaching (Assessoria)

### 3.1 Coaching Groups

| Aspect | Detail |
|--------|--------|
| Entry Point (Athlete) | Dashboard > Minha Assessoria; More > Minha Assessoria |
| Entry Point (Staff) | Staff Dashboard > Atletas |
| Screens | `my_assessoria_screen`, `join_assessoria_screen`, `coaching_groups_screen`, `coaching_group_details_screen` |
| Portal Pages | `(portal)/athletes/page.tsx`, `(portal)/dashboard/page.tsx` |
| BLoCs | `coaching_groups`, `coaching_group_details`, `my_assessoria` |
| RPCs | `fn_create_assessoria()`, `fn_request_join()`, `fn_approve_join_request()`, `fn_reject_join_request()`, `fn_remove_member()`, `fn_switch_assessoria()`, `fn_search_coaching_groups()` |
| Tables | `coaching_groups`, `coaching_members`, `coaching_invites` |
| RLS | Yes |

### 3.2 Coach Rankings

| Aspect | Detail |
|--------|--------|
| Screens | `group_rankings_screen`, `group_evolution_screen` |
| BLoCs | `coaching_rankings`, `group_evolution` |
| RPCs | `compute_leaderboard_assessoria()` |
| Tables | `coaching_rankings`, `coaching_ranking_entries` |
| RLS | Yes |

### 3.3 Coach Insights (AI)

| Aspect | Detail |
|--------|--------|
| Screens | `coach_insights_screen` |
| BLoCs | `coach_insights` |
| Tables | `coach_insights`, `athlete_baselines`, `athlete_trends` |
| RLS | Yes |

### 3.4 Assessoria Feed

| Aspect | Detail |
|--------|--------|
| Screens | `assessoria_feed_screen` |
| BLoCs | `assessoria_feed` |
| RPCs | `fn_get_assessoria_feed()` |
| Tables | `assessoria_feed` |
| RLS | Yes |

### 3.5 Partnerships

| Aspect | Detail |
|--------|--------|
| Screens | `partner_assessorias_screen` |
| RPCs | `fn_list_partnerships()`, `fn_partner_championships()`, `fn_request_partnership()`, `fn_respond_partnership()`, `fn_search_assessorias()` |
| Tables | `assessoria_partnerships` |
| RLS | Yes |

### 3.6 Staff Setup & Join Requests

| Aspect | Detail |
|--------|--------|
| Screens | `staff_setup_screen`, `staff_join_requests_screen` |
| RPCs | `fn_staff_onboarding`, `fn_join_as_professor()` |
| Tables | `coaching_members`, `coaching_invites` |
| RLS | Yes |

---

## 4. Training

### 4.1 Training Sessions & Attendance

| Aspect | Detail |
|--------|--------|
| Entry Point (Staff) | Staff Dashboard; Portal > Presença |
| Screens (Staff) | `staff_training_create_screen`, `staff_training_detail_screen`, `staff_training_list_screen`, `staff_training_scan_screen` |
| Screens (Athlete) | `athlete_attendance_screen`, `athlete_checkin_qr_screen` |
| Portal Pages | `(portal)/attendance/page.tsx`, `(portal)/attendance/[id]/page.tsx`, `(portal)/attendance-analytics/page.tsx` |
| BLoCs | `training_list`, `training_detail`, `checkin` |
| RPCs | `fn_mark_attendance()`, `fn_issue_checkin_token()` |
| Tables | `coaching_training_sessions`, `coaching_training_attendance` |
| RLS | Yes |

### 4.2 Athlete Verification

| Aspect | Detail |
|--------|--------|
| Entry Point | Dashboard banner; Verification gate on monetary features |
| Screens | `athlete_verification_screen` |
| Portal Pages | `(portal)/verification/page.tsx` |
| Edge Functions | `eval-athlete-verification`, `eval-verification-cron`, `verify-session` |
| RPCs | `eval_athlete_verification()`, `get_verification_state()`, `is_user_verified()`, `eval_my_verification()` |
| Tables | `athlete_verification` |
| Gate | Required before challenges with entry fees |
| RLS | Yes |

---

## 5. Workouts

### 5.1 Workout Builder & Templates

| Aspect | Detail |
|--------|--------|
| Entry Point (Staff) | Portal > Treinos |
| Screens (Staff) | `staff_workout_builder_screen`, `staff_workout_templates_screen` |
| Portal Pages | `(portal)/workouts/page.tsx`, `(portal)/workouts/analytics/page.tsx` |
| BLoCs | `workout_builder` |
| RPCs | `fn_assign_workout()` |
| Tables | `coaching_workout_templates`, `coaching_workout_blocks` |
| RLS | Yes |

### 5.2 Workout Assignments

| Aspect | Detail |
|--------|--------|
| Screens (Staff) | `staff_workout_assign_screen` |
| Screens (Athlete) | `athlete_workout_day_screen`, `athlete_training_list_screen`, `athlete_log_execution_screen` |
| Portal Pages | `(portal)/workouts/assignments/page.tsx` |
| BLoCs | `workout_assignments` |
| Tables | `coaching_workout_assignments` |
| RLS | Yes |

### 5.3 Workout Delivery (to Watch)

| Aspect | Detail |
|--------|--------|
| Screens (Staff) | via Portal > Entrega Treinos |
| Screens (Athlete) | `athlete_delivery_screen`, `athlete_device_link_screen` |
| Portal Pages | `(portal)/delivery/page.tsx` |
| RPCs | `fn_create_delivery_batch()`, `fn_generate_delivery_items()`, `fn_mark_item_published()`, `fn_athlete_confirm_item()` |
| Tables | `workout_delivery_batches`, `workout_delivery_items`, `workout_delivery_events`, `coaching_device_links` |
| RLS | Yes |

### 5.4 Workout Execution (Wearables)

| Aspect | Detail |
|--------|--------|
| Screens (Athlete) | `athlete_log_execution_screen` |
| RPCs | `fn_generate_workout_payload()`, `fn_import_execution()` |
| Tables | `coaching_workout_executions`, `coaching_device_links` |
| Portal Pages | `(portal)/executions/page.tsx` |
| RLS | Yes |

---

## 6. Gamification

### 6.1 Progression (XP & Levels)

| Aspect | Detail |
|--------|--------|
| Entry Point | Progress Hub > Nível e XP |
| Screens | `progression_screen`, `progress_hub_screen` |
| BLoCs | `progression` |
| Edge Functions | `calculate-progression` |
| RPCs | `increment_profile_progress()`, `fn_update_streak()`, `fn_generate_weekly_goal()`, `fn_check_weekly_goal()`, `fn_get_daily_session_xp()`, `fn_count_daily_sessions()`, `fn_mark_progression_applied()` |
| Tables | `profile_progress`, `xp_transactions`, `season_progress`, `weekly_goals` |
| Views | `v_user_progression`, `v_weekly_progress` |
| RLS | Yes |

### 6.2 Badges

| Aspect | Detail |
|--------|--------|
| Entry Point | Progress Hub > Conquistas |
| Screens | `badges_screen` |
| Portal Pages | `(portal)/badges/page.tsx`, `platform/conquistas/page.tsx` |
| BLoCs | `badges` |
| Edge Functions | `evaluate-badges`, `champ-activate-badge` |
| RPCs | `evaluate_badges_retroactive()` |
| Tables | `badges`, `badge_awards`, `coaching_badge_inventory`, `championship_badges` |
| RLS | Yes |

### 6.3 Missions

| Aspect | Detail |
|--------|--------|
| Entry Point | Progress Hub > Missões |
| Screens | `missions_screen` |
| BLoCs | `missions` |
| RPCs | `generate_weekly_goal()` |
| Tables | `missions`, `mission_progress`, `seasons` |
| RLS | Yes |

### 6.4 Leaderboards

| Aspect | Detail |
|--------|--------|
| Entry Point | Progress Hub > Ranking |
| Screens | `leaderboards_screen`, `streaks_leaderboard_screen` |
| BLoCs | `leaderboards` |
| Edge Functions | `compute-leaderboard` |
| RPCs | `compute_leaderboard_global_weekly()`, `compute_leaderboard_assessoria()`, `compute_leaderboard_championship()`, `compute_leaderboard_global()` |
| Tables | `leaderboards`, `leaderboard_entries` |
| RLS | Yes |

### 6.5 Leagues

| Aspect | Detail |
|--------|--------|
| Entry Point | Progress Hub > Liga |
| Screens | `league_screen` |
| Portal Pages | `platform/liga/page.tsx` |
| Edge Functions | `league-list`, `league-snapshot` |
| Tables | `league_seasons`, `league_enrollments`, `league_snapshots` |
| RLS | Yes |

### 6.6 Challenges (1v1 & Team)

| Aspect | Detail |
|--------|--------|
| Entry Point | Dashboard > Meus Desafios |
| Screens | `challenges_list_screen`, `challenge_details_screen`, `challenge_create_screen`, `challenge_join_screen`, `challenge_invite_screen`, `challenge_result_screen`, `matchmaking_screen` |
| BLoCs | `challenges` |
| Edge Functions | `challenge-create`, `challenge-get`, `challenge-join`, `challenge-list-mine`, `challenge-invite-group`, `challenge-accept-group-invite`, `settle-challenge`, `matchmake` |
| RPCs | `fn_enforce_challenge_limits()`, `fn_enforce_participant_limits()`, `fn_expire_queue_entries()`, `fn_compute_skill_bracket()`, `fn_try_match()`, `debit_wallet_checked()` |
| Tables | `challenges`, `challenge_participants`, `challenge_results`, `challenge_run_bindings`, `challenge_queue`, `challenge_team_invites` |
| Staff Screens | `staff_challenge_invites_screen` |
| RLS | Yes |

### 6.7 Championships

| Aspect | Detail |
|--------|--------|
| Entry Point (Athlete) | Dashboard > Campeonatos |
| Entry Point (Staff) | Staff Dashboard > Campeonatos |
| Screens | `athlete_championships_screen`, `athlete_championship_ranking_screen`, `staff_championship_templates_screen`, `staff_championship_manage_screen`, `staff_championship_invites_screen` |
| Edge Functions | `champ-create`, `champ-list`, `champ-open`, `champ-enroll`, `champ-invite`, `champ-accept-invite`, `champ-cancel`, `champ-participant-list`, `champ-update-progress`, `champ-lifecycle`, `champ-activate-badge` |
| Tables | `championship_templates`, `championships`, `championship_invites`, `championship_participants`, `championship_badges` |
| RLS | Yes |

### 6.8 Running DNA & Wrapped

| Aspect | Detail |
|--------|--------|
| Entry Point | Progress Hub |
| Screens | `running_dna_screen`, `wrapped_screen` |
| Edge Functions | `generate-running-dna`, `generate-wrapped` |
| Tables | `running_dna`, `user_wrapped` |
| RLS | Yes |

### 6.9 Personal Evolution

| Aspect | Detail |
|--------|--------|
| Entry Point | Progress Hub > Minha Evolução |
| Screens | `personal_evolution_screen`, `athlete_evolution_screen`, `athlete_my_evolution_screen`, `athlete_my_status_screen` |
| BLoCs | `athlete_evolution`, `athlete_profile` |
| RLS | Yes |

---

## 7. Financial

### 7.1 Wallet & OmniCoins

| Aspect | Detail |
|--------|--------|
| Entry Point (Athlete) | Dashboard > Meus Créditos |
| Screens | `wallet_screen` |
| BLoCs | `wallet` |
| RPCs | `increment_wallet_balance()`, `increment_wallet_pending()`, `release_pending_to_balance()`, `reconcile_wallet()`, `reconcile_all_wallets()` |
| Tables | `wallets`, `coin_ledger` |
| RLS | Yes |

### 7.2 Token Inventory & QR Operations

| Aspect | Detail |
|--------|--------|
| Entry Point (Staff) | Staff Dashboard > Créditos; More > Operações QR |
| Screens | `staff_credits_screen`, `staff_qr_hub_screen`, `staff_generate_qr_screen`, `staff_scan_qr_screen`, `athlete_checkin_qr_screen` |
| BLoCs | `staff_qr` |
| Edge Functions | `token-create-intent`, `token-consume-intent` |
| RPCs | `decrement_token_inventory()`, `increment_inventory_burned()`, `fn_credit_badge_inventory()`, `fn_decrement_badge_inventory()` |
| Tables | `coaching_token_inventory`, `token_intents` |
| RLS | Yes |

### 7.3 Billing & Purchases

| Aspect | Detail |
|--------|--------|
| Entry Point | Portal > Billing |
| Portal Pages | `(portal)/billing/page.tsx`, `(portal)/billing/success/page.tsx`, `(portal)/billing/cancelled/page.tsx` |
| API Routes | `api/checkout`, `api/billing-portal`, `api/auto-topup`, `api/gateway-preference` |
| Edge Functions | `create-checkout-session`, `create-checkout-mercadopago`, `create-portal-session`, `webhook-payments`, `webhook-mercadopago`, `auto-topup-check`, `auto-topup-cron`, `list-purchases`, `process-refund` |
| RPCs | `get_billing_limits()`, `check_daily_token_usage()`, `fn_fulfill_purchase()`, `fn_credit_institution()` |
| Tables | `billing_customers`, `billing_products`, `billing_purchases`, `billing_events`, `billing_limits`, `billing_auto_topup_settings`, `billing_refund_requests`, `institution_credit_purchases` |
| Gateways | Stripe + MercadoPago |
| RLS | Yes |

### 7.4 Clearing & Disputes

| Aspect | Detail |
|--------|--------|
| Entry Point | Portal > Compensações |
| Screens (Staff) | `staff_disputes_screen` |
| Portal Pages | `(portal)/clearing/page.tsx` |
| Edge Functions | `clearing-cron`, `clearing-confirm-sent`, `clearing-confirm-received`, `clearing-open-dispute` |
| Tables | `clearing_weeks`, `clearing_cases`, `clearing_case_items`, `clearing_case_events` |
| RLS | Yes |

### 7.5 Financial Management (Portal)

| Aspect | Detail |
|--------|--------|
| Portal Pages | `(portal)/financial/page.tsx`, `(portal)/financial/plans/page.tsx`, `(portal)/financial/subscriptions/page.tsx` |
| RPCs | `fn_create_ledger_entry()`, `fn_update_subscription_status()` |
| Tables | `coaching_plans`, `coaching_subscriptions`, `coaching_financial_ledger` |
| RLS | Yes |

### 7.6 Custody & Swap

| Aspect | Detail |
|--------|--------|
| Portal Pages | `(portal)/custody/page.tsx`, `(portal)/swap/page.tsx`, `(portal)/fx/page.tsx` |
| API Routes | `api/custody`, `api/custody/webhook`, `api/custody/withdraw`, `api/swap` |
| Roles | `admin_master` only |
| RLS | Yes |

---

## 8. Social

### 8.1 Friends

| Aspect | Detail |
|--------|--------|
| Entry Point | More > Meus Amigos |
| Screens | `friends_screen`, `friend_profile_screen`, `invite_friends_screen`, `invite_qr_screen` |
| BLoCs | `friends` |
| RPCs | `fn_friends_activity_feed()` |
| Tables | `friendships` |
| RLS | Yes |

### 8.2 Activity Feed

| Aspect | Detail |
|--------|--------|
| Screens | `friends_activity_feed_screen` |
| Status | **Coming soon** (marked in UI) |
| RLS | Yes |

### 8.3 Groups

| Aspect | Detail |
|--------|--------|
| Screens | `groups_screen`, `group_details_screen`, `group_members_screen`, `group_events_screen`, `group_evolution_screen`, `group_rankings_screen` |
| BLoCs | `groups` |
| Tables | `groups`, `group_members`, `group_goals` |
| RLS | Yes |

### 8.4 Events & Races

| Aspect | Detail |
|--------|--------|
| Screens | `events_screen`, `event_details_screen`, `race_event_details_screen` |
| BLoCs | `events`, `race_event_details`, `race_events` |
| Tables | `events`, `event_participations`, `race_events`, `race_participations`, `race_results` |
| RLS | Yes |

---

## 9. CRM (Coach Relationship Management)

| Aspect | Detail |
|--------|--------|
| Entry Point | Portal > CRM Atletas |
| Screens (Staff) | `staff_crm_list_screen`, `staff_athlete_profile_screen` |
| Portal Pages | `(portal)/crm/page.tsx`, `(portal)/crm/at-risk/page.tsx`, `(portal)/crm/[userId]/page.tsx` |
| API Routes | `api/crm`, `api/crm/notes`, `api/crm/tags` |
| RPCs | `fn_upsert_member_status()` |
| Tables | `coaching_tags`, `coaching_athlete_tags`, `coaching_athlete_notes`, `coaching_member_status` |
| RLS | Yes |

---

## 10. Communication

### 10.1 Announcements (Mural)

| Aspect | Detail |
|--------|--------|
| Screens (Staff) | `announcement_create_screen`, `announcement_detail_screen`, `announcement_feed_screen` |
| Portal Pages | `(portal)/announcements/page.tsx`, `(portal)/announcements/[id]/page.tsx`, `(portal)/announcements/[id]/edit/page.tsx` |
| API Routes | `api/announcements`, `api/announcements/[id]` |
| RPCs | `fn_mark_announcement_read()`, `fn_announcement_read_stats()` |
| Tables | `coaching_announcements`, `coaching_announcement_reads` |
| RLS | Yes |

### 10.2 Communications Hub

| Aspect | Detail |
|--------|--------|
| Portal Pages | `(portal)/communications/page.tsx` |
| Edge Functions | `send-push`, `notify-rules` |
| Tables | `notification_log`, `device_tokens` |
| RLS | Yes |

### 10.3 Support Tickets

| Aspect | Detail |
|--------|--------|
| Screens | `support_screen`, `support_ticket_screen` |
| Portal Pages | `platform/support/page.tsx`, `platform/support/[id]/page.tsx` |
| RLS | Yes |

---

## 11. Analytics

### 11.1 Coach Analytics

| Aspect | Detail |
|--------|--------|
| Portal Pages | `(portal)/engagement/page.tsx`, `(portal)/attendance-analytics/page.tsx`, `(portal)/workouts/analytics/page.tsx`, `(portal)/risk/page.tsx` |
| Edge Functions | `submit-analytics` |
| RPCs | `compute_coaching_kpis_daily()`, `compute_coaching_alerts_daily()` |
| Tables | `analytics_submissions`, `athlete_baselines`, `athlete_trends`, `coach_insights` |
| RLS | Yes |

### 11.2 Staff Performance & Retention

| Aspect | Detail |
|--------|--------|
| Screens | `staff_performance_screen`, `staff_retention_dashboard_screen`, `staff_weekly_report_screen` |
| Portal Pages | `(portal)/engagement/page.tsx` |
| RLS | Yes |

### 11.3 Exports

| Aspect | Detail |
|--------|--------|
| Portal Pages | `(portal)/exports/page.tsx` |
| API Routes | `api/export/alerts`, `api/export/announcements`, `api/export/athletes`, `api/export/attendance`, `api/export/crm`, `api/export/engagement`, `api/export/financial` |
| RLS | Yes |

### 11.4 Audit Log

| Aspect | Detail |
|--------|--------|
| Portal Pages | `(portal)/audit/page.tsx` |
| Tables | `portal_audit_log` |
| RPCs | `fn_get_user_id_by_email()` |
| RLS | Yes |

---

## 12. Integrations

### 12.1 Strava

| Aspect | Detail |
|--------|--------|
| Entry Point | Settings > Strava |
| Feature Module | `features/strava/` (data, domain, presentation) |
| Edge Functions | `strava-webhook`, `strava-register-webhook` |
| RPCs | `backfill_strava_sessions()` |
| Tables | `strava_connections`, `strava_activity_history` |
| RLS | Yes |

### 12.2 TrainingPeaks

| Aspect | Detail |
|--------|--------|
| Portal Pages | `(portal)/trainingpeaks/page.tsx` |
| Edge Functions | `trainingpeaks-oauth`, `trainingpeaks-sync` |
| RPCs | `fn_push_to_trainingpeaks()`, `fn_tp_sync_status()` |
| Tables | `coaching_tp_sync` |
| RLS | Yes |

### 12.3 Health (Apple Health / Google Fit)

| Aspect | Detail |
|--------|--------|
| Feature Module | `features/health_export/` |
| Datasources | `health_platform_service.dart`, `health_steps_source.dart` |
| Package | `health: ^13.3.1` |

### 12.4 Wearables (BLE)

| Aspect | Detail |
|--------|--------|
| Feature Module | `features/wearables_ble/` |
| Package | `flutter_blue_plus: ^2.1.1` |
| Screens | `athlete_device_link_screen` |

### 12.5 Watch Bridge

| Aspect | Detail |
|--------|--------|
| Feature Module | `features/watch_bridge/` |
| Watch (Wear OS) | `DataLayerManager.kt`, `WearListenerService.kt`, `OfflineSessionStore.kt` |
| Watch (Apple) | Scaffolded, not yet implemented |

---

## 13. Platform Admin

| Aspect | Detail |
|--------|--------|
| Portal Pages | `platform/page.tsx`, `platform/assessorias/page.tsx`, `platform/conquistas/page.tsx`, `platform/feature-flags/page.tsx`, `platform/fees/page.tsx`, `platform/financeiro/page.tsx`, `platform/invariants/page.tsx`, `platform/liga/page.tsx`, `platform/produtos/page.tsx`, `platform/reembolsos/page.tsx`, `platform/support/page.tsx`, `platform/support/[id]/page.tsx` |
| API Routes | `api/platform/assessorias`, `api/platform/feature-flags`, `api/platform/fees`, `api/platform/invariants`, `api/platform/liga`, `api/platform/products`, `api/platform/refunds`, `api/platform/support` |
| Role Required | `platform_admin` |
| Features | Global assessoria management, badge catalog, fee configuration, product catalog, refund processing, league admin, feature flags, system invariants, support ticket triage |

---

## 14. Portal Sidebar — Full Navigation Map

### NAV_ITEMS (Coach/Admin)

| # | Href | Label | Roles |
|---|------|-------|-------|
| 1 | `/dashboard` | Dashboard | admin_master, coach, assistant |
| 2 | `/custody` | Custódia | admin_master |
| 3 | `/clearing` | Compensações | admin_master, coach |
| 4 | `/swap` | Swap de Lastro | admin_master |
| 5 | `/fx` | Conversão Cambial | admin_master |
| 6 | `/badges` | Badges | admin_master, coach |
| 7 | `/audit` | Auditoria | admin_master, coach |
| 8 | `/distributions` | Distribuições | admin_master, coach |
| 9 | `/athletes` | Atletas | admin_master, coach, assistant |
| 10 | `/verification` | Verificação | admin_master, coach, assistant |
| 11 | `/engagement` | Engajamento | admin_master, coach, assistant |
| 12 | `/attendance` | Presença | admin_master, coach, assistant |
| 13 | `/crm` | CRM Atletas | admin_master, coach, assistant |
| 14 | `/announcements` | Mural | admin_master, coach, assistant |
| 15 | `/communications` | Comunicação | admin_master, coach |
| 16 | `/attendance-analytics` | Análise Presença | admin_master, coach, assistant |
| 17 | `/risk` | Alertas/Risco | admin_master, coach |
| 18 | `/exports` | Exports | admin_master, coach |
| 19 | `/workouts` | Treinos | admin_master, coach |
| 20 | `/workouts/analytics` | Análise Treinos | admin_master, coach |
| 21 | `/delivery` | Entrega Treinos | admin_master, coach |
| 22 | `/trainingpeaks` | TrainingPeaks | admin_master, coach (feature-flag gated) |
| 23 | `/financial` | Financeiro | admin_master, coach |
| 24 | `/executions` | Execuções | admin_master, coach, assistant |
| 25 | `/settings` | Configurações | admin_master, coach, assistant |

### PLATFORM_ITEMS

| # | Href | Label | Roles |
|---|------|-------|-------|
| 1 | `/platform/assessorias` | Admin Plataforma | platform_admin |

---

## 15. Feature Completeness Summary

| Category | Features | Tables | Edge Fns | Screens | Portal Pages |
|----------|----------|--------|----------|---------|-------------|
| Core | 4 | 4 | 4 | 7 | 4 |
| Running | 4 | 6 | 0 | 7 | 0 |
| Coaching | 6 | 5 | 0 | 8 | 2 |
| Training | 2 | 3 | 3 | 7 | 4 |
| Workouts | 4 | 8 | 0 | 8 | 5 |
| Gamification | 9 | 22 | 12 | 18 | 3 |
| Financial | 6 | 17 | 10 | 5 | 8 |
| Social | 4 | 7 | 0 | 10 | 0 |
| CRM | 1 | 4 | 0 | 2 | 3 |
| Communication | 3 | 4 | 2 | 4 | 5 |
| Analytics | 4 | 5 | 1 | 3 | 5 |
| Integrations | 5 | 3 | 5 | 1 | 1 |
| Platform Admin | 1 | 2 | 0 | 0 | 12 |
| **TOTAL** | **53** | **~90** | **37** | **80** | **52** |
