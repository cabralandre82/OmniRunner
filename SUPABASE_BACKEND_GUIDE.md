# SUPABASE_BACKEND_GUIDE.md — Omni Runner Backend

> **Atualizado:** 2026-02-21 (Phase 35.99.0 — QA completo)
> **Projeto:** Omni Runner (app de corrida com gamificação B2B)
> **Stack Backend:** Supabase (Postgres + Auth + Storage + Edge Functions + pg_cron)
> **Stack Mobile:** Flutter (Dart) — offline-first com Isar local
> **Stack Portal:** Next.js 14 (App Router) + Tailwind CSS + shadcn/ui — portal B2B web
> **Objetivo:** Documento de handoff completo para integração backend/frontend/portal

---

## 1. VISÃO GERAL DA ARQUITETURA

```
┌─────────────────────────────────────────────────────────────┐
│                    Flutter App (Dart)                        │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────────┐ │
│  │  Isar DB │  │  BLoCs   │  │ Repos    │  │ Supabase   │ │
│  │ (offline)│←→│ (state)  │←→│ (impl)   │←→│ Flutter SDK│ │
│  └──────────┘  └──────────┘  └──────────┘  └─────┬──────┘ │
└───────────────────────────────────────────────────┼────────┘
                                                    │
┌───────────────────────────────────────────────────┼────────┐
│              Next.js Portal (portal/)             │        │
│  ┌──────────┐  ┌──────────┐  ┌──────────────┐    │        │
│  │ App      │  │ API      │  │ Supabase     │    │        │
│  │ Router   │←→│ Routes   │←→│ JS Client    │────┤        │
│  └──────────┘  └──────────┘  └──────────────┘    │        │
└──────────────────────────────────────────────────┼────────┘
                                                    │
                              ┌──────────────────────┼────────────┐
                              │          Supabase Cloud           │
                              │  ┌──────────┐  ┌──────────────┐  │
                              │  │  Auth     │  │  Postgres DB │  │
                              │  │ (JWT)     │  │ (66 tables)  │  │
                              │  └──────────┘  └──────────────┘  │
                              │  ┌──────────┐  ┌──────────────┐  │
                              │  │  Storage  │  │ Edge Funcs   │  │
                              │  │ (GPS pts) │  │ (54 Deno/TS) │  │
                              │  └──────────┘  └──────────────┘  │
                              │  ┌──────────┐  ┌──────────────┐  │
                              │  │  pg_cron  │  │  Stripe      │  │
                              │  │ (hourly)  │  │ (payments)   │  │
                              │  └──────────┘  └──────────────┘  │
                              └──────────────────────────────────┘
```

### Princípios

- **Offline-first**: Isar é a fonte primária de verdade no device; Supabase sincroniza em background.
- **Server wins**: Em conflitos, dados do servidor prevalecem para features sociais/competitivas.
- **RLS everywhere**: Toda tabela tem Row Level Security ativa. Sem exceções.
- **Edge Functions para lógica crítica**: Cálculo de badges, settlement de desafios, anti-cheat, leaderboards, billing e refunds rodam no servidor.
- **Billing fora do app**: Compra de créditos é exclusivamente via portal web B2B (Apple/Google compliance).
- **Fail-open para rate limits**: Se o RPC de rate limit falhar, a operação prossegue (rate limiting já protege contra volume).

---

## 2. AUTENTICAÇÃO

### 2.1 Provedores Configurados

| Provedor | Identificador Supabase | Status |
|----------|----------------------|--------|
| **Google** | `auth.external.google` | Obrigatório |
| **Apple** | `auth.external.apple` | Obrigatório (App Store requer) |
| **Email/Password** | `auth.email` | Habilitado (fallback) |
| **Facebook/Instagram** | `auth.external.facebook` | Ativo — nativo (Meta OAuth cobre ambos) |
| **TikTok** | Edge Function `validate-social-login` | Planejado — Supabase não suporta nativamente |
| **Anonymous** | `enable_anonymous_sign_ins` | Habilitado (onboarding) |

### 2.2 Configuração no Dashboard Supabase

#### Google Sign-In

1. Criar projeto no Google Cloud Console
2. Ativar Google Identity API
3. Criar OAuth 2.0 Client ID (tipo: Web application)
4. Redirect URI: `https://<project>.supabase.co/auth/v1/callback`
5. No Supabase Dashboard → Authentication → Providers → Google:
   - Client ID: `<google_client_id>`
   - Client Secret: `<google_client_secret>`
6. No Flutter, usar `google_sign_in` para obter `idToken` e passar para `supabase.auth.signInWithIdToken()`

#### Apple Sign-In

1. Registrar App ID no Apple Developer Portal com "Sign in with Apple" capability
2. Criar Service ID para web-based auth flow
3. Gerar Key (P8) para autenticação server-side
4. No Supabase Dashboard → Authentication → Providers → Apple:
   - Client ID: `<apple_service_id>`
   - Secret: `<apple_p8_key_content>`
5. No Flutter, usar `sign_in_with_apple` para obter `identityToken` e passar para `supabase.auth.signInWithIdToken()`

#### Facebook / Instagram Sign-In

1. Criar app no Facebook Developers Console (tipo Consumer)
2. Habilitar Facebook Login + Instagram Basic Display
3. No Supabase Dashboard → Authentication → Providers → Facebook:
   - Client ID: `<facebook_app_id>`
   - Client Secret: `<facebook_app_secret>`
4. Redirect URI: `https://<project>.supabase.co/auth/v1/callback`
5. No Flutter, usar `supabase.auth.signInWithOAuth(OAuthProvider.facebook)` ou SDK nativo
6. O token Meta dá acesso ao perfil Facebook e, se autorizado, ao Instagram do usuário

> **Instagram**: Meta OAuth é o caminho nativo do Supabase para Instagram.
> Não existe provider separado "Instagram" no Supabase.

#### TikTok Sign-In (Custom — não nativo)

Supabase **não suporta** TikTok como provider OAuth nativo. A integração requer:

1. SDK nativo TikTok no Flutter obtém authorization code
2. Edge Function `validate-social-login` troca code → access_token → user info
3. Edge Function cria/vincula sessão Supabase via `supabase.auth.admin`
4. Detalhes em `docs/SOCIAL_AUTH_SETUP.md` §8 e §11

### 2.3 Mapeamento Auth → Profiles

Quando um usuário faz signup (qualquer provedor), o trigger `on_auth_user_created` cria automaticamente:

```sql
-- Trigger function (já no schema)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, display_name, avatar_url)
  VALUES (
    NEW.id,
    COALESCE(
      NEW.raw_user_meta_data->>'full_name',
      NEW.raw_user_meta_data->>'name',
      'Runner'
    ),
    NEW.raw_user_meta_data->>'avatar_url'
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

Também cria automaticamente `wallets` e `profile_progress` via `on_auth_user_gamification`.

### 2.4 Fluxo no Flutter

```dart
// Google
final googleUser = await GoogleSignIn().signIn();
final googleAuth = await googleUser!.authentication;
await supabase.auth.signInWithIdToken(
  provider: OAuthProvider.google,
  idToken: googleAuth.idToken!,
  accessToken: googleAuth.accessToken,
);

// Apple
final credential = await SignInWithApple.getAppleIDCredential(...);
await supabase.auth.signInWithIdToken(
  provider: OAuthProvider.apple,
  idToken: credential.identityToken!,
);
```

### 2.5 config.toml (atualizar para produção)

```toml
[auth.external.google]
enabled = true
client_id = "env(GOOGLE_CLIENT_ID)"
secret = "env(GOOGLE_CLIENT_SECRET)"
redirect_uri = ""
skip_nonce_check = false

[auth.external.apple]
enabled = true
client_id = "env(APPLE_SERVICE_ID)"
secret = "env(APPLE_P8_SECRET)"
redirect_uri = ""
skip_nonce_check = false
```

---

## 3. ESQUEMA DO BANCO DE DADOS

### 3.1 Mapa de Tabelas (61 tabelas)

```
CORE (3)
├── profiles               — Perfil público (extends auth.users) + active_coaching_group_id + onboarding_state/user_role/created_via
├── sessions               — Sessões de corrida sincronizadas
└── seasons                — Temporadas de 90 dias

GAMIFICAÇÃO (9)
├── badges                 — Catálogo de badges (admin-managed)
├── badge_awards           — Badges desbloqueados por usuários
├── profile_progress       — Progressão denormalizada (XP, streaks, stats)
├── xp_transactions        — Log imutável de créditos XP
├── season_progress        — Progresso por temporada por usuário
├── wallets                — Saldo de OmniCoins (balance_coins + pending_coins)
├── coin_ledger            — Log imutável de transações de Coins
├── missions               — Catálogo de missões
├── mission_progress       — Progresso do usuário em missões
└── weekly_goals           — Metas semanais por atleta

SOCIAL (8)
├── friendships            — Amizades bidirecionais
├── groups                 — Grupos de corrida
├── group_members          — Membros dos grupos
├── group_goals            — Metas coletivas de grupo
├── leaderboards           — Snapshots de leaderboard
├── leaderboard_entries    — Linhas individuais dos leaderboards
├── events                 — Eventos virtuais de corrida
└── event_participations   — Participação em eventos

DESAFIOS (4)
├── challenges             — Desafios 1v1 e grupo (triggers: max 20/day/user)
├── challenge_participants — Participantes (triggers: max 5 active + 10 pending/athlete)
├── challenge_results      — Resultados finalizados
└── challenge_run_bindings — Auditoria sessão↔desafio

