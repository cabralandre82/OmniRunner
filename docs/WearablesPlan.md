# WearablesPlan.md — Plano de Integração Wearable

> **Sprint:** W0.1
> **Status:** ATIVO
> **Pré-requisito:** GAP_WEARABLES_SDK.md lido e congelado
> **Referência:** ARCHITECTURE.md, MASTER_PLAN.md, DECISIONS.md

---

## 1. ESTADO ATUAL: GPS ONLY

O Omni Runner captura dados exclusivamente via `geolocator` (GPS do smartphone).
Não existe nenhum código funcional para sensores externos, APIs de saúde
ou comunicação Bluetooth.

### Ganchos existentes no código (não funcionais)

| Artefato | Arquivo | Status |
|----------|---------|--------|
| `AudioEventType.heartRateAlert` | `domain/entities/audio_event_entity.dart` | Enum definido, nunca emitido |
| `AudioEventType.paceAlert` | `domain/entities/audio_event_entity.dart` | Enum definido, nunca emitido |
| `IStepsSource` interface | `domain/usecases/integrity_detect_vehicle.dart` | Interface definida, sem implementação |
| `StepSample` struct | `domain/usecases/integrity_detect_vehicle.dart` | Struct definida, nunca instanciada |
| `IntegrityDetectVehicle` use case | `domain/usecases/integrity_detect_vehicle.dart` | Código completo, NÃO registrado no service_locator |
| `_hrText()` formatter | `data/repositories_impl/audio_coach_repo.dart` | Formatter pronto, nunca acionado |

---

## 2. LISTA COMPLETA DO GAP

### BLOCO A — BLE Heart Rate

**Objetivo:** Ler BPM em tempo real de qualquer cinta BLE (Garmin HRM-Pro, Polar H10, Wahoo TICKR, Coros HR)

| # | Item | Status |
|---|------|--------|
| A1 | Dependência `flutter_blue_plus` no pubspec | ✅ W0.3 |
| A2 | Permissões BLE no AndroidManifest (`BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`) | ✅ W0.3 |
| A3 | `uses-feature android.hardware.bluetooth_le` no AndroidManifest | ✅ W0.3 |
| A4 | `NSBluetoothAlwaysUsageDescription` no Info.plist | ✅ W0.3 |
| A5 | `UIBackgroundModes: bluetooth-central` no Info.plist | ✅ W0.3 |
| A6 | Datasource `BleHeartRateSource` (scan, connect, parse UUID 0x180D) | ✅ W1.2 |
| A7 | Entity `HeartRateSample` no domain | ✅ W1.2 |
| A8 | Interface `IHeartRateSource` no domain | ✅ W1.2 |
| A9 | Repository `BleHeartRateRepo` implementando `IHeartRateStream` | ✅ W1.2 (merged into BleHeartRateSource) |
| A10 | Registro no `service_locator.dart` | ✅ W1.2 |
| A11 | Integração no `TrackingBloc` (campo `currentHR`, subscription) | ❌ Ausente |
| A12 | `TrackingState` com campo `heartRateBpm` | ❌ Ausente |
| A13 | UI: HR na `TrackingBottomPanel` | ❌ Ausente |
| A14 | UI: Tela de scan/seleção de dispositivo BLE | ✅ W1.2 (DebugHrmScreen) |

**Arquivos que serão CRIADOS:**

| Arquivo | Camada |
|---------|--------|
| `lib/data/datasources/ble_hrm_datasource.dart` | data/datasource |
| `lib/domain/entities/heart_rate_sample.dart` | domain/entity |
| `lib/domain/repositories/i_heart_rate_stream.dart` | domain/repository |
| `lib/data/repositories_impl/ble_heart_rate_repo.dart` | data/repository |
| `lib/presentation/screens/hrm_scan_screen.dart` | presentation |
| `test/data/datasources/ble_hrm_datasource_test.dart` | test |
| `test/domain/usecases/heart_rate_zone_test.dart` | test |

**Arquivos que serão ALTERADOS:**

