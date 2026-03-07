# POST_REFACTOR_INVENTORY.md — Inventário Pós-Refatoração

> Data: 2026-03-07 | Status: Concluído

---

## 1. MAPA ESTRUTURAL

| Componente | Contagem |
|---|---|
| Arquivos .dart em lib/ | 641 |
| Arquivos .dart em test/ | 268 |
| Telas (screens) | 100 |
| Repository implementations | 45 |
| Domain entities | 66 |
| Domain use cases | 84 |
| Core files | 45 |
| Registros no DI (get_it) | 163 |
| Rotas go_router | 105 |
| BLoCs | 30 |
| Edge Functions | 59 |
| Portal páginas .tsx | 180 |
| SQL Migrations | 132 |

---

## 2. REFERÊNCIAS ISAR REMANESCENTES

| Categoria | Arquivos |
|---|---|
| Pubspec dependencies | 2 deps + 1 override |
| Isar models (lib/data/models/isar/) | 22 .dart + 22 .g.dart |
| Isar repositories (isar_*) | 17 + sync_repo.dart |
| Isar infrastructure (provider, migrator, secure store, DI) | 4 |
| Produção com import Isar real | 1 (workout_proto_mapper.dart) |
| Produção com comentários "Isar" | 15 |
| Tests com import Isar real | 1 (workout_proto_mapper_test.dart) |
| Tests com comentários "Isar" | 5 |
| Vendored third_party/isar_flutter_libs/ | 25 |
| **TOTAL com dependência de código Isar** | **68** |
| **TOTAL com menções em comentários** | **20** |

---

## 3. REFERÊNCIAS DRIFT

| Categoria | Arquivos | Status |
|---|---|---|
| drift_database.dart (28 tabelas) | 1 | Definido, NÃO wired |
| drift_converters.dart | 1 | Definido, NÃO usado |
| isar_to_drift_migrator.dart | 1 | Escrito, NUNCA executado |
| drift_database.g.dart | 0 | **NÃO EXISTE** — build_runner nunca rodou para Drift |
| DAOs Drift | 0 | Não criados |
| Repos Drift | 0 | Não criados |
| DI registration de AppDatabase | 0 | Não registrado |

**Nível de integração Drift: SCAFFOLDING_ONLY**

---

## 4. STACK TECNOLÓGICO ATIVO

| Camada | Tecnologia | Versão |
|---|---|---|
| UI/Framework | Flutter | 3.22+ |
| State Management | BLoC | 8.x |
| DI | get_it | 7.x |
| Persistência Local | **Isar** (ativo) / Drift (scaffolding) | 3.1 / 2.32 |
| Routing | go_router | 17.x |
| Mapas | MapLibre + MapTiler | 0.25+ |
| Backend | Supabase (PostgreSQL + Auth + Edge Functions + Storage) | 2.x |
| Crash Reporting | Sentry | 9.x |
| Portal | Next.js + next-intl + next-themes + Framer Motion | latest |
| Caching | Upstash Redis (portal) / SharedPreferences (app) | latest |
| CI/CD | GitHub Actions + Lefthook | latest |

---

## 5. FEATURE FLAGS ATIVOS

| Flag | Usado em |
|---|---|
| park_segments_enabled | park_screen.dart |
| league_enabled | league_screen.dart |
| trainingpeaks_enabled | (uso interno) |
| device_link_enabled | (uso interno) |

---

## 6. SCRIPTS E TOOLING

| Tool | Localização |
|---|---|
| Lefthook pre-commit | .lefthook.yml (portal-lint + flutter-analyze) |
| k6 load tests | tools/load-tests/ |
| Perf benchmark SQL | tools/perf_benchmark.sql + perf_benchmark_ci.sh |
| Playwright E2E | portal/e2e/ (22 specs) |
| Fastlane | omni_runner/fastlane/ (TODO: credenciais) |
| GitHub Actions | .github/workflows/ (flutter, portal, supabase, release) |