COACHING — Assessoria (12)
├── coaching_groups        — Grupos de assessoria (invite_code, invite_enabled, approval_status)
├── coaching_members       — Membros (admin_master/professor/assistente/atleta)
├── coaching_invites       — Convites para grupos de coaching
├── coaching_token_inventory — Estoque de tokens por grupo (never negative)
├── token_intents          — Intents QR (OPEN/CONSUMED/EXPIRED/CANCELED)
├── coaching_rankings      — Rankings de coaching
├── coaching_ranking_entries — Entradas dos rankings
├── race_events            — Eventos presenciais do coaching
├── race_participations    — Participação em corridas
├── race_results           — Resultados de corridas
└── assessoria_feed        — Feed de atividade da assessoria

CLEARING — Cross-Assessoria (4)
├── clearing_weeks         — Períodos semanais de compensação
├── clearing_cases         — Obrigações from→to (OPEN/SENT_CONFIRMED/PAID_CONFIRMED/DISPUTED/EXPIRED)
├── clearing_case_items    — Itens individuais (challenge + winner + loser + amount)
└── clearing_case_events   — Auditoria de confirmações e disputas

CHAMPIONSHIPS — Inter-Assessoria (5)
├── championship_templates — Templates reutilizáveis para campeonatos recorrentes
├── championships          — Campeonatos (draft/open/active/completed/cancelled; max 3 active/group)
├── championship_invites   — Convites para grupos (pending/accepted/declined/revoked)
├── championship_participants — Atletas inscritos (enrolled/active/completed/withdrawn/disqualified)
└── championship_badges    — Passes temporários (expiram no end_at)

BILLING — B2B Portal (9)
├── billing_customers      — Assessoria billing entity (legal_name, tax_id, email, stripe_customer_id, stripe_default_pm)
├── billing_products       — Credit package catalog (name, credits_amount, price_cents, currency, is_active)
├── billing_purchases      — Purchase orders (pending→paid→fulfilled|cancelled|refunded; source: manual/auto_topup)
├── billing_events         — Append-only audit (created/payment_confirmed/fulfilled/cancelled/refunded/refund_requested/note_added; stripe_event_id dedup)
├── billing_auto_topup_settings — Per-group auto top-up config (enabled, threshold, product, max_per_month, last_triggered_at)
├── billing_refund_requests — Refund lifecycle (requested→approved→processed|rejected; UNIQUE open per purchase)
├── billing_limits         — Per-group daily limits (daily_token_limit, daily_redemption_limit; defaults 5000)
└── institution_credit_purchases — Audit trail: platform→assessoria credit allocations

NOTIFICATIONS (2)
├── device_tokens          — FCM/APNS push tokens por user/device
└── notification_log       — Log de notificações enviadas

VERIFICATION (1)
└── athlete_verification   — State machine de verificação de atleta (UNVERIFIED/CALIBRATING/MONITORED/VERIFIED/DOWNGRADED; trust_score 0..100; own-read-only RLS; mutations via SECURITY DEFINER RPC only)

ANALYTICS & OBSERVABILITY (6)
├── analytics_submissions  — Idempotência de submit-analytics
├── athlete_baselines      — Baselines calculados (4-week rolling)
├── athlete_trends         — Tendências de evolução (weekly/monthly)
├── coach_insights         — Insights gerados para coaches
├── product_events         — Eventos de produto (billing, onboarding, etc.)
└── api_rate_limits        — Rate limiting per-user per-function (sliding window)

PARKS (4)
├── parks                  — Catálogo de 47 parques brasileiros (centro + raio para detecção)
├── park_activities        — Atividades detectadas em parques (unique por session_id)
├── park_leaderboard       — Rankings por parque por categoria (pace/distance/frequency/longestRun)
└── park_segments          — Segmentos dentro de parques com recordes (preparado para futuro)

STRAVA IMPORT (1)
└── strava_activity_history — Histórico de atividades importadas do Strava na conexão

STORAGE
└── session-points (bucket) — Rotas GPS comprimidas (Protobuf)
```

### 3.2 Diagrama de Relações (FK)

```
auth.users (id)
  │
  ├──→ profiles (id)
  ├──→ sessions (user_id)
  ├──→ badge_awards (user_id)
  ├──→ profile_progress (user_id)
  ├──→ xp_transactions (user_id)
  ├──→ wallets (user_id)
  ├──→ coin_ledger (user_id)
  ├──→ mission_progress (user_id)
  ├──→ season_progress (user_id)
  ├──→ friendships (user_id_a, user_id_b)
  ├──→ groups (created_by_user_id)
  ├──→ group_members (user_id)
  ├──→ challenges (creator_user_id)
  ├──→ challenge_participants (user_id)
  ├──→ challenge_results (user_id)
  ├──→ event_participations (user_id)
  ├──→ coaching_groups (coach_user_id)
  ├──→ coaching_members (user_id)
  ├──→ coaching_invites (invited_user_id, invited_by_user_id)
  ├──→ billing_refund_requests (requested_by, reviewed_by)
  ├──→ device_tokens (user_id)
  └──→ product_events (user_id)

seasons (id)
  ├──→ badges (season_id)
  ├──→ profile_progress (current_season_id)
  └──→ season_progress (season_id)

badges (id)
  ├──→ badge_awards (badge_id)
  └──→ events (badge_id)

sessions (id)
  ├──→ badge_awards (trigger_session_id)
  └──→ challenge_run_bindings (session_id)

challenges (id)
  ├──→ challenge_participants (challenge_id)
  ├──→ challenge_results (challenge_id)
  └──→ challenge_run_bindings (challenge_id)

groups (id)
  ├──→ group_members (group_id)
  ├──→ group_goals (group_id)
  └──→ leaderboards (group_id)

coaching_groups (id)
  ├──→ coaching_members (group_id)
  ├──→ coaching_invites (group_id)
  ├──→ coaching_rankings (group_id)
  ├──→ race_events (group_id)
  ├──→ coaching_token_inventory (group_id)
  ├──→ token_intents (group_id)
  ├──→ billing_customers (group_id)
  ├──→ billing_purchases (group_id)
  ├──→ billing_auto_topup_settings (group_id)
  ├──→ billing_refund_requests (group_id)
  ├──→ billing_limits (group_id)
  ├──→ institution_credit_purchases (group_id)
  ├──→ assessoria_feed (group_id)
  └──→ championships (host_group_id)

billing_products (id)
  ├──→ billing_purchases (product_id)
  └──→ billing_auto_topup_settings (product_id)

billing_purchases (id)
  ├──→ billing_events (purchase_id)
  └──→ billing_refund_requests (purchase_id)

parks (id)
  ├──→ park_activities (park_id)
  ├──→ park_leaderboard (park_id)
  └──→ park_segments (park_id)
