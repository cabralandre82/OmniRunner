# Watch Architecture — Apple Watch & WearOS Standalone Apps

> **Phase:** 12 — Watch Apps  
> **Sprint:** W12.0.1  
> **Status:** Arquitetura definida  
> **Última atualização:** 17 Fev 2026

---

## 1. Contexto e Motivação

### De onde viemos

O Omni Runner atualmente opera no modelo **phone-centric**:

```
[BLE HR Monitor] --BLE--> [Phone (Flutter)] --HealthKit/HC--> [Health Platform]
                           |
                           +-- GPS (phone)
                           +-- Steps (Health platform)
                           +-- TTS (phone speaker / earbuds)
                           +-- UI (phone screen)
```

O relógio (Apple Watch ou WearOS) é apenas uma **fonte passiva de dados** —
o phone lê HR e steps via HealthKit/Health Connect. O corredor precisa
levar o phone para tudo funcionar.

### Para onde vamos

Modelo **watch-standalone**:

```
[Watch App (nativo)]                    [Phone App (Flutter)]
  |                                       |
  +-- GPS (watch)                         +-- Full UI
  +-- HR (watch sensor)                   +-- Histórico
  +-- UI mínima (métricas)                +-- Mapas
  +-- Armazenamento local                 +-- Sync com backend
  +-- Haptic/Audio feedback               +-- Configurações
  |                                       |
  +----------- SYNC (post-run) ----------+
              WatchConnectivity (iOS)
              DataLayer API (Android)
```

**O corredor pode sair SEM o phone.** O watch captura GPS + HR + métricas,
armazena localmente, e sincroniza com o phone quando estiver próximo.

---

## 2. Realidade Técnica Fundamental

### Não existe "Flutter Watch App"

Flutter **não roda** em Apple Watch (watchOS) nem em WearOS (Wear Compose).

| Plataforma | Linguagem | UI Framework | IDE |
|-----------|-----------|-------------|-----|
| Apple Watch | **Swift** | SwiftUI + WatchKit | Xcode |
| WearOS | **Kotlin** | Jetpack Compose for Wear OS | Android Studio |

Isso significa:

- **2 apps nativos separados** — código completamente independente
- **0 código Flutter compartilhado** no watch
- Comunicação com o app Flutter via **bridge nativa** em cada plataforma
- Domínio/lógica de negócios **reimplementado** em Swift e Kotlin
  (ou simplificado para o escopo do watch)

### Consequências Arquiteturais

```
Repositórios de código:

omni_runner/                    # Flutter (phone) — EXISTENTE
  lib/
  android/
  ios/
    Runner/
    WatchApp/                   # ← NOVO: WatchKit Extension target
      WatchApp.swift
      ...

omni_runner_wearos/             # ← NOVO: projeto Android separado
  app/
    src/main/
      kotlin/
        com/omnirunner/watch/
```

**Apple Watch:** Reside DENTRO do projeto Xcode existente como um target
adicional (WatchKit App Extension). Isso é obrigatório pela Apple — o watch
app é distribuído junto com o iPhone app via App Store.

**WearOS:** Projeto Android independente. Pode ser distribuído standalone
via Play Store ou como módulo do mesmo projeto Gradle (multi-module).

---

## 3. Arquitetura de Comunicação

### 3.1. Apple Watch ↔ iPhone (WatchConnectivity)

