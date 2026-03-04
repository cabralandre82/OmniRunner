# USERZERO_00_SETUP — Discovery from Code

> Author perspective: UX Research Lead, first contact with the codebase.
> Method: code inspection only — no internal docs read, no assumptions.

---

## 1. What Are These Products?

The workspace contains **three co-located projects**:

| Project | Tech | What it appears to be |
|---------|------|-----------------------|
| `omni_runner/` | Flutter 3.22+ (Dart 3) | Mobile app (Android + iOS) for **athletes** |
| `portal/` | Next.js 14, TypeScript, Tailwind | Web portal for **assessorias** (coaching groups / running clubs) |
| `supabase/` | Supabase (Postgres, Edge Functions) | Shared backend |

**Evidence:**
- `README.md:3` — "Plataforma de corrida com gamificação e coaching"
- `omni_runner/pubspec.yaml:1-2` — name: `omni_runner`, description: "plataforma de corrida com gamificação e coaching"
- `portal/package.json:2` — name: `portal`
- `portal/README.md:1` — "Portal B2B para gestão de assessorias esportivas"

---

## 2. How to Run Each Product

### 2.1 Mobile App (Flutter)

```bash
cd omni_runner
flutter pub get
cp .env.example .env.dev
# Fill: SUPABASE_URL, SUPABASE_ANON_KEY, MAPTILER_API_KEY (required)
# Optional: SENTRY_DSN, GOOGLE_WEB_CLIENT_ID, STRAVA_CLIENT_ID, STRAVA_CLIENT_SECRET
flutter run --flavor dev --dart-define-from-file=.env.dev
```

**Evidence:** `omni_runner/README.md:20-29`, `omni_runner/lib/core/config/app_config.dart` (all env vars read via `String.fromEnvironment`).

### 2.2 Web Portal (Next.js)

```bash
cd portal
npm ci
cp .env.example .env.local
# Fill: NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY (required)
# Optional: NEXT_PUBLIC_SENTRY_DSN, SENTRY_ORG, SENTRY_PROJECT, SENTRY_AUTH_TOKEN
npm run dev
# → http://localhost:3000
```

**Evidence:** `portal/README.md:14-26`, `portal/package.json:6` (`"dev": "next dev"`).

### 2.3 Backend (Supabase)

No standalone run instructions found. The backend is hosted Supabase — edge functions and migrations live in `supabase/`. The apps connect via `SUPABASE_URL` + `SUPABASE_ANON_KEY`.

---

## 3. Environment Modes

### 3.1 Flutter App

Two modes: **dev** and **prod**, controlled by `APP_ENV` compile-time define.

| Mode | How to trigger | Behavior differences |
|------|---------------|---------------------|
| `dev` | `APP_ENV=dev` (default) | Full logging, Sentry tracesSampleRate = 1.0 |
| `prod` | `APP_ENV=prod` | Logger minLevel = info, Sentry tracesSampleRate = 0.2 |

**Graceful degradation (mock mode):** If `SUPABASE_URL` / `SUPABASE_ANON_KEY` are empty or `Supabase.initialize()` fails, the app enters `backendMode = 'mock'`. It shows the WelcomeScreen, and some features use local-only Isar data.

**Evidence:**
- `app_config.dart:19` — `appEnv = String.fromEnvironment('APP_ENV', defaultValue: 'dev')`
- `app_config.dart:48` — `backendMode => _supabaseInitOk ? 'remote' : 'mock'`
- `main.dart:78-79` — Sentry sample rates differ by env
- `main.dart:123-125` — Logger min level set in prod

### 3.2 Web Portal

Single-mode (inherits from `NEXT_PUBLIC_ENV`), but shows a staging banner when environment !== `production`.

**Evidence:** `portal/src/app/(portal)/layout.tsx:137` — `const environment = process.env.NEXT_PUBLIC_ENV ?? "production"`

### 3.3 Feature Flags

Both products support feature flags from a shared `feature_flags` Supabase table:

- **Flutter:** `FeatureFlagService` — loads flags at startup, deterministic per-user rollout via hash bucket (`userId:flagKey`). Evidence: `omni_runner/lib/core/config/feature_flags.dart`
- **Portal:** `isFeatureEnabled()` function. Evidence: `portal/src/app/(portal)/layout.tsx:119`
- **Admin UI:** `/platform/feature-flags` page in the portal. Evidence: `portal/src/app/platform/feature-flags/page.tsx` exists

---

## 4. What a First-Time User Encounters

### 4.1 Mobile App — Athlete Journey

The user flows through a strict gate (`AuthGate`):

