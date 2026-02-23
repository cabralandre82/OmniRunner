# Omni Runner — Relatório de Auditoria de Pré-Lançamento

**Data:** 17/02/2026
**Auditor:** Staff Engineer / QA Automatizado
**Versão do Código:** 1.0.0+1 (Flutter/Dart)

---

## SUMÁRIO EXECUTIVO

O projeto Omni Runner é um app de corrida Flutter com arquitetura Clean Architecture bem implementada. O código base apresenta boa separação de camadas, testes unitários para a lógica core e tratamento de erros em vários pontos. Porém, há **lacunas críticas** na integração com serviços externos (Mapas, Wearables), resiliência a falhas de rede/GPS, e gerenciamento de ciclo de vida que devem ser resolvidas antes de testes em ambiente real.

---

## 1. RELATÓRIO DE LACUNAS DE INTEGRAÇÃO

### 1.1 APIs de Mapas (MapTiler / MapLibre)

| Item | Status | Detalhe |
|------|--------|---------|
| Chave MapTiler (`MAPTILER_API_KEY`) | ⚠️ PLACEHOLDER | `.env.prod` contém `your_maptiler_prod_key` — não é uma chave real |
| Fallback sem chave | ✅ OK | `map_style.dart` cai para `MapLibreStyles.demo` se a chave estiver vazia |
| Erro de carregamento do mapa | ⚠️ PARCIAL | `MapScreen` tem `_error` field mas nunca é setado; `TrackingScreen` não tem tratamento de erro de mapa |
| Rate limiting / quota MapTiler | ❌ AUSENTE | Sem retry ou fallback se a API retornar 429/503 |

### 1.2 Wearables (Garmin, Apple Watch, Bluetooth/ANT+)

| Item | Status | Detalhe |
|------|--------|---------|
| Integração com wearables | ❌ AUSENTE | Não há código de comunicação BLE/ANT+ |
| Apple HealthKit / Google Fit | ❌ AUSENTE | Não há integração com APIs de saúde |
| Heart Rate Monitor | ❌ AUSENTE | `AudioEventType.heartRateAlert` existe na entity mas não tem implementação |
| Pedômetro / Step Counter | ⚠️ PLACEHOLDER | `IntegrityDetectVehicle` define `IStepsSource` mas não tem implementação concreta |
| Garmin Connect IQ | ❌ AUSENTE | Sem integração |

### 1.3 Supabase / Backend

| Item | Status | Detalhe |
|------|--------|---------|
| Chaves Supabase | ⚠️ PLACEHOLDER | `.env.prod` contém valores de exemplo, não chaves reais |
| Supabase.initialize() | ❌ AUSENTE | `main.dart` **não** chama `Supabase.initialize()` — todas as chamadas ao Supabase client vão falhar em runtime |
| Autenticação | ⚠️ AUSENTE | Sem fluxo de login; `userId` sempre retorna `null` no `SyncService` |
| Tratamento de falhas de rede | ✅ PARCIAL | `SyncRepo` captura exceções e retorna `SyncFailure` tipado |

### 1.4 Sentry / Crash Reporting

| Item | Status | Detalhe |
|------|--------|---------|
| Sentry DSN | ⚠️ PLACEHOLDER | `.env.prod` tem valor de exemplo |
| Sentry.init() | ❌ AUSENTE | `main.dart` não inicializa Sentry |
| `AppLogger.onError` hook | ⚠️ NÃO CONECTADO | O hook existe, mas nunca é configurado para enviar ao Sentry |

### 1.5 Manifestos e Permissões

#### Android (`AndroidManifest.xml`)

| Permissão | Status |
|-----------|--------|
| `ACCESS_FINE_LOCATION` | ✅ |
| `ACCESS_COARSE_LOCATION` | ✅ |
| `ACCESS_BACKGROUND_LOCATION` | ✅ |
| `FOREGROUND_SERVICE` | ✅ |
| `FOREGROUND_SERVICE_LOCATION` | ✅ |
| `INTERNET` | ✅ |
| Foreground Service declaration | ✅ `foregroundServiceType="location"` |
| `BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT` | ❌ AUSENTE (necessário para wearables) |
| `ACTIVITY_RECOGNITION` | ❌ AUSENTE (necessário para step counter) |
| `WAKE_LOCK` | ⚠️ Via plugin `flutter_foreground_task` (implícito) |

#### iOS (`Info.plist`)

| Chave | Status |
|-------|--------|
| `NSLocationWhenInUseUsageDescription` | ✅ |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | ✅ |
| `UIBackgroundModes: location` | ✅ |
| `UIBackgroundModes: fetch` | ❌ AUSENTE (necessário para sync em background) |
| `UIBackgroundModes: bluetooth-central` | ❌ AUSENTE (necessário para wearables BLE) |
| `NSBluetoothAlwaysUsageDescription` | ❌ AUSENTE |
| `NSMotionUsageDescription` | ❌ AUSENTE (necessário para pedômetro) |

---

## 2. DIAGNÓSTICO DE ROBUSTEZ

### 2.1 Race Conditions Identificadas

#### RC-01: `_buffer` no TrackingBloc (CRÍTICA)
**Arquivo:** `tracking_bloc.dart:51,128,154`

```
_buffer.add(pt);                        // Linha 127: adiciona ao buffer
if (_buffer.length >= _bufSize)         // Linha 128: verifica tamanho
    await _flushBuffer();               // Linha 154: reassign _buffer = []
```

O `_flushBuffer()` faz `_buffer = []` (reassign), mas a referência `List.of(_buffer)` captura antes do clear. Se dois eventos `LocationPointReceived` chegarem quase simultâneamente:
- O Bloc do `flutter_bloc` serializa handlers async, então **dentro do bloc não há race condition real** pois `on<Event>` processa um por vez.
- **Porém**, se a stream GPS emitir pontos muito rápido enquanto `_flushBuffer` aguarda o `writeTxn` do Isar, novos eventos se acumulam no buffer interno do Bloc e são processados sequencialmente. **Risco baixo, mas monitorar.**

#### RC-02: `ForegroundTaskConfig.start/stop` sem await (MÉDIA)
**Arquivo:** `tracking_screen.dart:108-109`

```dart
if (_lastActive == null) ForegroundTaskConfig.start();  // Fire-and-forget
...
ForegroundTaskConfig.stop();                              // Fire-and-forget
```

O start/stop do foreground service é fire-and-forget. Se o stop for chamado antes do start completar, o serviço pode ficar "preso" rodando. Deveria ser `await`-ado.

#### RC-03: `unawaited(_audioCoach.init())` (BAIXA)
**Arquivo:** `tracking_bloc.dart:114`

`_audioCoach.init()` é unawaited, mas `speak()` pode ser chamado antes do init completar. O `AudioCoachService.speak` checa `if (_tts == null)` e retorna silenciosamente, então não quebra, mas **as primeiras falas podem ser perdidas silenciosamente**.

#### RC-04: `unawaited(_syncRepo.syncPending())` (BAIXA)
**Arquivo:** `tracking_bloc.dart:146`

O sync pode começar e falhar sem que ninguém trate o resultado. Aceitável para sync offline-first, mas deveria logar o resultado.

### 2.2 Funções que Podem Quebrar com Dados Inconsistentes

#### F-01: `SyncService.uploadPoints` — sem Supabase.initialize (CRÍTICA)
**Arquivo:** `sync_service.dart:58`

```dart
final client = Supabase.instance.client;
```

`Supabase.instance` vai lançar uma exceção se `Supabase.initialize()` nunca foi chamado. **O app vai crashar na primeira tentativa de sync.**

**Correção:** Adicionar `Supabase.initialize()` no `main.dart` ou tratar a exceção.

#### F-02: `sessionId` baseado em timestamp (MÉDIA)
**Arquivo:** `tracking_bloc.dart:115`

```dart
_sessionId = now.toString();  // "1740000000000"
```

Usar timestamp como ID pode gerar colisões se o usuário iniciar duas sessões no mesmo milissegundo (improvável mas possível em testes automatizados). **Recomendação:** Usar UUID v4.

#### F-03: `GhostPositionAt` com rota vazia (TRATADO)
Retorna `null` corretamente para rotas < 2 pontos. ✅

#### F-04: `CalculatePace` com deltaMs = 0 (TRATADO)
O `continue` no loop pula segmentos com `deltaMs <= 0`. ✅