```
┌─────────────────────┐          ┌─────────────────────────┐
│   Apple Watch App    │          │   iPhone App (Flutter)   │
│   (Swift/SwiftUI)    │          │                          │
│                      │          │   ┌──────────────────┐   │
│  WCSession           │◄────────►│   │ WCSession        │   │
│  .default            │          │   │ (AppDelegate /    │   │
│                      │          │   │  MethodChannel)   │   │
│  ┌────────────────┐  │          │   └────────┬─────────┘   │
│  │ WorkoutManager │  │          │            │              │
│  │ - HKWorkout    │  │          │   ┌────────▼─────────┐   │
│  │ - CLLocation   │  │          │   │ WatchBridge      │   │
│  │ - HeartRate    │  │          │   │ (MethodChannel)  │   │
│  └────────────────┘  │          │   └────────┬─────────┘   │
│                      │          │            │              │
│  ┌────────────────┐  │          │   ┌────────▼─────────┐   │
│  │ LocalStorage   │  │          │   │ Flutter Domain   │   │
│  │ (CoreData /    │  │          │   │ Layer            │   │
│  │  SwiftData)    │  │          │   └──────────────────┘   │
│  └────────────────┘  │          │                          │
└─────────────────────┘          └─────────────────────────┘
```

#### WatchConnectivity — Canais de Comunicação

| Canal | Método | Quando Usar | Latência | Tamanho |
|-------|--------|-------------|----------|---------|
| **Interactive Message** | `sendMessage(_:replyHandler:)` | Apps ambos reachable (foreground) | ~instant | Pequeno (< 65 KB) |
| **User Info Transfer** | `transferUserInfo(_:)` | Sync assíncrono (background OK) | Segundos a minutos | Até ~500 KB |
| **File Transfer** | `transferFile(_:metadata:)` | Enviar GPS route / session data | Background, queued | Até ~50 MB |
| **Application Context** | `updateApplicationContext(_:)` | Estado atual (settings, status) | Sobrescreve anterior | Pequeno |
| **Complication UserInfo** | `transferCurrentComplicationUserInfo(_:)` | Atualizar complication | Budget limitado (50/dia) | Pequeno |

#### Fluxo de Dados — Apple Watch

```
═══════════════════════════════════════════════════════════
  INICIAR WORKOUT (Watch standalone)
═══════════════════════════════════════════════════════════

Watch:
  1. Usuário toca "Start" na UI do watch
  2. WorkoutManager inicia:
     - HKWorkoutSession (required para HR contínuo)
     - HKLiveWorkoutBuilder (acumula métricas)
     - CLLocationManager (GPS do watch)
  3. Dados fluem localmente:
     - HR: HKLiveWorkoutBuilder → delegate callback (~1/s)
     - GPS: CLLocationManager → delegate callback (~1/s)
     - Métricas: distância, pace, calorias calculadas
  4. UI atualiza: SwiftUI view com métricas ao vivo
  5. Haptic feedback: WKInterfaceDevice.play(.start)

═══════════════════════════════════════════════════════════
  DURANTE O WORKOUT
═══════════════════════════════════════════════════════════

Watch (standalone — phone pode estar em casa):
  1. GPS points acumulados em array local
  2. HR samples acumulados
  3. Métricas calculadas localmente (distância via CLLocation)
  4. Tudo persistido em CoreData/SwiftData (crash safety)

Se phone reachable (no bolso):
  5. Interactive message: enviar HR + pace a cada 5s
     → Phone pode mostrar dashboard ampliado
     → OPCIONAL, não obrigatório

═══════════════════════════════════════════════════════════
  FINALIZAR WORKOUT
═══════════════════════════════════════════════════════════

Watch:
  1. HKWorkoutBuilder.endCollection()
  2. HKWorkoutBuilder.finishWorkout() → salva no HealthKit do watch
  3. Serializar sessão completa:
     {
       sessionId: UUID,
       startMs: Int64,
       endMs: Int64,
       totalDistanceM: Double,
       movingMs: Int64,
       gpsPoints: [{lat, lng, alt, ts, accuracy, speed}],
       hrSamples: [{bpm, ts}],
       avgBpm: Int,
       maxBpm: Int,
       isVerified: Bool
     }
  4. Persistir em CoreData (offline-first)

═══════════════════════════════════════════════════════════
  SYNC COM PHONE
═══════════════════════════════════════════════════════════

Watch → Phone:
  1. transferFile() com sessão serializada (JSON ou Protobuf)
     - Funciona mesmo que phone esteja em background
     - Queue FIFO, entrega garantida quando reachable
  2. Phone recebe via WCSessionDelegate.session(_:didReceive:)
  3. Flutter WatchBridge (MethodChannel):
     - Deserializa sessão
     - Cria WorkoutSessionEntity + LocationPointEntity[]
     - Salva no Isar
     - Dispara sync com Supabase (se online)
  4. Confirma recebimento via Application Context:
     updateApplicationContext(["lastSyncedSessionId": uuid])
  5. Watch marca sessão como synced, pode limpar CoreData
```