| Arquivo | Alteração |
|---------|-----------|
| `pubspec.yaml` | Adicionar `flutter_blue_plus: ^2.1.1` |
| `android/app/src/main/AndroidManifest.xml` | Adicionar permissions BLE |
| `ios/Runner/Info.plist` | Adicionar BLE usage description + background mode |
| `lib/core/service_locator.dart` | Registrar `BleHrmDatasource`, `IHeartRateStream`, `BleHeartRateRepo` |
| `lib/presentation/blocs/tracking/tracking_bloc.dart` | HR subscription, `_hrSub`, cleanup no `close()` |
| `lib/presentation/blocs/tracking/tracking_state.dart` | Campo `heartRateBpm` em `TrackingActive` |
| `lib/presentation/blocs/tracking/tracking_event.dart` | Evento `HeartRateReceived`, `ConnectHrm`, `DisconnectHrm` |
| `lib/presentation/widgets/tracking_bottom_panel.dart` | Coluna HR no `_MetricsRow` |
| `lib/presentation/screens/tracking_screen.dart` | Botão de BLE na `_TopBar`, navegação para scan |

---

### BLOCO B — HealthKit + Health Connect

**Objetivo:** Ler HR/steps das plataformas de saúde; escrever workouts+rotas após corrida

| # | Item | Status |
|---|------|--------|
| B1 | Dependência `health` no pubspec | ✅ W0.3 |
| B2 | `NSHealthShareUsageDescription` no Info.plist | ✅ W0.3 |
| B3 | `NSHealthUpdateUsageDescription` no Info.plist | ✅ W0.3 |
| B4 | HealthKit Capability no Xcode (manual, fora do código) | ✅ W0.3 (entitlements) |
| B5 | Health Connect `<queries>` no AndroidManifest | ✅ W0.3 |
| B6 | Health Connect permissions no AndroidManifest (READ/WRITE HR, STEPS, EXERCISE, ROUTE) | ✅ W0.3 |
| B7 | `ACTIVITY_RECOGNITION` permission no AndroidManifest | ✅ W0.3 |
| B8 | Privacy policy `activity-alias` no AndroidManifest | ✅ W0.3 |
| B9 | `intent-filter` ACTION_SHOW_PERMISSIONS_RATIONALE no AndroidManifest | ✅ W0.3 |
| B10 | `MainActivity` estender `FlutterFragmentActivity` | ✅ W0.3 |
| B11 | Datasource `HealthPlatformService` (wrapper do `health` package) | ❌ Ausente |
| B12 | Interface `IHealthPlatformRepo` no domain | ❌ Ausente |
| B13 | Repository `HealthPlatformRepo` implementando interface | ❌ Ausente |
| B14 | Registro no `service_locator.dart` | ❌ Ausente |
| B15 | Fluxo de autorização na UI (pedir permissões de saúde) | ❌ Ausente |

**Arquivos que serão CRIADOS:**

| Arquivo | Camada |
|---------|--------|
| `lib/data/datasources/health_platform_service.dart` | data/datasource |
| `lib/domain/repositories/i_health_platform.dart` | domain/repository |
| `lib/data/repositories_impl/health_platform_repo.dart` | data/repository |
| `lib/domain/failures/health_failure.dart` | domain/failure |
| `test/data/datasources/health_platform_service_test.dart` | test |

**Arquivos que serão ALTERADOS:**

| Arquivo | Alteração |
|---------|-----------|
| `pubspec.yaml` | Adicionar `health: ^13.3.1` |
| `android/app/src/main/AndroidManifest.xml` | Health Connect queries, permissions, activity-alias, intent-filter |
| `android/app/src/main/kotlin/.../MainActivity.kt` | Estender `FlutterFragmentActivity` |
| `ios/Runner/Info.plist` | Health usage descriptions |
| `lib/core/service_locator.dart` | Registrar `HealthPlatformService`, `IHealthPlatformRepo` |
| `lib/presentation/screens/settings_screen.dart` | Toggle de health sync + botão autorizar |

---

### BLOCO C — Export Workouts

**Objetivo:** Ao finalizar corrida, exportar sessão para Apple Health / Health Connect

| # | Item | Status |
|---|------|--------|
| C1 | Use case `ExportWorkoutToHealth` | ❌ Ausente |
| C2 | Mapper de `LocationPointEntity` → `WorkoutRouteLocation` | ❌ Ausente |
| C3 | Chamada no `FinishSession` use case | ❌ Ausente |
| C4 | Flag `isExported` no `WorkoutSessionRecord` (Isar) | ❌ Ausente |
| C5 | Toggle de export automático nas settings | ❌ Ausente |

**Arquivos que serão CRIADOS:**

