# Omni Runner

Plataforma de corrida com gamificação e coaching. Inclui app mobile (Flutter), portal de gestão B2B (Next.js) e backend (Supabase).

## Projetos

| Diretório | Tecnologia | Descrição |
|-----------|------------|-----------|
| `omni_runner/` | Flutter 3.22+ | App mobile (Android/iOS) |
| `portal/` | Next.js 14 | Portal de gestão para assessorias |
| `omni_runner/supabase/` | Supabase | Migrations, Edge Functions, RLS policies |

## Funcionalidades

**App (Atleta)**
- Rastreamento GPS de corridas em tempo real
- Coaching por áudio (TTS)
- Gamificação: XP, níveis, badges, missões, desafios
- Mapas offline com MapLibre
- Integração Strava
- Modo offline com sync automático

**Portal (Assessoria)**
- Dashboard com KPIs e tendências
- Gestão de atletas e verificação
- Sistema de créditos/coins
- Ranking por assessoria
- Branding customizável
- Relatórios CSV

## Quick Start

```bash
# Clonar
git clone <repo-url>
cd project-running

# Instalar git hooks
npm install
npx lefthook install

# App Flutter
cd omni_runner
flutter pub get
cp .env.example .env.dev
# Preencher variáveis em .env.dev
flutter run --flavor dev --dart-define-from-file=.env.dev

# Portal Next.js
cd portal
npm ci
cp .env.example .env.local
# Preencher variáveis em .env.local
npm run dev
```

## Arquitetura

```
project-running/
├── omni_runner/            # App Flutter (Clean Architecture)
│   ├── lib/
│   │   ├── domain/         # Entities, repos interfaces, use cases
│   │   ├── data/           # Isar + Supabase implementations
│   │   └── presentation/   # BLoCs + Screens
│   └── test/               # Unit, widget, BLoC & contract tests
├── portal/                 # Portal Next.js (App Router)
│   └── src/
│       ├── app/            # Pages, API routes, layouts
│       ├── components/     # Sidebar, Header, UI components
│       └── lib/            # Supabase clients, audit, logger, schemas
├── docs/                   # Documentação (PLAN_95, DECISIONS_LOG, etc.)
└── scripts/                # Automação (bump_version.sh)
```

## CI/CD

- **GitHub Actions** — Lint, test e build para Flutter, Portal e Supabase
- **Dependabot** — Atualização automática de dependências
- **Commitlint + Lefthook** — Conventional Commits enforçados
- **PR Template** — Checklist padronizado para code review

## Convenções

- **Commits:** [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `docs:`, `test:`, `chore:`)
- **Branches:** `feat/`, `fix/`, `chore/`, `docs/`
- **Versionamento:** [Semantic Versioning](https://semver.org/)

## Testes

| Suite | Tipo | Quantidade | Comando |
|-------|------|-----------|---------|
| Flutter | Unit + Widget + BLoC + Contract + Screen | **1438** | `cd omni_runner && flutter test` |
| Portal | Unit (Vitest) | **299** | `cd portal && npm test` |
| Portal | E2E (Playwright) | **9 specs** | `cd portal && npm run test:e2e` |

```bash
# Flutter
cd omni_runner && flutter test

# Portal — unit
cd portal && npm test

# Portal — E2E (Playwright)
cd portal && npm run test:e2e
```

## Internacionalização (i18n)

- **App Flutter:** `flutter_localizations` + ARB files (`lib/l10n/app_pt.arb`, `app_en.arb`). Access via `context.l10n`.
- **Portal:** `next-intl` with JSON message files (`messages/pt-BR.json`, `messages/en.json`). Access via `useTranslations()`.

## Observabilidade

- **Logger estruturado** — `AppLogger` (Flutter) / `logger.ts` (Portal) com integração Sentry
- **Sentry** — Client, server e edge (Portal); app-wide (Flutter)
- **Health Check** — `GET /api/health` com ping ao banco
- **Diagnostics Screen** — Tela debug no app com status de serviços

## Segurança

- **CSP Headers** — Content-Security-Policy, HSTS, X-Frame-Options, etc.
- **Zod Validation** — Input validation em todas as API routes de mutação
- **Rate Limiting** — Todas as `POST` routes do Portal protegidas
- **Secret Scanning** — GitHub secret scanning configurado
- **Dependabot** — npm, pub, GitHub Actions

## Architecture Decision Records (ADRs)

| # | Decisão | Status |
|---|---------|--------|
| [001](docs/adr/001-flutter-clean-architecture.md) | Clean Architecture no Flutter | Accepted |
| [002](docs/adr/002-portal-next-app-router.md) | Next.js App Router para o Portal | Accepted |
| [003](docs/adr/003-feature-flags-supabase.md) | Feature Flags via Supabase | Accepted |
| [004](docs/adr/004-i18n-strategy.md) | Estratégia de i18n (Flutter + Portal) | Accepted |
| [005](docs/adr/005-observability-stack.md) | Stack de Observabilidade | Accepted |
| [006](docs/adr/006-testing-strategy.md) | Estratégia de Testes | Accepted |
| [007](docs/adr/007-custody-clearing-model.md) | Modelo de Custódia e Clearing | Accepted |

## Custódia & Clearing (Modelo B2B)

Infraestrutura de liquidação de stakes esportivas com custódia prévia e compensação automática interclub:

- **1 Coin = US$ 1.00 de lastro** — paridade fixa global
- **Custódia segregada** — saldos por assessoria (`custody_accounts`)
- **Emissão condicionada** — coins só podem ser emitidas se há lastro disponível
- **Clearing automático** — quando coins "estrangeiras" são queimadas, o portal compensa os clubes
- **Swap de lastro B2B** — assessorias negociam liquidez entre si
- **Taxas configuráveis** — clearing (default 3%), swap (default 1%), manutenção
- **Gestão de risco** — bloqueio automático de emissão por saldo insuficiente
- **Rastreabilidade total** — cada coin carrega `issuer_group_id` (assessoria emissora)

### Páginas do Portal

| Rota | Descrição | Acesso |
|------|-----------|--------|
| `/custody` | Dashboard de custódia, depósitos, saldos | admin_master |
| `/clearing` | Compensações interclub (recebíveis/obrigações) | admin_master, professor |
| `/swap` | Mercado B2B de swap de lastro | admin_master |
| `/platform/fees` | Configuração de taxas (admin plataforma) | platform_admin |

## Feature Flags

Sistema leve de feature flags com rollout gradual por usuário:

- **Tabela `feature_flags`** — `key`, `enabled`, `rollout_pct`
- **Flutter** — `FeatureFlagService` com bucket determinístico por userId
- **Portal** — `isFeatureEnabled()` em `lib/feature-flags.ts`
- **Admin** — `/platform/feature-flags` para gerenciamento visual