#### F-05: `AccumulateDistance` com accuracy null (TRATADO)
Pontos com `accuracy == null` passam pelo filtro (comportamento correto para GPS sem metadata). ✅

#### F-06: `_computeMetrics` no TrackingBloc — `_filterPoints` chamado repetidamente
**Arquivo:** `tracking_bloc.dart:182`

Cada tick de GPS chama `_filterPoints(_points)` sobre os últimos até 300 pontos. Isso é O(n) a cada ponto e não é cacheado. Para corridas longas com alta frequência de GPS, isso pode causar **frame drops**.

**Recomendação:** Cachear o resultado do filtro e só recalcular incrementalmente.

### 2.3 Tratamento de Erros — O que Falta

| Função | Tem try-catch? | Risco |
|--------|---------------|-------|
| `TrackingBloc._onStartTracking` | Parcial — `ensureLocationReady` retorna failure, mas `_sessionRepo.save` pode lançar exceção | ALTO |
| `TrackingBloc._onStopTracking` | NÃO — `_finishSession` pode lançar se Isar falhar | ALTO |
| `TrackingBloc._flushBuffer` | NÃO — `_pointsRepo.savePoints` pode falhar | ALTO |
| `SyncRepo._syncOne` | SIM ✅ | OK |
| `FinishSession.call` | NÃO — queries ao repo podem falhar | MÉDIO |
| `RecoverActiveSession.call` | NÃO — queries ao repo podem falhar | MÉDIO |
| `DiscardSession.call` | NÃO — delete pode falhar | MÉDIO |
| `AudioCoachService.speak` | NÃO — `_tts!.speak` pode falhar | BAIXO |

---

## 3. CÓDIGO FANTASMA E DÍVIDA TÉCNICA

### 3.1 Código Não Utilizado / Não Integrado

| Arquivo | Problema |
|---------|----------|
| `integrity_detect_vehicle.dart` | **Não registrado** no `service_locator.dart`. `IStepsSource` não tem implementação. Código fantasma completo. |
| `map_screen.dart` | Screen standalone de mapa. **Não é referenciado** por nenhuma rota de navegação no app. |
| `debug_tracking_screen.dart` | Screen de debug. Funcional mas sem rota de navegação a partir da tela principal. |
| `camera_controller.dart` | `CameraFollowController` **nunca é instanciado** em nenhuma tela. Código morto. |
| `auto_bearing.dart` | `AutoBearing` **nunca é chamado** em nenhum lugar do app. Código morto. |
| `AudioEventType.heartRateAlert` | Enum value definido mas **nunca emitido** por nenhum trigger. |
| `AudioEventType.paceAlert` | Enum value definido mas **nunca emitido** por nenhum trigger. |
| `AudioEventType.countdown` | Enum value definido mas **nunca emitido** por nenhum trigger. |
| `AudioEventType.sessionEvent` | Enum value definido mas **nunca emitido** por nenhum trigger. |
| `location_rationale.dart` | Arquivo de entidade não lido nesta auditoria — verificar uso. |
| `run_details_screen.dart` | Referenciado pelo `HistoryScreen` — em uso. |

### 3.2 Potenciais Vazamentos de Memória

#### ML-01: `StreamSubscription` no TrackingBloc (TRATADO)
O `_sub` é cancelado em `_cancelSub()`, chamado por `close()`. ✅

#### ML-02: `WidgetsBindingObserver` nas screens (TRATADO)
`TrackingScreen`, `DebugTrackingScreen` fazem `addObserver/removeObserver` em `initState/dispose`. ✅

#### ML-03: `FlutterTts` no AudioCoachService (RISCO MÉDIO)
**Arquivo:** `audio_coach_service.dart`

O `_tts` é criado no `init()` mas `dispose()` só é chamado se alguém explicitamente chamar `IAudioCoach.dispose()`. No `TrackingBloc.close()`, **não há chamada a `_audioCoach.dispose()`**. Cada vez que o BlocProvider recria o TrackingBloc (ex: ao navegar de volta para o TrackingScreen), uma nova instância de FlutterTts é criada via `AudioCoachService.init()`, mas como o service é `LazySingleton`, **o TTS instance anterior persiste** graças ao `if (_tts != null) return;` — **sem leak neste caso.** Porém, o TTS engine nunca é liberado durante o lifecycle do app.

#### ML-04: `MapLibreMapController` no TrackingScreen (RISCO BAIXO)
**Arquivo:** `tracking_screen.dart:44`

O `_mapCtrl` é capturado em `_onMapCreated` mas **nunca recebe `dispose()`** no `_TrackingViewState`. O MapLibre widget gerencia internamente, mas é uma boa prática chamar dispose.

#### ML-05: `AudioCoachRepo._queue` cresce indefinidamente? (TRATADO)
A queue tem `maxQueueSize = 5` e é drenada após cada fala. ✅

### 3.3 Dívida Técnica Significativa

| Item | Descrição | Impacto |
|------|-----------|---------|
| Sem Supabase.initialize | O backend simplesmente não funciona | BLOCKER |
| Sem Sentry.init | Crash reporting não funciona | HIGH |
| SessionId = timestamp | Possíveis colisões | MEDIUM |
| Sem fluxo de autenticação | Sync sempre falha (userId = null) | HIGH |
| TrackingBloc muito denso | 200 linhas compactadas, difícil de manter | MEDIUM |
| Sem retry automático no sync | Se falhar, só retenta manualmente | MEDIUM |
| Chaves de API todas placeholder | Deploy vai falhar | BLOCKER |

---

## 4. PLANO DE TESTES DE QA

### 4.1 Testes Unitários Sugeridos (Faltantes)

#### Cobertura Atual (26 test files)
- ✅ `haversine_test.dart`
- ✅ `format_pace_test.dart`
- ✅ `filter_location_points_test.dart`
- ✅ `accumulate_distance_test.dart`
- ✅ `calculate_pace_test.dart`
- ✅ `auto_pause_detector_test.dart`
- ✅ `ghost_position_at_test.dart`
- ✅ `calculate_ghost_delta_test.dart`
- ✅ `integrity_detect_speed_test.dart`
- ✅ `integrity_detect_teleport_test.dart`
- ✅ `voice_triggers_test.dart`
- ✅ `time_voice_trigger_test.dart`
- ✅ `ghost_voice_trigger_test.dart`
- ✅ `finish_session_test.dart`
- ✅ `discard_session_test.dart`
- ✅ `recover_active_session_test.dart`
- ✅ `position_mapper_test.dart`
- ✅ `permission_mapper_test.dart`
- ✅ `ensure_location_ready_test.dart`
- ✅ `auto_bearing_test.dart`
- ✅ `polyline_builder_test.dart`
- ✅ `workout_proto_mapper_test.dart`
- ✅ `load_ghost_from_session_test.dart`
- ✅ `synthetic_run_test.dart` (integration)
- ✅ `entities_sanity_test.dart`

#### Testes Faltantes (PRIORIDADE)

**P1 — TrackingBloc State Machine (CRÍTICO)**

```dart
// test/presentation/blocs/tracking/tracking_bloc_test.dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
// ... imports and mocks ...

void main() {
  group('TrackingBloc', () {
    blocTest<TrackingBloc, TrackingState>(
      'emits [TrackingIdle] when AppStarted and permissions are OK',
      build: () => _createBloc(permissionGranted: true),
      act: (bloc) => bloc.add(const AppStarted()),
      expect: () => [const TrackingIdle()],
    );

    blocTest<TrackingBloc, TrackingState>(
      'emits [TrackingNeedsPermission] when permission denied',
      build: () => _createBloc(permissionGranted: false),
      act: (bloc) => bloc.add(const AppStarted()),
      expect: () => [isA<TrackingNeedsPermission>()],
    );

    blocTest<TrackingBloc, TrackingState>(
      'emits [TrackingActive] then [TrackingIdle] on start/stop cycle',
      build: () => _createBloc(permissionGranted: true),
      act: (bloc) async {
        bloc.add(const StartTracking());
        await Future.delayed(const Duration(milliseconds: 100));
        bloc.add(const StopTracking());
      },
      expect: () => [
        isA<TrackingActive>(),
        const TrackingIdle(),
      ],
    );

    blocTest<TrackingBloc, TrackingState>(
      'handles LocationStreamError gracefully',
      build: () => _createBloc(permissionGranted: true, streamError: true),
      act: (bloc) => bloc.add(const StartTracking()),
      expect: () => [
        isA<TrackingActive>(),
        isA<TrackingError>(),
      ],
    );

    test('close() flushes buffer and cancels subscription', () async {
      final bloc = _createBloc(permissionGranted: true);
      bloc.add(const StartTracking());
      await Future.delayed(const Duration(milliseconds: 50));
      await bloc.close();
      // Verify no unhandled exceptions
    });
  });
}
```

