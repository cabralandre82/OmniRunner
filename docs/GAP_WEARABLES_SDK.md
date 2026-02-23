# Omni Runner — Gap Analysis: Estado Atual vs SDKs Oficiais Garmin / Apple Watch

**Data:** 17/02/2026
**Baseado em:** Connect IQ SDK 8.4.1 | Apple HealthKit (iOS 17+) | Health Connect (Android 14+) | `health` pub 13.3.1 | `flutter_blue_plus` pub 2.1.1

---

## 1. VISAO GERAL: O QUE EXISTE HOJE NO CÓDIGO

### Camadas relacionadas a sensores/wearables

| Componente | Existe? | Detalhe |
|------------|---------|---------|
| GPS (Geolocator) | ✅ Completo | `geolocator` ^11.0.0 — stream de Position funcional |
| Foreground Service (Android) | ✅ Completo | `flutter_foreground_task` ^8.0.0 com `foregroundServiceType="location"` |
| Background Location (iOS) | ✅ Configurado | `UIBackgroundModes: location` no Info.plist |
| Heart Rate via BLE | ❌ Zero | Nenhum código BLE |
| Heart Rate via HealthKit/Health Connect | ❌ Zero | Nenhuma dependência de saúde |
| Step Counter / Pedômetro | ⚠️ Interface apenas | `IStepsSource` + `StepSample` definidos em `integrity_detect_vehicle.dart`, sem implementação |
| Garmin Connect IQ | ❌ Zero | Nenhum código |
| Apple Watch (WatchKit/WatchConnectivity) | ❌ Zero | Nenhum código nativo iOS |
| ANT+ | ❌ Zero | Nenhuma dependência |
| Workout export (HealthKit/Health Connect) | ❌ Zero | Não exporta workouts para as plataformas de saúde |

### O único "gancho" que existe

```1:28:omni_runner/lib/domain/usecases/integrity_detect_vehicle.dart
// Step cadence data source (placeholder interface)

/// A single step-cadence sample.
final class StepSample {
  final int timestampMs;
  final double spm;
  const StepSample({required this.timestampMs, required this.spm});
}

/// Abstract source of step-cadence data.
abstract interface class IStepsSource {
  Future<List<StepSample>> samplesForSession(String sessionId);
}
```

Esta interface é o único ponto de extensão para sensores externos, mas **nunca é registrada no service locator, nunca é chamada pelo TrackingBloc, e não tem implementação concreta**.

---

## 2. O QUE CADA SDK OFICIAL EXIGE HOJE

### 2.1 Apple Watch / HealthKit (iOS)

#### Arquitetura de integração

Apple oferece **duas** formas de integrar:

**Caminho A: HealthKit (leitura/escrita de dados de saúde)**
- O app iPhone lê/escreve dados no HealthKit Store
- Dados de Apple Watch fluem automaticamente para o iPhone via HealthKit
- Não requer app nativo no Watch

**Caminho B: WatchOS App (app companion no relógio)**
- App nativo no Apple Watch em Swift/SwiftUI
- Comunica com o app Flutter via WatchConnectivity framework
- Acesso direto aos sensores do Watch (HR, acelerômetro, giroscópio)
- Requer projeto Xcode separado com WatchKit target

#### Requisitos de configuração — HealthKit

| Requisito | Estado Atual | O que Falta |
|-----------|-------------|-------------|
| `NSHealthShareUsageDescription` no Info.plist | ❌ Ausente | Adicionar string explicativa |
| `NSHealthUpdateUsageDescription` no Info.plist | ❌ Ausente | Adicionar string explicativa |
| HealthKit Capability no Xcode | ❌ Não ativado | Ativar em Signing & Capabilities |
| HealthKit Entitlement | ❌ Ausente | Gerado automaticamente ao ativar capability |
| Dependência `health` no pubspec | ❌ Ausente | `health: ^13.3.1` |
| Fluxo de autorização de tipos | ❌ Ausente | Solicitar permissão para HEART_RATE, STEPS, WORKOUT, WORKOUT_ROUTE |