```
App launch
  ↓
[Recovery check] — if crashed mid-session → RecoveryScreen (resume/discard)
  ↓
AuthGate resolves destination:
  ↓
[1] WelcomeScreen — animated landing with 4 bullets:
    • "Desafie corredores"
    • "Treine com sua assessoria"
    • "Participe de campeonatos"
    • "Evolua com métricas reais"
    CTA: "COMEÇAR"
  ↓
[2] LoginScreen — Social sign-in (Google, Apple on iOS, Instagram) or email/password
    • Sign-up and sign-in on the same form
    • Password reset supported
    • If invite link pending, shows banner: "Você recebeu um convite!"
  ↓
[3] OnboardingRoleScreen — PERMANENT role selection:
    • "Sou atleta" — trains, competes, tracks progress
    • "Represento uma assessoria" — manages athletes, organizes events
    ⚠ Warning: "Essa escolha é permanente e não pode ser alterada depois"
  ↓
[4a] If ATLETA → JoinAssessoriaScreen (enter assessoria code)
[4b] If STAFF  → StaffSetupScreen
  ↓
[5] OnboardingTourScreen (first-time only, athletes only)
  ↓
[6] HomeScreen (bottom tabs)
```

**Evidence:**
- `auth_gate.dart:28-32` — Flow comment
- `welcome_screen.dart:104-126` — 4 bullet points
- `login_screen.dart:12-16` — Docstring with social sign-in list
- `onboarding_role_screen.dart:9-13` — Permanent role selection
- `onboarding_role_screen.dart:68-71` — "Essa escolha é permanente" warning
- `home_screen.dart:13-14` — Athlete tabs: Início, Hoje, Histórico, Mais

### 4.2 Web Portal — Staff Journey

```
http://localhost:3000 → redirects to /dashboard
  ↓
Middleware checks auth → no user → redirect /login
  ↓
LoginScreen: "Omni Runner — Portal da Assessoria"
  • Google, Apple sign-in
  • Email/password
  ↓
Middleware checks coaching_members for staff role → no membership → /no-access
  ↓
If multiple groups → /select-group
If single group → set cookies, proceed to /dashboard
  ↓
Dashboard: KPIs — credits, athletes, verified, active (7d), runs, km, challenges
```

**Evidence:**
- `portal/src/app/page.tsx` — `redirect("/dashboard")`
- `portal/src/middleware.ts:69-74` — redirect to `/login` if no user
- `portal/src/middleware.ts:113-117` — redirect to `/no-access` if no staff membership
- `portal/src/app/login/page.tsx:213-214` — title "Omni Runner", subtitle "Portal da Assessoria"
- `portal/src/app/(portal)/dashboard/page.tsx` — KPI stat blocks

---

## 5. What Blocks a First-Time User

### 5.1 Mobile App

| Blocker | When | Severity |
|---------|------|----------|
| Missing env vars | App won't connect to backend; falls to mock mode | High — core features unusable |
| No Supabase connectivity | WelcomeScreen shown, most features offline-degraded | High |
| Role selection is permanent | User cannot undo ATLETA ↔ STAFF choice | Medium — irreversible UX decision at step 3 |
| Assessoria code required (athletes) | Must obtain from a coach to join a group | Medium — depends on external person |
| Strava connection needed | App strongly nudges Strava connect ("Conecte o Strava para começar") to enable run import | Medium — functional without, but degraded |

### 5.2 Web Portal

| Blocker | When | Severity |
|---------|------|----------|
| Missing env vars | Portal won't start | Critical |
| No staff membership | Redirected to `/no-access` — dead end | Critical — cannot self-register as staff |
| Must be coaching_members with role admin_master/coach/assistant | Pre-provisioned via Supabase | High — requires DB seeding |
| Group must exist | Cookie `portal_group_id` required | High — requires coaching_groups row |

**Evidence:**
- `middleware.ts:113-117` — no-access redirect
- `middleware.ts:87-88` — role must be in `["admin_master", "coach", "assistant"]`
- Portal has no self-registration flow — staff must be provisioned in the database

---

## 6. Authentication Methods

| Method | App | Portal |
|--------|-----|--------|
| Email + Password | Yes | Yes |
| Google OAuth | Yes | Yes |
| Apple Sign-In | Yes (iOS only) | Yes |
| Instagram OAuth | Yes | No |
| TikTok | Mentioned in docstring but no implementation found | No |

**Evidence:**
- `login_screen.dart:12` — "social sign-in buttons (Google, Apple, Instagram, TikTok)" (TikTok button not in build method)
- `portal/src/app/login/page.tsx:43` — `provider: "google" | "apple" | "facebook"` (Facebook listed but button is Apple)

---

## 7. Summary

This is a **two-sided platform** for the Brazilian running market:
- **Supply side (Portal):** Running coaches ("assessorias") manage their athletes, distribute virtual currency ("OmniCoins"), and track engagement.
- **Demand side (App):** Runners join an assessoria, participate in challenges/championships, earn XP/badges, and use Strava-imported run data as proof of activity.

To get a functional local environment, you need:
1. A Supabase project with migrations applied
2. Env vars configured for both app and portal
3. At least one `coaching_groups` row and one `coaching_members` staff row in the database for the portal to work
4. A Strava developer account (optional but strongly encouraged by the app UX)
