# ADR-003: Feature Flags via Supabase

**Status:** Accepted  
**Date:** 2026-02-01

## Context

Precisamos de rollout gradual de features sem deploy. Alternativas: LaunchDarkly (custo), PostHog (overhead), custom.

## Decision

Tabela `feature_flags` no Supabase com:
- `key` (string) — identificador único
- `enabled` (bool) — kill switch global
- `rollout_pct` (int 0-100) — percentual de rollout

Bucketing determinístico por `hash(userId + flagKey) % 100` — mesmo usuário sempre recebe o mesmo resultado.

Clients:
- **Flutter:** `FeatureFlagService` (load on startup, cache in memory)
- **Portal:** `isFeatureEnabled()` com TTL de 60s
- **Admin:** `/platform/feature-flags` para toggle visual

## Consequences

- Zero custo adicional (usa Supabase existente)
- Determinístico — sem flickering para o usuário
- Sem real-time push (TTL de 60s no Portal, manual refresh no App)
- Admin page permite non-engineers alterarem flags
