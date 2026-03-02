# PLAN_95.md — Plano para Nível 95/100

> **Data:** 2026-02-28
> **Situação atual:** App 62/100 · Portal 58/100
> **Meta:** 95/100 em ambos
> **Premissa:** Cada fase é entregável e incrementa a nota real.

---

## VISÃO GERAL DAS FASES

| Fase | Nome | Foco | Impacto na Nota | Esforço |
|------|------|------|:---------------:|:-------:|
| 1 | Higiene | Eliminar dívida técnica visível | +8 pts | 2-3 dias |
| 2 | Pipeline | CI/CD automatizado | +7 pts | 2-3 dias |
| 3 | Testes | Cobertura real (app + portal) | +6 pts | 4-5 dias |
| 4 | Design System | UI profissional com identidade | +6 pts | 5-7 dias |
| 5 | Observabilidade | Monitoring, logging, alertas | +3 pts | 2-3 dias |
| 6 | Hardening | Segurança, performance, a11y | +3 pts | 3-4 dias |
| 7 | Polish | i18n, feature flags, docs vivas | +2 pts | 3-4 dias |

**Total estimado: 21-29 dias de trabalho focado.**

---

## FASE 1 — HIGIENE (Nota: 62→70 / 58→66)

Objetivo: eliminar tudo que grita "projeto inacabado" a olho nu.

### 1.1 Remover código morto e TODOs

| Tarefa | Arquivo | O que fazer |
|--------|---------|-------------|
| Remover imports comentados | `service_locator.dart` | Eliminar os 8 blocos `// TODO(phase-15)`, `// TODO(sprint-16.5+)` com imports e registros comentados |
| Remover BLoCs comentados | `service_locator.dart` | Remover RaceEventsBloc, GroupsBloc, EventsBloc comentados |
| Decidir: implementar ou cortar | `i_event_repo.dart`, `i_group_repo.dart`, `i_race_event_repo.dart`, `i_race_participation_repo.dart`, `i_race_result_repo.dart` | Se não vai implementar em 60 dias → deletar interfaces, entities, usecases e telas órfãs |
| APK na raiz | `app-prod-release.apk` | Deletar do repositório, adicionar `*.apk` ao `.gitignore` |
| Limpar `.env` do repo | `.env.dev`, `.env.prod` | Já estão no `.gitignore` mas existem no working tree — confirmar que não estão tracked |

### 1.2 Versionamento semântico

| Tarefa | Detalhe |
|--------|---------|
| Definir versão real | Trocar `1.0.0+1` por versão que reflita o estado (ex: `0.9.0+1` se pré-launch, ou `1.0.0+13` se já lançou) |
| Criar script `bump_version.sh` | Lê pubspec.yaml, incrementa, gera tag git, atualiza CHANGELOG |
| Criar `CHANGELOG.md` | Histórico de mudanças por versão, formato Keep a Changelog |

### 1.3 Eliminar `catch (_) {}` silenciosos

| Arquivo | Linha(s) | Ação |
|---------|----------|------|
| `athlete_dashboard_screen.dart` | 107, 115, 137, 167, 199 | Substituir por `catch (e) { AppLogger.warn('...', tag: '...', error: e); }` |
| Varrer todo `lib/presentation/` | — | Buscar `catch (_)` e `catch (e) {}` → adicionar logging mínimo |

### 1.4 Corrigir description do pubspec

```yaml
# Antes
description: "A new Flutter project."
# Depois
description: "Omni Runner — plataforma de corrida com gamificação e coaching."
```

---

## FASE 2 — PIPELINE CI/CD (Nota: 70→77 / 66→73)

Objetivo: build, lint, test e deploy automatizados. Zero deploy manual.

### 2.1 GitHub Actions — App Flutter

Criar `.github/workflows/flutter.yml`:

