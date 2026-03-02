# ADR-006: Estratégia de Testes

**Status:** Accepted  
**Date:** 2026-02-01

## Context

O projeto possui duas aplicações (Flutter App + Next.js Portal) com lógica de negócio complexa (gamificação, billing, coaching). Precisamos de cobertura de testes eficaz sem dependências externas nos testes.

## Decision

### Flutter App
- **Unit tests** para use cases com fake repositories (in-memory)
- **Contract tests** para data layer repos — validam interface sem Isar binaries
- **BLoC tests** com `stream.listen` (sem `bloc_test` por conflito com `isar_generator`)
- **Widget tests** para widgets reutilizáveis e screens com `BlocProvider` + Cubit stubs
- Testes rodam em CI via `flutter test` (GitHub Actions)

### Next.js Portal
- **Unit tests** (Vitest + happy-dom) para componentes React e API routes
- **E2E tests** (Playwright) para fluxos críticos: auth, security, a11y
- Mocks: `vi.mock` para Supabase, `NextIntlClientProvider` wrapper para i18n
- CI: Vitest run + Playwright headless Chromium

### Shared
- Zero dependência de banco/API real nos testes
- Testes determinísticos (sem flakiness de rede)
- Pre-commit hooks (`lefthook`) rodam analyze/lint

## Consequences

- Testes rápidos (~5s Portal, ~30s Flutter)
- Fácil de adicionar novos testes seguindo padrões existentes
- Contract tests cobrem gaps onde integration tests seriam caros