### 3.2. WearOS ↔ Phone (DataLayer API)

```
┌─────────────────────┐          ┌─────────────────────────┐
│   WearOS App         │          │   Phone App (Flutter)   │
│   (Kotlin/Compose)   │          │                          │
│                      │          │   ┌──────────────────┐   │
│  DataClient          │◄────────►│   │ DataClient       │   │
│  MessageClient       │          │   │ (WearableListener│   │
│  ChannelClient       │          │   │  Service)         │   │
│                      │          │   └────────┬─────────┘   │
│  ┌────────────────┐  │          │            │              │
│  │ ExerciseClient │  │          │   ┌────────▼─────────┐   │
│  │ - GPS          │  │          │   │ WearBridge       │   │
│  │ - HeartRate    │  │          │   │ (MethodChannel)  │   │
│  │ - Steps        │  │          │   └────────┬─────────┘   │
│  └────────────────┘  │          │            │              │
│                      │          │   ┌────────▼─────────┐   │
│  ┌────────────────┐  │          │   │ Flutter Domain   │   │
│  │ Room Database  │  │          │   │ Layer            │   │
│  └────────────────┘  │          │   └──────────────────┘   │
└─────────────────────┘          └─────────────────────────┘
```

#### DataLayer API — Canais de Comunicação

| Canal | Classe | Quando Usar | Características |
|-------|--------|-------------|-----------------|
| **DataItem** | `DataClient` | Sync de dados estruturados (key-value) | Auto-sync, persistente, < 100 KB |
| **Message** | `MessageClient` | Comando imediato (start/stop) | Fire-and-forget, requer reachable |
| **Channel** | `ChannelClient` | Transferência grande (GPS route) | Streaming, até ~500 KB chunks |
| **Asset** | Via DataItem | Binários (session file) | Attached to DataItem, < 256 KB |

#### Fluxo de Dados — WearOS

```
═══════════════════════════════════════════════════════════
  INICIAR WORKOUT (WearOS standalone)
═══════════════════════════════════════════════════════════

Watch:
  1. Usuário toca "Start" no Compose UI
  2. Health Services ExerciseClient inicia:
     - ExerciseClient.startExercise(ExerciseConfig)
     - ExerciseType.RUNNING
     - DataTypes: HEART_RATE_BPM, LOCATION, STEPS_PER_MINUTE
  3. FusedLocationProviderClient (GPS)
  4. Ongoing Activity notification (required)
  5. Foreground Service (keeps app alive)

═══════════════════════════════════════════════════════════
  DURANTE O WORKOUT
═══════════════════════════════════════════════════════════

Watch (standalone):
  1. ExerciseClient.setUpdateCallback → HR, location, steps
  2. Acumular em Room Database (crash safety)
  3. Compose UI atualiza via Flow/StateFlow
  4. Vibration feedback via Vibrator service

Se phone reachable:
  5. MessageClient.sendMessage → HR + pace cada 5s (opcional)

═══════════════════════════════════════════════════════════
  FINALIZAR + SYNC
═══════════════════════════════════════════════════════════

Watch:
  1. ExerciseClient.endExercise()
  2. Serializar sessão (Protobuf ou JSON)
  3. Salvar em Room Database

Watch → Phone:
  4. ChannelClient.openChannel() para sessão grande
     OU DataClient.putDataItem() para sessão pequena
  5. Phone WearableListenerService recebe
  6. Flutter WearBridge (MethodChannel):
     - Deserializa → Isar → Supabase sync
  7. DataClient.putDataItem("sync_ack", sessionId) confirma
  8. Watch limpa Room Database para sessão synced
```

