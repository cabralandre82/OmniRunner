# WearOS Watch App — Setup Guide

> **Sprint:** W12.2.1  
> **Status:** Projeto criado, compilável  
> **Referência:** docs/WatchArchitecture.md

---

## 1. Visão Geral

O app WearOS é um **projeto Android nativo independente** localizado em `watch/wear_os/`. Ele NÃO é um módulo do projeto Flutter — possui seu próprio Gradle build system, dependencies e signing.

**Stack tecnológica:**

| Tecnologia | Versão | Propósito |
|-----------|--------|-----------|
| Kotlin | 1.9.22 | Linguagem principal |
| Compose for Wear OS | 1.3.0 | UI framework |
| AGP (Android Gradle Plugin) | 8.2.2 | Build system |
| Gradle | 8.5 | Build tool |
| Compose Compiler | 1.5.10 | Compose compilation |
| Health Services | 1.0.0-rc02 | ExerciseClient (workout tracking) |
| Play Services Wearable | 18.1.0 | DataLayer API (phone communication) |
| Play Services Location | 21.1.0 | FusedLocationProvider (GPS) |
| Room | 2.6.1 | Persistência local (SQLite) |
| Target SDK | 34 | Android 14 |
| Min SDK | 30 | Wear OS 3+ |

---

## 2. Estrutura do Projeto

```
watch/wear_os/
├── settings.gradle.kts           # Plugin management + project name
├── build.gradle.kts              # Root build (plugin versions)
├── gradle.properties             # JVM + AndroidX flags
├── gradle/wrapper/
│   └── gradle-wrapper.properties # Gradle 8.5 distribution
├── app/
│   ├── build.gradle.kts          # Module build (deps, SDK, compose)
│   ├── proguard-rules.pro        # R8 rules for release builds
│   └── src/
│       ├── main/
│       │   ├── AndroidManifest.xml
│       │   ├── kotlin/com/omnirunner/watch/
│       │   │   ├── OmniRunnerWatchApp.kt    # Application class
│       │   │   ├── MainActivity.kt          # Compose entry point
│       │   │   ├── ui/
│       │   │   │   ├── theme/Theme.kt       # Material Wear theme
│       │   │   │   └── screens/StartScreen.kt
│       │   │   ├── service/
│       │   │   │   └── WorkoutService.kt    # Foreground service (skeleton)
│       │   │   ├── data/sync/
│       │   │   │   └── WearListenerService.kt  # DataLayer listener (skeleton)
│       │   │   └── domain/models/
│       │   │       ├── HeartRateSample.kt
│       │   │       ├── LocationSample.kt
│       │   │       └── HrZone.kt
│       │   └── res/
│       │       ├── values/strings.xml
│       │       ├── values/colors.xml
│       │       ├── drawable/ic_run.xml
│       │       ├── drawable/ic_play.xml
│       │       └── mipmap-hdpi/ic_launcher.xml
│       └── test/kotlin/com/omnirunner/watch/
│           └── (testes unitários JUnit)
```

---

## 3. Como Abrir no Android Studio

### Passo a passo

1. Abrir Android Studio
2. File → Open → selecionar `watch/wear_os/`
3. Aguardar Gradle sync completar
4. Selecionar o módulo `:app`
5. Conectar um Wear OS emulador ou dispositivo real

### Criar emulador Wear OS

1. Tools → Device Manager → Create Device
2. Selecionar **Wear OS** na categoria
3. Escolher **Wear OS Square** ou **Round** (API 34)
4. Baixar system image **Wear OS 4** (API 34, x86_64)
5. Finalizar e iniciar o emulador

### Executar o app

```bash
cd watch/wear_os
./gradlew :app:installDebug
```

Ou pelo Android Studio: Run → Run 'app' com o emulador/device selecionado.

---

## 4. Gerar Gradle Wrapper (primeira vez)

