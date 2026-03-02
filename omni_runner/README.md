# Omni Runner — App

Plataforma de corrida com gamificação e coaching. App mobile multiplataforma (Android/iOS) construído com Flutter.

## Stack

- **Framework:** Flutter 3.22+ (Dart 3)
- **Arquitetura:** Clean Architecture (domain → data → presentation)
- **State Management:** BLoC / Cubit
- **DI:** GetIt
- **Local DB:** Isar
- **Backend:** Supabase (PostgreSQL, Auth, Edge Functions, Storage)
- **Mapas:** MapLibre + MapTiler
- **GPS:** Geolocator + flutter_foreground_task
- **Crash Reporting:** Sentry
- **Testes:** flutter_test + mocktail

## Setup Local

```bash
# 1. Instalar dependências
flutter pub get

# 2. Configurar variáveis de ambiente
cp ../.env.example ../.env.dev
# Preencher SUPABASE_URL, SUPABASE_ANON_KEY, MAPTILER_API_KEY, etc.

# 3. Rodar em modo debug
flutter run --dart-define-from-file=../.env.dev
```

## Build

```bash
# APK de release
flutter build apk --release --dart-define-from-file=../.env.prod

# App Bundle (Google Play)
flutter build appbundle --release --dart-define-from-file=../.env.prod
```

## Testes

```bash
# Rodar todos os testes
flutter test

# Rodar com coverage
flutter test --coverage

# Rodar testes de um arquivo específico
flutter test test/domain/services/baseline_calculator_test.dart
```

## Arquitetura

```
lib/
├── core/                   # Infraestrutura compartilhada
│   ├── config/             # AppConfig (env vars)
│   ├── logging/            # AppLogger
│   ├── theme/              # AppTheme (light/dark), ThemeNotifier
│   ├── sync/               # AutoSyncManager
│   ├── push/               # Push notifications
│   └── service_locator.dart
├── domain/                 # Regras de negócio (sem dependências externas)
│   ├── entities/           # Entidades imutáveis (Equatable)
│   ├── repositories/       # Interfaces (abstract interface class)
│   ├── usecases/           # Casos de uso (single-responsibility)
│   └── services/           # Serviços puros (calculators, analyzers)
├── data/                   # Implementação de acesso a dados
│   ├── repositories_impl/  # Implementações dos repos (Isar + Supabase)
│   ├── datasources/        # Fontes de dados (GPS, foreground task)
│   └── models/             # Modelos Isar (gerados)
├── presentation/           # UI
│   ├── blocs/              # BLoCs e Cubits
│   ├── screens/            # Telas
│   └── widgets/            # Widgets reutilizáveis
└── features/               # Features auto-contidas (parks, watch, etc.)
```

## Variáveis de Ambiente

| Variável | Obrigatória | Descrição |
|----------|:-----------:|-----------|
| `APP_ENV` | Sim | `dev` ou `prod` |
| `SUPABASE_URL` | Sim | URL do projeto Supabase |
| `SUPABASE_ANON_KEY` | Sim | Chave anônima |
| `MAPTILER_API_KEY` | Sim | API key do MapTiler (mapas) |
| `SENTRY_DSN` | Não | DSN do Sentry (crash reporting) |
| `GOOGLE_WEB_CLIENT_ID` | Não | Google Sign-In |
| `STRAVA_CLIENT_ID` | Não | Integração Strava |
| `STRAVA_CLIENT_SECRET` | Não | Integração Strava |

## CI/CD

Pipeline via GitHub Actions (`.github/workflows/flutter.yml`):
1. Analyze (`flutter analyze`)
2. Test (`flutter test --coverage`)
3. Build APK (somente em push para master)