#### Tipos de dados relevantes para Omni Runner

| Tipo HealthKit | Uso no Omni Runner | Prioridade |
|----------------|-------------------|------------|
| `HEART_RATE` (BPM) | HR em tempo real, zonas cardíacas, alertas de HR | P1 |
| `STEPS` (COUNT) | Anti-cheat (vehicle detection), cadência | P1 |
| `WORKOUT` (RUNNING) | Exportar sessão completa para Apple Health | P2 |
| `WORKOUT_ROUTE` | Exportar rota GPS para Apple Health | P2 |
| `ACTIVE_ENERGY_BURNED` (CALORIES) | Calorias queimadas na corrida | P3 |
| `DISTANCE_WALKING_RUNNING` (METERS) | Cross-reference com distância calculada | P3 |
| `RESTING_HEART_RATE` | Baseline para zonas cardíacas | P3 |
| `HEART_RATE_VARIABILITY_SDNN` | Indicador de recuperação pós-treino | P4 |
| `VO2_MAX` | Fitness score ao longo do tempo | P4 |

#### Código necessário para integração básica (HealthKit)

```dart
// O que precisa existir — exemplo mínimo com o package `health`
import 'package:health/health.dart';

class HealthKitService {
  final _health = Health();
  bool _configured = false;

  Future<void> configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  Future<bool> requestAuthorization() async {
    final types = [
      HealthDataType.HEART_RATE,
      HealthDataType.STEPS,
      HealthDataType.WORKOUT,
      HealthDataType.WORKOUT_ROUTE,
      HealthDataType.ACTIVE_ENERGY_BURNED,
      HealthDataType.DISTANCE_WALKING_RUNNING,
    ];
    final permissions = types.map((_) => HealthDataAccess.READ_WRITE).toList();
    return _health.requestAuthorization(types, permissions: permissions);
  }

  /// Read heart rate samples during a time window
  Future<List<HealthDataPoint>> getHeartRate(DateTime from, DateTime to) async {
    return _health.getHealthDataFromTypes(
      types: [HealthDataType.HEART_RATE],
      startTime: from,
      endTime: to,
    );
  }

  /// Read step count for interval
  Future<int?> getSteps(DateTime from, DateTime to) async {
    return _health.getTotalStepsInInterval(from, to);
  }

  /// Write a completed workout to HealthKit
  Future<bool> writeWorkout({
    required DateTime start,
    required DateTime end,
    required double totalDistanceM,
    required double totalCalories,
  }) async {
    return _health.writeWorkoutData(
      activityType: HealthWorkoutActivityType.RUNNING,
      start: start,
      end: end,
      totalDistance: totalDistanceM.round(),
      totalDistanceUnit: HealthDataUnit.METER,
      totalEnergyBurned: totalCalories.round(),
      totalEnergyBurnedUnit: HealthDataUnit.KILOCALORIE,
    );
  }

  /// Write workout route (GPS points) to HealthKit
  Future<void> writeWorkoutRoute({
    required List<WorkoutRouteLocation> locations,
    required String workoutUuid,
  }) async {
    final builderId = await _health.startWorkoutRoute();
    await _health.insertWorkoutRouteData(
      builderId: builderId,
      locations: locations,
    );
    await _health.finishWorkoutRoute(
      builderId: builderId,
      workoutUuid: workoutUuid,
    );
  }
}
```

**Delta com código atual: 100% ausente. Nenhuma linha existe.**

---

### 2.2 Google Health Connect (Android)

#### Requisitos de configuração