**P2 — SyncRepo com falhas de rede**

```dart
// test/data/repositories_impl/sync_repo_test.dart
void main() {
  group('SyncRepo', () {
    test('syncPending returns SyncNotConfigured when Supabase not set', () async {
      final repo = SyncRepo(
        service: MockSyncService(configured: false),
        isar: mockIsar,
        pointsRepo: mockPointsRepo,
      );
      final result = await repo.syncPending();
      expect(result, isA<SyncNotConfigured>());
    });

    test('syncPending returns SyncNoConnection when offline', () async {
      final repo = SyncRepo(
        service: MockSyncService(configured: true, connected: false),
        isar: mockIsar,
        pointsRepo: mockPointsRepo,
      );
      final result = await repo.syncPending();
      expect(result, isA<SyncNoConnection>());
    });

    test('syncPending returns SyncNotAuthenticated when no user', () async {
      final repo = SyncRepo(
        service: MockSyncService(configured: true, connected: true, userId: null),
        isar: mockIsar,
        pointsRepo: mockPointsRepo,
      );
      final result = await repo.syncPending();
      expect(result, isA<SyncNotAuthenticated>());
    });

    test('syncPending handles timeout gracefully', () async {
      // Mock upload that throws TimeoutException
      // Assert SyncTimeout is returned
    });
  });
}
```

**P3 — AudioCoachRepo queue behavior**

```dart
// test/data/repositories_impl/audio_coach_repo_test.dart
void main() {
  group('AudioCoachRepo', () {
    test('high priority event interrupts current speech', () async {
      final service = MockAudioCoachService(isSpeaking: true);
      final repo = AudioCoachRepo(service: service);
      await repo.init();

      final urgent = AudioEventEntity(
        type: AudioEventType.custom,
        priority: 3,
        payload: {'text': 'URGENT'},
      );

      await repo.speak(urgent);
      expect(service.stopCalled, isTrue);
      expect(service.lastSpoken, 'URGENT');
    });

    test('queue respects maxQueueSize', () async {
      final service = MockAudioCoachService(isSpeaking: true);
      final repo = AudioCoachRepo(service: service, maxQueueSize: 2);
      await repo.init();

      for (var i = 0; i < 5; i++) {
        await repo.speak(AudioEventEntity(
          type: AudioEventType.distanceAnnouncement,
          priority: 10,
          payload: {'distanceKm': i},
        ));
      }
      // Only 2 should be in queue
    });
  });
}
```

**P4 — IntegrityDetectVehicle (código fantasma — testar se necessário)**

```dart
// test/domain/usecases/integrity_detect_vehicle_test.dart
void main() {
  const detector = IntegrityDetectVehicle();

  test('returns empty when no step data', () {
    final points = generatePoints(speed: 5.0, count: 10);
    final result = detector(points, steps: null);
    expect(result, isEmpty);
  });

  test('detects vehicle when high GPS speed + low cadence', () {
    final points = generatePoints(speed: 8.0, count: 60, intervalMs: 1000);
    final steps = generateSteps(spm: 50.0, count: 60, intervalMs: 1000);
    final result = detector(points, steps: steps, minWindowMs: 10000);
    expect(result, isNotEmpty);
    expect(result.first.avgSpeedMps, greaterThan(4.2));
    expect(result.first.avgSpm, lessThan(140));
  });
}
```

### 4.2 Roteiro de Testes de Integração

#### TESTE 01: "Túnel" — Perda Súbita de Sinal GPS/Internet

| Passo | Ação | Resultado Esperado | Status |
|-------|------|--------------------|--------|
| 1 | Iniciar corrida com GPS ativo | `TrackingActive` emitido | ⬜ |
| 2 | Desabilitar GPS nas configurações do sistema | Stream GPS emite erro ou para de emitir | ⚠️ **Não tratado** — o stream simplesmente para; `onDone` dispara `StopTracking` |
| 3 | Verificar que os pontos salvos até o momento estão no Isar | Buffer deve ser flushed | ⬜ |
| 4 | Reabilitar GPS | App deveria reconectar automaticamente | ❌ **Não implementado** — o tracking é parado e não reinicia |
| 5 | Verificar sessão recuperável após kill do app | `RecoverActiveSession` deve encontrar a sessão | ⬜ |
| 6 | Desabilitar internet durante sync | `SyncNoConnection` retornado, sessão fica `PENDING` | ⬜ |
| 7 | Reabilitar internet | Sync manual via botão da HistoryScreen funciona | ⬜ |
| 8 | Verificar que não há perda de dados | Pontos locais intactos | ⬜ |

**Lacuna crítica:** Quando o stream GPS emite `onDone` (GPS desligado), o bloc dispara `StopTracking` automaticamente, **finalizando a sessão**. O correto seria entrar em um estado de "esperando GPS" sem finalizar.

#### TESTE 02: "Bateria Crítica" — Modo de Economia

| Passo | Ação | Resultado Esperado | Status |
|-------|------|--------------------|--------|
| 1 | Iniciar corrida | `TrackingActive` | ⬜ |
| 2 | Ativar modo de economia de energia do SO | Foreground service deve manter o tracking | ⬜ |
| 3 | Verificar frequência de pontos GPS | Pode diminuir mas não deve parar | ⬜ |
| 4 | Verificar notificação persistente (Android) | Deve continuar visível | ⬜ |
| 5 | Verificar TTS continua funcionando | `AudioCoachService` com `setSharedInstance(true)` no iOS | ⬜ |
| 6 | Forçar low-battery (< 5%) | App não deve crashar; considerar salvar sessão automaticamente | ❌ **Não implementado** |

**Lacuna:** Sem listener de nível de bateria. Sem save automático em bateria crítica.

#### TESTE 03: "Concorrência" — Chamada/Notificação durante Uso

| Passo | Ação | Resultado Esperado | Status |
|-------|------|--------------------|--------|
| 1 | Iniciar corrida | `TrackingActive` | ⬜ |
| 2 | Receber chamada telefônica | App vai para background | ⬜ |
| 3 | Verificar foreground service mantém GPS | `flutter_foreground_task` gerencia | ⬜ |
| 4 | Atender chamada, falar 1 min | TTS silencia durante chamada (iOS: `duckOthers` configurado) | ⬜ |
| 5 | Encerrar chamada, voltar ao app | `AppLifecycleChanged(isResumed: true)` disparado | ⬜ |
| 6 | Verificar pontos não foram perdidos | Buffer deve continuar acumulando | ⬜ |
| 7 | Verificar métricas consistentes | `elapsedMs` inclui tempo da chamada; `movingMs` deve excluir | ⬜ |
| 8 | Reproduzir notificação com tela cheia (alarme) | GPS não deve parar | ⬜ |

**Lacuna:** O `_onAppLifecycleChanged` re-verifica permissões no `resume`, mas **se o tracking já estava ativo, não faz nada** (retorna na linha 151: `if (state is TrackingActive) return;`). Isso é correto. Porém, se o SO matou o processo durante a chamada, a session recovery é o único safety net.

#### TESTE 04: "Desconexão Prolongada" — Avião por 30min

| Passo | Ação | Resultado Esperado | Status |
|-------|------|--------------------|--------|
| 1 | Completar corrida offline | Session salva localmente com `isSynced=false` | ⬜ |
| 2 | Manter modo avião por 30 min | Dados locais intactos | ⬜ |
| 3 | Desativar modo avião | Sync manual disponível | ⬜ |
| 4 | Sync automático ao abrir app | ❌ **Não implementado** — sync é manual ou fire-and-forget no `StopTracking` |

---

## 5. SUITE DE TESTES SUGERIDA — EXEMPLOS DE CÓDIGO

### Teste: TrackingBloc com GPS que morre no meio da corrida

