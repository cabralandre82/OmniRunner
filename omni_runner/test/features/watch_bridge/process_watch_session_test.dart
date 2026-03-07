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
import 'package:omni_runner/features/wearables_ble/heart_rate_sample.dart';

// ── Fakes ─────────────────────────────────────────────────────────

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

  @override
  Future<List<WorkoutSessionEntity>> getUnsyncedCompleted() async => [];

  @override
  Future<void> markSynced(String id) async {}
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
  late WatchBridge watchBridge;
  late ProcessWatchSession useCase;
  late MethodChannel channel;
  final ackCalls = <MethodCall>[];

  setUp(() {
    sessionRepo = _FakeSessionRepo();
    pointsRepo = _FakePointsRepo();
    channel = const MethodChannel('omnirunner/watch');
    watchBridge = WatchBridge(channel: channel);
    watchBridge.init();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      ackCalls.add(call);
      return null;
    });

    useCase = ProcessWatchSession(
      sessionRepo: sessionRepo,
      pointsRepo: pointsRepo,
      watchBridge: watchBridge,
    );
  });

  tearDown(() {
    watchBridge.dispose();
    ackCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  WatchSessionPayload makePayload({
    String sessionId = 'test-sess-1',
    String source = 'apple_watch',
    int numPoints = 3,
    int numHr = 2,
  }) {
    return WatchSessionPayload(
      version: 1,
      source: source,
      sessionId: sessionId,
      startMs: 1000000,
      endMs: 1060000,
      totalDistanceM: 5000.0,
      movingMs: 58000,
      avgBpm: 150,
      maxBpm: 180,
      isVerified: true,
      integrityFlags: const [],
      points: List.generate(
        numPoints,
        (i) => LocationPointEntity(
          lat: -23.55 + i * 0.001,
          lng: -46.63 + i * 0.001,
          alt: 750.0,
          accuracy: 4.0,
          speed: 3.2,
          timestampMs: 1000000 + i * 1000,
        ),
      ),
      hrSamples: List.generate(
        numHr,
        (i) => HeartRateSample(bpm: 140 + i * 5, timestampMs: 1000000 + i),
      ),
    );
  }

  test('persists session and sends ACK', () async {
    final payload = makePayload();

    final result = await useCase(payload);

    expect(result, true);

    final saved = await sessionRepo.getById('test-sess-1');
    expect(saved, isNotNull);
    expect(saved!.id, 'test-sess-1');
    expect(saved.status, WorkoutStatus.completed);
    expect(saved.totalDistanceM, 5000.0);
    expect(saved.avgBpm, 150);
    expect(saved.maxBpm, 180);

    final points = await pointsRepo.getBySessionId('test-sess-1');
    expect(points, hasLength(3));

    expect(ackCalls, hasLength(1));
    expect(ackCalls.first.method, 'acknowledgeSession');
    expect(ackCalls.first.arguments, {'sessionId': 'test-sess-1'});
  });

  test('idempotent: skips if session already exists', () async {
    final payload = makePayload();

    await useCase(payload);
    ackCalls.clear();

    final result = await useCase(payload);

    expect(result, true);

    final all = await sessionRepo.getAll();
    expect(all, hasLength(1));

    expect(ackCalls, hasLength(1));
  });

  test('persists without GPS points when empty', () async {
    final payload = makePayload(numPoints: 0);

    final result = await useCase(payload);

    expect(result, true);

    final points = await pointsRepo.getBySessionId(payload.sessionId);
    expect(points, isEmpty);
  });

  test('sets avgBpm/maxBpm to null when zero', () async {
    const payload = WatchSessionPayload(
      version: 1,
      source: 'wear_os',
      sessionId: 'no-hr-session',
      startMs: 1000,
      endMs: 2000,
      totalDistanceM: 100.0,
      movingMs: 900,
      avgBpm: 0,
      maxBpm: 0,
      isVerified: true,
      integrityFlags: [],
      points: [],
      hrSamples: [],
    );

    await useCase(payload);

    final saved = await sessionRepo.getById('no-hr-session');
    expect(saved!.avgBpm, isNull);
    expect(saved.maxBpm, isNull);
  });

  test('preserves integrity flags', () async {
    const payload = WatchSessionPayload(
      version: 1,
      source: 'apple_watch',
      sessionId: 'flagged-session',
      startMs: 1000,
      endMs: 2000,
      totalDistanceM: 100.0,
      movingMs: 900,
      avgBpm: 120,
      maxBpm: 160,
      isVerified: false,
      integrityFlags: ['SPEED_EXCEEDED'],
      points: [],
      hrSamples: [],
    );

    await useCase(payload);

    final saved = await sessionRepo.getById('flagged-session');
    expect(saved!.isVerified, false);
    expect(saved.integrityFlags, ['SPEED_EXCEEDED']);
  });

  test('handles multiple distinct sessions from different sources', () async {
    final applePayload = makePayload(
      sessionId: 'apple-sess',
      source: 'apple_watch',
      numPoints: 2,
      numHr: 1,
    );
    final wearPayload = makePayload(
      sessionId: 'wear-sess',
      source: 'wear_os',
      numPoints: 4,
      numHr: 3,
    );

    await useCase(applePayload);
    await useCase(wearPayload);

    final all = await sessionRepo.getAll();
    expect(all, hasLength(2));

    final applePoints = await pointsRepo.getBySessionId('apple-sess');
    expect(applePoints, hasLength(2));

    final wearPoints = await pointsRepo.getBySessionId('wear-sess');
    expect(wearPoints, hasLength(4));

    expect(ackCalls, hasLength(2));
  });

  test('session endTimeMs is persisted correctly', () async {
    final payload = makePayload();

    await useCase(payload);

    final saved = await sessionRepo.getById('test-sess-1');
    expect(saved!.endTimeMs, 1060000);
    expect(saved.startTimeMs, 1000000);
  });

  test('session route points match payload GPS data', () async {
    final payload = makePayload(numPoints: 2);

    await useCase(payload);

    final saved = await sessionRepo.getById('test-sess-1');
    expect(saved!.route, hasLength(2));
    expect(saved.route.first.lat, closeTo(-23.55, 0.001));
  });
}
