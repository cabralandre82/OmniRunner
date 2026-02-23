# Watch Project Structure — Apple Watch & WearOS

> **Sprint:** W12.0.2  
> **Status:** Estrutura criada (sem código ainda)  
> **Referência:** docs/WatchArchitecture.md

---

## 1. Localização no Monorepo

```
project-running/
├── omni_runner/               # Flutter phone app (existente)
│   ├── lib/
│   ├── android/
│   ├── ios/
│   └── test/
│
├── watch/                     # ← NOVO: apps nativos de watch
│   ├── apple_watch/           # Apple Watch (Swift/SwiftUI)
│   └── wear_os/               # WearOS (Kotlin/Compose)
│
├── docs/
└── ...
```

A pasta `watch/` é **independente** do projeto Flutter. Os apps de watch
são projetos nativos separados, cada um com seu próprio build system.

---

## 2. Apple Watch — Estrutura

```
watch/apple_watch/
├── OmniRunnerWatch/
│   ├── Sources/
│   │   ├── App/               # Entry point (WatchApp, @main)
│   │   │                      #   OmniRunnerWatchApp.swift
│   │   │
│   │   ├── Views/             # SwiftUI views
│   │   │                      #   WorkoutView.swift       — métricas ao vivo
│   │   │                      #   SummaryView.swift       — pós-corrida
│   │   │                      #   StartView.swift         — tela inicial
│   │   │                      #   SettingsView.swift      — config (HR max, etc)
│   │   │
│   │   ├── Managers/          # Lógica de serviço
│   │   │                      #   WorkoutManager.swift    — HKWorkoutSession + GPS
│   │   │                      #   LocationManager.swift   — CLLocationManager
│   │   │                      #   ConnectivityManager.swift — WatchConnectivity
│   │   │                      #   HapticManager.swift     — feedback tátil
│   │   │
│   │   ├── Models/            # Entidades de domínio
│   │   │                      #   WorkoutSession.swift    — sessão local
│   │   │                      #   LocationSample.swift    — ponto GPS
│   │   │                      #   HeartRateSample.swift   — amostra HR
│   │   │                      #   HrZone.swift            — zonas cardíacas
│   │   │                      #   SyncStatus.swift        — estado de sync
│   │   │
│   │   └── Utils/             # Helpers puros
│   │                          #   MetricsCalculator.swift — distância, pace
│   │                          #   Haversine.swift         — cálculo de distância
│   │                          #   FormatPace.swift        — formatação
│   │
│   ├── Resources/             # Assets, Info.plist do watch
│   │                          #   Assets.xcassets
│   │                          #   Info.plist
│   │
│   └── Preview Content/       # SwiftUI Preview assets
│
└── OmniRunnerWatchTests/      # Testes unitários (XCTest)
```

### Relação com o Projeto Xcode do Flutter

O Apple Watch app **não é um projeto Xcode standalone**. Ele precisa ser
adicionado como target ao workspace Xcode existente do Flutter:

```
omni_runner/ios/Runner.xcworkspace    ← abrir este
  ├── Runner (iPhone app — Flutter)
  ├── Pods (CocoaPods dependencies)
  └── OmniRunnerWatch (watch target)  ← será adicionado aqui
```

Isso é obrigatório pela Apple: o watch app é distribuído junto com o
iPhone app via App Store. Não existe watch app sem iPhone app companion.

---

## 3. WearOS — Estrutura

```
watch/wear_os/
├── app/
│   └── src/
│       ├── main/
│       │   ├── kotlin/com/omnirunner/watch/
│       │   │   ├── ui/
│       │   │   │   ├── screens/       # Compose screens
│       │   │   │   │                  #   WorkoutScreen.kt    — métricas ao vivo
│       │   │   │   │                  #   SummaryScreen.kt    — pós-corrida
│       │   │   │   │                  #   StartScreen.kt      — tela inicial
│       │   │   │   │
│       │   │   │   ├── components/    # Compose components reutilizáveis
│       │   │   │   │                  #   MetricCard.kt
│       │   │   │   │                  #   HrZoneIndicator.kt
│       │   │   │   │
│       │   │   │   └── theme/         # Material Design 3 Wear theme
│       │   │   │                      #   Theme.kt
│       │   │   │                      #   Color.kt
│       │   │   │
│       │   │   ├── data/
│       │   │   │   ├── local/         # Persistência local
│       │   │   │   │                  #   SessionDao.kt       — Room DAO
│       │   │   │   │                  #   AppDatabase.kt      — Room database
│       │   │   │   │                  #   SessionEntity.kt    — Room entity
│       │   │   │   │
│       │   │   │   └── sync/          # Comunicação com phone
│       │   │   │                      #   DataLayerManager.kt — DataClient/MessageClient
│       │   │   │                      #   WearListenerService.kt — recebe do phone
│       │   │   │
│       │   │   ├── domain/
│       │   │   │   ├── models/        # Entidades de domínio
│       │   │   │   │                  #   WorkoutSession.kt
│       │   │   │   │                  #   LocationSample.kt
│       │   │   │   │                  #   HeartRateSample.kt
│       │   │   │   │                  #   HrZone.kt
│       │   │   │   │
│       │   │   │   └── usecases/      # Lógica de negócio
│       │   │   │                      #   MetricsCalculator.kt
│       │   │   │                      #   HrZoneCalculator.kt
│       │   │   │
│       │   │   └── service/           # Android Services
│       │   │                          #   WorkoutService.kt   — Foreground Service
│       │   │                          #   ExerciseManager.kt  — Health Services
│       │   │
│       │   └── res/
│       │       ├── values/            # strings.xml, colors.xml, styles.xml
│       │       ├── drawable/          # ícones vetoriais
│       │       ├── mipmap-hdpi/       # app icon
│       │       ├── mipmap-xhdpi/      # app icon
│       │       └── layout/           # (reservado, Compose é preferido)
│       │
│       └── test/
│           └── kotlin/com/omnirunner/watch/
│                                      # Testes unitários (JUnit)
│
├── gradle/                            # Gradle wrapper
│   └── wrapper/
│       └── gradle-wrapper.properties
│
├── build.gradle.kts                   # ← a criar (root build script)
├── settings.gradle.kts                # ← a criar
├── gradle.properties                  # ← a criar
└── app/
    └── build.gradle.kts               # ← a criar (module build script)
```