```yaml
name: Flutter CI
on:
  push:
    branches: [master]
  pull_request:
    branches: [master]

jobs:
  analyze:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.22.x'
          channel: 'stable'
      - run: flutter pub get
        working-directory: omni_runner
      - run: flutter analyze --no-pub
        working-directory: omni_runner

  test:
    runs-on: ubuntu-latest
    needs: analyze
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.22.x'
      - run: flutter pub get
        working-directory: omni_runner
      - run: flutter test --coverage
        working-directory: omni_runner
      - name: Check coverage threshold
        run: |
          COVERAGE=$(lcov --summary omni_runner/coverage/lcov.info 2>&1 | grep 'lines' | grep -oP '\d+\.\d+')
          echo "Coverage: $COVERAGE%"
          # Fail if below 60%
          python3 -c "import sys; sys.exit(0 if float('$COVERAGE') >= 60 else 1)"

  build-apk:
    runs-on: ubuntu-latest
    needs: test
    if: github.ref == 'refs/heads/master'
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.22.x'
      - run: flutter build apk --release --dart-define-from-file=.env.prod
        working-directory: omni_runner
      - uses: actions/upload-artifact@v4
        with:
          name: apk-release
          path: omni_runner/build/app/outputs/flutter-apk/app-release.apk
```

### 2.2 GitHub Actions — Portal Next.js

Criar `.github/workflows/portal.yml`:

```yaml
name: Portal CI
on:
  push:
    branches: [master]
    paths: ['portal/**']
  pull_request:
    paths: ['portal/**']

jobs:
  lint-test-build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
          cache-dependency-path: portal/package-lock.json
      - run: npm ci
        working-directory: portal
      - run: npm run lint
        working-directory: portal
      - run: npm test -- --ci --coverage
        working-directory: portal
      - run: npm run build
        working-directory: portal
```

### 2.3 GitHub Actions — Supabase Migrations

Criar `.github/workflows/supabase.yml`:

```yaml
name: Supabase CI
on:
  push:
    paths: ['omni_runner/supabase/migrations/**']

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: supabase/setup-cli@v1
      - run: supabase db lint
        working-directory: omni_runner
```

### 2.4 Pre-commit hooks

Criar `.husky/` e `lint-staged` para o portal. Criar `lefthook.yml` na raiz:

```yaml
pre-commit:
  parallel: true
  commands:
    flutter-analyze:
      root: omni_runner/
      run: flutter analyze --no-pub
    portal-lint:
      root: portal/
      run: npx next lint
```

### 2.5 Proteção de branch

- Branch `master` protegida: require PR, require CI pass, require 1 review
- Nenhum push direto em master

---

## FASE 3 — TESTES (Nota: 77→83 / 73→79)

Objetivo: cobertura significativa nas camadas que importam.

### 3.1 App Flutter — completar cobertura

| Camada | Arquivos com teste | Arquivos sem teste | Meta |
|--------|:------------------:|:------------------:|:----:|
| domain/usecases | 25/38 | 13 | 100% |
| domain/services | 0/6 | 6 | 100% |
| data/repositories_impl | 0/27 | 27 | 50% (14 repos) |
| presentation/blocs | 0/21 | 21 | 50% (11 blocs) |
| features/ | 11/40 | 29 | 50% (15 features) |

**Prioridade de testes novos:**

1. **BLoC tests (alta prioridade — 11 blocs):**
   - `challenges_bloc_test.dart` — fluxo completo (load, create, join, settle)
   - `wallet_bloc_test.dart` — load, transações
   - `coaching_groups_bloc_test.dart` — load, criar grupo
   - `friends_bloc_test.dart` — send invite, accept
   - `progression_bloc_test.dart` — load XP, level up
   - `missions_bloc_test.dart` — load, complete
   - `badges_bloc_test.dart` — load, check unlock
   - `my_assessoria_bloc_test.dart` — load, switch
   - `coach_insights_bloc_test.dart`
   - `athlete_evolution_bloc_test.dart`
   - `leaderboards_bloc_test.dart`

2. **Domain services (alta prioridade — 6 serviços):**
   - `baseline_calculator_test.dart`
   - `coaching_ranking_calculator_test.dart`
   - `event_detector_test.dart`
   - `evolution_analyzer_test.dart`
   - `insight_generator_test.dart`
   - `event_ranking_calculator_test.dart`

3. **Use cases faltantes (13):**
   - Todos os de `coaching/` (7): accept, create, get_details, get_members, invite, remove, switch
   - Todos os de `social/` (6): accept_friend, block_user, create_group, evaluate_event, join_event, send_friend_invite