| Arquivo | Camada |
|---------|--------|
| `lib/domain/usecases/export_workout_to_health.dart` | domain/usecase |
| `lib/data/mappers/health_workout_mapper.dart` | data/mapper |
| `test/domain/usecases/export_workout_to_health_test.dart` | test |

**Arquivos que serão ALTERADOS:**

| Arquivo | Alteração |
|---------|-----------|
| `lib/domain/usecases/finish_session.dart` | Chamar export após finalizar (opcional, flag-gated) |
| `lib/data/models/isar/workout_session_record.dart` | Campo `isExported` |
| `lib/data/models/isar/workout_session_record.g.dart` | Regenerar com `build_runner` |
| `lib/core/service_locator.dart` | Registrar `ExportWorkoutToHealth` |
| `lib/presentation/screens/settings_screen.dart` | Toggle export automático |

---

### BLOCO D — Steps Reais

**Objetivo:** Implementar `IStepsSource` com dados reais do pedômetro via `health` package, ativar `IntegrityDetectVehicle`

| # | Item | Status |
|---|------|--------|
| D1 | Implementação concreta de `IStepsSource` usando `health` package | ❌ Ausente |
| D2 | Registro de `IStepsSource` no `service_locator.dart` | ❌ Ausente |
| D3 | Registro de `IntegrityDetectVehicle` no `service_locator.dart` | ❌ Ausente |
| D4 | Integração no `TrackingBloc._checkIntegrity()` | ❌ Ausente |

**Arquivos que serão CRIADOS:**

| Arquivo | Camada |
|---------|--------|
| `lib/data/datasources/health_steps_source.dart` | data/datasource |
| `test/data/datasources/health_steps_source_test.dart` | test |

**Arquivos que serão ALTERADOS:**

| Arquivo | Alteração |
|---------|-----------|
| `lib/core/service_locator.dart` | Registrar `HealthStepsSource`, `IntegrityDetectVehicle` |
| `lib/presentation/blocs/tracking/tracking_bloc.dart` | Chamar vehicle detection no `_checkIntegrity()` |

---

### BLOCO E — Voice HR Alerts

**Objetivo:** Emitir alertas de voz quando HR entra/sai de zonas cardíacas

| # | Item | Status |
|---|------|--------|
| E1 | Use case `HeartRateZoneCalculator` | ❌ Ausente |
| E2 | Entity `HeartRateZone` | ❌ Ausente |
| E3 | Voice trigger `HrZoneVoiceTrigger` | ❌ Ausente |
| E4 | Coach settings: toggle de HR alerts | ❌ Ausente |
| E5 | Settings UI: campo de HR max do usuário | ❌ Ausente |

**Arquivos que serão CRIADOS:**

| Arquivo | Camada |
|---------|--------|
| `lib/domain/entities/heart_rate_zone.dart` | domain/entity |
| `lib/domain/usecases/heart_rate_zone_calculator.dart` | domain/usecase |
| `lib/domain/usecases/hr_zone_voice_trigger.dart` | domain/usecase |
| `test/domain/usecases/heart_rate_zone_calculator_test.dart` | test |
| `test/domain/usecases/hr_zone_voice_trigger_test.dart` | test |

**Arquivos que serão ALTERADOS:**

| Arquivo | Alteração |
|---------|-----------|
| `lib/domain/entities/coach_settings_entity.dart` | Campos `hrAlertEnabled`, `maxHr` |
| `lib/data/repositories_impl/coach_settings_repo.dart` | Persistir novos campos |
| `lib/presentation/blocs/tracking/tracking_bloc.dart` | Chamar HR zone trigger no `_evalTriggers()` |
| `lib/core/service_locator.dart` | Registrar use cases |
| `lib/presentation/screens/settings_screen.dart` | Toggle HR alerts + campo HR max |

---

## 3. RESUMO DE IMPACTO POR ARQUIVO

### Arquivos NOVOS (15 arquivos)

