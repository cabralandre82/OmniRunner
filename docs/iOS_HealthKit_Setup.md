# iOS HealthKit Setup — Omni Runner

> **Sprint:** W2.1
> **Status:** Configurado
> **Referência:** WearablesPlan.md, WearablesTestMatrix.md

---

## 1. Visão Geral

O Omni Runner integra com o Apple HealthKit para:

- **Leitura:** Heart rate, steps, workout data do Apple Health
- **Escrita:** Salvar workouts (tipo RUNNING), distância, calorias e rota GPS no Apple Health

Isso permite que o usuário tenha um histórico unificado de fitness entre o Omni Runner e outros apps (Apple Watch, Strava, Nike Run Club, etc.).

---

## 2. Configuração Realizada

### 2.1. Info.plist

Dois usage descriptions obrigatórios foram adicionados em `ios/Runner/Info.plist`:

```xml
<!-- HealthKit -->
<key>NSHealthShareUsageDescription</key>
<string>Omni Runner reads your heart rate, steps, and workout data from Apple Health to track your performance and progress.</string>

<key>NSHealthUpdateUsageDescription</key>
<string>Omni Runner saves your running workouts, heart rate data, and distance to Apple Health so you have a unified fitness history.</string>
```

| Chave | Propósito | Quando aparece |
|-------|-----------|----------------|
| `NSHealthShareUsageDescription` | Leitura de dados do Health | Primeiro acesso a `requestAuthorization(toShare:read:)` |
| `NSHealthUpdateUsageDescription` | Escrita de dados no Health | Mesmo momento |

> **Importante:** Se estas chaves estiverem ausentes, o app crashará ao tentar acessar HealthKit.

### 2.2. Runner.entitlements

Arquivo criado em `ios/Runner/Runner.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.healthkit</key>
    <true/>
    <key>com.apple.developer.healthkit.access</key>
    <array/>
    <key>com.apple.developer.healthkit.background-delivery</key>
    <true/>
</dict>
</plist>
```

| Entitlement | Propósito |
|-------------|-----------|
| `com.apple.developer.healthkit` | Habilita o capability HealthKit |
| `com.apple.developer.healthkit.access` | Array de tipos clínicos (vazio = não usamos clinical data) |
| `com.apple.developer.healthkit.background-delivery` | Permite receber updates de saúde em background |

### 2.3. Xcode Project (project.pbxproj)

O arquivo `Runner.entitlements` foi referenciado no Xcode project:

1. **PBXFileReference** — Registra o arquivo como recurso do projeto
2. **PBXGroup (Runner)** — Adiciona ao grupo Runner para visibilidade no Xcode
3. **CODE_SIGN_ENTITLEMENTS** — Adicionado nas 3 build configurations:
   - `Debug`
   - `Release`
   - `Profile`

### 2.4. UIBackgroundModes

Em `Info.plist`, o background mode `bluetooth-central` foi adicionado (em W0.3) para BLE HR em background. HealthKit background delivery é habilitado via entitlements, não via `UIBackgroundModes`.

---

## 3. Dependência Flutter

O package `health: ^13.3.1` já foi adicionado ao `pubspec.yaml` no SPRINT W0.3:

```yaml
dependencies:
  health: ^13.3.1
```

Este package abstrai tanto HealthKit (iOS) quanto Health Connect (Android) com uma API unificada.

---

## 4. Tipos de Dados HealthKit Utilizados

| HKQuantityType / HKWorkoutType | Leitura | Escrita | Uso no Omni Runner |
|--------------------------------|---------|---------|---------------------|
| `HKQuantityType.heartRate` | ✅ | ✅ | HR em tempo real e histórico |
| `HKQuantityType.stepCount` | ✅ | ❌ | Contagem de passos para anti-cheat |
| `HKQuantityType.distanceWalkingRunning` | ✅ | ✅ | Distância da corrida |
| `HKQuantityType.activeEnergyBurned` | ❌ | ✅ | Calorias no workout export |
| `HKWorkoutType.workout` | ✅ | ✅ | Export de workouts completos |
| `HKSeriesType.workoutRoute` | ❌ | ✅ | Rota GPS no workout |

---

## 5. Fluxo de Permissões iOS

```
App inicia
  → Health.hasPermissions(types, permissions)
    → Se não tem → Health.requestAuthorization(types, permissions)
      → iOS mostra dialog nativo com as NSHealth*UsageDescription
        → Usuário seleciona quais tipos autorizar
          → Se tudo OK → Health.getHealthDataFromTypes() funciona
          → Se negado → App degrada gracefully (GPS-only mode)
```

### Particularidades iOS:
- **HealthKit não informa se permissão foi negada.** `HKAuthorizationStatus.sharingDenied` existe para escrita, mas para leitura o iOS retorna dados vazios ao invés de erro. O app não tem como saber se o usuário negou ou simplesmente não tem dados.
- **Permissões são por tipo.** O usuário pode autorizar HR mas negar Steps.
- **Não há "permanently denied"** como no Android. O usuário pode sempre reconfigurar em Settings > Health > Omni Runner.
- **Primeiro acesso após reboot** pode falhar se o dispositivo está locked (HealthKit requer unlock).

---

## 6. Requisitos de Ambiente

| Requisito | Valor |
|-----------|-------|
| iOS mínimo | 13.0 (HealthKit disponível desde iOS 8, mas o `health` package requer 13+) |
| Dispositivo | iPhone real (HealthKit não funciona no Simulator) |
| Apple Developer Account | Necessária para signing com HealthKit capability |
| Xcode | 15.0+ recomendado |

---

## 7. Checklist de Verificação

- [x] `NSHealthShareUsageDescription` em Info.plist
- [x] `NSHealthUpdateUsageDescription` em Info.plist
- [x] `Runner.entitlements` criado com HealthKit capabilities
- [x] `Runner.entitlements` referenciado no project.pbxproj (PBXFileReference)
- [x] `Runner.entitlements` no grupo Runner (PBXGroup)
- [x] `CODE_SIGN_ENTITLEMENTS` em Debug, Release e Profile configs
- [x] `com.apple.developer.healthkit` = true
- [x] `com.apple.developer.healthkit.background-delivery` = true
- [x] `health: ^13.3.1` no pubspec.yaml
- [ ] HealthKit capability habilitado no Apple Developer Portal (manual, requer conta de desenvolvedor)

---

## 8. Troubleshooting

### Build falha com "Signing requires a provisioning profile"
O HealthKit capability requer um Apple Developer Account com provisioning profile que inclua o entitlement. Free accounts não suportam HealthKit.

### App crasha ao chamar HealthKit no Simulator
HealthKit não está disponível no iOS Simulator. Use `Health().isHealthConnectAvailable()` (Android) ou verifique `HKHealthStore.isHealthDataAvailable()` antes de qualquer chamada.

### Dialog de permissão não aparece
Verifique se as duas `NSHealth*UsageDescription` estão no Info.plist. Sem elas, o iOS rejeita silenciosamente a request.

### Dados vazios após autorização
Isso é comportamento normal do iOS. Se o usuário negou leitura, o HealthKit retorna dados vazios ao invés de um erro. Trate arrays vazios como "sem dados disponíveis".