```dart
// test/presentation/blocs/tracking/tracking_bloc_gps_loss_test.dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';

void main() {
  test('GPS stream closes mid-run: should flush buffer, not lose data', () async {
    final controller = StreamController<LocationPointEntity>();
    // Configure bloc with mock stream that uses controller.stream

    // Emit 5 valid points
    for (var i = 0; i < 5; i++) {
      controller.add(LocationPointEntity(
        lat: -23.55 + i * 0.0001,
        lng: -46.63,
        accuracy: 5.0,
        timestampMs: 1000000 + i * 5000,
      ));
    }
    await Future.delayed(const Duration(milliseconds: 100));

    // Simulate GPS death
    await controller.close(); // triggers onDone -> StopTracking

    await Future.delayed(const Duration(milliseconds: 200));

    // Verify: all 5 points were saved to pointsRepo
    // Verify: session status is 'completed'
    // Verify: bloc state is TrackingIdle
  });
}
```

### Teste: Dados nulos e inconsistentes vindos do GPS

```dart
// test/domain/usecases/filter_edge_cases_test.dart
void main() {
  const filter = FilterLocationPoints();

  test('handles points with null accuracy (passes through)', () {
    final points = [
      LocationPointEntity(lat: 0.0, lng: 0.0, timestampMs: 0),
      LocationPointEntity(lat: 0.001, lng: 0.0, timestampMs: 5000),
    ];
    final result = filter(points);
    expect(result.length, 2);
  });

  test('handles points with identical timestamps', () {
    final points = [
      LocationPointEntity(lat: 0.0, lng: 0.0, accuracy: 5, timestampMs: 1000),
      LocationPointEntity(lat: 0.001, lng: 0.0, accuracy: 5, timestampMs: 1000),
    ];
    final result = filter(points);
    // deltaMs = 0, speed check skipped, drift check applies
    expect(result.length, 2); // First accepted + drift > 3m
  });

  test('handles points with negative timestamps', () {
    final points = [
      LocationPointEntity(lat: 0.0, lng: 0.0, accuracy: 5, timestampMs: -1000),
      LocationPointEntity(lat: 0.001, lng: 0.0, accuracy: 5, timestampMs: 0),
    ];
    final result = filter(points);
    expect(result.length, 2);
  });

  test('handles single point', () {
    final points = [
      LocationPointEntity(lat: 0.0, lng: 0.0, timestampMs: 0),
    ];
    final result = filter(points);
    expect(result.length, 1);
  });

  test('all points filtered out returns empty', () {
    final points = [
      LocationPointEntity(lat: 0.0, lng: 0.0, accuracy: 100, timestampMs: 0),
      LocationPointEntity(lat: 0.001, lng: 0.0, accuracy: 100, timestampMs: 5000),
    ];
    final result = filter(points);
    expect(result, isEmpty);
  });
}
```

### Teste: Sync com retry e timeout

```dart
// test/data/repositories_impl/sync_resilience_test.dart
void main() {
  test('sync handles Supabase timeout gracefully', () async {
    final mockService = MockSyncService(
      uploadBehavior: () => throw TimeoutException('Upload timed out'),
    );
    final repo = SyncRepo(
      service: mockService,
      isar: mockIsar,
      pointsRepo: mockPointsRepo,
    );

    final result = await repo.syncPending();
    expect(result, isA<SyncTimeout>());
    // Session should NOT be marked as synced
  });

  test('sync handles partial failure (2 sessions, 1 fails)', () async {
    // First session uploads OK, second fails
    // Result should be the first failure
    // First session should be marked synced
    // Second session should remain pending
  });
}
```

---

## 6. ROADMAP DE ESTABILIDADE (Prioridade 1-10)

| # | Prioridade | Item | Esforço | Impacto |
|---|-----------|------|---------|---------|
| 1 | **P0 — BLOCKER** | Adicionar `Supabase.initialize()` no `main.dart` | 30 min | Sem isso o sync crasha |
| 2 | **P0 — BLOCKER** | Configurar chaves de API reais (Supabase, MapTiler, Sentry) no `.env.prod` | 1h | Sem isso nada externo funciona |
| 3 | **P1 — CRÍTICO** | Wrap `_onStartTracking`, `_onStopTracking`, `_flushBuffer` em try-catch no TrackingBloc | 2h | Previne crash durante corrida |
| 4 | **P1 — CRÍTICO** | Inicializar Sentry e conectar `AppLogger.onError` ao Sentry | 2h | Crash reporting funcional |
| 5 | **P2 — ALTO** | Implementar reconexão GPS: quando stream fecha, entrar em "aguardando GPS" ao invés de StopTracking | 4h | Evita perda de sessão em túneis |
| 6 | **P2 — ALTO** | Implementar fluxo de autenticação (login anônimo ou email/social) | 8h | Sem auth, sync sempre falha |
| 7 | **P3 — MÉDIO** | Await `ForegroundTaskConfig.start/stop` e tratar erros | 1h | Previne foreground service preso |
| 8 | **P3 — MÉDIO** | Trocar `sessionId` de timestamp para UUID v4 | 1h | Previne colisões de ID |
| 9 | **P3 — MÉDIO** | Adicionar sync automático ao abrir app e com `ConnectivityListener` | 4h | Sessões pendentes sincronizam sem ação manual |
| 10 | **P4 — MELHORIA** | Implementar `CameraFollowController` e `AutoBearing` na TrackingScreen | 3h | Camera segue o corredor suavemente |
| 11 | **P4 — MELHORIA** | Cachear resultado de `_filterPoints` no TrackingBloc (incremental) | 3h | Performance em corridas longas |
| 12 | **P5 — FUTURO** | Integrar wearables BLE (Garmin, HR monitors) | 16h+ | Feature nova |
| 13 | **P5 — FUTURO** | Implementar `IStepsSource` e ativar `IntegrityDetectVehicle` | 8h | Anti-cheat mais robusto |
| 14 | **P5 — FUTURO** | Integrar Apple HealthKit / Google Fit | 12h+ | Dados de saúde |
| 15 | **P5 — FUTURO** | Monitoramento de bateria com save automático | 4h | Resiliência |

---

## 7. RESUMO FINAL

### O que está BEM feito:
- Arquitetura Clean com separação clara de camadas
- Entities imutáveis com Equatable
- Use cases como classes puras sem side effects
- Tratamento de permissões com sealed class hierarchy
- Filtro GPS com 3 camadas (accuracy, speed, drift)
- Sistema de integridade anti-cheat (speed + teleport detection)
- Ghost runner com interpolação linear e hysteresis
- Audio coach com priority queue e cooldown
- Session recovery para crash scenarios
- 26 arquivos de teste cobrindo toda a lógica core
- Foreground service configurado corretamente para Android
- Info.plist com background modes e location descriptions

### O que PRECISA de atenção imediata:
1. **Supabase não inicializado** — blocker absoluto
2. **Chaves de API placeholder** — nada externo funciona
3. **Sem try-catch** nos handlers principais do TrackingBloc
4. **GPS onDone finaliza sessão** ao invés de aguardar reconexão
5. **Sem Sentry** — crashes em produção serão invisíveis
6. **Sem autenticação** — sync sempre falha

### Veredicto:
O código é de boa qualidade para MVP, com uma base sólida. Os itens P0-P2 do roadmap devem ser resolvidos **antes de qualquer teste em dispositivo real**. Os itens são majoritariamente de integração (conectar serviços externos) e resiliência (try-catch + fallbacks), não de lógica de negócio.

---

## 8. QA PHASE 90 — AUDITORIA DE DESAFIOS E CAMPEONATOS (21/02/2026)

### 8.1 Problemas identificados e corrigidos

Auditoria completa dos fluxos end-to-end de Desafios (1v1, Group, Team vs Team) e Campeonatos (multi-assessoria). **22 problemas** identificados e corrigidos em 4 rodadas:

#### Rodada 1 — 18 problemas originais