### Relação com o Projeto Android do Flutter

Diferente do Apple Watch, o WearOS app é um **projeto Android independente**.
Ele NÃO é um módulo do projeto Gradle do Flutter. Razões:

1. O app phone Flutter já usa AGP via `dev.flutter.flutter-gradle-plugin`
2. Misturar WearOS (Compose for Wear OS) no mesmo Gradle causaria conflitos
3. WearOS tem `minSdk = 30`, enquanto o phone app tem `minSdk = 26`
4. Release e signing independentes

O WearOS app se comunica com o phone app via DataLayer API em runtime,
não em build time.

---

## 4. Como Abrir no Xcode (Apple Watch)

### Passo a passo

```bash
# 1. Abrir o workspace Flutter existente (NÃO o .xcodeproj)
open omni_runner/ios/Runner.xcworkspace
```

> **Importante:** Sempre abrir o `.xcworkspace`, nunca o `.xcodeproj`.
> O workspace inclui as dependências CocoaPods necessárias para o Flutter.

### Adicionar o Watch Target (uma vez, na sprint de implementação)

No Xcode, com o workspace aberto:

1. **File → New → Target...**
2. Selecionar **watchOS → App**
3. Configurar:
   - Product Name: `OmniRunnerWatch`
   - Team: (sua Apple Developer Team)
   - Organization Identifier: `com.omnirunner`
   - Bundle Identifier: `com.omnirunner.omni-runner.watchkitapp`
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Watch App for: **Existing iOS App** → selecionar `Runner`
4. **Finish** — Xcode cria os arquivos iniciais

5. Mover os arquivos gerados para a estrutura em `watch/apple_watch/`:
   - Configurar os **folder references** no Xcode para apontar para
     `watch/apple_watch/OmniRunnerWatch/Sources/` etc.

6. Adicionar capabilities ao target do watch:
   - **HealthKit** (para HKWorkoutSession)
   - **Location Updates** (para GPS)

### Build e Run

```
# No Xcode:
1. Selecionar o scheme "OmniRunnerWatch"
2. Selecionar um Apple Watch Simulator (ou device pareado)
3. Cmd+R para build e run

# O watch app será instalado junto com o iPhone app companion.
```

### Requisitos

| Requisito | Valor |
|-----------|-------|
| Xcode | 15.0+ |
| watchOS Deployment Target | 10.0 (mínimo para SwiftUI moderno) |
| Swift | 5.9+ |
| Apple Developer Account | Necessária (HealthKit requer provisioning profile) |
| Hardware para teste | Apple Watch real (simulator não tem GPS/HR) |

---

## 5. Como Abrir no Android Studio (WearOS)

### Passo a passo

```bash
# 1. Abrir o projeto WearOS diretamente (NÃO o projeto Flutter)
#    No Android Studio: File → Open → selecionar a pasta:
cd watch/wear_os/
```

> **Importante:** Abrir `watch/wear_os/` como projeto raiz, NÃO
> `omni_runner/android/`. São projetos Gradle completamente separados.

### Configuração Inicial (uma vez, na sprint de implementação)

Na sprint de implementação, os seguintes arquivos serão criados:

1. **`settings.gradle.kts`** — declara o módulo `:app`
2. **`build.gradle.kts` (root)** — plugins Kotlin, AGP, Compose
3. **`app/build.gradle.kts`** — configuração do módulo:
   - `minSdk = 30` (Wear OS 3+)
   - `targetSdk = 34`
   - Dependencies: Compose for Wear OS, Health Services, DataLayer, Room
