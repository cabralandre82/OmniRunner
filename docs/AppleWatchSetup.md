# Apple Watch App Setup — Omni Runner

> **Sprint:** W12.1.1  
> **Status:** Projeto watchOS criado  
> **Última atualização:** 17 Fev 2026

---

## 1. Visão Geral

O Apple Watch app é um **target nativo SwiftUI** dentro do projeto Xcode existente do Flutter.  
Não usa Flutter — é 100% Swift/SwiftUI, com comunicação futura via `WatchConnectivity`.

### Arquitetura

```
omni_runner/ios/
├── Runner/                    # iPhone app (Flutter)
├── Runner.xcodeproj/          # Projeto Xcode (contém ambos os targets)
├── Runner.xcworkspace/        # Workspace (abrir este)
├── OmniRunnerWatch/           # ← NOVO: Watch app (SwiftUI nativo)
│   ├── OmniRunnerWatchApp.swift    # @main entry point
│   ├── ContentView.swift           # UI placeholder
│   ├── Info.plist                  # Configurações watchOS
│   ├── OmniRunnerWatch.entitlements # HealthKit capability
│   └── Assets.xcassets/            # Ícones e assets do watch
│       ├── Contents.json
│       └── AppIcon.appiconset/
│           └── Contents.json
└── RunnerTests/
```

---

## 2. Targets no Xcode

| Target | Tipo | Plataforma | Bundle ID |
|--------|------|-----------|-----------|
| **Runner** | iOS App (Flutter) | iOS 12.0+ | `com.omnirunner.omniRunner` |
| **RunnerTests** | Unit Tests | iOS | `com.omnirunner.omniRunner.RunnerTests` |
| **OmniRunnerWatch** | watchOS App | watchOS 10.0+ | `com.omnirunner.omniRunner.watchkitapp` |

> **Nota:** O bundle ID do watch DEVE ser um filho (child) do bundle ID do iPhone app.  
> `com.omnirunner.omniRunner` → `com.omnirunner.omniRunner.watchkitapp`

---

## 3. Capabilities Configuradas

### 3.1. HealthKit

Arquivo: `OmniRunnerWatch/OmniRunnerWatch.entitlements`

| Entitlement | Valor | Propósito |
|------------|-------|-----------|
| `com.apple.developer.healthkit` | `true` | Acesso ao HealthKit no watch |
| `com.apple.developer.healthkit.access` | `[]` | Tipos de dados (configurar em runtime) |
| `com.apple.developer.healthkit.background-delivery` | `true` | HR contínuo durante workout |

### 3.2. Background Workout Mode

Arquivo: `OmniRunnerWatch/Info.plist`

```xml
<key>WKBackgroundModes</key>
<array>
    <string>workout-processing</string>
</array>
```

O modo `workout-processing` permite que o app continue executando quando:
- O usuário abaixa o pulso (tela desliga)
- O watch entra em modo ambient/always-on
- Outra complication é mostrada brevemente

**Obrigatório para:** `HKWorkoutSession` com HR contínuo e GPS tracking.

### 3.3. Standalone Watch App

```xml
<key>WKApplication</key>
<true/>
<key>WKCompanionAppBundleIdentifier</key>
<string>com.omnirunner.omniRunner</string>
<key>WKRunsIndependentlyOfCompanionApp</key>
<true/>
```

| Chave | Propósito |
|-------|-----------|
| `WKApplication` | Indica app SwiftUI lifecycle (watchOS 10+) |
| `WKCompanionAppBundleIdentifier` | Vincula ao iPhone app para distribuição conjunta |
| `WKRunsIndependentlyOfCompanionApp` | Permite uso sem iPhone por perto |

---

## 4. Permissões de Uso (Info.plist)

| Chave | Descrição | Quando aparece |
|-------|-----------|----------------|
| `NSHealthShareUsageDescription` | Leitura de HR e dados HealthKit | Primeira solicitação de permissão HealthKit |
| `NSHealthUpdateUsageDescription` | Escrita de workouts no HealthKit | Primeira solicitação de escrita |
| `NSLocationWhenInUseUsageDescription` | GPS para rota de corrida | Primeira solicitação de localização |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | GPS em background durante workout | Após conceder "When In Use" |

