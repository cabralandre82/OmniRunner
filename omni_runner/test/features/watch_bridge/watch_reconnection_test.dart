import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';
import 'package:omni_runner/domain/repositories/i_points_repo.dart';
import 'package:omni_runner/domain/repositories/i_session_repo.dart';
import 'package:omni_runner/features/watch_bridge/process_watch_session.dart';
import 'package:omni_runner/features/watch_bridge/watch_bridge.dart';
import 'package:omni_runner/features/watch_bridge/watch_session_payload.dart';

// ── Fakes ─────────────────────────────────────────────────────────

class _FakeSessionRepo implements ISessionRepo {
  final Map<String, WorkoutSessionEntity> _db = {};

  /// When > 0, the next N calls to [save] will throw.
  int failNextSaves = 0;

  @override
  Future<void> save(WorkoutSessionEntity session) async {
    if (failNextSaves > 0) {
      failNextSaves--;
      throw Exception('Simulated DB failure');
    }
    _db[session.id] = session;
  }

  @override
  Future<WorkoutSessionEntity?> getById(String id) async => _db[id];

  @override
  Future<List<WorkoutSessionEntity>> getAll() async => _db.values.toList();

  @override
  Future<List<WorkoutSessionEntity>> getByStatus(WorkoutStatus status) async =>
      _db.values.where((s) => s.status == status).toList();

  @override
  Future<void> deleteById(String id) async => _db.remove(id);

  @override
  Future<bool> updateStatus(String id, WorkoutStatus status) async => true;

  @override
  Future<bool> updateMetrics({
    required String id,
    required double totalDistanceM,
    required int movingMs,
    int? endTimeMs,
  }) async =>
      true;

  @override
  Future<bool> updateGhostSessionId(String id, String ghostSessionId) async =>
      true;

  @override
  Future<bool> updateIntegrityFlags(
    String id, {
    required bool isVerified,
    required List<String> flags,
  }) async =>
      true;

  @override
  Future<bool> updateHrMetrics(
    String id, {
    required int avgBpm,
    required int maxBpm,
  }) async =>
      true;
}

class _FakePointsRepo implements IPointsRepo {
  final Map<String, List<LocationPointEntity>> _db = {};

  @override
  Future<void> savePoint(String sessionId, LocationPointEntity point) async {
    _db.putIfAbsent(sessionId, () => []);
    _db[sessionId]!.add(point);
  }

  @override
  Future<void> savePoints(
    String sessionId,
    List<LocationPointEntity> points,
  ) async {
    _db.putIfAbsent(sessionId, () => []);
    _db[sessionId]!.addAll(points);
  }

  @override
  Future<List<LocationPointEntity>> getBySessionId(String sessionId) async =>
      _db[sessionId] ?? [];

  @override
  Future<void> deleteBySessionId(String sessionId) async =>
      _db.remove(sessionId);

  @override
  Future<int> countBySessionId(String sessionId) async =>
      _db[sessionId]?.length ?? 0;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSessionRepo sessionRepo;
  late _FakePointsRepo pointsRepo;
  late WatchBridge bridge;
  late ProcessWatchSession processSession;
  late MethodChannel channel;