---

## 4. Estratégia Offline-First

### Princípio Central

> O watch NUNCA depende do phone para funcionar durante o workout.
> Sync é eventual, não obrigatória.

### Capacidades Offline

| Capacidade | Apple Watch | WearOS | Requer Phone? |
|-----------|-------------|--------|---------------|
| Iniciar workout | ✅ | ✅ | ❌ |
| GPS tracking | ✅ (GPS integrado) | ✅ (GPS integrado) | ❌ |
| Heart rate | ✅ (sensor óptico) | ✅ (sensor óptico) | ❌ |
| Cálculo de métricas | ✅ (local) | ✅ (local) | ❌ |
| Persistência local | ✅ (CoreData) | ✅ (Room) | ❌ |
| UI ao vivo | ✅ (SwiftUI) | ✅ (Compose) | ❌ |
| Haptic feedback | ✅ | ✅ | ❌ |
| Salvar no HealthKit/HC | ✅ (watch HealthKit) | ✅ (Health Services) | ❌ |
| Sync com phone | ⏳ (quando reachable) | ⏳ (quando reachable) | ⏳ |
| Sync com backend | ❌ (via phone) | ⚠️ (LTE watches) | Geralmente sim |
| Mapas | ❌ (sem tiles no watch) | ❌ (sem tiles) | Via phone post-run |
| Ghost runner | ❌ (dados no phone) | ❌ (dados no phone) | Futuro: pre-load |
| Audio coaching (TTS) | ⚠️ (haptic only) | ⚠️ (speaker limitado) | ❌ |

### Ciclo de Vida de uma Sessão

```
               WATCH                                PHONE
               =====                                =====

  [1] START    ┌─────────────────┐
               │ Workout ativo   │
               │ GPS + HR + calc │
               │ Save to local   │
               └────────┬────────┘
                        │
  [2] END      ┌────────▼────────┐
               │ Workout salvo   │
               │ em CoreData/Room│
               │ + HealthKit/HC  │
               │ syncStatus=     │
               │   PENDING       │
               └────────┬────────┘
                        │
  [3] SYNC     ┌────────▼────────┐     ┌─────────────────┐
  (eventual)   │ Transfer file   │────►│ Recebe sessão   │
               │ via WC/DataLayer│     │ Salva no Isar   │
               └────────┬────────┘     │ syncStatus=     │
                        │              │   SYNCED_LOCAL  │
  [4] ACK      ┌────────▼────────┐     └────────┬────────┘
               │ syncStatus=     │              │
               │   SYNCED        │     ┌────────▼────────┐
               │ Pode limpar     │     │ Upload Supabase │
               │ dados locais    │     │ syncStatus=     │
               └─────────────────┘     │   SYNCED_CLOUD  │
                                       └─────────────────┘
```

### Estados de Sync

```dart
enum WatchSessionSyncStatus {
  /// Workout finalizado, aguardando sync com phone.
  pending,

  /// Transferido para o phone, aguardando ACK.
  transferring,

  /// Phone confirmou recebimento.
  synced,

  /// Erro na transferência — retry na próxima oportunidade.
  failed,
}
```

### Gestão de Storage no Watch

| Plataforma | Storage disponível | Política |
|-----------|-------------------|----------|
| Apple Watch | ~1-4 GB (série dependente) | Manter últimas 20 sessões não-synced |
| WearOS | ~2-8 GB | Manter últimas 20 sessões não-synced |

