# CHAOS ARCHITECTURE MAP

## System Overview

```
project-running/
├── omni_runner/          # Flutter mobile app (100 screens, 26 blocs, 38 repos)
├── portal/               # Next.js web portal (53 pages, 37 API routes, 33 components)
├── supabase/             # Backend: 79 migrations, 57 edge functions
├── docs/                 # Documentation
└── tools/                # Scripts
```

## Component Counts

| Component | Count |
|-----------|-------|
| Flutter Screens | 100 |
| Flutter BLoCs | 26 |
| Flutter Repositories | 38 |
| Flutter Data Services | 3 |
| Flutter Domain Entities | 66 |
| Isar Collections | 27 |
| Portal Pages | 53 |
| Portal API Routes | 37 |
| Portal Components | 33 |
| Supabase Migrations | 79 |
| Edge Functions | 57 |
| Functions with verify_jwt=false | 42 |

## Data Flow

```
┌──────────────────────────────────────────────────────┐
│                    EXTERNAL                          │
├──────────┬──────────┬──────────┬─────────┬──────────┤
│  Strava  │MercadoPago│ Stripe  │Firebase │ Health   │
│  Webhook │ Webhook  │ Webhook │ (FCM)   │ Kit/BLE  │
└────┬─────┴────┬─────┴────┬────┴────┬────┴──────────┘
     │          │          │         │
     ▼          ▼          ▼         ▼
┌──────────────────────────────────────────────────────┐
│          SUPABASE EDGE FUNCTIONS (57)                │
│  42 with verify_jwt=false → requireUser() for auth   │
│  Webhooks: no JWT, service-role client               │
└────┬─────────────────────────────────────────────────┘
     │
     ▼
┌──────────────────────────────────────────────────────┐
│            SUPABASE (PostgreSQL + RLS)               │
│  profiles, coaching_groups, coaching_members,        │
│  sessions, wallet, billing_*, challenges,            │
│  feature_flags, workout_*, wearable_*, ...           │
└────┬─────────────────┬────────────────┬──────────────┘
     │                 │                │
     ▼                 ▼                ▼
┌───────────┐  ┌───────────────┐  ┌───────────┐
│  FLUTTER  │  │   PORTAL      │  │  ISAR     │
│  APP      │  │   (Next.js)   │  │  (Local)  │
│  100 scr  │  │   53 pages    │  │  27 colls │
└───────────┘  └───────────────┘  └───────────┘
```

## Auth Boundaries

| Boundary | Mechanism |
|----------|-----------|
| Flutter → Supabase | Supabase SDK with stored JWT |
| Portal → Supabase | Server client via cookies |
| Edge functions (user) | `requireUser()` validates JWT |
| Edge functions (webhooks) | HMAC/service-role, no JWT |
| Platform admin | `profiles.platform_role = 'admin'` |
| Staff routes | `coaching_members` role check |

## Key Risk Areas for Chaos Testing

| # | Risk Area | Impact |
|---|-----------|--------|
| 1 | ~40 screens bypass repositories (direct Supabase) | Inconsistent error handling |
| 2 | Offline queue in SharedPreferences | Duplicate/stuck operations |
| 3 | Isar + Supabase sync conflicts | Split-brain data |
| 4 | Feature flags unavailable | App fails to load |
| 5 | Portal cookies tampered | Cross-tenant access |
| 6 | Payment webhook idempotency | Duplicate charges |
| 7 | BLE/Health hardware failures | Crash propagation |
| 8 | Deep link race conditions | Lost invite codes |
| 9 | 42 edge functions with verify_jwt=false | Auth bypass if requireUser() missing |
| 10 | Concurrent sync operations | Data corruption |