4. **Repos prioritários (14 dos 27):**
   - `isar_session_repo_test.dart`
   - `isar_challenge_repo_test.dart`
   - `isar_coaching_group_repo_test.dart`
   - `profile_repo_test.dart`
   - `sync_repo_test.dart`
   - (+ 9 mais críticos)

**Ferramentas a adicionar ao `pubspec.yaml`:**
```yaml
dev_dependencies:
  bloc_test: ^9.1.0
  mocktail: ^1.0.0
```

### 3.2 Portal Next.js — criar suite de testes do zero

**Instalar framework:**
```bash
cd portal
npm install -D vitest @testing-library/react @testing-library/jest-dom jsdom @vitejs/plugin-react
```

**Criar `vitest.config.ts`:**
```typescript
import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';
import path from 'path';

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    setupFiles: ['./src/test/setup.ts'],
    globals: true,
  },
  resolve: {
    alias: { '@': path.resolve(__dirname, './src') },
  },
});
```

**Testes prioritários para o portal (22 testes):**

| Categoria | Arquivo de teste | O que testa |
|-----------|------------------|-------------|
| Middleware | `src/__tests__/middleware.test.ts` | Rotas públicas passam, privadas redirecionam, RBAC bloqueia |
| Rate limiter | `src/__tests__/rate-limit.test.ts` | Permite até maxRequests, bloqueia após, reseta após window |
| Audit log | `src/__tests__/audit.test.ts` | Insert correto, fire-and-forget não lança |
| API checkout | `src/__tests__/api/checkout.test.ts` | Validação de input, criação de sessão |
| API distribute | `src/__tests__/api/distribute-coins.test.ts` | Validação, rate limit, audit |
| API export | `src/__tests__/api/export-athletes.test.ts` | CSV gerado corretamente |
| API branding | `src/__tests__/api/branding.test.ts` | GET/POST, validação de cores |
| API team | `src/__tests__/api/team.test.ts` | Invite, remove, permissões |
| API verification | `src/__tests__/api/verification.test.ts` | Evaluate, permissões |
| API platform | `src/__tests__/api/platform.test.ts` | Assessorias CRUD, refunds, products |
| Component Sidebar | `src/__tests__/components/sidebar.test.tsx` | Renderiza itens por role, mobile toggle |
| Component Header | `src/__tests__/components/header.test.tsx` | Nome do grupo, logout |
| Page Dashboard | `src/__tests__/pages/dashboard.test.tsx` | KPIs renderizados, trend arrows, alert créditos |
| Page Athletes | `src/__tests__/pages/athletes.test.tsx` | Lista, filtro, distribuição |
| Page Credits | `src/__tests__/pages/credits.test.tsx` | Saldo, pacotes, botão comprar |
| Page Settings | `src/__tests__/pages/settings.test.tsx` | Formulários, salvamento |
| Page Verification | `src/__tests__/pages/verification.test.tsx` | Status, reavaliação |
| Page Engagement | `src/__tests__/pages/engagement.test.tsx` | Métricas, gráficos |
| Page Login | `src/__tests__/pages/login.test.tsx` | Formulário, redirect |
| Page Select-group | `src/__tests__/pages/select-group.test.tsx` | Multi-group selection |
| Platform Assessorias | `src/__tests__/pages/platform-assessorias.test.tsx` | Approve/reject/suspend |
| Platform Support | `src/__tests__/pages/platform-support.test.tsx` | Lista tickets, chat |

### 3.3 E2E Tests (Playwright)

**Portal E2E:**
```bash
cd portal
npm install -D @playwright/test
npx playwright install
```

Criar 5 fluxos E2E críticos:
1. Login → Dashboard → ver KPIs
2. Login → Athletes → Distribuir coins
3. Login → Credits → Iniciar checkout
4. Login → Settings → Alterar branding
5. Login → Verification → Reavaliar atleta

---

## FASE 4 — DESIGN SYSTEM (Nota: 83→89 / 79→85)

Objetivo: identidade visual própria, não parecer "app template Flutter + Tailwind genérico".

### 4.1 App Flutter — Design System

**4.1.1 Tipografia customizada**

Escolher e adicionar 1-2 fontes (ex: Inter, Outfit, ou Poppins):

```yaml
# pubspec.yaml
flutter:
  fonts:
    - family: Inter
      fonts:
        - asset: assets/fonts/Inter-Regular.ttf
        - asset: assets/fonts/Inter-Medium.ttf
          weight: 500
        - asset: assets/fonts/Inter-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/Inter-Bold.ttf
          weight: 700
```