Política de eviction:
1. Sessões `synced` → deletar após 7 dias
2. Sessões `pending` → manter indefinidamente (até sync)
3. Se storage > 80% → alertar usuário para sync
4. NUNCA deletar sessão `pending` automaticamente

---

## 5. Formato de Dados Compartilhado

### Sessão de Workout (Wire Format)

Para interoperabilidade entre Watch → Phone, definir um formato compartilhado.
JSON para simplicidade no MVP; Protobuf como otimização futura.

```json
{
  "version": 1,
  "source": "apple_watch" | "wearos",
  "sessionId": "uuid-v4",
  "startMs": 1708185600000,
  "endMs": 1708189200000,
  "totalDistanceM": 5230.5,
  "movingMs": 3240000,
  "avgBpm": 152,
  "maxBpm": 178,
  "isVerified": true,
  "integrityFlags": [],
  "points": [
    {
      "lat": -23.550520,
      "lng": -46.633308,
      "alt": 760.0,
      "accuracy": 8.0,
      "speed": 3.1,
      "timestampMs": 1708185601000
    }
  ],
  "hrSamples": [
    { "bpm": 142, "timestampMs": 1708185601000 },
    { "bpm": 145, "timestampMs": 1708185602000 }
  ]
}
```

### Tamanho Estimado

| Duração | GPS points (~1/s) | HR samples (~1/s) | JSON size | Gzip |
|---------|-------------------|-------------------|-----------|------|
| 30 min | ~1.800 | ~1.800 | ~400 KB | ~80 KB |
| 60 min | ~3.600 | ~3.600 | ~800 KB | ~160 KB |
| 120 min | ~7.200 | ~7.200 | ~1.6 MB | ~320 KB |

Todos dentro dos limites de `transferFile` (WatchConnectivity) e
`ChannelClient` (DataLayer API).

---

## 6. Flutter Bridge (Phone Side)

### Arquitetura do Bridge

Cada plataforma terá um MethodChannel dedicado no lado phone para receber
dados do watch e encaminhar ao domain layer Flutter.

```
┌─────────────────────────────────────────────┐
│                 Flutter (Dart)               │
│                                              │
│  ┌──────────────────────────────────────┐    │
│  │  IWatchBridge (domain interface)     │    │
│  │    onSessionReceived(WatchSession)   │    │
│  │    sendSettingsToWatch(Settings)     │    │
│  │    getWatchStatus() → WatchStatus    │    │
│  └──────────────┬───────────────────────┘    │
│                 │                             │
│  ┌──────────────▼───────────────────────┐    │
│  │  WatchBridgeService (data layer)     │    │
│  │    MethodChannel('omnirunner/watch') │    │
│  │    - handleSessionFromWatch()        │    │
│  │    - deserialize JSON → entities     │    │
│  │    - save to Isar                    │    │
│  │    - trigger Supabase sync           │    │
│  └──────────────────────────────────────┘    │
│                                              │
├──────────────────┬───────────────────────────┤
│    iOS Native    │    Android Native          │
│  (AppDelegate)   │  (WearableListenerService) │
│                  │                            │
│  WCSession       │  DataClient                │
│  delegate →      │  onDataChanged →           │
│  MethodChannel   │  MethodChannel             │
└──────────────────┴───────────────────────────┘
```

### Domain Interface

```dart
/// Contract for watch ↔ phone communication.
abstract interface class IWatchBridge {
  /// Stream of sessions received from the watch.
  Stream<WatchSessionData> get onSessionReceived;

  /// Send coach settings to the watch.
  Future<void> sendSettings(CoachSettingsEntity settings);

  /// Get current watch connectivity status.
  Future<WatchConnectionStatus> getStatus();

  /// Acknowledge session receipt to the watch.
  Future<void> acknowledgeSession(String sessionId);
}
```

---

## 7. Funcionalidades por Plataforma

### Apple Watch — Componentes Necessários

