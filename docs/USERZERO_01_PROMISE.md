# USERZERO_01_PROMISE — First Impression Analysis

> Author perspective: UX Research Lead, first contact with the product.
> Method: code inspection of user-facing screens only. No internal docs consulted.

---

## Product Promise in 5 Lines

1. **Omni Runner is a gamified running platform** that turns everyday runs into competitive challenges between athletes managed by professional coaching groups ("assessorias").
2. **Athletes earn XP, badges, streaks, and virtual currency (OmniCoins)** by running — with data imported automatically from Strava and any GPS watch.
3. **Assessorias (running clubs/coaches) manage their athletes** through a B2B portal with KPIs, credit distribution, verification, CRM, and financial tools.
4. **OmniCoins create a closed-loop economy** where coaches buy credits, distribute them to athletes as rewards/stakes for challenges, and the platform handles custody and clearing between clubs.
5. **The platform targets the Brazilian market** with Portuguese UI, Brazilian park detection, and integration with local payment systems (MercadoPago).

---

## Who Is This For

### Primary Users

| Persona | Product | Evidence |
|---------|---------|----------|
| **Recreational/amateur runners** in Brazil | Mobile App | `welcome_screen.dart:108-126` — bullets: "Desafie corredores", "Treine com sua assessoria", "Participe de campeonatos", "Evolua com métricas reais" |
| **Running assessorias (coaching groups/clubs)** | Web Portal | `portal/README.md:1` — "Portal B2B para gestão de assessorias esportivas"; sidebar has 25+ nav items for management |
| **Assessoria staff** — admin_master, coach, assistant | Web Portal | `sidebar.tsx:14-40` — role-based nav with 3 staff tiers |
| **Platform administrators** | Web Portal (`/platform/*`) | `sidebar.tsx:42-44` — PLATFORM_ITEMS with `platform_admin` role |

### The Assessoria Model

The product is built around the concept of "assessorias" — organized running groups led by coaches. This is a distinctly **Brazilian running culture** concept. Athletes don't use the app solo; they belong to a group.

**Evidence:**
- `onboarding_role_screen.dart:187-203` — first gate after login is choosing between "Sou atleta" and "Represento uma assessoria"
- `athlete_dashboard_screen.dart:434-449` — if no assessoria, the card says "Entrar em assessoria" / "Toque para encontrar"
- `more_screen.dart:63-99` — "Minha Assessoria" section with QR scanning and pending deliveries
- Challenges and championships require an assessoria: `athlete_dashboard_screen.dart:214` — `AssessoriaRequiredSheet.guard()`

---

## What It Is NOT

| It is NOT... | Evidence |
|--------------|----------|
| A general fitness tracker | No weight training, cycling, swimming, or gym features found. All entities revolve around running: `WorkoutSessionEntity`, `totalDistanceM`, `pace`, `km` |
| A Strava replacement | The app explicitly integrates WITH Strava as a data source (`today_screen.dart:458-459` — "O Omni Runner funciona com o Strava"). It does not record GPS natively as the primary flow — it imports |
| A solo runner app | Social/group mechanics are core, not optional. Challenges, assessoria membership, friend feeds, championships — all require other people |
| An English-first product | All UI strings in Portuguese (`login_screen.dart:55` — "Preencha email e senha"; `welcome_screen.dart:108` — "Desafie corredores"); English exists in i18n files but PT-BR is the default |
| A free consumer app | The B2B portal has billing (`/billing`, `/credits`, `/custody`), MercadoPago checkout, credit purchasing, and a custody/clearing system with USD-backed coins. Revenue model is assessorias buying credits |
| A workout prescription tool | Although "Treinos" (workouts) and "Entrega Treinos" exist in the portal sidebar, the app focuses on tracking/gamification rather than training plan authoring |

---

## First Impression Analysis

### What the App Shows (Athlete Side)

**Bottom navigation:** 4 tabs — Inicio (Home), Hoje (Today), Historico (History), Mais (More)

**Home (AthleteDashboardScreen):** Grid of 7 cards:
1. Meus desafios (My challenges)
2. Minha assessoria / Entrar em assessoria (My group / Join a group)
3. Meu progresso (My progress — XP, badges, missions)
4. Verificacao (Verified athlete status)
5. Campeonatos (Championships)
6. Parques (Parks — rankings & community)
7. Meus creditos (My OmniCoins)

**Evidence:** `athlete_dashboard_screen.dart:421-494`

**Today (TodayScreen):** Daily dashboard with:
- Streak banner (fire emoji, days consecutive, milestones with XP rewards)
- Active challenges card
- Active championships card
- "Bora correr?" CTA / Strava connect prompt
- Last run recap (distance, pace, duration, HR, comparison vs. previous)
- Park check-in (auto-detected from GPS polygon)
- Quick stats (Level, XP, weekly sessions, lifetime km, total runs)

**Evidence:** `today_screen.dart:454-538`

**More screen:** Assessoria management, QR scanner, social features (invite friends, my friends, activity feed), profile, settings, logout.

**Evidence:** `more_screen.dart:59-283`

### What the Portal Shows (Assessoria Side)

**Sidebar navigation (25 items):**

| Section | Pages |
|---------|-------|
| Overview | Dashboard |
| Financial/Currency | Custodia, Compensacoes, Swap de Lastro, Conversao Cambial |
| Gamification | Badges |
| Compliance | Auditoria |
| Operations | Distribuicoes, Atletas, Verificacao |
| Engagement | Engajamento, Presenca, CRM Atletas, Mural, Comunicacao, Analise Presenca, Alertas/Risco |
| Exports | Exports |
| Training | Treinos, Analise Treinos, Entrega Treinos, TrainingPeaks |
| Financial | Financeiro |
| Activity | Execucoes |
| Admin | Configuracoes |