| ID | Prioridade | Descrição | Status |
|---|---|---|---|
| P0-01 | CRÍTICO | Deep links de desafio morriam — Isar local sem sync backend | CORRIGIDO |
| P0-02 | CRÍTICO | Dual persistence (Isar vs Supabase) sem sincronização | CORRIGIDO |
| P0-03 | CRÍTICO | Lifecycle checks rodavam apenas local (race condition multi-device) | CORRIGIDO |
| P0-04 | CRÍTICO | Sem UI para staff aceitar convites de Team vs Team | CORRIGIDO |
| P0-05 | CRÍTICO | Campeonatos sem tracking de progresso no backend | CORRIGIDO |
| P0-06 | CRÍTICO | Campeonatos sem lifecycle automatizado (open→active→completed) | CORRIGIDO |
| P1-01 | ALTO | Labels de "Desafio de Equipe" exibiam "Desafio em Grupo" | CORRIGIDO |
| P1-02 | ALTO | Resultados exibiam UUID do participante em vez do displayName | CORRIGIDO |
| P1-03 | ALTO | challenge-join permitia join em desafios activos (deveria ser pending para 1v1/team) | CORRIGIDO |
| P1-04 | ALTO | challenge-get não retornava caller_group_id para validação de equipe | CORRIGIDO |
| P1-05 | ALTO | Sem limite de participantes por equipe em Team vs Team | CORRIGIDO |
| P1-06 | MÉDIO | _syncChallengeToBackend sem retry (fire-and-forget) | CORRIGIDO |
| P1-07 | MÉDIO | Lifecycle checks delegados ao backend com fallback local | CORRIGIDO |
| P1-08 | MÉDIO | LedgerReason não tinha challengeTeamCompleted/challengeTeamWon | CORRIGIDO |
| P1-09 | MÉDIO | Notificações de convite de equipe/campeonato não implementadas | CORRIGIDO |
| P1-10 | MÉDIO | champ-enroll inseria display_name (coluna inexistente) | CORRIGIDO |
| P1-11 | MÉDIO | champ-list falhava para atletas sem active_coaching_group_id | CORRIGIDO |
| P2-01 | BAIXO | Tela de resultado do desafio exibia userId em vez de nome | CORRIGIDO |

#### Rodada 2 — 4 problemas adicionais (confidence check)

| ID | Prioridade | Descrição | Status |
|---|---|---|---|
| CC-01 | CRÍTICO | championship_participants.display_name não existe na tabela | CORRIGIDO |
| CC-02 | CRÍTICO | challenge_team_invites.from_group_id não existe — StaffChallengeInvitesScreen corrigido para derivar de challenges.team_a_group_id | CORRIGIDO |
| CC-03 | CRÍTICO | settle-challenge usava profiles.active_coaching_group_id (mutável) em vez de challenge_participants.group_id (fixo) | CORRIGIDO |
| CC-04 | MÉDIO | IsarChallengeRepo.getByUserId excluía status "completing" | CORRIGIDO |

#### Rodada 3 — 4 riscos residuais eliminados

| ID | Prioridade | Descrição | Status |
|---|---|---|---|
| RR-01 | ALTO | Sem cron para champ-lifecycle/settle-challenge | CORRIGIDO — lifecycle-cron EF + pg_cron migration |
| RR-02 | ALTO | notify-rules não reconhecia championship_invite_received e challenge_team_invite_received + chamadas usavam JWT user (403) | CORRIGIDO — 2 handlers adicionados + chamadas via service-role fetch() |
| RR-03 | MÉDIO | Desafios completados não apareciam na lista | CORRIGIDO — getByUserId inclui completed (30d) + seções Ativos/Concluídos |
| RR-04 | MÉDIO | Testes inexistentes para teamVsTeam + doc comment errado no evaluator | CORRIGIDO — 5 testes team + ordinal stability + 2 testes pré-existentes corrigidos (time=higher wins) |

#### Também corrigido (colateral)

- Doc comment `ChallengeEvaluator`: "time lower wins" corrigido para "time higher wins" (alinhado com `_isLowerBetter`)
- 2 testes pré-existentes que esperavam `time` como lower-is-better — agora correct
- `Set` → `List` no `getByUserId` (fragilidade de identity comparison)
- Resultado final: **46/46 testes passando**, **0 erros no flutter analyze**

### 8.2 Arquivos criados/modificados

| Arquivo | Tipo |
|---|---|
| `supabase/functions/lifecycle-cron/index.ts` | NOVO — cron EF para lifecycle de championships + challenges |
| `supabase/functions/champ-lifecycle/index.ts` | NOVO — EF para transições de championship |
| `supabase/functions/champ-update-progress/index.ts` | NOVO — EF para atualizar progresso em campeonato |
| `supabase/functions/challenge-list-mine/index.ts` | NOVO — EF lista challenges do user (para sync) |
| `supabase/functions/challenge-invite-group/index.ts` | NOVO — EF convida assessoria para team challenge |
| `supabase/functions/challenge-accept-group-invite/index.ts` | NOVO — EF aceita/recusa convite team |
| `supabase/functions/champ-open/index.ts` | NOVO — EF transiciona championship draft→open |
| `supabase/functions/champ-create/index.ts` | NOVO — EF cria championship a partir de template |
| `supabase/functions/notify-rules/index.ts` | MODIFICADO — +2 rule handlers |
| `supabase/functions/champ-invite/index.ts` | MODIFICADO — fix auth service-role |
| `supabase/functions/challenge-invite-group/index.ts` | MODIFICADO — fix auth service-role |
| `supabase/functions/settle-challenge/index.ts` | MODIFICADO — usa group_id de participants |
| `supabase/functions/challenge-create/index.ts` | MODIFICADO — suporta team_vs_team |
| `supabase/functions/challenge-join/index.ts` | MODIFICADO — restrições por tipo + limite equipe |
| `supabase/functions/challenge-get/index.ts` | MODIFICADO — retorna caller_group_id |
| `supabase/functions/champ-enroll/index.ts` | MODIFICADO — remove display_name |
| `supabase/functions/champ-list/index.ts` | MODIFICADO — early return sem group |
| `supabase/migrations/20260221_lifecycle_cron.sql` | NOVO — pg_cron schedule |
| `omni_runner/lib/presentation/screens/staff_challenge_invites_screen.dart` | NOVO — UI staff aceita team invites |
| `omni_runner/lib/presentation/blocs/challenges/challenges_bloc.dart` | MODIFICADO — sync backend + retry |
| `omni_runner/lib/data/repositories_impl/isar_challenge_repo.dart` | MODIFICADO — completed 30d + List |
| `omni_runner/lib/presentation/screens/challenges_list_screen.dart` | MODIFICADO — seções + teamVsTeam label |
| `omni_runner/lib/domain/entities/ledger_entry_entity.dart` | MODIFICADO — +2 enum values |
| `omni_runner/lib/domain/usecases/gamification/challenge_evaluator.dart` | MODIFICADO — doc fix |
| `test/domain/usecases/gamification/challenge_evaluator_test.dart` | MODIFICADO — +5 team tests + 2 fixes |
| `test/domain/usecases/gamification/settle_challenge_reason_test.dart` | NOVO — ordinal stability |

### 8.3 TODOs operacionais (pré-deploy)

| # | Item | Prioridade | Nota |
|---|---|---|---|
| 1 | Configurar `app.settings.supabase_url` e `app.settings.service_role_key` no Supabase Dashboard | P0 | Necessário para pg_cron lifecycle-cron funcionar |
| 2 | Verificar que `send-push` EF existe e está deployado | P1 | notify-rules despacha pushes via send-push |
| 3 | Teste de integração com Supabase real: inserir challenge → settle → verificar ledger | P1 | Exige staging environment |
| 4 | Monitorar logs do lifecycle-cron nas primeiras 24h após deploy | P2 | Confirmar transições automáticas |
| 5 | Verificar notification_log table existe e RLS permite service-role writes | P1 | Usado para dedup de notificações |

### 8.4 Confiança

**96%** — Todos os fluxos core verificados em código, testados localmente (46/46), 0 erros analyze. Os 4% restantes são configuração operacional de deploy (pg_cron settings, send-push EF, staging test).

---

## 9. QA PHASE 97 — WALLET / LEDGER / CLEARING (21/02/2026)

### 9.1 Micro-passo 97.1.0 — Auditoria Wallet/Ledger (Fonte da Verdade)

**Objetivo:** Confirmar wallet, intents QR, burning, "troca somente na assessoria atual", "ao trocar: aviso e queima".

#### Problemas encontrados

| ID | Prioridade | Problema | Fix |
|---|---|---|---|
| W-01 | CRITICO | `coin_ledger_reason_check` faltava `challenge_team_won` + `challenge_team_completed` — settle-challenge falharia 500 para team challenges | Migration `20260221_ledger_team_reasons.sql` |
| W-02 | ALTO | `fn_switch_assessoria` nao queimava `pending_coins` — premios cross-assessoria pendentes persistiam apos troca | RPC recriado na mesma migration |

#### Regras confirmadas