4. **`app/src/main/AndroidManifest.xml`** — permissões e services
5. **`gradle.properties`** — configuração do Gradle

### Build e Run

```
# No Android Studio:
1. Sync Gradle (File → Sync Project with Gradle Files)
2. Selecionar o device: WearOS emulator ou watch real
3. Run (Shift+F10)

# Criar emulador WearOS:
#   Tools → Device Manager → Create Device
#   → Wear OS → Wear OS Large Round (API 33)
```

### Requisitos

| Requisito | Valor |
|-----------|-------|
| Android Studio | Hedgehog (2023.1) ou superior |
| AGP | 8.2+ |
| Kotlin | 1.9+ |
| Compose for Wear OS | 1.3+ |
| Health Services | 1.0+ |
| Play Services Wearable | 18.1+ |
| minSdk | 30 (Wear OS 3.0) |
| targetSdk | 34 |
| Hardware para teste | WearOS watch real (emulator não tem GPS/HR reais) |

---

## 6. Mapeamento de Funcionalidades → Arquivos

### Apple Watch

| Funcionalidade | Arquivo | Framework |
|---------------|---------|-----------|
| Entry point | `Sources/App/OmniRunnerWatchApp.swift` | SwiftUI `@main` |
| Workout tracking | `Sources/Managers/WorkoutManager.swift` | HealthKit |
| GPS tracking | `Sources/Managers/LocationManager.swift` | CoreLocation |
| Phone sync | `Sources/Managers/ConnectivityManager.swift` | WatchConnectivity |
| Haptic alerts | `Sources/Managers/HapticManager.swift` | WatchKit |
| UI ao vivo | `Sources/Views/WorkoutView.swift` | SwiftUI |
| Pós-corrida | `Sources/Views/SummaryView.swift` | SwiftUI |
| Sessão local | `Sources/Models/WorkoutSession.swift` | SwiftData |
| Distância/pace | `Sources/Utils/MetricsCalculator.swift` | Swift puro |
| Zonas HR | `Sources/Models/HrZone.swift` | Swift puro |

### WearOS

| Funcionalidade | Arquivo | Framework |
|---------------|---------|-----------|
| Entry point | `MainActivity.kt` (a criar) | Activity |
| Workout tracking | `service/ExerciseManager.kt` | Health Services |
| GPS tracking | `service/WorkoutService.kt` | FusedLocation |
| Phone sync | `data/sync/DataLayerManager.kt` | DataLayer API |
| Foreground service | `service/WorkoutService.kt` | Android Service |
| UI ao vivo | `ui/screens/WorkoutScreen.kt` | Compose for Wear |
| Pós-corrida | `ui/screens/SummaryScreen.kt` | Compose for Wear |
| Sessão local | `data/local/SessionEntity.kt` | Room |
| Distância/pace | `domain/usecases/MetricsCalculator.kt` | Kotlin puro |
| Zonas HR | `domain/models/HrZone.kt` | Kotlin puro |

---

## 7. Paralelismo com o Domain Flutter

Várias entidades e use cases do Flutter domain serão **reimplementados**
em Swift e Kotlin para o watch. A lógica é simples o suficiente para
não justificar um mecanismo de compartilhamento de código.

| Conceito Flutter (Dart) | Apple Watch (Swift) | WearOS (Kotlin) |
|------------------------|--------------------|--------------------|
| `HrZone` + `HrZoneCalculator` | `HrZone.swift` | `HrZone.kt` |
| `haversineMeters()` | `Haversine.swift` | `Haversine.kt` |
| `CalculatePace` | `MetricsCalculator.swift` | `MetricsCalculator.kt` |
| `WorkoutSessionEntity` | `WorkoutSession.swift` | `WorkoutSession.kt` |
| `LocationPointEntity` | `LocationSample.swift` | `LocationSample.kt` |
| `HeartRateSample` | `HeartRateSample.swift` | `HeartRateSample.kt` |
| Wire format JSON v1 | Codable structs | Kotlinx Serialization |

---

## 8. O que NÃO está nesta sprint

Esta sprint cria **apenas a estrutura de diretórios e documentação**.
Nenhum código-fonte, build script ou configuração de projeto foi criado.

| Item | Sprint | Status |
|------|--------|--------|
| Estrutura de pastas | W12.0.2 (esta) | ✅ Criado |
| Documentação de estrutura | W12.0.2 (esta) | ✅ Criado |
| Xcode target (watch) | W12.1.1 | Pendente |
| Gradle build scripts (WearOS) | W12.2.1 | Pendente |
| Código Swift (WorkoutManager, etc.) | W12.1.2+ | Pendente |
| Código Kotlin (ExerciseManager, etc.) | W12.2.2+ | Pendente |
| Flutter bridge (MethodChannel) | W12.1.5 / W12.2.5 | Pendente |