| # | Path | Bloco |
|---|------|-------|
| 1 | `lib/data/datasources/ble_hrm_datasource.dart` | A |
| 2 | `lib/domain/entities/heart_rate_sample.dart` | A |
| 3 | `lib/domain/repositories/i_heart_rate_stream.dart` | A |
| 4 | `lib/data/repositories_impl/ble_heart_rate_repo.dart` | A |
| 5 | `lib/presentation/screens/hrm_scan_screen.dart` | A |
| 6 | `lib/data/datasources/health_platform_service.dart` | B |
| 7 | `lib/domain/repositories/i_health_platform.dart` | B |
| 8 | `lib/data/repositories_impl/health_platform_repo.dart` | B |
| 9 | `lib/domain/failures/health_failure.dart` | B |
| 10 | `lib/domain/usecases/export_workout_to_health.dart` | C |
| 11 | `lib/data/mappers/health_workout_mapper.dart` | C |
| 12 | `lib/data/datasources/health_steps_source.dart` | D |
| 13 | `lib/domain/entities/heart_rate_zone.dart` | E |
| 14 | `lib/domain/usecases/heart_rate_zone_calculator.dart` | E |
| 15 | `lib/domain/usecases/hr_zone_voice_trigger.dart` | E |

### Arquivos ALTERADOS (16 arquivos)

| # | Path | Blocos |
|---|------|--------|
| 1 | `pubspec.yaml` | A, B |
| 2 | `android/app/src/main/AndroidManifest.xml` | A, B |
| 3 | `android/app/src/main/kotlin/.../MainActivity.kt` | B |
| 4 | `ios/Runner/Info.plist` | A, B |
| 5 | `lib/core/service_locator.dart` | A, B, C, D, E |
| 6 | `lib/presentation/blocs/tracking/tracking_bloc.dart` | A, D, E |
| 7 | `lib/presentation/blocs/tracking/tracking_state.dart` | A |
| 8 | `lib/presentation/blocs/tracking/tracking_event.dart` | A |
| 9 | `lib/presentation/widgets/tracking_bottom_panel.dart` | A |
| 10 | `lib/presentation/screens/tracking_screen.dart` | A |
| 11 | `lib/presentation/screens/settings_screen.dart` | B, C, E |
| 12 | `lib/domain/usecases/finish_session.dart` | C |
| 13 | `lib/data/models/isar/workout_session_record.dart` | C |
| 14 | `lib/data/models/isar/workout_session_record.g.dart` | C (regenerado) |
| 15 | `lib/domain/entities/coach_settings_entity.dart` | E |
| 16 | `lib/data/repositories_impl/coach_settings_repo.dart` | E |

### Testes NOVOS (7 arquivos)

| # | Path | Bloco |
|---|------|-------|
| 1 | `test/data/datasources/ble_hrm_datasource_test.dart` | A |
| 2 | `test/domain/usecases/heart_rate_zone_test.dart` | A, E |
| 3 | `test/data/datasources/health_platform_service_test.dart` | B |
| 4 | `test/domain/usecases/export_workout_to_health_test.dart` | C |
| 5 | `test/data/datasources/health_steps_source_test.dart` | D |
| 6 | `test/domain/usecases/heart_rate_zone_calculator_test.dart` | E |
| 7 | `test/domain/usecases/hr_zone_voice_trigger_test.dart` | E |

---

## 4. ORDEM DE IMPLEMENTAÇÃO RECOMENDADA

```
Sprint W1: Bloco B (HealthKit/Health Connect) — infraestrutura base
  ↓ health package configurado, permissions, MainActivity
Sprint W2: Bloco A (BLE HR) — sensor em tempo real
  ↓ stream de BPM funcionando
Sprint W3: Bloco E (HR Zones + Voice) — valor ao usuário
  ↓ alertas de voz por zona cardíaca
Sprint W4: Bloco C (Export) — workout para Apple Health / HC
  ↓ corrida aparece no Apple Health / Health Connect
Sprint W5: Bloco D (Steps reais) — anti-cheat com dados reais
  ↓ IntegrityDetectVehicle ativo
```

Justificativa: Bloco B primeiro porque o `health` package é dependência de B, C e D.
Bloco A (BLE) é independente mas precisa de permissões BLE que são configuradas junto.

---

## 5. CONFORMIDADE COM ARCHITECTURE.md

| Regra | Conformidade |
|-------|-------------|
| Clean Architecture layers | ✅ Todos os novos arquivos seguem domain → data → presentation |
| Domain sem dependências externas | ✅ Interfaces e entities são Dart puro |
| Grafo de dependência | ✅ presentation → application → domain ← infrastructure |
| Unidades internas | ✅ HR em BPM (int), steps em COUNT (int), distância em metros |
| service_locator como único DI | ✅ Todos registrados via `sl.register*` |
| Arquivo ≤ 200 linhas (R8) | ✅ Planejado para compliance |

---

*Documento gerado na Sprint W0.1*