```

### 3.3 Arquivos SQL

| Arquivo | Conteúdo |
|---------|----------|
| `supabase/migrations/20260217_analytics_tables.sql` | 4 tabelas analytics + RLS |
| `supabase/migrations/20260218_full_schema.sql` | 32 tabelas core + triggers + RLS + Storage |
| `supabase/migrations/20260218_rpc_helpers.sql` | RPC functions (increment_wallet, increment_progress, compute_leaderboard) |
| `supabase/migrations/20260221_api_rate_limits.sql` | Rate limiting table + RPC (increment_rate_limit, cleanup) |
| `supabase/migrations/20260222_coaching_roles_expansion.sql` | Expand coaching_members roles: coach→admin_master, assistant→assistente, athlete→atleta + professor; update 5 RLS policies |
| `supabase/migrations/20260222_active_coaching_group.sql` | profiles.active_coaching_group_id (FK) + partial unique index enforcing 1 group per atleta |
| `supabase/migrations/20260222_fn_switch_assessoria.sql` | RPC fn_switch_assessoria (burn coins + switch group + membership) + coin_ledger reason expansion |
| `supabase/migrations/20260223_fn_search_coaching_groups.sql` | RPC fn_search_coaching_groups (SECURITY DEFINER search by name or UUID array, for onboarding) |
| `supabase/migrations/20260223_fn_staff_onboarding.sql` | RPCs fn_create_assessoria (create group + admin_master membership + invite_code) + fn_join_as_professor (join group as professor); both SECURITY DEFINER, require ASSESSORIA_STAFF role |
| `supabase/migrations/20260225_invite_codes.sql` | coaching_groups: invite_code (unique, 8-char alphanumeric, auto-generated) + invite_enabled; fn_generate_invite_code helper; fn_lookup_group_by_invite_code RPC (SECURITY DEFINER); fn_create_assessoria updated to return invite_link |
| `supabase/migrations/20260222_token_inventory_intents.sql` | coaching_token_inventory (per-group stock) + token_intents (QR nonce lifecycle) |
| `supabase/migrations/20260222_coin_ledger_token_reasons.sql` | coin_ledger reason expansion (institution_token_issue/burn) + RPCs (decrement_token_inventory, increment_inventory_burned) |
| `supabase/migrations/20260222_pending_coins.sql` | wallets.pending_coins + coin_ledger reasons (challenge_prize_pending/cleared) + RPCs (increment_wallet_pending, release_pending_to_balance) |
| `supabase/migrations/20260222_clearing_tables.sql` | clearing_weeks, clearing_cases, clearing_case_items, clearing_case_events + RLS staff access |
| `supabase/migrations/20260222_championship_tables.sql` | championship_templates, championships, championship_invites, championship_participants, championship_badges + RLS |
| `supabase/migrations/20260222_profile_onboarding.sql` | profiles: onboarding_state (NEW/ROLE_SELECTED/READY), user_role (ATLETA/ASSESSORIA_STAFF), created_via (ANON/EMAIL/OAUTH_GOOGLE/OAUTH_APPLE/OTHER) + updated handle_new_user trigger |
| `supabase/migrations/20260226_progression_fields_views.sql` | profile_progress extra fields + weekly_goals table + views para dashboard |
| `supabase/migrations/20260226_progression_idempotency.sql` | Idempotency guards para calculate-progression |
| `supabase/migrations/20260226_badges_catalog_update.sql` | Badges catalog updates (new badges, tier adjustments) |
| `supabase/migrations/20260227_leaderboard_v2.sql` | Leaderboard v2 schema improvements |
| `supabase/migrations/20260228_assessoria_feed.sql` | assessoria_feed table (group activity feed) |
| `supabase/migrations/20260221_push_device_tokens.sql` | device_tokens table (FCM/APNS tokens per user/device) |
| `supabase/migrations/20260221_notification_log.sql` | notification_log table (push notification history) |
| `supabase/migrations/20260221_product_events.sql` | product_events table (analytics: billing, onboarding, etc.) |
| `supabase/migrations/20260301_institution_credit_purchases.sql` | institution_credit_purchases (B2B audit trail, append-only, no monetary values) + fn_credit_institution RPC (atomic audit + inventory increment, SECURITY DEFINER) + RLS admin_master read-only |
| `supabase/migrations/20260221_billing_portal_tables.sql` | billing_customers + billing_products + billing_purchases + billing_events (B2B portal tables) + fn_fulfill_purchase RPC (paid→fulfilled + fn_credit_institution, SECURITY DEFINER) + RLS admin_master read (customers/purchases/events), staff read (products catalog) |
| `supabase/migrations/20260221_billing_webhook_dedup.sql` | ALTER billing_events ADD stripe_event_id TEXT + UNIQUE partial index for webhook idempotency |
| `supabase/migrations/20260221_billing_auto_topup_settings.sql` | billing_auto_topup_settings table + RLS (admin_master SELECT/UPDATE/INSERT). See DECISAO 050 |
| `supabase/migrations/20260221_billing_customers_stripe.sql` | ALTER billing_customers ADD stripe_customer_id + stripe_default_pm; ALTER billing_purchases ADD source ('manual'/'auto_topup'). See DECISAO 050 |
| `supabase/migrations/20260221_auto_topup_cron.sql` | pg_cron + pg_net: fn_invoke_auto_topup_cron() helper + hourly schedule 'auto-topup-hourly'. Requires app.supabase_url + app.service_role_key DB settings |
| `supabase/migrations/20260221_billing_refund_requests.sql` | billing_refund_requests table (requested→approved→processed/rejected) + RLS admin_master SELECT/INSERT + UNIQUE partial index open requests + ALTER billing_purchases status adds 'refunded' + ALTER billing_events event_type adds 'refund_requested'. See DECISAO 051 |
| `supabase/migrations/20260221_billing_limits.sql` | billing_limits table (group_id PK, daily_token_limit, daily_redemption_limit) + RLS staff SELECT / admin_master UPDATE + RPCs get_billing_limits() and check_daily_token_usage(). See DECISAO 052 |
| `supabase/migrations/20260221_challenge_limits.sql` | DB triggers: fn_enforce_challenge_limits (max 20 challenges/day/user) on challenges INSERT + fn_enforce_participant_limits (max 5 accepted + max 10 pending per athlete) on challenge_participants INSERT/UPDATE. See DECISAO 052 |
| `supabase/migrations/20260224000001_athlete_verification.sql` | athlete_verification table (state machine) + RLS own-read-only + eval_athlete_verification RPC (SECURITY DEFINER) + is_user_verified helper + handle_new_user_gamification trigger update + backfill |
| `supabase/migrations/20260224000002_verification_checklist_rpc.sql` | Updated eval_athlete_verification (N=7, trust=80, scoring recalibrado) + get_verification_state RPC (read-only checklist + counts + thresholds) |
| `supabase/migrations/20260224000003_verification_monetization_gate.sql` | Monetization gate: RLS INSERT policy atualizada (challenges); DB triggers `fn_enforce_verified_stake_gate` (challenges INSERT/UPDATE) + `fn_enforce_verified_join_gate` (challenge_participants INSERT); impossível burlar mesmo com service_role |
| `supabase/migrations/20260224000004_verification_cron.sql` | pg_cron schedule: `eval-verification-cron` diário 03:00 UTC via pg_net HTTP |
| `supabase/migrations/20260226100000_join_request_approval_required.sql` | Approval obrigatório para join requests: requested_role column, fn_request_join com p_role, fn_approve_join_request role-aware, DROP fn_join_as_professor, status 'cancelled' |
| `supabase/migrations/20260226110000_platform_approval_assessorias.sql` | Platform approval: profiles.platform_role, coaching_groups.approval_status + review columns, fn_platform_approve/reject/suspend, fn_search/fn_lookup filtram approved, RLS platform_admin_read. DECISAO 061 |
| `supabase/migrations/20260226120000_support_tickets.sql` | support_tickets + support_messages + trigger trg_support_message_touch + RLS (staff lê/escreve do grupo, platform_admin lê/escreve todos). DECISAO 076 |
| `supabase/migrations/20260226200000_user_wrapped.sql` | user_wrapped table (cache com TTL 24h) + RLS. DECISAO 069 |
| `supabase/migrations/20260226210000_league_tables.sql` | league_seasons + league_enrollments + league_snapshots + RLS. DECISAO 070 |
| `supabase/migrations/20260226220000_running_dna.sql` | running_dna cache (unique por user, TTL 7 dias) + RLS. DECISAO 071 |
| `supabase/migrations/20260226230000_social_profiles.sql` | profiles: instagram_handle + tiktok_handle; friendships: invited_by; fn_search_users RPC. DECISAO 072 |
| `supabase/migrations/20260226300000_parks_tables.sql` | parks (47 parques seed) + park_activities + park_leaderboard + park_segments + fn_refresh_park_leaderboard + trigger. DECISAO 084 |
| `supabase/migrations/20260226310000_strava_activity_history.sql` | strava_activity_history (upsert por strava_activity_id) + RLS own read/insert. DECISAO 084 |
| `supabase/migrations/20260227100000_coaching_groups_state.sql` | coaching_groups.state (UF) + fn_create_assessoria com p_state. DECISAO 086 |

---

## 4. ROW LEVEL SECURITY (RLS)

### 4.1 Matriz de Acesso

| Tabela | SELECT | INSERT | UPDATE | DELETE |
|--------|--------|--------|--------|--------|
| `profiles` | Todos | Auto (trigger) | Próprio | - |
| `sessions` | Próprio | Próprio | Próprio | - |
| `seasons` | Todos | Admin | Admin | - |
| `badges` | Todos | Admin | Admin | - |
| `badge_awards` | Todos | Server | - | - |
| `profile_progress` | Todos | Auto (trigger) | Server | - |
| `xp_transactions` | Próprio | Server | - | - |
| `season_progress` | Próprio | Server | Server | - |
| `wallets` | Próprio | Auto (trigger) | Server | - |
| `coin_ledger` | Próprio | Server | - | - |
| `missions` | Todos | Admin | Admin | - |
| `mission_progress` | Próprio | Server | Server | - |
| `friendships` | Ambos lados | Participante | Participante | - |
| `groups` | Open/Closed=todos, Secret=membros | Auth | Admin | - |
| `group_members` | Membros do grupo | Próprio | Próprio ou Mod/Admin | - |
| `group_goals` | Membros do grupo | Mod/Admin | Server | - |
| `challenges` | Participantes | Criador (stake=0 livre; stake>0 VERIFIED only — RLS + trigger) | Server | - |
| `challenge_participants` | Participantes | Server (stake>0 VERIFIED only — trigger) | Próprio | - |
| `challenge_results` | Participantes | Server | - | - |
| `challenge_run_bindings` | Próprio | Server | - | - |
| `leaderboards` | Global/Season=todos, Group=membros | Server | Server | - |
| `leaderboard_entries` | Via leaderboard | Server | Server | - |
| `events` | Todos | Auth | Server | - |
| `event_participations` | Próprio + Co-participantes | Próprio | Server | - |
| `coaching_groups` | Membros + Platform Admin | Coach | Coach | - |
| `coaching_members` | Membros do grupo | Server | Server | - |
| `coaching_invites` | Convidado ou Coach/Assistant | Server | Convidado | - |
| `coaching_token_inventory` | Staff do grupo | Server/RPC | Server/RPC | - |
| `token_intents` | Staff do grupo + Atleta alvo | Server/RPC | Server/RPC | - |
| `coaching_rankings` | Membros | Server | - | - |
| `coaching_ranking_entries` | Membros | Server | - | - |
| `race_events` | Membros | Coach/Assistant | Server | - |
| `race_participations` | Membros | Server | Server | - |
| `race_results` | Membros | Server | - | - |
| `analytics_submissions` | Próprio | Próprio | - | - |
| `athlete_baselines` | Próprio ou Coach/Assistant | Server | Server | - |
| `athlete_trends` | Próprio ou Coach/Assistant | Server | Server | - |
| `coach_insights` | Coach/Assistant | Server | Coach/Assistant | - |
| `clearing_weeks` | Todos (SELECT) | Server/Cron | - | - |
| `clearing_cases` | Staff dos grupos envolvidos | Edge Functions | Edge Functions | - |
| `clearing_case_items` | Staff dos grupos envolvidos | Server/Cron | - | - |
| `clearing_case_events` | Staff dos grupos envolvidos | Edge Functions | - | - |
| `championship_templates` | Staff do grupo owner | Edge Functions | - | - |
| `championships` | Todos (open/active/completed) + Staff host (draft) | Edge Functions | Edge Functions | - |
| `championship_invites` | Staff dos grupos envolvidos | Edge Functions | Edge Functions | - |
| `championship_participants` | Todos (open/active/completed champs) | Edge Functions | Edge Functions | - |
| `championship_badges` | Próprio + Staff host | Edge Functions | - | - |
| `institution_credit_purchases` | Admin_master do grupo | Server/RPC (`fn_credit_institution`) | - | - |
| `billing_customers` | Admin_master do grupo | Server | Server | - |
| `billing_products` | Staff (admin_master/professor/assistente) | Server | Server | - |
| `billing_purchases` | Admin_master do grupo | Server | Server/RPC (`fn_fulfill_purchase`) | - |
| `billing_events` | Admin_master do grupo (via purchase join) | Server | - | - |
| `billing_auto_topup_settings` | Admin_master | Admin_master | Admin_master | - (disable only) |
| `billing_refund_requests` | Admin_master do grupo | Admin_master (requested_by=self) | Server (status transitions) | - |
| `billing_limits` | Staff (admin_master/professor/assistente) | Server | Admin_master | - |
| `device_tokens` | Próprio | Próprio | Próprio | - |
| `notification_log` | Próprio | Server | - | - |
| `product_events` | - | Server/Edge Functions | - | - |
| `api_rate_limits` | - | Server/RPC (`increment_rate_limit`) | Server/RPC | Server/RPC (`cleanup_rate_limits`) |
| `assessoria_feed` | Membros do grupo | Server | - | - |
| `weekly_goals` | Próprio | Server | Server | - |
| `parks` | Todos | Server (seed) | - | - |
| `park_activities` | Todos | Server/Trigger | - | - |
| `park_leaderboard` | Todos | Server/Trigger | Server/Trigger | - |
| `park_segments` | Todos | Server | Server | - |
| `strava_activity_history` | Próprio | Próprio | - | - |
| `support_tickets` | Staff do grupo + Platform Admin | Staff | Staff | - |
| `support_messages` | Staff do grupo + Platform Admin | Staff + Platform Admin | - | - |
| `user_wrapped` | Próprio | Server | Server | - |
| `league_seasons` | Todos | Server | Server | - |
| `league_enrollments` | Todos | Staff | - | - |
| `league_snapshots` | Todos | Server | - | - |
| `running_dna` | Próprio | Server | Server | - |

> **"Server"** = Edge Function com `service_role` key, que bypassa RLS.
> **"Admin"** = Operação via Supabase Dashboard ou migration.

### 4.2 Padrões Aplicados

1. **Dados pessoais (sessions, wallets, xp_transactions)**: `auth.uid() = user_id`
2. **Dados públicos (profiles, badges, seasons, events)**: `FOR SELECT USING (true)`
3. **Dados de grupo**: Subquery verifica membership ativa no grupo
4. **Dados de coaching**: Subquery verifica role IN ('admin_master', 'professor', 'assistente')
5. **Dados competitivos (challenges)**: Subquery verifica participação
6. **Dados imutáveis (badge_awards, coin_ledger, challenge_results)**: Apenas INSERT via server

---

## 5. EDGE FUNCTIONS

### 5.1 Inventário (54 Edge Functions)

| # | Function | Auth | Rate Limit | Descrição |
|:-:|----------|------|:----------:|-----------|
| 1 | `verify-session` | JWT | 60/60s | Pipeline único anti-cheat server-side: 11 checks (7 critical + 4 quality), flags oficiais de `_shared/integrity_flags.ts`, server OVERWRITES client flags; pós-verdict chama `eval_athlete_verification` RPC (fire-and-forget) |
| 2 | `evaluate-badges` | JWT | 20/60s | Avalia catálogo de badges e credita XP/Coins |
| 3 | `calculate-progression` | JWT | 20/60s | Calcula XP, nível, streaks e metas |
| 4 | `settle-challenge` | JWT | 10/60s | Calcula resultados, distribui Coins (stake cap 10k), fecha challenges |
| 5 | `compute-leaderboard` | JWT | 10/60s | Materializa leaderboards global/season weekly/monthly |
| 6 | `submit-analytics` | JWT | 60/60s | Baselines, trends, insights para coaching groups |
| 7 | `token-create-intent` | JWT (staff) | 60/60s | Cria intent OPEN com nonce + expiry + daily limit check (DECISAO 052) |
| 8 | `token-consume-intent` | JWT | 30/60s | Consome intent: ISSUE/BURN/CHAMP_BADGE + daily group/athlete limits |
| 9 | `clearing-confirm-sent` | JWT (staff) | - | Confirma envio de tokens; OPEN → SENT_CONFIRMED |
| 10 | `clearing-confirm-received` | JWT (staff) | - | Confirma recebimento; SENT_CONFIRMED → PAID_CONFIRMED; libera pending |
| 11 | `clearing-open-dispute` | JWT (staff) | - | Abre disputa; OPEN/SENT_CONFIRMED → DISPUTED |
| 12 | `champ-create` | JWT (staff) | 20/60s | Cria campeonato draft (max 3 active/group — DECISAO 052) |
| 13 | `champ-invite` | JWT (staff) | - | Convida grupo para campeonato (idempotente) |
| 14 | `champ-activate-badge` | JWT | - | Consome intent CHAMP_BADGE_ACTIVATE → badge + enrollment |
| 15 | `champ-list` | JWT | - | Lista campeonatos (filtros: status, host, participating) |
| 16 | `champ-participant-list` | JWT | - | Lista participantes + display_name + badge info |
| 17 | `complete-social-profile` | JWT | - | Upsert profile com created_via auto-detectado do provider |
| 18 | `set-user-role` | JWT | - | Define user_role + avança onboarding_state |
| 19 | `send-push` | Service role | - | Envia push notification via FCM/APNS |
| 20 | `notify-rules` | Service role | - | Engine de regras para notificações inteligentes |
| 21 | `create-checkout-session` | JWT (admin_master) | 10/60s | Cria Stripe Checkout session + billing_purchase |
| 22 | `webhook-payments` | Stripe signature | - | Processa webhooks Stripe (idempotente via stripe_event_id) |
| 23 | `list-purchases` | JWT (admin_master) | 20/60s | Lista compras do grupo com billing_events |
| 24 | `auto-topup-check` | Service role | - | Verifica threshold e dispara recarga automática (DECISAO 050) |
| 25 | `auto-topup-cron` | Service role | - | Sweep horário: itera grupos enabled, chama auto-topup-check |
| 26 | `create-portal-session` | JWT (admin_master) | 10/60s | Cria Stripe Customer Portal session |
| 27 | `process-refund` | Service role | - | Executa refund aprovado: Stripe API + debit credits (DECISAO 051) |
| 28 | `eval-athlete-verification` | JWT | 10/60s | Avalia verificação do atleta: session count + integrity + trust_score → state machine transition (idempotente); retorna checklist completo |
| 29 | `eval-verification-cron` | Service role | - | Cron diário (03:00 UTC): reavalia candidatos (CALIBRATING/MONITORED/DOWNGRADED, flags recentes, não avaliados 24h); batch max 100; usa eval_athlete_verification RPC |
| 30 | `delete-account` | JWT | - | Soft-delete: remove de coaching groups, cancela desafios pendentes, anonimiza perfil, deleta strava connection, deleta auth user via admin API |
| 31 | `validate-social-login` | No JWT | - | Gera auth_url para TikTok OAuth (quando TIKTOK_CLIENT_KEY configurado); retorna erro gracioso se não configurado |

### 5.8 Clearing — Detalhes

**Fluxo de dupla confirmação (7 dias):**

1. Cron semanal agrega challenges cross-assessoria em `clearing_cases` (from_group → to_group)
2. `clearing-confirm-sent` — Staff da assessoria devedora (from_group) confirma envio
3. `clearing-confirm-received` — Staff da assessoria credora (to_group) confirma recebimento
4. No PAID_CONFIRMED: para cada item, `release_pending_to_balance(winner)` + ledger `challenge_prize_cleared`
5. `clearing-open-dispute` — Qualquer grupo pode disputar (OPEN/SENT_CONFIRMED → DISPUTED)

**Regras:**
- Deadline de 7 dias a partir da criação do case
- Após PAID_CONFIRMED: irreversível (pending liberado)
- Apenas admin_master/professor podem confirmar ou disputar
- Plataforma não intervém em disputas (resolução externa entre assessorias)
- Todas as ações são idempotentes

### 5.9 Championships — Detalhes

**Fluxo completo:**

1. Staff host cria campeonato via `champ-create` (status `draft`)
2. Staff host convida grupos via `champ-invite` (status `pending`)
3. Staff do grupo convidado aceita convite (direto no DB ou via futura function)
4. Staff host muda status para `open` (aceita inscrições)
5. Para campeonatos com `requires_badge = true`:
   - Staff host cria intent `CHAMP_BADGE_ACTIVATE` via `token-create-intent`
   - Atleta escaneia QR e chama `champ-activate-badge` → consome intent, cria badge com `expires_at = championship.end_at`, e inscreve como participant
6. Para campeonatos sem badge: atleta se inscreve diretamente
7. `champ-list` para descobrir campeonatos; `champ-participant-list` para ver ranking/inscritos

**Regras:**
- Apenas admin_master/professor podem criar campeonatos e convidar grupos
- Atletas NÃO podem criar campeonatos
- Badge SEMPRE expira no `end_at` do campeonato (nunca sem expiração)
- Host group athletes auto-qualificam; outros precisam de invite aceito
- Todas as operações de escrita são idempotentes (upsert em unique constraints)

### 5.2 Fluxo Pós-Sessão (Pipeline)

```
Atleta finaliza corrida no device
       │
       ▼
  [1] Sync session + GPS points → sessions table + Storage bucket
       │
       ▼
  [2] POST /verify-session
       │  → Analisa rota GPS server-side
       │  → Atualiza is_verified + integrity_flags
       │
       ▼ (se is_verified = true)
  [3] POST /evaluate-badges
       │  → Avalia badges não-desbloqueados
       │  → INSERT badge_awards, xp_transactions, coin_ledger
       │  → RPC increment_profile_progress, increment_wallet_balance
       │
       ▼ (se atleta está em coaching group)
  [4] POST /submit-analytics
       │  → Recalcula baselines e trends
       │  → Gera insights para o coach
       │
       ▼ (se atleta está em challenges ativos)
  [5] Client atualiza challenge_participants.progress_value
       │  (via RLS UPDATE próprio)
       │
       ▼ (cron hourly)
  [6] POST /settle-challenge
       │  → Fecha challenges expirados
       │  → Calcula resultados e distribui Coins