---

## 5. Build Settings Chave

| Setting | Valor | Propósito |
|---------|-------|-----------|
| `SDKROOT` | `watchos` | Compilar para watchOS |
| `WATCHOS_DEPLOYMENT_TARGET` | `10.0` | Mínimo watchOS 10 (SwiftUI lifecycle) |
| `TARGETED_DEVICE_FAMILY` | `4` | Apenas Apple Watch |
| `SWIFT_VERSION` | `5.0` | Compatibilidade Swift |
| `SKIP_INSTALL` | `YES` | Watch app é embeddido, não instalado diretamente |
| `PRODUCT_BUNDLE_IDENTIFIER` | `com.omnirunner.omniRunner.watchkitapp` | Child do bundle do iPhone |

---

## 6. Como Abrir e Compilar

### Pré-requisitos

- **macOS** (não é possível compilar watchOS no Linux)
- **Xcode 15.0+** (para watchOS 10 SDK)
- **Apple Watch Series 4+** (watchOS 10 requer Series 4 ou posterior)
- Apple Developer account (para code signing)

### Passos

```bash
# 1. Abrir o workspace (NÃO o .xcodeproj)
cd omni_runner/ios
open Runner.xcworkspace

# 2. No Xcode:
#    - Selecionar o scheme "OmniRunnerWatch" no dropdown de schemes
#    - Selecionar um Apple Watch simulator como destination
#    - Cmd+B para compilar
#    - Cmd+R para rodar no simulador

# 3. Para testar no device real:
#    - Configurar Team no Signing & Capabilities
#    - Conectar Apple Watch pareado via Wi-Fi
#    - Build & Run
```

### Troubleshooting

| Problema | Solução |
|----------|---------|
| "No such module 'SwiftUI'" | Verificar que SDKROOT = watchos no target |
| Watch target não aparece em Schemes | Product → Scheme → Manage Schemes → adicionar OmniRunnerWatch |
| Code signing error | Configurar Team em Signing & Capabilities para o target OmniRunnerWatch |
| "Bundle identifier collision" | Verificar que watch bundle ID é child do iPhone bundle ID |
| watchOS 10 não disponível | Atualizar Xcode para 15.0+ |

---

## 7. Estrutura de Embedding

O iPhone app (Runner) **embeda** automaticamente o watch app:

```
Runner target
  └── Build Phases
       └── Embed Watch Content
            └── OmniRunnerWatch.app
```

Quando o usuário instala o iPhone app via App Store, o watch app é instalado automaticamente no Apple Watch pareado.

### Target Dependency

```
Runner ──depends on──► OmniRunnerWatch
```

Isso garante que o watch app é compilado antes do iPhone app.

---

## 8. Próximos Passos (Sprints Futuros)

| Sprint | Implementação |
|--------|---------------|
| W12.1.2 | `WorkoutManager` — `HKWorkoutSession` + `CLLocationManager` |
| W12.1.3 | SwiftUI views — workout view + summary |
| W12.1.4 | `WatchConnectivity` — sync sessão → phone |
| W12.1.5 | Flutter bridge iOS — `MethodChannel` + Isar |

---

## 9. Referências

- [Apple: Creating a watchOS App](https://developer.apple.com/documentation/watchos-apps/creating-a-watchos-app)
- [Apple: HKWorkoutSession](https://developer.apple.com/documentation/healthkit/hkworkoutsession)
- [Apple: Background execution on watchOS](https://developer.apple.com/documentation/watchkit/background_execution)
- [Apple: WKBackgroundModes](https://developer.apple.com/documentation/bundleresources/information_property_list/wkbackgroundmodes)
- [docs/WatchArchitecture.md](WatchArchitecture.md) — Arquitetura completa
- [docs/WatchProjectStructure.md](WatchProjectStructure.md) — Estrutura de diretórios