| Requisito | Estado Atual | O que Falta |
|-----------|-------------|-------------|
| Health Connect app instalada no device | N/A (runtime) | Detectar e orientar o usuário |
| `<queries>` para Health Connect no Manifest | ❌ Ausente | Adicionar query para `com.google.android.apps.healthdata` |
| Permission declarations no Manifest | ❌ Ausente | `READ_HEART_RATE`, `WRITE_HEART_RATE`, `READ_STEPS`, `WRITE_STEPS`, `READ_EXERCISE`, `WRITE_EXERCISE`, `READ_EXERCISE_ROUTE`, `WRITE_EXERCISE_ROUTE` |
| `ACTIVITY_RECOGNITION` permission | ❌ Ausente | Necessário para step data |
| Privacy Policy activity-alias | ❌ Ausente | Obrigatório para app review |
| `MainActivity` extends `FlutterFragmentActivity` | ❌ Usa `FlutterActivity` | Necessário para `registerForActivityResult` no Android 14 |
| `READ_HEALTH_DATA_IN_BACKGROUND` | ❌ Ausente | Para sync em background |
| `intent-filter` ACTION_SHOW_PERMISSIONS_RATIONALE | ❌ Ausente | Obrigatório |
| Dependência `health` no pubspec | ❌ Ausente | `health: ^13.3.1` |

#### AndroidManifest.xml — o que precisa ser adicionado

```xml
<!-- Health Connect queries -->
<queries>
  <package android:name="com.google.android.apps.healthdata" />
  <intent>
    <action android:name="androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE" />
  </intent>
</queries>

<!-- Health Connect permissions -->
<uses-permission android:name="android.permission.health.READ_HEART_RATE"/>
<uses-permission android:name="android.permission.health.WRITE_HEART_RATE"/>
<uses-permission android:name="android.permission.health.READ_STEPS"/>
<uses-permission android:name="android.permission.health.WRITE_STEPS"/>
<uses-permission android:name="android.permission.health.READ_EXERCISE"/>
<uses-permission android:name="android.permission.health.WRITE_EXERCISE"/>
<uses-permission android:name="android.permission.health.READ_EXERCISE_ROUTE"/>
<uses-permission android:name="android.permission.health.WRITE_EXERCISE_ROUTE"/>
<uses-permission android:name="android.permission.health.READ_DISTANCE"/>
<uses-permission android:name="android.permission.health.WRITE_DISTANCE"/>
<uses-permission android:name="android.permission.health.READ_ACTIVE_CALORIES_BURNED"/>
<uses-permission android:name="android.permission.health.WRITE_ACTIVE_CALORIES_BURNED"/>
<uses-permission android:name="android.permission.health.READ_HEALTH_DATA_IN_BACKGROUND"/>
<uses-permission android:name="android.permission.ACTIVITY_RECOGNITION"/>

<!-- Privacy policy redirect (obrigatório para Google review) -->
<activity-alias
    android:name="ViewPermissionUsageActivity"
    android:exported="true"
    android:targetActivity=".MainActivity"
    android:permission="android.permission.START_VIEW_PERMISSION_USAGE">
    <intent-filter>
        <action android:name="android.intent.action.VIEW_PERMISSION_USAGE" />
        <category android:name="android.intent.category.HEALTH_PERMISSIONS" />
    </intent-filter>
</activity-alias>
```

#### MainActivity.kt — mudança necessária

```kotlin
// ATUAL:
import io.flutter.embedding.android.FlutterActivity
class MainActivity: FlutterActivity()

// NECESSÁRIO:
import io.flutter.embedding.android.FlutterFragmentActivity
class MainActivity: FlutterFragmentActivity()
```

**Delta com código atual: 100% ausente.**

---

### 2.3 Garmin Connect IQ

Garmin funciona de forma fundamentalmente diferente. Existem **3 caminhos** de integração:

#### Caminho A: Connect IQ Data Field (app no relógio Garmin)

| Aspecto | Detalhe |
|---------|---------|
| Linguagem | Monkey C (linguagem proprietária Garmin) |
| SDK | Connect IQ SDK 8.4.1 |
| Funcionalidade | Cria um "Data Field" que aparece nas atividades do Garmin |
| Sensores disponíveis | HR, GPS, acelerômetro, barômetro, temperatura, SpO2, Body Battery, stress |
| Comunicação com phone | Via BLE usando Garmin Mobile SDK |
| Limitação | O Data Field roda DENTRO do app Garmin, não dentro do Omni Runner |