```

### 5.3 verify-session — Detalhes

**Endpoint:** `POST /functions/v1/verify-session`

**Payload:**
```json
{
  "session_id": "uuid",
  "user_id": "uuid",
  "route": [
    {"lat": -23.55, "lng": -46.63, "speed": 3.5, "timestamp_ms": 1707753600000},
    ...
  ],
  "total_distance_m": 5230.5,
  "start_time_ms": 1707753600000,
  "end_time_ms": 1707755400000,
  "avg_bpm": 152
}
```

**Checks realizados:**

| Check | Threshold | Flag |
|-------|-----------|------|
| Pontos GPS mínimos | < 5 pontos | `TOO_FEW_POINTS` |
| Duração mínima | < 60s | `TOO_SHORT_DURATION` |
| Distância mínima | < 50m | `TOO_SHORT_DISTANCE` |
| Velocidade excessiva | > 12.5 m/s (45 km/h) em >10% dos segmentos | `SPEED_EXCEEDED` |
| Teleporte | Salto > 500m entre pontos consecutivos | `TELEPORT_DETECTED` |
| Pace implausível | < 1:30/km em distância > 1km | `IMPLAUSIBLE_PACE` |

**Response:**
```json
{
  "status": "ok",
  "session_id": "uuid",
  "is_verified": true,
  "integrity_flags": []
}
```

### 5.4 evaluate-badges — Detalhes

**Endpoint:** `POST /functions/v1/evaluate-badges`

**Payload:**
```json
{
  "user_id": "uuid",
  "session_id": "uuid"
}
```

**Criteria types mapeados (criteria_type → criteria_json):**

| criteria_type | criteria_json example |
|---------------|---------------------|
| `single_session_distance` | `{"threshold_m": 5000}` |
| `lifetime_distance` | `{"threshold_m": 50000}` |
| `session_count` | `{"count": 10}` |
| `pace_below` | `{"max_pace_sec_per_km": 360, "min_distance_m": 5000}` |
| `single_session_duration` | `{"threshold_ms": 3600000}` |
| `lifetime_duration` | `{"threshold_ms": 36000000}` |
| `daily_streak` | `{"days": 7}` |
| `challenges_completed` | `{"count": 5}` |
| `session_before_hour` | `{"hour_local": 6}` |
| `session_after_hour` | `{"hour_local": 22}` |

**Response:**
```json
{
  "status": "ok",
  "badges_unlocked": 2,
  "badge_ids": ["badge_first_5k", "badge_10_runs"],
  "xp_awarded": 150,
  "coins_awarded": 0
}
```

### 5.5 settle-challenge — Detalhes

**Endpoint:** `POST /functions/v1/settle-challenge`

**Payload:** `{ "challenge_id": "uuid" }` ou `{}` (settle all due)

**Lógica:**
1. Busca challenges com `status IN ('active', 'completing')` e `ends_at_ms <= now()`
2. Para cada challenge:
   - Ordena participantes por `progress_value` (desc para distance/time, asc para pace)
   - Tiebreaker: `last_submitted_at_ms` (quem terminou primeiro vence empate)
   - Calcula outcome (won/lost/tied/completed_target/participated/did_not_finish)
   - Distribui Coins: vencedor recebe o pool integral (soma dos entry fees reais coletados via `coin_ledger`). Empate divide igualmente. Ninguém correu = refund para todos.
   - **Cross-assessoria (1v1):** pool entra como `pending_coins` (reason `challenge_prize_pending`) e só é liberado após clearing via `release_pending_to_balance`
   - **Same assessoria / sem grupo:** comportamento normal — tudo direto para `balance_coins`
3. INSERT challenge_results + coin_ledger
4. UPDATE wallets via `increment_wallet_balance` (imediato) e/ou `increment_wallet_pending` (cross)
5. UPDATE challenge.status = 'completed'

### 5.6 compute-leaderboard — Detalhes

**Endpoint:** `POST /functions/v1/compute-leaderboard`

**Payload:** `{ "scope": "global", "period": "weekly", "finalize": false }`

**Métricas computadas:** distance, sessions, moving_time (avg_pace em roadmap)

### 5.7 submit-analytics — Detalhes

Já documentado em `contracts/analytics_api.md`. Processa baselines (4 semanas), trends (weekly/monthly), e gera insights (performance_decline, inactivity_warning, overtraining_risk, etc.).

### 5.10 Billing — create-checkout-session

**Endpoint:** `POST /functions/v1/create-checkout-session`
**Auth:** JWT (admin_master only)
**Payload:** `{ "group_id": "uuid", "product_id": "uuid" }`

**Fluxo:**
1. Valida admin_master role no grupo
2. Busca produto ativo em `billing_products`
3. Cria `billing_purchase` (status=pending, source=manual)
4. Cria Stripe Checkout Session com metadata (purchase_id, group_id)
5. Retorna `checkout_url` para redirect

### 5.11 Billing — webhook-payments

**Endpoint:** `POST /functions/v1/webhook-payments`
**Auth:** Stripe webhook signature (`STRIPE_WEBHOOK_SECRET`)

**Eventos tratados:**
- `checkout.session.completed` → purchase.status=paid → fn_fulfill_purchase RPC (paid→fulfilled + credita inventory)
- Idempotência via `billing_events.stripe_event_id` (UNIQUE partial index)

### 5.12 Billing — Auto Top-Up (DECISAO 050)

**`auto-topup-check`** — Service-role only, invocado após debit ou pelo cron.

**Decision tree:**
```
1. settings.enabled?          → skip: "disabled"
2. balance < threshold?       → skip: "above_threshold"
3. monthly count < max?       → skip: "monthly_cap_reached"
4. last_triggered_at > 24h?   → skip: "cooldown"
5. stripe_customer + pm?      → skip: "no_payment_method"
6. product active?            → skip: "product_unavailable"
7. → Create billing_purchase (source=auto_topup) + Stripe PaymentIntent (off-session)
8. → If PaymentIntent succeeds immediately: fn_fulfill_purchase inline
```

**`auto-topup-cron`** — Hourly sweep via pg_cron → pg_net → Edge Function.
- Busca todos os grupos com `enabled=true`
- Chama `auto-topup-check` para cada (200ms delay entre calls)

### 5.13 Billing — create-portal-session

**Endpoint:** `POST /functions/v1/create-portal-session`
**Auth:** JWT (admin_master only)
**Payload:** `{ "group_id": "uuid" }`

**Fluxo:**
1. Auto-provisiona Stripe Customer se não existir
2. Cria Stripe Billing Portal session
3. Retorna `portal_url` para redirect ao portal Stripe

### 5.14 Billing — process-refund (DECISAO 051)

**Endpoint:** `POST /functions/v1/process-refund`
**Auth:** Service-role only (platform team operation)
**Payload:** `{ "refund_request_id": "uuid" }`

**Fluxo:**
1. Valida refund request status = `approved`
2. Valida purchase status = `fulfilled` + `payment_reference` presente
3. Calcula `credits_to_debit` (full = credits_amount; partial = floor(credits * amount / price))
4. Verifica `available_tokens >= credits_to_debit` (RF-1: never negative)
5. Stripe `refunds.create()` (full ou partial amount)
6. `decrement_token_inventory` RPC (atomic debit)
7. Update purchase status → `refunded` (full) ou mantém `fulfilled` (partial)
8. Update refund request → `processed` + `processed_at`
9. Insert `billing_events` (refunded) + analytics

**Error handling:**
- Stripe failure → 502 (no DB changes)
- Debit failure (after Stripe success) → 500 + critical log for manual reconciliation

### 5.15 Operational Limits (DECISAO 052)

**RPCs disponíveis:**
- `get_billing_limits(group_id)` — retorna limites efetivos com fallback 5000
- `check_daily_token_usage(group_id, type)` — retorna capacidade restante (limit - used today)

**Enforcement em Edge Functions:**

| Function | Limite | Erro |
|----------|--------|------|
| `token-create-intent` | 5,000 tokens/grupo/dia (ISSUE + BURN) | 429 `DAILY_LIMIT_EXCEEDED` |
| `token-consume-intent` | 5,000/grupo/dia + 500/atleta/dia (BURN) | 429 `DAILY_LIMIT_EXCEEDED` / `ATHLETE_DAILY_BURN_LIMIT` |
| `settle-challenge` | 10,000 coins max/challenge settlement | Challenge expired + error log |
| `champ-create` | 3 active championships/group (draft+active) | 429 `CHAMPIONSHIP_LIMIT` |

**Enforcement em DB triggers:**

| Trigger | Tabela | Limite | Erro |
|---------|--------|--------|------|
| `trg_challenge_creation_limit` | `challenges` INSERT | 20/day/user | RAISE EXCEPTION |
| `trg_participant_limits` | `challenge_participants` INSERT/UPDATE | 5 accepted + 10 pending | RAISE EXCEPTION |
| `trg_challenges_verified_stake_gate` | `challenges` INSERT/UPDATE(entry_fee_coins) | entry_fee_coins>0 requires VERIFIED | RAISE EXCEPTION ATHLETE_NOT_VERIFIED |
| `trg_participants_verified_join_gate` | `challenge_participants` INSERT | challenge.entry_fee_coins>0 requires VERIFIED | RAISE EXCEPTION ATHLETE_NOT_VERIFIED |

---

## 5B. BILLING PORTAL WEB (Next.js)

### Arquitetura

```
portal/ (Next.js 14, App Router)
├── src/app/
│   ├── login/              — Supabase Auth (email/password)
│   ├── select-group/       — Seletor de assessoria (multi-group)
│   ├── (portal)/           — Layout autenticado com sidebar
│   │   ├── dashboard/      — Dashboard principal
│   │   ├── credits/        — Compra de créditos (pacotes + BuyButton)
│   │   ├── billing/        — Histórico de compras + ManageBillingButton
│   │   └── settings/       — Config: PortalButton + AutoTopupForm + Equipe
│   └── api/
│       ├── checkout/       — Proxy → create-checkout-session
│       ├── billing-portal/ — Proxy → create-portal-session
│       ├── auto-topup/     — Upsert billing_auto_topup_settings (service client)
│       └── platform/
│           ├── assessorias/ — Approve/reject/suspend assessorias
│           ├── products/    — CRUD billing products
│           ├── refunds/     — Approve/reject/process refunds
│           ├── liga/        — Create/activate/complete league seasons + trigger snapshot
│           └── support/     — Reply/close/reopen support tickets
├── src/lib/
│   ├── supabase/server.ts  — Server-side Supabase client
│   └── supabase/service.ts — Service-role client (bypasses RLS)
└── src/components/
    └── sidebar.tsx          — Navegação (Dashboard, Créditos, Cobranças, Configurações)