| Componente | Framework | Prioridade |
|-----------|-----------|-----------|
| `WorkoutManager` | HealthKit (`HKWorkoutSession` + `HKLiveWorkoutBuilder`) | P0 |
| `LocationManager` | CoreLocation (`CLLocationManager`) | P0 |
| `WatchConnectivityManager` | WatchConnectivity (`WCSession`) | P0 |
| `MetricsCalculator` | Swift puro (distância, pace) | P0 |
| `SessionStorage` | SwiftData ou CoreData | P0 |
| `WorkoutView` | SwiftUI (métricas ao vivo) | P0 |
| `SummaryView` | SwiftUI (pós-corrida) | P1 |
| `SettingsView` | SwiftUI (HR max, alertas) | P1 |
| `HapticManager` | WatchKit (`WKInterfaceDevice`) | P1 |
| `HrZoneCalculator` | Swift puro (reuso da lógica Dart) | P1 |
| `ComplicationProvider` | ClockKit / WidgetKit | P2 |
| `IntegrityChecker` | Swift puro (speed/teleport básico) | P2 |

### WearOS — Componentes Necessários

| Componente | Framework | Prioridade |
|-----------|-----------|-----------|
| `ExerciseManager` | Health Services (`ExerciseClient`) | P0 |
| `LocationManager` | FusedLocationProvider | P0 |
| `DataLayerManager` | Wearable DataLayer API | P0 |
| `MetricsCalculator` | Kotlin puro | P0 |
| `SessionStorage` | Room Database | P0 |
| `WorkoutScreen` | Compose for Wear OS | P0 |
| `OngoingNotification` | Ongoing Activity API | P0 |
| `SummaryScreen` | Compose for Wear OS | P1 |
| `SettingsScreen` | Compose for Wear OS | P1 |
| `VibrationManager` | Vibrator service | P1 |
| `HrZoneCalculator` | Kotlin puro | P1 |
| `TileProvider` | Tiles API | P2 |

---

## 8. Limitações e Riscos

### Apple Watch

| Limitação | Impacto | Mitigação |
|----------|---------|-----------|
| GPS do watch consome muita bateria (~5h max) | Corridas > 4h podem ficar sem GPS | Alert ao usuário; reduzir frequência GPS (1/3s) |
| Tela always-on drena bateria | Bateria pode acabar em 3-4h | Always-on mostra métricas simplificadas |
| WatchConnectivity requer iPhone pareado | Sync impossível sem iPhone | Sync adiada; dados seguros no watch |
| Sem speaker no watch antigo (< Series 3) | TTS indisponível | Haptic feedback como alternativa |
| 1 GB RAM (Series 3-5) | App pode ser terminado por memória | Persistência incremental, eviction agressiva |
| Extended Runtime Session max 1h (workout excepted) | N/A para workout (HKWorkoutSession não tem limite) | Usar HKWorkoutSession, não ExtendedRuntimeSession |

### WearOS

| Limitação | Impacto | Mitigação |
|----------|---------|-----------|
| GPS consome ~6-8h de bateria (depende do watch) | Corridas longas limitadas | Reduzir frequência GPS; alert de bateria |
| Health Services ExerciseClient — apenas 1 exercício ativo | Não pode ter 2 workouts simultâneos | OK, caso de uso esperado |
| DataLayer API requer phone com Play Services | Sync impossível sem phone com Google apps | Sync adiada; dados seguros no watch |
| Fragmentação de hardware WearOS | Comportamento varia entre watches | Testar em 2-3 dispositivos referência |
| Ambient mode pode pausar updates | UI pode não atualizar em ambient | Usar AlwaysOnDisplay callbacks |
| Battery Saver pode matar foreground service | Workout pode parar | OngoingActivity + Foreground Service Type |

### Riscos Compartilhados