Criar `lib/core/theme/app_theme.dart`:
```dart
abstract final class AppTheme {
  static ThemeData light() => ThemeData(
    useMaterial3: true,
    colorSchemeSeed: const Color(0xFF2563EB), // brand blue
    fontFamily: 'Inter',
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 1,
    ),
    cardTheme: CardTheme(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
    // ... tokens de design completos
  );

  static ThemeData dark() => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorSchemeSeed: const Color(0xFF2563EB),
    fontFamily: 'Inter',
    // ... espelhado do light com ajustes
  );
}
```

**4.1.2 Ícones e ilustrações**

| Ação | Detalhe |
|------|---------|
| Ícone do app | Criar ícone profissional (Figma ou contratado), gerar com `flutter_launcher_icons` |
| Splash screen | Criar splash nativo com `flutter_native_splash` |
| Ilustrações de empty state | SVG ou Lottie para telas vazias (corridas, desafios, assessoria) |
| Ícones customizados | Substituir `Icons.sports_kabaddi_rounded` etc. por icon set coerente (Phosphor, Lucide, ou custom SVG) |

**4.1.3 Dark mode consistente**

- Eliminar todos os `isDark ?` ad-hoc nos widgets
- Centralizar tudo no `ThemeData.dark()`
- Testar cada tela nos dois modos
- Criar `ThemeNotifier` para persistir preferência

**4.1.4 Animações e transições**

| Onde | O que adicionar |
|------|----------------|
| Navegação entre telas | `PageRouteBuilder` com fade/slide customizado |
| Cards do dashboard | Stagger animation melhorado (já tem base) |
| Loading states | Substituir `CircularProgressIndicator` genérico por shimmer em todas as telas |
| Success feedback | Expandir `success_overlay.dart` para todos os fluxos de conclusão |
| Pull-to-refresh | Indicador de refresh customizado com branding |

**4.1.5 Declarative routing**

Migrar de `Navigator.push` imperativo para `go_router`:

```yaml
dependencies:
  go_router: ^14.0.0
```

Criar `lib/core/routing/app_router.dart` com:
- Named routes
- Deep link handling integrado
- Guards de autenticação
- Redirect logic centralizado
- Shell routes para bottom navigation

### 4.2 Portal — Component Library

**4.2.1 Instalar shadcn/ui**

```bash
cd portal
npx shadcn-ui@latest init
npx shadcn-ui@latest add button card badge input label select dialog table tabs avatar dropdown-menu sheet tooltip
```

**4.2.2 Criar componentes reutilizáveis**

| Componente | Arquivo | Substitui |
|------------|---------|-----------|
| `KpiCard` | `src/components/ui/kpi-card.tsx` | Inline `KpiCard` em `dashboard/page.tsx` |
| `DataTable` | `src/components/ui/data-table.tsx` | Tabelas inline em athletes, billing, etc. |
| `StatusBadge` | `src/components/ui/status-badge.tsx` | Classes Tailwind ad-hoc para status |
| `EmptyState` | `src/components/ui/empty-state.tsx` | Mensagens inline de lista vazia |
| `ConfirmDialog` | `src/components/ui/confirm-dialog.tsx` | `window.confirm()` ou alerts inline |
| `PageHeader` | `src/components/ui/page-header.tsx` | `<h1>` + `<p>` repetidos em cada página |
| `MetricChart` | `src/components/ui/metric-chart.tsx` | Gráfico de barras inline no dashboard |
| `LoadingSkeleton` | `src/components/ui/loading-skeleton.tsx` | Telas sem loading state |

**4.2.3 Layout e responsividade**

- Testar todas as páginas em mobile (atualmente algumas quebram)
- Sidebar: já tem mobile drawer (bom)
- Tabelas: adicionar scroll horizontal em mobile
- Forms: stack vertical em mobile, side-by-side em desktop

**4.2.4 Favicon, meta tags, OG image**

```tsx
// layout.tsx
export const metadata = {
  title: 'Omni Runner Portal',
  description: 'Portal de gestão para assessorias esportivas',
  openGraph: {
    title: 'Omni Runner Portal',
    description: 'Gerencie sua assessoria de corrida',
    images: ['/og-image.png'],
  },
};
```