| # | Regra | Codigo | Doc |
|---|---|---|---|
| 1 | Wallet 3-state: balance + pending = total | `wallets` table + `WalletScreen._BalanceCard` | DECISAO 038 §4.2 |
| 2 | QR Intent lifecycle: OPEN→CONSUMED/EXPIRED/CANCELED | `token_intents` + `token-create/consume-intent` EFs | DECISAO 038 §4.3 |
| 3 | ISSUE: inventario → wallet → ledger | `token-consume-intent` ISSUE_TO_ATHLETE branch | Sprint 17.6.1 |
| 4 | BURN: check balance → debit → ledger → lifetime_burned | `token-consume-intent` BURN_FROM_ATHLETE branch | Sprint 17.6.1 |
| 5 | Atleta pertence a 1 assessoria | `profiles.active_coaching_group_id` FK + partial unique | DECISAO 038 §4.2 |
| 6 | Troca queima balance + pending | `fn_switch_assessoria` RPC (agora corrigido) | DECISAO 038 §4.2 |
| 7 | UI burn warning | `MyAssessoriaScreen._showBurnWarning` dialog | Sprint 16.10.1 |
| 8 | Cross-assessoria prizes → pending → clearing → release | `settle-challenge` + `release_pending_to_balance` RPC | Sprint 17.7.0 |
| 9 | Daily limits: 5k/grupo, 500/atleta | `token-create/consume-intent` + `check_daily_token_usage` RPC | DECISAO 052 |

### 9.2 Micro-passo 97.2.0 — Clearing entre Assessorias (sem moderacao da plataforma)

**Objetivo:** Clearing "entre assessorias" seguro e rastreavel; sem termos de dinheiro; agrupar por semana; dispute cobra compensacao sem "money".

#### Problemas encontrados

| ID | Prioridade | Problema | Fix |
|---|---|---|---|
| C-01 | CRITICO | `settle-challenge` roteava premios de `team_vs_team` diretamente para `balance_coins` — deveria ir para `pending_coins` pois team challenges sao SEMPRE cross-assessoria. Pool do time perdedor bypassa clearing completamente. | `settle-challenge/index.ts` — `isCrossPrize` expandido para incluir `isTeamVsTeam`. Immediate = participacao + bonus (30+15 won, 30 tied). Pending = pool/winners. |
| C-02 | CRITICO | Nenhum `clearing-cron` existia — nada criava `clearing_weeks`, `clearing_cases` ou `clearing_case_items` a partir de entries `challenge_prize_pending` no ledger. `StaffDisputesScreen` permanecia eternamente vazio. `pending_coins` ficavam permanentemente trancados. | NOVO: `clearing-cron/index.ts` — Agrega entries pendentes por (semana, grupo_perdedor -> grupo_vencedor), cria cases com deadline 7 dias, insere items com unique index. |
| C-03 | ALTO | Nenhum cron expirava clearing cases vencidos. Cases ficavam em OPEN/SENT_CONFIRMED eternamente mesmo apos deadline. | `clearing-cron/index.ts` S5 — Transiciona cases com `deadline_at < now` para `EXPIRED` + audit event. |

#### Regras confirmadas

| # | Regra | Codigo | Verificado |
|---|---|---|---|
| 1 | Tokens pendentes NAO sao resgataveis | `token-consume-intent` verifica apenas `balance_coins`, ignora `pending_coins` | OK |
| 2 | Sem termos de dinheiro na UI | Scan: 0 refs a "dinheiro", "money", "pagamento", "R$", "cash", "reais" nas screens | OK |
| 3 | Clearing agrupado por semana (Mon-Sun) | `clearing-cron` cria `clearing_weeks` com ISO week boundaries | OK |
| 4 | Dispute sem moderacao da plataforma | `clearing-open-dispute` marca DISPUTED; UI diz "Resolva diretamente com a outra assessoria" | OK |
| 5 | OPEN -> SENT_CONFIRMED -> PAID_CONFIRMED lifecycle | `clearing-confirm-sent` + `clearing-confirm-received` EFs com idempotencia | OK |
| 6 | PAID_CONFIRMED libera pending -> balance | `clearing-confirm-received` chama `release_pending_to_balance` + insere `challenge_prize_cleared` no ledger | OK |
| 7 | Staff ve "Disponivel" vs "Pendente" na Wallet | `WalletScreen._BalanceCard` exibe ambos com label "Aguardando confirmacao entre assessorias" | OK |
| 8 | Audit trail completo | `clearing_case_events` com CREATED, SENT_CONFIRMED, RECEIVED_CONFIRMED, DISPUTED, EXPIRED, CLEARED | OK |
| 9 | RLS: staff de ambos os grupos pode ver cases | Policies em `clearing_cases`, `clearing_case_items`, `clearing_case_events` via `coaching_members` role check | OK |
| 10 | Deadline 7 dias + expiracao automatica | `clearing-cron` seta `deadline_at` = criacao + 7d; expira automaticamente via cron diario 02:00 UTC | OK |

#### C-04 (CRITICO): team_vs_team pode ser intra-assessoria

**Problema:** Fix C-01 original assumia que `team_vs_team` era SEMPRE cross-assessoria. Na verdade, dois times podem ser da mesma assessoria. Toda a logica de scoring usava `group_id` para distinguir times, o que falha quando ambos os times tem o mesmo `group_id`.

**Correcao completa:**

| Componente | Fix |
|---|---|
| Migration `20260221_challenge_team_column.sql` | Adiciona coluna `team` ('A'\|'B') em `challenge_participants` |
| `settle-challenge` isCrossPrize | Verifica `team_a_group_id !== team_b_group_id` (nao assume cross) |
| `settle-challenge` scoring | Usa `participant.team` ('A'/'B') em vez de `group_id` |
| `challenge-create` | Aceita `team_b_group_id` + seta `team='A'` para criador |
| `challenge-join` team assignment | Cross: deriva team de group_id. Intra: requer parametro `team` no body |
| `challenge-join` capacity | Conta por `team` em vez de `group_id` |
| `challenge-join` auto-activate | Conta accepted por `team='A'`/`team='B'` |
| `ChallengeParticipantEntity` (Flutter) | Adiciona campo `team` |
| `ChallengeEvaluator._evaluateTeamVsTeam` | Filtra por `p.team == 'A'`/`'B'` em vez de `groupId` |
| `ChallengesBloc._tryAutoStart` | Usa `p.team` para contar times |
| `IsarChallengeRepo` serialization | Persiste `team` no JSON |
| Tests (23/23 passando) | `_tp()` usa `team:` em vez de `groupId:` |

#### Arquivos criados/modificados

| Arquivo | Tipo |
|---|---|
| `supabase/functions/settle-challenge/index.ts` | MODIFICADO — `isCrossPrize` verifica `team_a != team_b`; scoring por `team` |
| `supabase/functions/challenge-create/index.ts` | MODIFICADO — aceita `team_b_group_id` + seta `team='A'` |
| `supabase/functions/challenge-join/index.ts` | MODIFICADO — team assignment cross/intra + capacity/auto-activate por `team` |
| `supabase/functions/clearing-cron/index.ts` | NOVO — cron EF: agrega pending -> clearing_cases semanais + expira vencidos |
| `supabase/migrations/20260221_clearing_cron.sql` | NOVO — pg_cron schedule diario 02:00 UTC |
| `supabase/migrations/20260221_challenge_team_column.sql` | NOVO — coluna `team` em challenge_participants |
| `supabase/config.toml` | MODIFICADO — registra `clearing-cron` |
| `omni_runner/lib/domain/entities/challenge_participant_entity.dart` | MODIFICADO — campo `team` |
| `omni_runner/lib/domain/usecases/gamification/challenge_evaluator.dart` | MODIFICADO — filtra por `team` |
| `omni_runner/lib/presentation/blocs/challenges/challenges_bloc.dart` | MODIFICADO — parse/merge/autostart por `team` |
| `omni_runner/lib/data/repositories_impl/isar_challenge_repo.dart` | MODIFICADO — serializa `team` |
| `test/.../challenge_evaluator_test.dart` | MODIFICADO — usa `team:` |

---

## Phase 97.3.0 — Dispute UX (amigável, sem acusação)

**Data:** 2026-02-21

### Objetivo

Garantir que toda UX de dispute/invalidação seja amigável, sem acusação, com orientação clara para o usuário.

### Auditoria completa