```

### Auth Model (DECISAO 048)

| Role | Acesso |
|------|--------|
| `admin_master` | Todas as telas (comprar, billing, settings, equipe, auto top-up) |
| `professor` | Dashboard, Configurações (equipe read-only) |
| `assistente` | Dashboard, Configurações (equipe read-only) |
| `atleta` | Bloqueado (redirect para app) |

### Componentes Client-Side

| Componente | Arquivo | Função |
|-----------|---------|--------|
| `BuyButton` | `credits/buy-button.tsx` | Inicia checkout → redirect Stripe |
| `PortalButton` | `settings/portal-button.tsx` | Abre Stripe Customer Portal |
| `ManageBillingButton` | `billing/manage-billing-button.tsx` | Mesmo que PortalButton (billing page) |
| `AutoTopupForm` | `settings/auto-topup-form.tsx` | Toggle + threshold + product + max_per_month |
| `InviteForm` | `settings/invite-form.tsx` | Convidar professor/assistente |
| `RemoveButton` | `settings/remove-button.tsx` | Remover membro |

---

## 6. STORAGE

### 6.1 Bucket: session-points

| Aspecto | Valor |
|---------|-------|
| Nome | `session-points` |
| Público | Não |
| Formato | Protobuf comprimido (via `workout_proto_mapper.dart`) |
| Caminho | `{user_id}/{session_id}.pb` |
| Tamanho máximo | 50 MiB (config.toml) |
| RLS Upload | Apenas na pasta do próprio user |
| RLS Download | Apenas da pasta do próprio user |

### 6.2 Políticas

```sql
-- Upload: user só pode criar dentro da sua pasta
CREATE POLICY "session_points_own_upload" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'session-points'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Download: user só pode ler da sua pasta
CREATE POLICY "session_points_own_read" ON storage.objects
  FOR SELECT USING (
    bucket_id = 'session-points'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );
```

---

## 7. VARIÁVEIS DE AMBIENTE

### 7.1 Flutter (.env.dev / .env.prod)

```
APP_ENV=dev|prod
SUPABASE_URL=https://<project>.supabase.co
SUPABASE_ANON_KEY=<anon_key>
MAPTILER_API_KEY=<key>
SENTRY_DSN=<dsn>
```

### 7.2 Supabase Edge Functions (automáticas)

| Variável | Fonte | Usado por |
|----------|-------|-----------|
| `SUPABASE_URL` | Auto-injetada | Todas as functions |
| `SUPABASE_ANON_KEY` | Auto-injetada | Todas as functions |
| `SUPABASE_SERVICE_ROLE_KEY` | Auto-injetada | auto-topup-*, process-refund, webhook-payments |
| `STRIPE_SECRET_KEY` | Secret manual | create-checkout-session, webhook-payments, auto-topup-check, create-portal-session, process-refund |
| `STRIPE_WEBHOOK_SECRET` | Secret manual | webhook-payments |
| `PORTAL_URL` | Secret manual | create-portal-session (return URL; default: https://portal.omnirunner.app) |

### 7.3 Portal Web (.env.local)

| Variável | Descrição |
|----------|-----------|
| `NEXT_PUBLIC_SUPABASE_URL` | URL do projeto Supabase |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Chave pública (client-side) |
| `SUPABASE_SERVICE_ROLE_KEY` | Chave server (server-side only, API routes) |

### 7.4 Auth Providers (Supabase Dashboard → Settings → Auth)

| Variável | Onde configurar |
|----------|-----------------|
| `GOOGLE_CLIENT_ID` | Dashboard → Auth → Google |
| `GOOGLE_CLIENT_SECRET` | Dashboard → Auth → Google |
| `APPLE_SERVICE_ID` | Dashboard → Auth → Apple |
| `APPLE_P8_SECRET` | Dashboard → Auth → Apple |

---

## 8. INTEGRAÇÃO FLUTTER ↔ SUPABASE

### 8.1 Pacotes necessários

```yaml
dependencies:
  supabase_flutter: ^2.0.0
  google_sign_in: ^6.0.0
  sign_in_with_apple: ^6.0.0
```

### 8.2 Inicialização

```dart
await Supabase.initialize(
  url: AppConfig.supabaseUrl,
  anonKey: AppConfig.supabaseAnonKey,
);
```

### 8.3 Padrão de sync (exemplo: sessão)

```dart
// 1. Salvar localmente no Isar
await isarSessionRepo.save(session);

// 2. Sync para Supabase
final response = await supabase.from('sessions').upsert({
  'id': session.id,
  'user_id': session.userId,
  'status': session.status.index,
  'start_time_ms': session.startTimeMs,
  'end_time_ms': session.endTimeMs,
  'total_distance_m': session.totalDistanceM,
  // ...
});

// 3. Upload GPS points
await supabase.storage
  .from('session-points')
  .uploadBinary('${userId}/${sessionId}.pb', protoBytes);

// 4. Trigger server-side verification
await supabase.functions.invoke('verify-session', body: {
  'session_id': session.id,
  'user_id': session.userId,
  'route': session.route.map((p) => {
    'lat': p.lat, 'lng': p.lng, 'speed': p.speed,
    'timestamp_ms': p.timestampMs,
  }).toList(),
  'total_distance_m': session.totalDistanceM,
  'start_time_ms': session.startTimeMs,
  'end_time_ms': session.endTimeMs,
});

// 5. Trigger badge evaluation
await supabase.functions.invoke('evaluate-badges', body: {
  'user_id': session.userId,
  'session_id': session.id,
});
```

### 8.4 Realtime Subscriptions (opcionais)

```dart
// Escutar novos badge_awards para UI toast
supabase.from('badge_awards')
  .stream(primaryKey: ['id'])
  .eq('user_id', currentUserId)
  .listen((data) {
    // Mostrar toast de badge desbloqueado
  });

// Escutar updates em challenges do usuário
supabase.from('challenge_participants')
  .stream(primaryKey: ['challenge_id', 'user_id'])
  .eq('user_id', currentUserId)
  .listen((data) {
    // Atualizar UI de challenges
  });