---

## FASE 5 — OBSERVABILIDADE (Nota: 89→92 / 85→88)

Objetivo: saber o que acontece em produção antes do usuário reclamar.

### 5.1 Portal — Error tracking

```bash
cd portal
npm install @sentry/nextjs
npx @sentry/wizard@latest -i nextjs
```

Configurar `sentry.client.config.ts`, `sentry.server.config.ts`, `sentry.edge.config.ts`.

### 5.2 Portal — Structured logging

Criar `src/lib/logger.ts`:
```typescript
export const logger = {
  info: (msg: string, meta?: Record<string, unknown>) => {
    console.log(JSON.stringify({ level: 'info', msg, ...meta, ts: Date.now() }));
  },
  warn: (msg: string, meta?: Record<string, unknown>) => {
    console.warn(JSON.stringify({ level: 'warn', msg, ...meta, ts: Date.now() }));
  },
  error: (msg: string, error?: unknown, meta?: Record<string, unknown>) => {
    console.error(JSON.stringify({ level: 'error', msg, error: String(error), ...meta, ts: Date.now() }));
    // Sentry.captureException(error) se Sentry configurado
  },
};
```

Substituir todos os `console.error(...)` por `logger.error(...)`.

### 5.3 Portal — Rate limiter com Redis

Substituir rate limiter in-memory por `@upstash/ratelimit`:

```bash
npm install @upstash/ratelimit @upstash/redis
```

O rate limiter in-memory reinicia a cada deploy e não funciona com múltiplas instances.

### 5.4 App — Health check dashboard

Criar tela de diagnóstico (acessível em Settings > Debug):
- Versão do app, versão do Flutter
- Status da conexão Supabase
- Status do Strava (conectado/desconectado)
- Último sync timestamp
- Tamanho do banco Isar
- Push token registrado

### 5.5 Uptime monitoring

- Configurar UptimeRobot ou Better Stack para `/api/health` do portal
- Criar `portal/src/app/api/health/route.ts`:
```typescript
export async function GET() {
  // Check Supabase connection
  return Response.json({ status: 'ok', ts: Date.now() });
}
```

---

## FASE 6 — HARDENING (Nota: 92→94 / 88→92)

Objetivo: segurança, performance e acessibilidade no nível esperado de um app profissional.

### 6.1 Segurança

| Ação | Detalhe |
|------|---------|
| Dependabot | Ativar no GitHub para `portal/package.json` e `omni_runner/pubspec.yaml` |
| Content Security Policy | Adicionar headers CSP no `next.config.js` |
| CORS | Verificar que API routes do portal não aceitam origens arbitrárias |
| Input validation | Criar schema validation com Zod em todas as API routes do portal |
| Secrets scanning | Ativar GitHub secret scanning |
| `.env.example` completo | Documentar todas as variáveis necessárias sem valores reais |

**Zod validation para API routes:**

```bash
cd portal
npm install zod
```

Exemplo para `/api/distribute-coins`:
```typescript
import { z } from 'zod';

const distributeSchema = z.object({
  userId: z.string().uuid(),
  amount: z.number().int().positive().max(10000),
  reason: z.string().min(1).max(200),
});
```

### 6.2 Performance — App

| Ação | Detalhe |
|------|---------|
| const constructors | Verificar que todos os widgets sem estado usam `const` |
| RepaintBoundary | Adicionar em widgets complexos que mudam frequentemente (mapa, lista de corridas) |
| Image caching | Usar `CachedNetworkImage` para avatares e logos de assessorias |
| Lazy loading | Telas pesadas (WrappedScreen, RunningDnaScreen) devem carregar dados on-demand |
| Isar queries | Verificar que queries frequentes têm índices (sessions por data, challenges por status) |

### 6.3 Performance — Portal

| Ação | Detalhe |
|------|---------|
| `loading.tsx` | Criar skeletons para cada page group (dashboard, athletes, credits, etc.) |
| `error.tsx` | Criar error boundaries para cada page group |
| Image optimization | Usar `next/image` para logos (já usando? verificar) |
| Bundle analysis | `npm install -D @next/bundle-analyzer`, identificar e eliminar bundles grandes |
| Caching headers | Configurar `Cache-Control` para API routes que são leitura pesada |