  setUp(() {
    sessionRepo = _FakeSessionRepo();
    pointsRepo = _FakePointsRepo();
    channel = const MethodChannel('omnirunner/watch');
    bridge = WatchBridge(channel: channel);
    bridge.init();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);

    processSession = ProcessWatchSession(
      sessionRepo: sessionRepo,
      pointsRepo: pointsRepo,
      watchBridge: bridge,
    );
  });

  tearDown(() {
    bridge.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  WatchSessionPayload makePayload({String sessionId = 'retry-test'}) {
    return WatchSessionPayload(
      version: 1,
      source: 'apple_watch',
      sessionId: sessionId,
      startMs: 1000,
      endMs: 2000,
      totalDistanceM: 1000.0,
      movingMs: 900,
      avgBpm: 140,
      maxBpm: 170,
      isVerified: true,
      integrityFlags: const [],
      points: const [
        LocationPointEntity(
          lat: -23.55,
          lng: -46.63,
          timestampMs: 1000,
        ),
      ],
      hrSamples: const [],
    );
  }

  group('Reconnection & Retry', () {
    test('ProcessWatchSession returns false on DB failure', () async {
      sessionRepo.failNextSaves = 1;

      final result = await processSession(makePayload());

      expect(result, false);

      final saved = await sessionRepo.getById('retry-test');
      expect(saved, isNull);
    });

    test('ProcessWatchSession succeeds after DB failure is resolved', () async {
      sessionRepo.failNextSaves = 1;

      // First attempt fails
      final r1 = await processSession(makePayload());
      expect(r1, false);

      // Second attempt succeeds (failNextSaves decremented to 0)
      final r2 = await processSession(makePayload());
      expect(r2, true);

      final saved = await sessionRepo.getById('retry-test');
      expect(saved, isNotNull);
      expect(saved!.totalDistanceM, 1000.0);
    });

    test(
      'idempotent: re-processing already saved session sends ACK again',
      () async {
        final ackCalls = <MethodCall>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          ackCalls.add(call);
          return null;
        });

        final payload = makePayload(sessionId: 'idem-test');

        // First time: persists
        await processSession(payload);
        expect(ackCalls, hasLength(1));

        // Second time: skips save, still ACKs
        await processSession(payload);
        expect(ackCalls, hasLength(2));

        // Only one in DB
        final all = await sessionRepo.getAll();
        expect(all, hasLength(1));
      },
    );

    test(
      'retry on reconnect: bridge emits reachability → pending retried',
      () async {
        final processed = Completer<void>();
        StreamSubscription<void>? sessionSub;
        StreamSubscription<void>? reachabilitySub;

        final pendingRetries = <String, WatchSessionPayload>{};

        // Wire session listener with retry queue
        sessionSub = bridge.onSessionReceived.listen((payload) async {
          final ok = await processSession(payload);
          if (!ok) {
            pendingRetries[payload.sessionId] = payload;
          } else {
            pendingRetries.remove(payload.sessionId);
          }
        });

        // Wire reachability listener → retry pending
        reachabilitySub =
            bridge.onReachabilityChanged.listen((isReachable) async {
          if (isReachable && pendingRetries.isNotEmpty) {
            final entries = Map.of(pendingRetries);
            for (final e in entries.entries) {
              final ok = await processSession(e.value);
              if (ok) {
                pendingRetries.remove(e.key);
              }
            }
            if (pendingRetries.isEmpty) {
              processed.complete();
            }
          }
        });

        // Make DB fail on first save
        sessionRepo.failNextSaves = 1;

        // Send session → will fail
        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
          'omnirunner/watch',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('onSessionReceived', <String, dynamic>{
              'version': 1,
              'source': 'wear_os',
              'sessionId': 'reconnect-test',
              'startMs': 1000,
              'endMs': 2000,
              'totalDistanceM': 500.0,
              'movingMs': 900,
              'avgBpm': 130,
              'maxBpm': 165,
              'isVerified': true,
              'integrityFlags': <String>[],
              'points': <Map<String, dynamic>>[],
              'hrSamples': <Map<String, dynamic>>[],
            }),
          ),
          (_) {},
        );

        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Session should be in pending queue
        expect(pendingRetries, hasLength(1));
        expect(await sessionRepo.getById('reconnect-test'), isNull);

        // Simulate reconnection → triggers retry
        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
          'omnirunner/watch',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall(
              'onReachabilityChanged',
              <String, dynamic>{'isReachable': true},
            ),
          ),
          (_) {},
        );

        // Wait for retry to complete
        await processed.future.timeout(const Duration(seconds: 2));

        // Session should now be persisted
        final saved = await sessionRepo.getById('reconnect-test');
        expect(saved, isNotNull);
        expect(saved!.totalDistanceM, 500.0);
        expect(pendingRetries, isEmpty);

        sessionSub.cancel();
        reachabilitySub.cancel();
      },
    );

    test(
      'multiple sessions: only failed ones are queued for retry',
      () async {
        final pending = <String, WatchSessionPayload>{};

        // Process session 1 — will succeed
        final p1 = makePayload(sessionId: 'ok-session');
        final r1 = await processSession(p1);
        expect(r1, true);

        // Process session 2 — will fail
        sessionRepo.failNextSaves = 1;
        final p2 = makePayload(sessionId: 'fail-session');
        final r2 = await processSession(p2);
        expect(r2, false);
        pending[p2.sessionId] = p2;

        expect(pending, hasLength(1));
        expect(pending.containsKey('fail-session'), true);

        // Retry — should succeed now
        final r3 = await processSession(pending['fail-session']!);
        expect(r3, true);
        pending.remove('fail-session');

        final all = await sessionRepo.getAll();
        expect(all, hasLength(2));
      },
    );
  });
}