```

---

## 9. CRON JOBS (pg_cron)

| Job | Schedule | Mecanismo | Descrição |
|-----|----------|-----------|-----------|
| Auto top-up sweep | `0 * * * *` (hourly) | pg_cron → pg_net → `auto-topup-cron` | Verifica threshold de todos os grupos enabled |
| Settle challenges | Cada 1 hora | External trigger / `settle-challenge` | Fecha challenges expirados |
| Compute leaderboards | Cada 6 horas | External trigger / `compute-leaderboard` | Materializa rankings |
| Expire missions | Diário 00:05 UTC | SQL direto | `UPDATE mission_progress SET status='expired' WHERE ...` |
| Cleanup rate limits | Periódico | `cleanup_rate_limits()` RPC | Remove windows > 1 hora de `api_rate_limits` |
| Season transition | Trimestral | SQL + Edge Function | Muda status da season, distribui recompensas |

### 9.1 Setup pg_cron (produção)

```sql
-- Requer configuração manual por ambiente (NÃO em migration):
ALTER DATABASE postgres SET app.supabase_url = 'https://<ref>.supabase.co';
ALTER DATABASE postgres SET app.service_role_key = 'eyJ...';
```

---

## 10. SEED DATA

### 10.1 Badges (catálogo MVP — 30 badges)

```sql
INSERT INTO public.badges (id, category, tier, name, description, xp_reward, coins_reward, criteria_type, criteria_json, is_secret) VALUES
-- Distância
('badge_first_km', 'distance', 'bronze', 'Primeiro Quilômetro', 'Complete 1 sessão ≥ 1 km', 50, 0, 'single_session_distance', '{"threshold_m": 1000}', false),
('badge_5k', 'distance', 'bronze', '5K Runner', 'Complete 1 sessão ≥ 5 km', 50, 0, 'single_session_distance', '{"threshold_m": 5000}', false),
('badge_10k', 'distance', 'silver', '10K Runner', 'Complete 1 sessão ≥ 10 km', 100, 0, 'single_session_distance', '{"threshold_m": 10000}', false),
('badge_half_marathon', 'distance', 'gold', 'Meia Maratona', 'Complete 1 sessão ≥ 21.1 km', 200, 0, 'single_session_distance', '{"threshold_m": 21100}', false),
('badge_marathon', 'distance', 'diamond', 'Maratona', 'Complete 1 sessão ≥ 42.195 km', 500, 0, 'single_session_distance', '{"threshold_m": 42195}', false),
('badge_50km_total', 'distance', 'bronze', '50 km Acumulados', 'Distância lifetime ≥ 50 km', 50, 0, 'lifetime_distance', '{"threshold_m": 50000}', false),
('badge_200km_total', 'distance', 'silver', '200 km Acumulados', 'Distância lifetime ≥ 200 km', 100, 0, 'lifetime_distance', '{"threshold_m": 200000}', false),
('badge_1000km_total', 'distance', 'gold', '1000 km Acumulados', 'Distância lifetime ≥ 1000 km', 200, 0, 'lifetime_distance', '{"threshold_m": 1000000}', false),
-- Frequência
('badge_first_run', 'frequency', 'bronze', 'Primeiro Passo', '1ª sessão verificada', 50, 0, 'session_count', '{"count": 1}', false),
('badge_10_runs', 'frequency', 'bronze', '10 Corridas', '10 sessões verificadas', 50, 0, 'session_count', '{"count": 10}', false),
('badge_50_runs', 'frequency', 'silver', '50 Corridas', '50 sessões verificadas', 100, 0, 'session_count', '{"count": 50}', false),
('badge_100_runs', 'frequency', 'gold', '100 Corridas', '100 sessões verificadas', 200, 0, 'session_count', '{"count": 100}', false),
('badge_500_runs', 'frequency', 'diamond', '500 Corridas', '500 sessões verificadas', 500, 0, 'session_count', '{"count": 500}', false),
('badge_streak_7', 'frequency', 'silver', '7 Dias Seguidos', 'Streak diário de 7 dias', 100, 10, 'daily_streak', '{"days": 7}', false),
('badge_streak_30', 'frequency', 'gold', '30 Dias Seguidos', 'Streak diário de 30 dias', 200, 50, 'daily_streak', '{"days": 30}', false),
-- Velocidade
('badge_pace_6', 'speed', 'bronze', 'Abaixo de 6:00/km', 'Pace < 6:00/km em ≥ 5 km', 50, 0, 'pace_below', '{"max_pace_sec_per_km": 360, "min_distance_m": 5000}', false),
('badge_pace_5', 'speed', 'silver', 'Abaixo de 5:00/km', 'Pace < 5:00/km em ≥ 5 km', 100, 0, 'pace_below', '{"max_pace_sec_per_km": 300, "min_distance_m": 5000}', false),
('badge_pace_430', 'speed', 'gold', 'Abaixo de 4:30/km', 'Pace < 4:30/km em ≥ 5 km', 200, 0, 'pace_below', '{"max_pace_sec_per_km": 270, "min_distance_m": 5000}', false),
('badge_pace_4', 'speed', 'diamond', 'Abaixo de 4:00/km', 'Pace < 4:00/km em ≥ 5 km', 500, 0, 'pace_below', '{"max_pace_sec_per_km": 240, "min_distance_m": 5000}', false),
('badge_pr_pace', 'speed', 'bronze', 'PR Pace', 'Novo recorde pessoal de pace', 50, 0, 'personal_record_pace', '{"min_distance_m": 1000}', false),
-- Resistência
('badge_1h_run', 'endurance', 'bronze', '1 Hora Correndo', 'Sessão ≥ 60 min', 50, 0, 'single_session_duration', '{"threshold_ms": 3600000}', false),
('badge_2h_run', 'endurance', 'silver', '2 Horas Correndo', 'Sessão ≥ 120 min', 100, 0, 'single_session_duration', '{"threshold_ms": 7200000}', false),
('badge_10h_total', 'endurance', 'bronze', '10 Horas Acumuladas', 'Tempo total ≥ 600 min', 50, 0, 'lifetime_duration', '{"threshold_ms": 36000000}', false),
('badge_100h_total', 'endurance', 'gold', '100 Horas Acumuladas', 'Tempo total ≥ 6000 min', 200, 0, 'lifetime_duration', '{"threshold_ms": 360000000}', false),
-- Social
('badge_first_challenge', 'social', 'bronze', 'Primeiro Desafio', 'Complete qualquer desafio', 50, 0, 'challenges_completed', '{"count": 1}', false),
('badge_5_challenges', 'social', 'silver', '5 Desafios', 'Complete 5 desafios', 100, 0, 'challenges_completed', '{"count": 5}', false),
('badge_invicto', 'social', 'gold', 'Invicto', 'Vença 10 desafios 1v1 consecutivos', 200, 0, 'consecutive_wins', '{"count": 10}', false),
('badge_group_leader', 'social', 'silver', 'Líder de Grupo', 'Rank #1 em grupo ≥ 5 participantes', 100, 0, 'group_leader', '{"min_participants": 5}', false),
-- Especial
('badge_early_bird', 'special', 'bronze', 'Madrugador', 'Sessão antes das 06:00', 50, 0, 'session_before_hour', '{"hour_local": 6}', false),
('badge_night_owl', 'special', 'bronze', 'Coruja', 'Sessão após 22:00', 50, 0, 'session_after_hour', '{"hour_local": 22}', false);
```

---

## 11. DEPLOY CHECKLIST

### 11.1 Primeira vez — Backend

```bash
# 1. Link ao projeto remoto
supabase link --project-ref <project_id>

# 2. Push migrations (60 migration files)
supabase db push

# 3. Deploy ALL Edge Functions (54 functions)
for fn in verify-session evaluate-badges calculate-progression settle-challenge \
  compute-leaderboard submit-analytics token-create-intent token-consume-intent \
  clearing-confirm-sent clearing-confirm-received clearing-open-dispute \
  champ-create champ-invite champ-activate-badge champ-list champ-participant-list \
  complete-social-profile set-user-role send-push notify-rules \
  create-checkout-session webhook-payments list-purchases \
  auto-topup-check auto-topup-cron create-portal-session process-refund \
  eval-athlete-verification eval-verification-cron delete-account validate-social-login; do
  supabase functions deploy "$fn"
done

# 4. Set Edge Function secrets
supabase secrets set STRIPE_SECRET_KEY=sk_live_...
supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_...
supabase secrets set PORTAL_URL=https://portal.omnirunner.app

# 5. Configure pg_cron (run in SQL Editor)
ALTER DATABASE postgres SET app.supabase_url = 'https://<ref>.supabase.co';
ALTER DATABASE postgres SET app.service_role_key = 'eyJ...';

# 6. Seed badges (execute SQL from §10.1 in Dashboard SQL Editor)

# 7. Seed billing products (execute SQL from supabase/seed.sql)

# 8. Configure Auth Providers (Dashboard → Auth → Providers)
#    Google, Apple, Facebook

# 9. Configure Stripe webhook endpoint
#    URL: https://<ref>.supabase.co/functions/v1/webhook-payments
#    Events: checkout.session.completed, charge.refunded

# 10. Create first season
INSERT INTO public.seasons (name, status, starts_at_ms, ends_at_ms)
VALUES ('Temporada de Verão 2026', 'active', 1735689600000, 1743465600000);
```

### 11.2 Primeira vez — Portal Web

```bash
cd portal/
npm install
cp .env.example .env.local
# Edit .env.local with NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY

# Local dev
npm run dev

# Production build
npm run build

# Deploy (Vercel recommended)
vercel --prod
```

### 11.3 Atualizações

```bash
# Nova migration
supabase migration new <nome_descritivo>
# Editar supabase/migrations/<timestamp>_<nome>.sql
supabase db push

# Atualizar Edge Function
supabase functions deploy <function-name>