### 6.4 Acessibilidade

**App Flutter:**
- Verificar `Semantics` widgets em todos os cards interativos
- Testar com TalkBack (Android) e VoiceOver (iOS)
- Contrast ratio: verificar que textos sobre backgrounds coloridos têm ratio >= 4.5:1

**Portal:**
- Adicionar `aria-label` em botões de ícone
- Testar navegação por teclado em todas as páginas
- Verificar contrast ratio (ferramentas: axe-core, Lighthouse)
- Instalar e rodar `npm install -D @axe-core/react` em desenvolvimento

---

## FASE 7 — POLISH (Nota: 94→95 / 92→95)

Objetivo: detalhes que separam um produto bom de um produto excelente.

### 7.1 Internacionalização (i18n)

**App Flutter:**
```yaml
dependencies:
  flutter_localizations:
    sdk: flutter
  intl: ^0.19.0
```

- Criar `lib/l10n/` com `app_pt.arb` (português) e `app_en.arb` (inglês)
- Extrair todas as strings hardcoded (estimativa: 500+ strings)
- Configurar `generate: true` no `pubspec.yaml`
- Começar com pt-BR como default, en como secundário

**Portal:**
- Instalar `next-intl` ou usar `i18next`
- Extrair strings das páginas
- Menor urgência que o app (portal é B2B, público inicial é BR)

### 7.2 Feature Flags

Criar sistema simples de feature flags via Supabase:

```sql
CREATE TABLE feature_flags (
  key TEXT PRIMARY KEY,
  enabled BOOLEAN DEFAULT false,
  rollout_pct INT DEFAULT 0,
  metadata JSONB DEFAULT '{}'
);
```

App Flutter: `FeatureFlagService` que carrega flags no startup.
Portal: middleware que lê flags para habilitar/desabilitar páginas.

Flags iniciais sugeridas:
- `parks_enabled` (feature nova, pode precisar rollback)
- `matchmaking_enabled`
- `wrapped_enabled`
- `running_dna_enabled`

### 7.3 Documentação viva

| Documento | Ação |
|-----------|------|
| `README.md` (raiz) | Reescrever: visão do produto, screenshots, setup local, stack, contribuição |
| `README.md` (portal) | Setup local, variáveis de ambiente, deploy, testes |
| `README.md` (omni_runner) | Setup local, flavors, build, testes, arquitetura |
| API docs do portal | Gerar com OpenAPI/Swagger ou documentar manualmente em `docs/PORTAL_API.md` |
| Storybook (portal) | Opcional: documentar componentes visuais com Storybook |
| ADR template | Formalizar Architecture Decision Records (já tem `DECISIONS_LOG.md`, transformar em ADR format) |

### 7.4 Git hygiene