**Isso exige um projeto separado em Monkey C, não é possível fazer em Flutter.**

#### Caminho B: Garmin Health API (dados na nuvem)

| Aspecto | Detalhe |
|---------|---------|
| Tipo | REST API server-to-server |
| Dados | Atividades, dailies, sleep, stress, Body Battery, HR |
| Autenticação | OAuth 1.0a |
| Requisito | Conta de desenvolvedor Garmin + aprovação do programa |
| Latência | Dados disponíveis após sync do relógio → Garmin Connect → webhook |
| Limitação | Não é real-time. Dados chegam minutos/horas depois |

**Não serve para HR em tempo real durante corrida, mas serve para importar histórico de treinos do Garmin.**

#### Caminho C: BLE Heart Rate Profile direto

| Aspecto | Detalhe |
|---------|---------|
| Protocolo | Bluetooth Low Energy — Heart Rate Service (UUID 0x180D) |
| Compatibilidade | Garmin Forerunner/Fenix/Venu (quando configurado para broadcast HR) |
| Package Flutter | `flutter_blue_plus: ^2.1.1` |
| Funcionalidade | Leitura de BPM em tempo real via BLE |
| Vantagem | Funciona com QUALQUER HRM BLE (Garmin, Polar, Wahoo, Coros) |
| Limitação | Só heart rate. Não lê GPS, cadência, ou outros dados do Garmin |

**Este é o caminho mais prático para MVP — e é 100% ausente no código.**

#### Requisitos para BLE Heart Rate Monitor

| Requisito | Android | iOS | Estado Atual |
|-----------|---------|-----|-------------|
| `BLUETOOTH_SCAN` permission | ✅ Necessário | N/A | ❌ Ausente |
| `BLUETOOTH_CONNECT` permission | ✅ Necessário | N/A | ❌ Ausente |
| `NSBluetoothAlwaysUsageDescription` | N/A | ✅ Necessário | ❌ Ausente |
| `UIBackgroundModes: bluetooth-central` | N/A | ✅ Necessário (BLE em background) | ❌ Ausente |
| `uses-feature bluetooth_le` | ✅ Recomendado | N/A | ❌ Ausente |
| `flutter_blue_plus` dependency | ✅ | ✅ | ❌ Ausente |

#### Código necessário para BLE HR Monitor

```dart
// O que precisa existir — integração BLE HR
import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// BLE Heart Rate Monitor service UUIDs (Bluetooth SIG standard)
class BleHrmConstants {
  static final heartRateServiceUuid = Guid("180D");
  static final heartRateMeasurementUuid = Guid("2A37");
  static final bodySensorLocationUuid = Guid("2A38");
}

/// Datasource that streams heart rate from any BLE HRM device.
/// Works with: Garmin HRM-Pro/Dual, Polar H10/OH1, Wahoo TICKR, etc.
class BleHrmDatasource {
  BluetoothDevice? _device;
  StreamSubscription? _hrSub;
  final _controller = StreamController<int>.broadcast();

  Stream<int> get heartRateStream => _controller.stream;
  bool get isConnected => _device?.isConnected ?? false;

  /// Scan for BLE devices advertising Heart Rate Service
  Future<List<BluetoothDevice>> scan({Duration timeout = const Duration(seconds: 10)}) async {
    final devices = <BluetoothDevice>[];
    final sub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        if (r.advertisementData.serviceUuids.contains(BleHrmConstants.heartRateServiceUuid)) {
          if (!devices.contains(r.device)) devices.add(r.device);
        }
      }
    });
    await FlutterBluePlus.startScan(
      withServices: [BleHrmConstants.heartRateServiceUuid],
      timeout: timeout,
    );
    await FlutterBluePlus.isScanning.where((v) => !v).first;
    sub.cancel();
    return devices;
  }

  /// Connect to a specific HRM device and start streaming
  Future<void> connect(BluetoothDevice device) async {
    await device.connect(autoConnect: true);
    _device = device;
    final services = await device.discoverServices();
    final hrService = services.firstWhere(
      (s) => s.serviceUuid == BleHrmConstants.heartRateServiceUuid,
    );
    final hrChar = hrService.characteristics.firstWhere(
      (c) => c.characteristicUuid == BleHrmConstants.heartRateMeasurementUuid,
    );
    await hrChar.setNotifyValue(true);
    _hrSub = hrChar.onValueReceived.listen((value) {
      if (value.isNotEmpty) {
        // BLE HR Measurement format: bit 0 of flags byte
        // 0 = HR is uint8 in byte[1], 1 = HR is uint16 in byte[1..2]
        final flags = value[0];
        final int bpm;
        if (flags & 0x01 == 0) {
          bpm = value[1]; // uint8
        } else {
          bpm = value[1] | (value[2] << 8); // uint16 LE
        }
        _controller.add(bpm);
      }
    });
  }

  /// Disconnect and clean up
  Future<void> disconnect() async {
    await _hrSub?.cancel();
    _hrSub = null;
    await _device?.disconnect();
    _device = null;
  }

  void dispose() {
    disconnect();
    _controller.close();
  }
}
```