Se o `gradlew` e `gradlew.bat` não existirem, gere-os:

```bash
cd watch/wear_os
gradle wrapper --gradle-version 8.5
```

Isso cria:
- `gradlew` (Linux/macOS)
- `gradlew.bat` (Windows)
- `gradle/wrapper/gradle-wrapper.jar`

> **Nota:** O arquivo `gradle-wrapper.properties` já está configurado.
> O `gradle-wrapper.jar` não é commitado por padrão (binário).

---

## 5. Permissões Configuradas

O `AndroidManifest.xml` já declara todas as permissões necessárias:

| Permissão | Propósito |
|-----------|-----------|
| `ACCESS_FINE_LOCATION` | GPS de alta precisão |
| `ACCESS_COARSE_LOCATION` | Fallback de localização |
| `ACCESS_BACKGROUND_LOCATION` | GPS com tela desligada |
| `BODY_SENSORS` | HR do sensor óptico do watch |
| `BODY_SENSORS_BACKGROUND` | HR com tela desligada |
| `ACTIVITY_RECOGNITION` | Steps/cadência |
| `FOREGROUND_SERVICE` | Serviço de workout |
| `FOREGROUND_SERVICE_HEALTH` | Tipo health para o foreground service |
| `FOREGROUND_SERVICE_LOCATION` | Tipo location para o foreground service |
| `VIBRATE` | Alertas hápticos |
| `WAKE_LOCK` | CPU ativo durante workout |
| `INTERNET` | Sync futura com cloud |

### Meta-data

- `com.google.android.wearable.standalone = true` — app funciona sem o phone
- `uses-feature android.hardware.type.watch` — marca como app exclusivo de watch

---

## 6. Componentes Declarados

| Componente | Tipo | Status |
|-----------|------|--------|
| `MainActivity` | Activity | Funcional (Compose UI) |
| `WorkoutService` | Foreground Service | Skeleton (W12.2.2) |
| `WearListenerService` | WearableListenerService | Skeleton (W12.2.4) |

---

## 7. Relação com o Phone App Flutter

O WearOS app é **independente** do projeto Flutter. A comunicação acontece em **runtime** via DataLayer API:

```
┌─────────────────┐     DataLayer API      ┌─────────────────┐
│  WearOS Watch   │ ←────────────────────→  │  Android Phone  │
│  (Kotlin/Compose)│   Message / DataItem   │  (Flutter)      │
└─────────────────┘                         └─────────────────┘
```

- **Watch → Phone:** Workout sessions, live samples
- **Phone → Watch:** ACK, settings (maxHR, alerts)
- **Wire format:** JSON (MVP), Protobuf futuro

---

## 8. Diferenças vs Apple Watch

| Aspecto | Apple Watch | WearOS |
|---------|-------------|--------|
| Localização no repo | `omni_runner/ios/OmniRunnerWatch/` | `watch/wear_os/` |
| Relação com phone app | Target dentro do Xcode project | Projeto Gradle independente |
| Workout API | `HKWorkoutSession` + `HKLiveWorkoutBuilder` | Health Services `ExerciseClient` |
| GPS | `CLLocationManager` | `FusedLocationProviderClient` |
| Sync API | `WatchConnectivity` | `DataLayer API` |
| UI | SwiftUI | Compose for Wear OS |
| Persistência local | Planned: SwiftData/CoreData | Room Database |
| Distribuição | Junto com iPhone app (App Store) | APK separado (Play Store) |

---

## 9. Próximos Sprints

| Sprint | Descrição |
|--------|-----------|
| W12.2.2 | Tracking (ExerciseClient + GPS + metrics) |
| W12.2.3 | UI Compose (workout screen + summary) |
| W12.2.4 | DataLayer API (sync session → phone) |
| W12.2.5 | Flutter bridge Android (MethodChannel + Isar) |
| W12.2.6 | Testes E2E WearOS → Phone → Isar |