| Superfície | Linguagem | Resultado |
|---|---|---|
| `InvalidatedRunCard` (corrida inválida) | "Não conseguimos validar esta atividade", razões neutras (GPS, sinal), dicas | OK — excelente |
| `GpsTipsSheet` | Dicas práticas e amigáveis | OK |
| `DisputeStatusCard` (atleta) | Todas as fases: tom neutro, orientações claras | OK (melhorado DISPUTED) |
| `StaffDisputesScreen` (staff clearing) | OPEN/SENT_CONFIRMED OK | Melhorado DISPUTED + EXPIRED |
| `ChallengeResultScreen` | "Boa tentativa!" (loss), "Não concluído" (DNF) | OK |
| `ChallengesListScreen` | Labels neutros (Cancelado, Expirado) | OK |
| `WalletScreen` | Ledger reasons sem termos de dinheiro | OK |
| `ChampionshipManageScreen` | "Desqualificado" -> "Não elegível" | Corrigido |

### Problemas encontrados e corrigidos

| ID | Severidade | Problema | Correção |
|---|---|---|---|
| D-01 | MEDIUM | Staff DISPUTED: "Resolva diretamente..." sem orientação de COMO | Texto expandido com passos: combinar por telefone/mensagem, alinhar valores, confirmar normalmente |
| D-02 | MEDIUM | Staff EXPIRED: "Resolva manualmente..." sem próximos passos | Texto expandido: contatar outra assessoria, OmniCoins reservados até resolução |
| D-03 | LOW | "Desqualificado" em championship — tom acusatório | Renomeado para "Não elegível" |
| D-04 | HIGH | `challenge_result_screen._buildTeamResults` e `_HeroSection` filtram por `groupId` — quebra intra-assessoria | Usa `p.team == 'A'`/`'B'` quando intra-assessoria; winner usa `participant.team` |

### Melhorias de tom/ícone

| Componente | Antes | Depois |
|---|---|---|
| Ícone DISPUTED (staff + atleta) | `Icons.report_outlined` (denúncia) | `Icons.rate_review_rounded` (revisão) |
| Cor DISPUTED (atleta card) | Vermelho (erro/acusação) | Laranja (atenção amigável) |
| Texto DISPUTED (atleta) | "abriu uma revisão sobre este desafio" | "estão verificando os detalhes... Isso é normal" |
| `_HeroSection` winner team | Usava `groupId` (quebra intra) | Usa `participant.team` |

### Regras confirmadas (sem alteração necessária)

- Loss outcome: "Boa tentativa!" (nunca "Você perdeu")
- DNF outcome: "Não concluído" (nunca "Desistência")
- Anti-cheat display: "Padrão (GPS + anti-cheat)" — neutro
- Clearing pending: "Seu prêmio está reservado" — tranquilizador
- Expired clearing: "Entre em contato com o professor" — orientador

### Arquivos modificados

| Arquivo | Tipo |
|---|---|
| `omni_runner/lib/presentation/screens/staff_disputes_screen.dart` | MODIFICADO — DISPUTED/EXPIRED com guidance detalhado, ícone `rate_review` |
| `omni_runner/lib/presentation/widgets/dispute_status_card.dart` | MODIFICADO — DISPUTED: ícone laranja, tom neutro |
| `omni_runner/lib/presentation/screens/challenge_result_screen.dart` | MODIFICADO — team filtering por `team` + winner por `team` |
| `omni_runner/lib/presentation/screens/staff_championship_manage_screen.dart` | MODIFICADO — "Desqualificado" -> "Não elegível" |

### Verificação

- `dart analyze`: 0 erros, 0 warnings
- Todas as mensagens em PT-BR
- Zero termos acusatórios ("fraude", "trapaceou", "violação", "denúncia")
- Zero ícones agressivos em contexto de dispute

---

## Phase 98.1.0 — Auditoria Billing B2B (Portal + Gateway + Webhook + Auto Top-Up)

**Data:** 2026-02-21

### Resultado: TUDO EXISTE E ESTÁ IMPLEMENTADO

O repositório possui uma infraestrutura de billing B2B **completa e funcional**. Nenhum componente está faltando.

### 1. Portal B2B — EXISTE

**Stack:** Next.js 14 (App Router) + Tailwind + Supabase SSR

**Diretório:** `portal/`

| Página | Rota | Funcionalidade |
|---|---|---|
| Login | `/login` | Auth via Supabase (same user base do app) |
| Seletor de grupo | `/select-group` | Multi-grupo: staff de várias assessorias escolhe qual |
| No Access | `/no-access` | Gate para quem não é staff |
| Dashboard | `/dashboard` | KPIs: créditos, atletas, compras realizadas, total adquirido |
| Créditos | `/credits` | Saldo atual + catálogo de pacotes com BuyButton → checkout |
| Faturamento | `/billing` | Histórico de compras: data, créditos, valor (BRL), método, status, recibo |
| Billing Success | `/billing/success` | Retorno pós-checkout Stripe |
| Billing Cancelled | `/billing/cancelled` | Retorno se usuário cancela checkout |
| Configurações | `/settings` | Portal Stripe, recarga automática, equipe (invite/remove) |
| Engajamento | `/engagement` | Métricas de engajamento |
| Atletas | `/athletes` | Lista de atletas da assessoria |

**Autenticação/RBAC (middleware.ts):**
- Public routes: `/login`, `/no-access`, `/api/auth/callback`
- Admin-only: `/billing`, `/settings`, `/credits/history`, `/credits/request`
- Admin+Professor: `/engagement/export`, `/settings/invite`
- Role cookies: `portal_group_id` + `portal_role` (httpOnly, 8h TTL)

**API Routes:**
- `POST /api/checkout` — proxy para `create-checkout-session` EF
- `POST /api/billing-portal` — proxy para `create-portal-session` EF
- `POST /api/auto-topup` — save auto-topup settings
- `POST /api/team/invite` — invite staff member
- `POST /api/team/remove` — remove staff member
- `GET /api/auth/callback` — OAuth callback

### 2. Gateway (Stripe) — EXISTE

| Edge Function | Funcionalidade |
|---|---|
| `create-checkout-session` | Cria `billing_purchase` (pending) + Stripe Checkout Session (card/pix/boleto). Rate-limited, admin_master only. 30min TTL. |
| `create-portal-session` | Cria Stripe Customer Portal session para admin_master ver faturas/recibos e gerenciar cartões. Auto-cria Customer se necessário. |
| `list-purchases` | Lista compras do grupo |

**Checkout flow:**
1. Admin seleciona pacote no portal → `BuyButton` → `POST /api/checkout`
2. API route chama `create-checkout-session` EF
3. EF insere `billing_purchases(status=pending)` + cria Stripe Checkout Session
4. Retorna `checkout_url` → redirect para Stripe
5. Success/cancel → retorno para `/billing/success` ou `/billing/cancelled`

**Payment methods:** `card`, `pix`, `boleto` (BRL); `card` only (outras moedas)

### 3. Webhook — EXISTE

| Edge Function | Eventos tratados |
|---|---|
| `webhook-payments` | `checkout.session.completed`, `checkout.session.async_payment_succeeded`, `checkout.session.async_payment_failed`, `checkout.session.expired`, `charge.refunded`, `charge.dispute.created` |

**Lifecycle:**
- `pending → paid` (via webhook `payment_confirmed`)
- `paid → fulfilled` (via `fn_fulfill_purchase` RPC — atomic credit allocation)
- `pending → cancelled` (via webhook `session_expired` ou `payment_failed`)

**Idempotência (3 camadas):**
- L1: `billing_events.stripe_event_id` UNIQUE partial index
- L2: Conditional UPDATE (`WHERE status = 'pending'`)
- L3: `fn_fulfill_purchase` checks `status = 'paid'` with `FOR UPDATE` lock

**Signature verification:** `stripe.webhooks.constructEventAsync` com `STRIPE_WEBHOOK_SECRET`

### 4. Auto Top-Up — EXISTE

| Edge Function | Funcionalidade |
|---|---|
| `auto-topup-cron` | Scheduled via pg_cron (hourly). Busca todos os grupos com auto top-up habilitado e chama `auto-topup-check` para cada. |
| `auto-topup-check` | Decision tree: (1) enabled? (2) balance < threshold? (3) monthly cap? (4) 24h cooldown? (5) Stripe customer + PM? → cria billing_purchase(source=auto_topup) + PaymentIntent off-session. |

**Config UX:** `portal/src/app/(portal)/settings/auto-topup-form.tsx`
- Threshold (créditos mínimos)
- Produto para recarregar
- Máximo recargas por mês