**Delta com código atual: 100% ausente.**

---

### 2.4 Apple Watch App Nativa (WatchOS)

| Aspecto | Detalhe |
|---------|---------|
| Requisito | Projeto Xcode com WatchKit target em Swift |
| Comunicação | `WatchConnectivity` framework (mensagens entre Watch ↔ iPhone) |
| Sensores | `HKWorkoutSession` + `HKLiveWorkoutBuilder` para HR, calorias, distância em tempo real |
| Background | Watch app roda independente com extended runtime session |
| Complexidade | Alta — requer desenvolvimento nativo Swift/SwiftUI separado |
| Flutter bridge | Via method channel ou plugin customizado |

**Veredicto: Não é viável para MVP. Caminho recomendado é HealthKit (Caminho A) + BLE HR (Caminho C).**

---

## 3. TABELA COMPARATIVA COMPLETA

```
┌─────────────────────────────────┬────────────┬─────────────────────────────────┐
│           CAPACIDADE            │ OMNI RUNNER│   O QUE OS SDKs OFERECEM       │
│                                 │   HOJE     │                                 │
├─────────────────────────────────┼────────────┼─────────────────────────────────┤
│ GPS tracking em tempo real      │ ✅ COMPLETO │ Geolocator stream funcional    │
│ GPS em background (Android)     │ ✅ COMPLETO │ ForegroundService + location   │
│ GPS em background (iOS)         │ ✅ COMPLETO │ UIBackgroundModes: location    │
├─────────────────────────────────┼────────────┼─────────────────────────────────┤
│ Heart Rate — BLE HRM genérico   │ ❌ ZERO     │ flutter_blue_plus + UUID 180D  │
│ Heart Rate — Apple Watch        │ ❌ ZERO     │ HealthKit HEART_RATE read      │
│ Heart Rate — Garmin via CIQ     │ ❌ ZERO     │ Connect IQ Data Field (MonkeyC)│
│ Heart Rate — Garmin via BLE     │ ❌ ZERO     │ Garmin HRM broadcast mode      │
│ Zonas cardíacas                 │ ❌ ZERO     │ Cálculo baseado em HR max/rest │
│ HR alerts (AudioEventType)      │ ⚠️ ENUM ONLY│ heartRateAlert definido, nunca │
│                                 │            │ emitido                         │
├─────────────────────────────────┼────────────┼─────────────────────────────────┤
│ Step counter — via pedômetro    │ ⚠️ INTERFACE│ IStepsSource sem implementação │
│ Step counter — HealthKit        │ ❌ ZERO     │ health package STEPS type      │
│ Step counter — Health Connect   │ ❌ ZERO     │ READ_STEPS permission          │
│ Cadência (steps/min)            │ ⚠️ STRUCT   │ StepSample.spm definido        │
├─────────────────────────────────┼────────────┼─────────────────────────────────┤
│ Export workout → Apple Health   │ ❌ ZERO     │ writeWorkoutData() + route     │
│ Export workout → Health Connect │ ❌ ZERO     │ WRITE_EXERCISE + route         │
│ Export workout → Garmin Connect │ ❌ ZERO     │ Garmin Health API (REST)       │
│ Import workout ← Health apps   │ ❌ ZERO     │ READ_EXERCISE                  │
├─────────────────────────────────┼────────────┼─────────────────────────────────┤
│ Garmin Device App (Connect IQ)  │ ❌ ZERO     │ MonkeyC SDK 8.4.1 separado    │
│ Garmin Data Field               │ ❌ ZERO     │ FIT recording + custom fields  │
│ Garmin Health API (cloud sync)  │ ❌ ZERO     │ OAuth 1.0a REST API            │
│ Garmin sensor history           │ ❌ ZERO     │ SensorHistory API (HR, stress, │
│                                 │            │ elevation, SpO2, temp, battery)│
├─────────────────────────────────┼────────────┼─────────────────────────────────┤
│ Apple Watch native app          │ ❌ ZERO     │ WatchKit + WatchConnectivity   │
│ Apple Watch workout session     │ ❌ ZERO     │ HKWorkoutSession live builder  │
│ Apple Watch HR broadcast        │ ❌ ZERO     │ Via HealthKit ou BLE           │
├─────────────────────────────────┼────────────┼─────────────────────────────────┤
│ ANT+ sensors                    │ ❌ ZERO     │ Requer plugin nativo (raro     │
│                                 │            │ em Flutter, mais comum iOS)    │
├─────────────────────────────────┼────────────┼─────────────────────────────────┤
│ Bluetooth scan/connect          │ ❌ ZERO     │ flutter_blue_plus full BLE     │
│ BLUETOOTH_SCAN permission       │ ❌ AUSENTE  │ Required Android 12+           │
│ BLUETOOTH_CONNECT permission    │ ❌ AUSENTE  │ Required Android 12+           │
│ NSBluetoothAlwaysUsageDescription│ ❌ AUSENTE │ Required iOS                   │
│ UIBackgroundModes: bluetooth    │ ❌ AUSENTE  │ Required iOS BLE background    │
├─────────────────────────────────┼────────────┼─────────────────────────────────┤
│ NSHealthShareUsageDescription   │ ❌ AUSENTE  │ Required iOS HealthKit         │
│ NSHealthUpdateUsageDescription  │ ❌ AUSENTE  │ Required iOS HealthKit         │
│ HealthKit Capability (Xcode)    │ ❌ AUSENTE  │ Required iOS HealthKit         │
│ Health Connect queries (Android)│ ❌ AUSENTE  │ Required Android Health Connect│
│ Health permissions (Android)    │ ❌ AUSENTE  │ READ/WRITE per data type       │
│ ACTIVITY_RECOGNITION            │ ❌ AUSENTE  │ Required for steps on Android  │
│ FlutterFragmentActivity         │ ❌ AUSENTE  │ Required Android 14+ Health    │
│ Privacy policy activity-alias   │ ❌ AUSENTE  │ Required Google Play review    │
└─────────────────────────────────┴────────────┴─────────────────────────────────┘
```