# Atualizar Portal
cd portal/ && npm run build && vercel --prod
```

---

## 12. MAPEAMENTO ENTITY → TABLE

| Dart Entity | Supabase Table | PK | Notas |
|-------------|---------------|-----|-------|
| `WorkoutSessionEntity` | `sessions` | `id` (UUID) | `status` é SMALLINT (ordinal do enum) |
| `LocationPointEntity` | Storage `session-points` (Protobuf) | - | Não tabela; arquivo binário no bucket |
| `BadgeEntity` | `badges` | `id` (TEXT) | Catálogo estático; `criteria` split em `criteria_type` + `criteria_json` |
| `BadgeAwardEntity` | `badge_awards` | `id` (UUID) | UNIQUE(user_id, badge_id) |
| `ProfileProgressEntity` | `profile_progress` | `user_id` (UUID) | 1:1 com auth.users |
| `XpTransactionEntity` | `xp_transactions` | `id` (UUID) | Append-only |
| `WalletEntity` | `wallets` | `user_id` (UUID) | 1:1 com auth.users |
| `LedgerEntryEntity` | `coin_ledger` | `id` (UUID) | Append-only |
| `SeasonEntity` | `seasons` | `id` (UUID) | Admin-managed |
| `SeasonProgressEntity` | `season_progress` | (`user_id`, `season_id`) | Composite PK |
| `MissionEntity` | `missions` | `id` (UUID) | `criteria` split como badges |
| `MissionProgressEntity` | `mission_progress` | `id` (UUID) | - |
| `FriendshipEntity` | `friendships` | `id` (UUID) | CHECK(user_id_a < user_id_b) |
| `GroupEntity` | `groups` | `id` (UUID) | - |
| `GroupMemberEntity` | `group_members` | `id` (UUID) | UNIQUE(group_id, user_id) |
| `GroupGoalEntity` | `group_goals` | `id` (UUID) | - |
| `LeaderboardEntity` | `leaderboards` | `id` (TEXT) | Composite string ID |
| `LeaderboardEntryEntity` | `leaderboard_entries` | (`leaderboard_id`, `user_id`) | - |
| `ChallengeEntity` | `challenges` | `id` (UUID) | Rules denormalized into columns |
| `ChallengeParticipantEntity` | `challenge_participants` | (`challenge_id`, `user_id`) | - |
| `ChallengeResultEntity` | `challenge_results` | `id` (UUID) | One row per participant |
| `ChallengeRunBindingEntity` | `challenge_run_bindings` | (`session_id`, `challenge_id`) | - |
| `EventEntity` | `events` | `id` (UUID) | Rewards denormalized into columns |
| `EventParticipationEntity` | `event_participations` | `id` (UUID) | UNIQUE(event_id, user_id) |
| `CoachingGroupEntity` | `coaching_groups` | `id` (UUID) | - |
| `CoachingMemberEntity` | `coaching_members` | `id` (UUID) | UNIQUE(group_id, user_id) |
| `CoachingInviteEntity` | `coaching_invites` | `id` (UUID) | - |
| — | `billing_customers` | `group_id` (UUID) | Portal-only; 1:1 com coaching_groups |
| — | `billing_products` | `id` (UUID) | Portal-only; is_active flag |
| — | `billing_purchases` | `id` (UUID) | Portal-only; status lifecycle + source (manual/auto_topup) |
| — | `billing_events` | `id` (UUID) | Portal-only; append-only audit; stripe_event_id dedup |
| — | `billing_auto_topup_settings` | `group_id` (UUID) | Portal-only; 1:1 PK |
| — | `billing_refund_requests` | `id` (UUID) | Portal-only; UNIQUE open per purchase |
| — | `billing_limits` | `group_id` (UUID) | Portal-only; daily caps |
| — | `strava_activity_history` | `user_id` (UUID), `strava_activity_id` (BIGINT) | Histórico importado do Strava; upsert por strava_activity_id |
| — | `parks` | `id` (TEXT) | Catálogo de parques; 47 seedados; center_lat, center_lng, radius_m para detecção |
| — | `park_activities` | `id` (UUID) | Unique por session_id; FK → parks.id, profiles.id |
| — | `park_leaderboard` | `park_id` + `user_id` + `category` | Rankings recalculados automaticamente via trigger |
| — | `park_segments` | `id` (UUID), `park_id` (TEXT) | Segmentos dentro de parques com recordes |

---

## 12b. TABELAS NOVAS — Sprint 25.0.0 (Strava-Only + Parks)

### `strava_activity_history`

| Coluna | Tipo | Notas |
|--------|------|-------|
| `user_id` | UUID | FK → profiles.id; RLS: own read/write |
| `strava_activity_id` | BIGINT | Unique; ID do Strava |
| `name` | TEXT | Nome da atividade |
| `distance_m` | DOUBLE | Distância em metros |
| `moving_time_s` | INT | Tempo em movimento (segundos) |
| `elapsed_time_s` | INT | Tempo total (segundos) |
| `total_elevation_gain_m` | DOUBLE | Elevação total |
| `average_speed_mps` | DOUBLE | Velocidade média (m/s) |
| `max_speed_mps` | DOUBLE | Velocidade máxima (m/s) |
| `average_heartrate` | DOUBLE | FC média |
| `max_heartrate` | DOUBLE | FC máxima |
| `start_date_utc` | TIMESTAMPTZ | Data/hora UTC |
| `summary_polyline` | TEXT | Polyline encoded (Google format) |
| `imported_at` | TIMESTAMPTZ | Data de importação |

### `park_activities`

| Coluna | Tipo | Notas |
|--------|------|-------|
| `id` | UUID | PK |
| `user_id` | UUID | FK → profiles.id |
| `park_id` | TEXT | ID do parque (do seed) |
| `distance_m` | DOUBLE | Distância dentro do parque |
| `start_time` | TIMESTAMPTZ | Início da atividade |
| `display_name` | TEXT | Nome do usuário (desnormalizado) |

### `park_leaderboard`

| Coluna | Tipo | Notas |
|--------|------|-------|
| `park_id` | TEXT | ID do parque |
| `user_id` | UUID | FK → profiles.id |
| `category` | TEXT | pace/distance/frequency/streak/evolution/longestRun |
| `rank` | INT | Posição no ranking |
| `value` | DOUBLE | Valor da métrica |
| `period` | TEXT | all_time / weekly / monthly |
| `display_name` | TEXT | Nome do usuário (desnormalizado) |

### `park_segments`

| Coluna | Tipo | Notas |
|--------|------|-------|
| `id` | UUID | PK |
| `park_id` | TEXT | ID do parque |
| `name` | TEXT | Nome do segmento |
| `length_m` | DOUBLE | Comprimento em metros |
| `record_holder_name` | TEXT | Nome do recordista |
| `record_pace_sec_per_km` | DOUBLE | Pace do recorde |

---

## 13. INSTRUÇÕES PARA INTEGRAÇÃO

### Ao receber este documento:

1. **Leia as migrations SQL** em `supabase/migrations/` (60 arquivos) — elas são o schema definitivo.
2. **Leia as Edge Functions** em `supabase/functions/` (54 functions) — elas contêm toda a lógica server-side.
3. **Leia o portal** em `portal/` — Next.js 14, App Router, Tailwind + shadcn/ui.
4. **Use o mapeamento Entity→Table** (§12) para traduzir entre Dart e SQL.
5. **Respeite as RLS policies** — nunca sugira queries que ignorem segurança.
6. **Toda lógica de gamificação** que afeta Coins/XP/Badges deve passar por Edge Functions, nunca diretamente pelo client.
7. **Billing NUNCA aparece no app mobile** — preços, checkout, pagamentos são exclusivos do portal web.
8. **O frontend mobile é offline-first** — dados locais (Isar) são sincronizados em background.
9. **Referências de specs**: `GAMIFICATION_POLICY.md`, `PROGRESSION_SPEC.md`, `SOCIAL_SPEC.md`, `contracts/analytics_api.md`.
10. **Decisões arquiteturais**: `docs/DECISIONS_LOG.md` (111 decisões documentadas, incluindo billing, auto top-up, refunds, limites, strava-only, parks, social, push, polimento, liga, wrapped, running dna, backend audit, liga estadual, auditoria final, Strava OAuth fix, cooperative→team, FlutterWebAuth2, verificação min-distance + Strava backfill, Strava connect AuthFailed fix, CallbackActivity host disambiguation).

### RPCs disponíveis (funções SQL SECURITY DEFINER):

| RPC | Descrição |
|-----|-----------|
| `increment_wallet_balance(user_id, delta)` | Credita/debita balance_coins |
| `increment_wallet_pending(user_id, delta)` | Credita/debita pending_coins |
| `release_pending_to_balance(user_id, amount)` | Move pending → balance |
| `increment_profile_progress(user_id, ...)` | Atualiza XP, streaks, stats |
| `decrement_token_inventory(group_id, amount)` | Debita available_tokens (CHECK >= 0) |
| `increment_inventory_burned(group_id, amount)` | Incrementa lifetime_burned |
| `increment_rate_limit(user_id, fn, window_seconds)` | Rate limiting atômico |
| `cleanup_rate_limits()` | Remove entries > 1h |
| `fn_fulfill_purchase(purchase_id)` | paid → fulfilled + fn_credit_institution |
| `fn_credit_institution(group_id, amount, ...)` | Audit + inventory increment |
| `fn_switch_assessoria(user_id, group_id)` | Burn coins + switch group |
| `fn_search_coaching_groups(query)` | Search by name ou UUID array (filtra approved) |
| `fn_create_assessoria(name, ...)` | Create group + admin + invite_code (status: pending_approval) |
| `fn_lookup_group_by_invite_code(code)` | Lookup by 8-char code (filtra approved) |
| `fn_platform_approve_assessoria(group_id)` | Platform admin aprova assessoria |
| `fn_platform_reject_assessoria(group_id, reason)` | Platform admin rejeita assessoria |
| `fn_platform_suspend_assessoria(group_id, reason)` | Platform admin suspende assessoria |
| `get_billing_limits(group_id)` | Daily limits com fallback defaults |
| `check_daily_token_usage(group_id, type)` | Remaining capacity today |
| `fn_search_users(query)` | Busca por nome para adicionar amigos (SECURITY DEFINER) |
| `fn_refresh_park_leaderboard(p_park_id)` | Recalcula rankings de um parque (chamado via trigger) |

### Tarefas típicas:

- Implementar repositórios Supabase no Flutter (camada `data/datasources/supabase_*`)
- Wiring do sync pipeline (pós-sessão → verify → badges → analytics)
- Implementar Realtime subscriptions para challenges e leaderboards
- Criar UI para Social features conectada ao Supabase
- Portal: novas telas billing, relatórios, configurações avançadas
- Integrar auto top-up notifications no app (via push quando top-up triggered)

---

*Gerado em 2026-02-18, atualizado em 2026-02-26 (Sprint 25.0.0 + Parks E2E + Backend Audit + Liga Admin + Liga Estadual + Auditoria Final) — 70 tabelas, 55 Edge Functions, 63 migrations, DECISAO 102*