**Safeguards:**
- 24h cooldown entre top-ups
- Monthly cap (max_per_month)
- Fallback: se cartão recusar (3DS, declined) → cancela purchase + log

### 5. Refund — EXISTE

| Edge Function | Funcionalidade |
|---|---|
| `process-refund` | Service-role only. Valida refund_request(approved) → verifica purchase(fulfilled) → check inventory balance → Stripe Refunds API → debit credits via `decrement_token_inventory` RPC → update statuses. Full + partial refunds. |

### 6. Migrations (Schema)

| Migration | Conteúdo |
|---|---|
| `20260221_billing_portal_tables.sql` | `billing_customers`, `billing_products`, `billing_purchases`, `billing_events`, `fn_fulfill_purchase` RPC. RLS: admin_master read. |
| `20260221_billing_customers_stripe.sql` | `stripe_customer_id`, `stripe_default_pm` em `billing_customers` |
| `20260221_billing_auto_topup_settings.sql` | `billing_auto_topup_settings` table (enabled, threshold, product_id, max_per_month, last_triggered_at) |
| `20260221_billing_webhook_dedup.sql` | `stripe_event_id` UNIQUE partial index em `billing_events` |
| `20260221_billing_refund_requests.sql` | `billing_refund_requests` table (pending→approved→processed) |
| `20260221_billing_limits.sql` | Rate limits / spending limits |

### 7. Environment Variables

| Variável | Onde | Uso |
|---|---|---|
| `STRIPE_SECRET_KEY` | `.env` / EF secrets | Stripe API calls |
| `STRIPE_WEBHOOK_SECRET` | `.env` / EF secrets | Webhook signature verification |
| `PORTAL_URL` | `.env` / EF secrets | Checkout success/cancel URLs |
| `NEXT_PUBLIC_SUPABASE_URL` | `portal/.env.local` | Portal SSR auth |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | `portal/.env.local` | Portal SSR auth |
| `SUPABASE_SERVICE_ROLE_KEY` | `portal/.env.local` | Service client for admin ops |

### 8. Sobre Mercado Pago

O gateway utilizado é **Stripe** (não Mercado Pago). Porém, Stripe suporta nativamente **Pix** e **Boleto** para BRL — que são os métodos de pagamento do Mercado Pago. Na prática, o resultado é equivalente:
- Pix: disponível via Stripe Checkout
- Boleto: disponível via Stripe Checkout
- Cartão: disponível via Stripe Checkout

Se for necessário adicionar Mercado Pago como gateway separado, seria um novo EF (`create-mp-checkout-session`) + webhook handler (`webhook-mp`), mas isso **não é necessário** dado que Stripe já cobre Pix/Boleto/Card.

### Conclusão

| Componente | Existe? | Status |
|---|---|---|
| Portal B2B (Next.js) | SIM | Completo: 11 páginas, RBAC, SSR auth |
| Gateway (Stripe) | SIM | Checkout Session + Customer Portal |
| Webhook | SIM | 6 event types, 3 camadas idempotência |
| Auto Top-Up | SIM | Cron hourly + decision tree + safeguards |
| Refund | SIM | Full + partial, inventory debit |
| Migrations | SIM | 6 billing migrations |
| Env vars | SIM | Documentadas em `.env.example` |

**Zero lacunas encontradas. Infra de billing B2B está completa.**

---

## Phase 98.2.0 — Plano de criação do portal

**Resultado: N/A** — O portal já existe completo (`portal/`). Nenhum plano de criação necessário.

---

## Phase 98.3.0 — Loja-Safe Checklist (App Store / Play Store Compliance)

**Data:** 2026-02-21

### Checklist de compliance

| # | Regra | Verificação | Resultado |
|---|---|---|---|
| 1 | App NÃO mostra preços (R$, BRL, centavos) | `grep -ri 'R\$\|BRL\|reais\|centavos\|price_cents\|formatBRL' omni_runner/lib/` | **0 ocorrências** |
| 2 | App NÃO faz compra in-app | Sem deps: `in_app_purchase`, `revenue_cat`, `purchases_flutter` no `pubspec.yaml` | **0 deps IAP** |
| 3 | App NÃO menciona dinheiro/saque/aposta | `grep -ri 'dinheiro\|money\|cash\|saque\|withdraw\|aposta\|bet\|gambl' lib/` | **0 ocorrências** |
| 4 | Sem permissão BILLING no Android | `grep -ri 'BILLING\|com.android.vending' android/` | **0 ocorrências** |
| 5 | Sem StoreKit/IAP entitlement no iOS | `grep -ri 'StoreKit\|IAP' ios/` | **0 ocorrências** |
| 6 | Sem Stripe/Mercado Pago SDK no app | `grep -ri 'stripe\|mercadopago\|checkout' lib/` | **0 ocorrências** |
| 7 | Portal abre no browser externo | `_PortalCta` usa `launchUrl(uri, mode: LaunchMode.externalApplication)` | **OK** |
| 8 | `StaffCreditsScreen` não mostra valores monetários | Comentário explícito: "No monetary values, no purchase flow, no payment references" | **OK** |
| 9 | `AppConfig.portalUrl` documentado como browser-only | Comentário: "Never load checkout inside the app — App Store / Play Store safe" | **OK** |
| 10 | Ledger reasons sem menção a dinheiro | `cosmeticPurchase` → "Personalização desbloqueada", `crossAssessoriaPending` → "Pendente (entre assessorias)" | **OK** |
| 11 | Wallet screen sem conversão monetária | Zero refs a R$, taxa, cotação, valor monetário | **OK** |
| 12 | OmniCoins tratados como gamificação | Apenas "créditos", "OmniCoins", "tokens" — nunca "moeda", "dinheiro", "valor" | **OK** |

### Onde vive o fluxo de pagamento

| Componente | Localização | Acessível pelo app? |
|---|---|---|
| Checkout (preços, cartão, pix, boleto) | `portal/` (Next.js, browser) | NÃO — browser externo apenas |
| Stripe SDK | `supabase/functions/` (server-side EFs) | NÃO — nunca no client |
| Billing tables | Supabase PostgreSQL | NÃO — RLS bloqueia acesso do app (admin_master only via portal) |
| Portal CTA no app | `StaffCreditsScreen._PortalCta` | SIM — mas apenas redireciona para browser externo |

### Conclusão

**Compliance 100%.** O app mobile:
- Nunca mostra preços
- Nunca processa pagamentos
- Nunca menciona dinheiro, saque, ou aposta
- Nunca carrega checkout dentro do app
- Não tem dependências de IAP
- OmniCoins são gamificação pura (earn by running, spend on cosmetics/challenges)
- Todo fluxo B2B vive no portal web (browser externo)

---

## DEPLOY CONFIG AUDIT (Pre-APK)

### Correções aplicadas:

| # | Correção | Arquivo |
|---|---|---|
| CFG-01 | Google Services Gradle plugin adicionado (condicional: só aplica se `google-services.json` existir) | `android/settings.gradle`, `android/app/build.gradle` |
| CFG-02 | `GoogleSignIn` agora recebe `serverClientId` via `GOOGLE_WEB_CLIENT_ID` (--dart-define) | `remote_auth_datasource.dart`, `app_config.dart` |
| CFG-03 | `.env.example` atualizado com `GOOGLE_WEB_CLIENT_ID` | `.env.example` |
| CFG-04 | Script `preflight_check.sh` criado — valida todas as dependências antes do build | `scripts/preflight_check.sh` |

### Checklist de configuração externa (ações do operador):

| # | Ação | Status |
|---|---|---|
| 1 | Criar projeto Firebase + baixar `google-services.json` | PENDENTE |
| 2 | Criar `.env.dev` com SUPABASE_URL + SUPABASE_ANON_KEY reais | PENDENTE |
| 3 | Configurar GOOGLE_WEB_CLIENT_ID no `.env.dev` | PENDENTE |
| 4 | Habilitar Google OAuth no Supabase Dashboard | PENDENTE |
| 5 | `supabase db push` (aplicar 38 migrations) | PENDENTE |
| 6 | `supabase functions deploy` (40 Edge Functions) | PENDENTE |
| 7 | (Opcional) MAPTILER_API_KEY | PENDENTE |
| 8 | (Opcional) SENTRY_DSN | PENDENTE |

### Validação pós-correção:
- `flutter analyze`: 0 errors
- `flutter test`: 913/913 passando