---

## 4. PLANO DE IMPLEMENTAÇÃO RECOMENDADO

### Fase 1 — MVP Wearable (2-3 semanas)

**Objetivo: HR em tempo real de qualquer cinta BLE + export para Apple Health / Health Connect**

| # | Task | Esforço | Dependências |
|---|------|---------|-------------|
| 1 | Adicionar `health: ^13.3.1` ao pubspec | 10 min | — |
| 2 | Adicionar `flutter_blue_plus: ^2.1.1` ao pubspec | 10 min | — |
| 3 | Atualizar `AndroidManifest.xml` com permissões BLE + Health Connect | 1h | — |
| 4 | Atualizar `Info.plist` com HealthKit + Bluetooth descriptions | 30 min | — |
| 5 | Mudar `MainActivity` para `FlutterFragmentActivity` | 15 min | — |
| 6 | Criar `BleHrmDatasource` (scan, connect, stream HR via UUID 180D) | 4h | #2, #3, #4 |
| 7 | Criar `IHeartRateStream` interface no domain | 1h | — |
| 8 | Criar `HeartRateStreamRepo` implementando interface | 2h | #6, #7 |
| 9 | Criar `HealthPlatformService` datasource (wrapper do `health` package) | 4h | #1, #3, #4 |
| 10 | Criar `IHealthPlatformRepo` interface + implementação | 2h | #9 |
| 11 | Adicionar HR ao `LocationPointEntity` ou criar `HeartRateSample` entity | 1h | #7 |
| 12 | Integrar HR stream no `TrackingBloc` (novo campo `currentHR`) | 3h | #8, #11 |
| 13 | Criar `HeartRateZoneCalculator` use case | 2h | #11 |
| 14 | Implementar `heartRateAlert` no sistema de voice triggers | 2h | #13 |
| 15 | Criar `ExportWorkoutToHealth` use case | 3h | #10 |
| 16 | Chamar export no `FinishSession` | 1h | #15 |
| 17 | Implementar `IStepsSource` usando `health` package (step data) | 2h | #10 |
| 18 | Registrar `IntegrityDetectVehicle` no service locator | 30 min | #17 |
| 19 | UI: mostrar HR na `TrackingBottomPanel` e `RunSummaryScreen` | 3h | #12 |
| 20 | UI: tela de scan/seleção de dispositivo BLE HR | 4h | #6 |
| **Total** | | **~36h** | |

