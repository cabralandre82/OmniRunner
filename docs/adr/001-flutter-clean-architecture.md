# ADR-001: Clean Architecture no Flutter App

**Status:** Accepted  
**Date:** 2025-06-01

## Context

O app Flutter precisa escalar para dezenas de funcionalidades (rastreamento GPS, gamificação, coaching, social, marketplace) mantendo testabilidade e manutenibilidade.

## Decision

Adotar Clean Architecture com 3 camadas:

- **Domain** — Entities, Repository interfaces (`I*Repo`), Use Cases
- **Data** — Isar (local) + Supabase (remote) repository implementations
- **Presentation** — BLoC pattern para state management, Screens e Widgets

Dependency Injection via `GetIt` (`service_locator.dart`).

## Consequences

- Use cases são testáveis com fake repositories (sem deps externas)
- BLoCs isolados — testáveis sem UI
- Troca de backend (ex: Isar → Drift) sem impacto na camada de domínio
- Curva de aprendizado maior para novos devs (muitas abstrações)