| Ação | Detalhe |
|------|---------|
| Branch naming | `feat/`, `fix/`, `chore/`, `docs/` |
| Commit convention | Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`, `test:`) |
| PR template | Criar `.github/pull_request_template.md` com checklist |
| Issue templates | Criar templates para bug report e feature request |
| `commitlint` | Validar formato de commits no CI |

### 7.5 Release automation

- Criar workflow de release que:
  1. Bump versão (semver)
  2. Gera CHANGELOG automaticamente (conventional-changelog)
  3. Cria tag git
  4. Build APK/IPA
  5. Upload artefato como GitHub Release
  6. Notifica no Slack/Discord (opcional)

---

## SCORECARD POR FASE

| Categoria | Atual App | Fase 1 | Fase 2 | Fase 3 | Fase 4 | Fase 5 | Fase 6 | Fase 7 | Meta |
|-----------|:---------:|:------:|:------:|:------:|:------:|:------:|:------:|:------:|:----:|
| Arquitetura | 75 | 78 | 78 | 78 | 82 | 82 | 82 | 82 | 82 |
| Qualidade código | 65 | 75 | 80 | 85 | 88 | 90 | 92 | 95 | 95 |
| Testes | 55 | 55 | 60 | 85 | 85 | 85 | 88 | 90 | 90 |
| UI/UX | 45 | 45 | 45 | 45 | 85 | 85 | 88 | 90 | 90 |
| Segurança | 70 | 72 | 75 | 75 | 75 | 80 | 90 | 92 | 92 |
| DevOps/CI | 15 | 20 | 90 | 92 | 92 | 95 | 95 | 98 | 98 |
| Documentação | 75 | 78 | 80 | 80 | 82 | 82 | 82 | 95 | 95 |
| Completude | 60 | 68 | 68 | 70 | 78 | 80 | 82 | 85 | 85 |
| **MÉDIA** | **62** | **70** | **77** | **83** | **89** | **92** | **94** | **95** | **95** |

| Categoria | Atual Portal | Fase 1 | Fase 2 | Fase 3 | Fase 4 | Fase 5 | Fase 6 | Fase 7 | Meta |
|-----------|:------------:|:------:|:------:|:------:|:------:|:------:|:------:|:------:|:----:|
| Arquitetura | 60 | 62 | 62 | 65 | 70 | 72 | 75 | 78 | 78 |
| Qualidade código | 55 | 65 | 70 | 78 | 85 | 88 | 92 | 95 | 95 |
| Testes | 10 | 10 | 15 | 80 | 82 | 82 | 85 | 88 | 88 |
| UI/UX | 55 | 55 | 55 | 55 | 88 | 88 | 90 | 92 | 92 |
| Segurança | 65 | 68 | 72 | 72 | 72 | 78 | 92 | 95 | 95 |
| DevOps/CI | 15 | 15 | 88 | 90 | 90 | 92 | 95 | 98 | 98 |
| Documentação | 40 | 45 | 48 | 50 | 55 | 58 | 60 | 90 | 90 |
| Completude | 65 | 68 | 68 | 72 | 80 | 82 | 85 | 88 | 88 |
| **MÉDIA** | **58** | **66** | **73** | **79** | **85** | **88** | **92** | **95** | **95** |

---

## DEPENDÊNCIAS ENTRE FASES

```
Fase 1 (Higiene) ─────┐
                       ├──→ Fase 2 (Pipeline) ──→ Fase 3 (Testes) ──┐
                       │                                              │
                       └──→ Fase 4 (Design System) ──────────────────┤
                                                                      │
                                          Fase 5 (Observabilidade) ◄──┤
                                                                      │
                                          Fase 6 (Hardening) ◄────────┤
                                                                      │
                                          Fase 7 (Polish) ◄───────────┘
```

- Fases 1-2 são sequenciais (pipeline depende de código limpo)
- Fases 3 e 4 podem rodar em paralelo após Fase 2
- Fases 5-7 dependem de 3 e 4 estarem substancialmente completas

---

## MÉTRICAS DE SUCESSO

| Métrica | Valor inicial | Valor atual | Meta | Status |
|---------|:------------:|:-----------:|:----:|:------:|
| Testes Flutter | ~700 | 1465 | ≥ 1400 | DONE |
| Testes Portal | 0 | 438 | ≥ 400 | DONE |
| Testes E2E (portal) | 0 | ≥ 5 fluxos | ≥ 5 fluxos | DONE |
| CI/CD pipelines | 0 | 4 (flutter, portal, supabase, release) | 3 | DONE |
| Erros TypeScript | 20+ | 0 | 0 | DONE |
| Formatters duplicados | 13 | 0 | 0 | DONE |
| Componentes UI (portal) | 2 | 9 (KpiCard, DataTable, Sparkline, BarChart, etc.) | ≥ 8 | DONE |
| i18n keys | 60 | 120 (pt-BR + en) | ≥ 100 | DONE |
| Modelo B2B completo | Não | Sim (custódia, clearing, swap, invariantes) | Sim | DONE |
| Webhook validation | Não | Sim (Stripe HMAC + generic HMAC) | Sim | DONE |
| CSRF protection | Não | Sim (Origin/Referer check) | Sim | DONE |
| Metrics/APM lib | Não | Sim (pluggable MetricsCollector) | Sim | DONE |
| Health check + invariants | Básico | DB + custody invariants | DB + invariants | DONE |
| Coverage CI | Não | Sim (v8, artifacts) | Sim | DONE |
| Fontes customizadas (app) | 0 | 1 (Inter) | 1-2 | DONE |
| Tempo para deploy (manual) | ~30 min | < 5 min (CI) | < 5 min | DONE |

---

*Documento gerado em 28/02/2026. Última atualização: 28/02/2026.*