**Evidence:** `sidebar.tsx:14-39`

**Dashboard KPIs:** Credits available, athlete count, verified count, active users (7d), runs (7d), km (7d), challenges (30d), purchases — with week-over-week trends.

**Evidence:** `portal/src/app/(portal)/dashboard/page.tsx:200-253`

---

## First Impression Grade: 72/100

### Strengths (+)

| Strength | Evidence | Impact |
|----------|----------|--------|
| **Clear value proposition** on WelcomeScreen | `welcome_screen.dart:104-126` — 4 concise bullets | User immediately understands what the app does |
| **Smooth onboarding animation** | `welcome_screen.dart:17-51` — staggered fade/slide with AnimationController | Professional first impression |
| **Multi-provider auth** | Google, Apple, Instagram, Email — covers main Brazilian preferences | Low friction to sign up |
| **Offline resilience** | Mock mode, Isar fallback, ConnectivityMonitor, OfflineQueue | App works without network |
| **Rich "Today" screen** | Streak, challenges, recap, park check-in, comparison | Actionable daily engagement |
| **Role-based portal** | 3 staff roles with filtered sidebar | Appropriate complexity management |
| **Portal dashboard has trends** | Week-over-week session/distance trends | Coaches can track group health |
| **i18n infrastructure in place** | ARB files (Flutter), next-intl (Portal) | Ready for expansion |

### Weaknesses (-)

| Weakness | Evidence | Impact |
|----------|----------|--------|
| **Permanent role selection with no escape** | `onboarding_role_screen.dart:68-71` — "não pode ser alterada depois" | Terrifying for a new user; high abandon risk at onboarding |
| **Assessoria code required** | `join_assessoria_screen.dart` — must obtain code from a coach | Dead end for organic users without a coaching group |
| **No portal self-registration** | `middleware.ts:113-117` — redirect to `/no-access` if not pre-provisioned | Assessoria admins cannot onboard themselves |
| **Strava dependency for core experience** | `today_screen.dart:897-993` — prominent CTA "Conecte o Strava para começar" | Users without Strava see an empty/degraded Today screen |
| **Portal sidebar has 25 items** | `sidebar.tsx:14-39` — flat list, no grouping or collapse | Cognitive overload; no progressive disclosure |
| **All UI text hardcoded in Portuguese** | UI strings like "Bora correr?", "Desafie corredores" scattered across files | International users excluded; translation debt |
| **No root page.tsx** | `portal/src/app/page.tsx` — just `redirect("/dashboard")` | No marketing landing page; cold entry |
| **WelcomeScreen says nothing about OmniCoins/economy** | `welcome_screen.dart:104-126` — only mentions challenges, assessoria, championships, metrics | The economic layer (a major differentiator) is hidden until deep in the app |

### Risks

| Risk | Evidence |
|------|----------|
| User might select wrong role and be permanently stuck | `onboarding_role_screen.dart` — confirmation dialog warns but doesn't prevent |
| Organic growth limited — athletes must know an assessoria to get full value | `AssessoriaRequiredSheet.guard()` gates challenges and championships |
| Portal assumes provisioned data — no zero-state onboarding for new coaching groups | Dashboard shows "0" for everything with no setup wizard |

---

## Evidence Index

| File | What it revealed |
|------|------------------|
| `README.md` | Product description, architecture, custody model |
| `omni_runner/pubspec.yaml` | App name, version (0.9.0), dependencies (Strava, BLE, QR, maps) |
| `portal/package.json` | Portal name, scripts, dependencies (Supabase, next-intl, zod) |
| `omni_runner/lib/core/config/app_config.dart` | Environment modes (dev/prod), mock fallback |
| `omni_runner/lib/core/config/feature_flags.dart` | Feature flag system with deterministic rollout |
| `omni_runner/lib/main.dart` | Bootstrap flow, Sentry, Firebase, recovery check |
| `omni_runner/lib/presentation/screens/auth_gate.dart` | Full onboarding flow with 8 destination states |
| `omni_runner/lib/presentation/screens/welcome_screen.dart` | 4-bullet value prop, "COMECAR" CTA |
| `omni_runner/lib/presentation/screens/login_screen.dart` | 4 auth methods, invite banner |
| `omni_runner/lib/presentation/screens/onboarding_role_screen.dart` | Permanent ATLETA vs STAFF choice |
| `omni_runner/lib/presentation/screens/home_screen.dart` | Tab structure: athlete (4 tabs) vs staff (2 tabs) |
| `omni_runner/lib/presentation/screens/athlete_dashboard_screen.dart` | 7-card grid, assessoria-dependent features |
| `omni_runner/lib/presentation/screens/today_screen.dart` | Streaks, challenges, run recap, park detection, Strava CTA |
| `omni_runner/lib/presentation/screens/more_screen.dart` | Social, QR, settings, sign-out |
| `portal/src/app/page.tsx` | Root redirect to /dashboard |
| `portal/src/app/login/page.tsx` | Portal login (Google, Apple, email) |
| `portal/src/middleware.ts` | Auth + role enforcement, no-access redirect |
| `portal/src/app/(portal)/layout.tsx` | Layout with branding, role verification, feature flags |
| `portal/src/components/sidebar.tsx` | 25 nav items, role filtering |
| `portal/src/app/(portal)/dashboard/page.tsx` | KPI stat blocks with trends |
