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

// ── Fakes (same as process_watch_session_test.dart) ─────────────

class _FakeSessionRepo implements ISessionRepo {
  final Map<String, WorkoutSessionEntity> _db = {};

  @override
  Future<void> save(WorkoutSessionEntity session) async =>
      _db[session.id] = session;

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
  StreamSubscription<void>? sub;

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
    sub?.cancel();
    bridge.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'auto-subscription: session emitted on bridge is persisted automatically',
    () async {
      // Wire auto-subscription (mirrors initWatchBridge)
      final persisted = Completer<void>();
      sub = bridge.onSessionReceived.listen((payload) async {
        await processSession(payload);
        persisted.complete();
      });

      // Simulate native sending a session
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        'omnirunner/watch',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onSessionReceived', <String, dynamic>{
            'version': 1,
            'source': 'wear_os',
            'sessionId': 'auto-sub-test',
            'startMs': 1000000,
            'endMs': 1060000,
            'totalDistanceM': 3000.0,
            'movingMs': 55000,
            'avgBpm': 145,
            'maxBpm': 175,
            'isVerified': true,
            'integrityFlags': <String>[],
            'points': <Map<String, dynamic>>[
              <String, dynamic>{
                'lat': -23.55,
                'lng': -46.63,
                'alt': 750.0,
                'accuracy': 4.0,
                'speed': 3.2,
                'timestampMs': 1000001,
              },
            ],
            'hrSamples': <Map<String, dynamic>>[
              <String, dynamic>{'bpm': 145, 'timestampMs': 1000001},
            ],
          }),
        ),
        (_) {},
      );

      // Wait for async processing
      await persisted.future.timeout(const Duration(seconds: 2));

      // Verify session was persisted
      final saved = await sessionRepo.getById('auto-sub-test');
      expect(saved, isNotNull);
      expect(saved!.id, 'auto-sub-test');
      expect(saved.status, WorkoutStatus.completed);
      expect(saved.totalDistanceM, 3000.0);
      expect(saved.avgBpm, 145);

      // Verify GPS points were persisted
      final points = await pointsRepo.getBySessionId('auto-sub-test');
      expect(points, hasLength(1));
    },
  );

  test(
    'duplicate session via bridge stream does not create duplicates',
    () async {
      final count = Completer<void>();
      var callCount = 0;

      sub = bridge.onSessionReceived.listen((payload) async {
        await processSession(payload);
        callCount++;
        if (callCount == 2) count.complete();
      });

      final sessionData = {
        'version': 1,
        'source': 'apple_watch',
        'sessionId': 'dup-test',
        'startMs': 1000,
        'endMs': 2000,
        'totalDistanceM': 100.0,
        'movingMs': 900,
        'avgBpm': 120,
        'maxBpm': 160,
        'isVerified': true,
        'integrityFlags': <String>[],
        'points': <Map<String, dynamic>>[],
        'hrSamples': <Map<String, dynamic>>[],
      };

      // Send same session twice
      for (var i = 0; i < 2; i++) {
        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
          'omnirunner/watch',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('onSessionReceived', sessionData),
          ),
          (_) {},
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      await count.future.timeout(const Duration(seconds: 2));

      // Only one session in DB
      final all = await sessionRepo.getAll();
      expect(all, hasLength(1));
    },
  );
}
