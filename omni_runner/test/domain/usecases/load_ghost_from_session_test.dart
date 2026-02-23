import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';
import 'package:omni_runner/domain/repositories/i_points_repo.dart';
import 'package:omni_runner/domain/repositories/i_session_repo.dart';
import 'package:omni_runner/domain/usecases/load_ghost_from_session.dart';

final class _FakeSessionRepo implements ISessionRepo {
  final Map<String, WorkoutSessionEntity> _store = {};

  _FakeSessionRepo([List<WorkoutSessionEntity>? sessions]) {
    for (final s in sessions ?? <WorkoutSessionEntity>[]) {
      _store[s.id] = s;
    }
  }

  @override
  Future<WorkoutSessionEntity?> getById(String id) async => _store[id];
  @override
  Future<void> save(WorkoutSessionEntity session) async {}
  @override
  Future<List<WorkoutSessionEntity>> getAll() async => [];
  @override
  Future<List<WorkoutSessionEntity>> getByStatus(WorkoutStatus s) async => [];
  @override
  Future<void> deleteById(String id) async {}
  @override
  Future<bool> updateStatus(String id, WorkoutStatus s) async => false;
  @override
  Future<bool> updateMetrics({
    required String id,
    required double totalDistanceM,
    required int movingMs,
    int? endTimeMs,
  }) async => false;
  @override
  Future<bool> updateGhostSessionId(String id, String ghostSessionId) async => false;
  @override
  Future<bool> updateIntegrityFlags(String id, {required bool isVerified, required List<String> flags}) async => false;
  @override
  Future<bool> updateHrMetrics(String id, {required int avgBpm, required int maxBpm}) async => false;
}

final class _FakePointsRepo implements IPointsRepo {
  final Map<String, List<LocationPointEntity>> _store;

  _FakePointsRepo([Map<String, List<LocationPointEntity>>? points])
      : _store = points ?? {};

  @override
  Future<List<LocationPointEntity>> getBySessionId(String id) async =>
      _store[id] ?? [];
  @override
  Future<void> savePoint(String id, LocationPointEntity p) async {}
  @override
  Future<void> savePoints(String id, List<LocationPointEntity> p) async {}
  @override
  Future<void> deleteBySessionId(String id) async {}
  @override
  Future<int> countBySessionId(String id) async =>
      _store[id]?.length ?? 0;
}

WorkoutSessionEntity _session({
  String id = 'session-1',
  int startTimeMs = 0,
}) => WorkoutSessionEntity(
      id: id,
      status: WorkoutStatus.completed,
      startTimeMs: startTimeMs,
      route: const [],
    );

LocationPointEntity _point({
  required double lat,
  double lng = 0.0,
  required int timestampMs,
}) => LocationPointEntity(
      lat: lat,
      lng: lng,
      accuracy: 5.0,
      timestampMs: timestampMs,
    );

void main() {
  group('LoadGhostFromSession', () {
    test('returns null when session does not exist', () async {
      final uc = LoadGhostFromSession(
        sessionRepo: _FakeSessionRepo(),
        pointsRepo: _FakePointsRepo(),
      );
      expect(await uc('nonexistent'), isNull);
    });
    test('returns null when session has zero points', () async {
      final uc = LoadGhostFromSession(
        sessionRepo: _FakeSessionRepo([_session(id: 's1')]),
        pointsRepo: _FakePointsRepo(),
      );
      expect(await uc('s1'), isNull);
    });
    test('returns null when session has only one point', () async {
      final uc = LoadGhostFromSession(
        sessionRepo: _FakeSessionRepo([_session(id: 's1')]),
        pointsRepo: _FakePointsRepo({
          's1': [_point(lat: 0.0, timestampMs: 1000)],
        }),
      );
      expect(await uc('s1'), isNull);
    });
    test('returns null when duration is zero (same timestamps)', () async {
      final uc = LoadGhostFromSession(
        sessionRepo: _FakeSessionRepo([_session(id: 's1')]),
        pointsRepo: _FakePointsRepo({
          's1': [
            _point(lat: 0.0, timestampMs: 1000),
            _point(lat: 0.001, timestampMs: 1000),
          ],
        }),
      );
      expect(await uc('s1'), isNull);
    });

    test('loads ghost with correct sessionId', () async {
      final uc = LoadGhostFromSession(
        sessionRepo: _FakeSessionRepo([_session(id: 'run-42')]),
        pointsRepo: _FakePointsRepo({
          'run-42': [
            _point(lat: 0.0, timestampMs: 0),
            _point(lat: 0.001, timestampMs: 30000),
          ],
        }),
      );
      final r = await uc('run-42');
      expect(r, isNotNull);
      expect(r!.sessionId, 'run-42');
    });

    test('loads ghost with full route', () async {
      final points = [
        _point(lat: 0.0, timestampMs: 0),
        _point(lat: 0.001, timestampMs: 10000),
        _point(lat: 0.002, timestampMs: 20000),
        _point(lat: 0.003, timestampMs: 30000),
      ];
      final uc = LoadGhostFromSession(
        sessionRepo: _FakeSessionRepo([_session(id: 's1')]),
        pointsRepo: _FakePointsRepo({'s1': points}),
      );
      final r = await uc('s1');
      expect(r, isNotNull);
      expect(r!.route, hasLength(4));
      expect(r.route.first.lat, 0.0);
      expect(r.route.last.lat, 0.003);
    });

    test('calculates durationMs from first and last point', () async {
      final uc = LoadGhostFromSession(
        sessionRepo: _FakeSessionRepo([_session(id: 's1')]),
        pointsRepo: _FakePointsRepo({
          's1': [
            _point(lat: 0.0, timestampMs: 5000),
            _point(lat: 0.001, timestampMs: 15000),
            _point(lat: 0.002, timestampMs: 35000),
          ],
        }),
      );
      final r = await uc('s1');
      expect(r, isNotNull);
      expect(r!.durationMs, 30000);
    });

    test('uses session startTimeMs', () async {
      final uc = LoadGhostFromSession(
        sessionRepo: _FakeSessionRepo([
          _session(id: 's1', startTimeMs: 1704067200000),
        ]),
        pointsRepo: _FakePointsRepo({
          's1': [
            _point(lat: 0.0, timestampMs: 1704067200000),
            _point(lat: 0.001, timestampMs: 1704067230000),
          ],
        }),
      );
      final r = await uc('s1');
      expect(r, isNotNull);
      expect(r!.startTimeMs, 1704067200000);
    });

    test('works with large route (1000 points)', () async {
      final points = List.generate(
        1000,
        (i) => _point(lat: i * 0.0001, timestampMs: i * 1000),
      );
      final uc = LoadGhostFromSession(
        sessionRepo: _FakeSessionRepo([_session(id: 's1')]),
        pointsRepo: _FakePointsRepo({'s1': points}),
      );
      final r = await uc('s1');
      expect(r, isNotNull);
      expect(r!.route, hasLength(1000));
      expect(r.durationMs, 999000);
    });
  });
}