| Risco | Probabilidade | Impacto | Mitigação |
|-------|--------------|---------|-----------|
| GPS do watch menos preciso que phone | Alta | Métricas de distância/pace menos confiáveis | Filtros agressivos (mesmos do phone: accuracy, speed, drift) |
| HR óptico menos preciso que cinta peitoral | Média | Zonas cardíacas podem oscilar | Hysteresis (já implementado no `HrZoneVoiceTrigger`) |
| Sync falha repetidamente | Baixa | Dados ficam presos no watch | Retry exponencial; alert visual no watch |
| Dados corrompidos durante transfer | Muito baixa | Sessão perdida | Checksum no payload; watch mantém até ACK |
| Conflito: mesmo workout no watch e phone | Média | Duplicata no Isar | Dedup por sessionId (UUID gerado no watch) |

---

## 9. Plano de Sprints — Phase 12

| Sprint | Descrição | Plataforma | Esforço |
|--------|-----------|-----------|---------|
| W12.0.1 | Definir arquitetura (este documento) | Docs | 4h |
| W12.0.2 | Definir wire format + IWatchBridge interface | Flutter domain | 4h |
| W12.1.1 | Criar WatchKit target no Xcode | Apple Watch | 4h |
| W12.1.2 | WorkoutManager (HKWorkoutSession + GPS) | Apple Watch | 16h |
| W12.1.3 | UI SwiftUI — workout view + summary | Apple Watch | 12h |
| W12.1.4 | WatchConnectivity — sync sessão → phone | Apple Watch | 8h |
| W12.1.5 | Flutter bridge iOS (MethodChannel + Isar) | Flutter + iOS | 8h |
| W12.1.6 | Testes E2E Apple Watch → Phone → Isar | Integração | 8h |
| W12.2.1 | Criar projeto WearOS + ExerciseClient | WearOS | 8h |
| W12.2.2 | WorkoutManager (Exercise + GPS) | WearOS | 16h |
| W12.2.3 | UI Compose — workout screen + summary | WearOS | 12h |
| W12.2.4 | DataLayer API — sync sessão → phone | WearOS | 8h |
| W12.2.5 | Flutter bridge Android (MethodChannel + Isar) | Flutter + Android | 8h |
| W12.2.6 | Testes E2E WearOS → Phone → Isar | Integração | 8h |
| W12.3.1 | HR zones + haptic alerts (ambas plataformas) | Watch nativo | 8h |
| W12.3.2 | Settings sync (maxHr, alerts) phone → watch | Ambos | 4h |
| W12.3.3 | Complication (Apple) + Tile (WearOS) | Watch nativo | 8h |
| **Total** | | | **~144h** |

---

## 10. Decisões Arquiteturais

| # | Decisão | Justificativa |
|---|---------|---------------|
| 1 | Apps nativos (Swift + Kotlin), não Flutter | Flutter não suporta watchOS/WearOS |
| 2 | JSON como wire format (MVP) | Simplicidade; Protobuf como otimização futura |
| 3 | Offline-first no watch | Corredor pode sair sem phone |
| 4 | Sync via file transfer (não real-time) | Confiabilidade > latência para dados de sessão |
| 5 | UUID gerado no watch | Evita conflito/duplicata; watch é source of truth |
| 6 | CoreData (Apple) / Room (WearOS) para persistência | Padrão nativo de cada plataforma |
| 7 | MethodChannel para bridge | Mais simples que plugin; bidirecional |
| 8 | HKWorkoutSession obrigatório (Apple) | Única forma de ter HR contínuo no Apple Watch |
| 9 | ExerciseClient obrigatório (WearOS) | API oficial para workouts no Wear OS |
| 10 | Anti-cheat simplificado no watch | Processar integridade completa no phone pós-sync |
| 11 | Apple Watch target DENTRO do projeto Xcode existente | Requisito Apple: watch app é distribuído com o iPhone app |
| 12 | WearOS como projeto separado | Flexibilidade de build e release independente |