### Fase 2 — Garmin Cloud Integration (1-2 semanas)

| # | Task | Esforço |
|---|------|---------|
| 21 | Registrar app no Garmin Developer Portal | 2h |
| 22 | Implementar OAuth 1.0a para Garmin Health API | 8h |
| 23 | Criar webhook endpoint no Supabase Edge Functions | 4h |
| 24 | Importar atividades do Garmin Connect para o app | 4h |
| 25 | Cross-reference: comparar rota Garmin vs rota Omni Runner | 4h |

### Fase 3 — Apple Watch App (3-4 semanas)

| # | Task | Esforço |
|---|------|---------|
| 26 | Criar WatchKit target no Xcode | 4h |
| 27 | Implementar HKWorkoutSession com live HR | 16h |
| 28 | Bridge WatchConnectivity ↔ Flutter via method channel | 8h |
| 29 | UI SwiftUI para watch face com métricas | 12h |
| 30 | Sync bidirecional de sessões Watch ↔ Phone | 8h |

---

## 5. RESUMO

| Integração | Gap (%) | Caminho mais curto | Esforço estimado |
|------------|---------|-------------------|-----------------|
| BLE Heart Rate (qualquer cinta) | 100% | `flutter_blue_plus` + UUID 180D | 8h |
| Apple HealthKit (read/write) | 100% | `health` package + Info.plist | 12h |
| Google Health Connect | 100% | `health` package + Manifest | 12h |
| Garmin BLE HR broadcast | 100% | Mesmo que "BLE Heart Rate" acima | 0h (incluso) |
| Garmin Connect IQ (app no watch) | 100% | Monkey C SDK separado | 40h+ |
| Garmin Health API (cloud) | 100% | OAuth + REST + webhooks | 20h |
| Apple Watch native app | 100% | Swift/WatchKit + MethodChannel | 50h+ |
| ANT+ sensors | 100% | Plugin nativo customizado | 30h+ |
| Step counter (pedômetro) | 90% | `health` package → IStepsSource | 4h |
| Workout export | 100% | `health` package writeWorkout | 4h |

**Conclusão:** O app está a **~36 horas de desenvolvimento** de ter integração funcional com qualquer cinta de HR via BLE + exportação de workouts para Apple Health e Health Connect. A integração com Garmin como Data Field ou Apple Watch como companion app são projetos significativamente maiores que requerem desenvolvimento nativo fora do ecossistema Flutter.
