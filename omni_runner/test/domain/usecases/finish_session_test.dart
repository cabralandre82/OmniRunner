import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';
import 'package:omni_runner/domain/repositories/i_points_repo.dart';
import 'package:omni_runner/domain/repositories/i_session_repo.dart';
import 'package:omni_runner/domain/usecases/finish_session.dart';

final class _FakeSR implements ISessionRepo {
  final Map<String, WorkoutSessionEntity> _store = {};
  WorkoutStatus? lastUpdatedStatus;
  double? lastUpdatedDistance;
  int? lastUpdatedMovingMs;
  int? lastUpdatedEndTimeMs;
  _FakeSR([List<WorkoutSessionEntity>? sessions]) {
    for (final s in sessions ?? <WorkoutSessionEntity>[]) {
      _store[s.id] = s;
    }
  }
  @override
  Future<WorkoutSessionEntity?> getById(String id) async => _store[id];
  @override
  Future<bool> updateStatus(String id, WorkoutStatus status) async {
    if (!_store.containsKey(id)) return false;
    lastUpdatedStatus = status;
    return true;
  }
  @override
  Future<bool> updateMetrics({
    required String id, required double totalDistanceM,
    required int movingMs, int? endTimeMs,
  }) async {
    if (!_store.containsKey(id)) return false;
    lastUpdatedDistance = totalDistanceM;
    lastUpdatedMovingMs = movingMs;
    lastUpdatedEndTimeMs = endTimeMs;
    return true;
  }
  @override
  Future<bool> updateGhostSessionId(String id, String ghostSessionId) async => true;
  @override
  Future<bool> updateIntegrityFlags(String id, {required bool isVerified, required List<String> flags}) async => true;
  @override
  Future<bool> updateHrMetrics(String id, {required int avgBpm, required int maxBpm}) async => true;
  @override
  Future<void> save(WorkoutSessionEntity s) async => _store[s.id] = s;
  @override
  Future<List<WorkoutSessionEntity>> getAll() async =>
      _store.values.toList();
  @override
  Future<List<WorkoutSessionEntity>> getByStatus(WorkoutStatus s) async =>
      _store.values.where((e) => e.status == s).toList();
  @override
  Future<void> deleteById(String id) async => _store.remove(id);
}

final class _FakePR implements IPointsRepo {
  final Map<String, List<LocationPointEntity>> _store = {};
  _FakePR([Map<String, List<LocationPointEntity>>? pts]) {
    if (pts != null) _store.addAll(pts);
  }
  @override
  Future<List<LocationPointEntity>> getBySessionId(String id) async =>
      _store[id] ?? [];
  @override
  Future<void> savePoint(String id, LocationPointEntity pt) async {}
  @override
  Future<void> savePoints(String id, List<LocationPointEntity> pts) async {}
  @override
  Future<void> deleteBySessionId(String id) async {}
  @override
  Future<int> countBySessionId(String id) async => _store[id]?.length ?? 0;
}

WorkoutSessionEntity _ses({
  String id = 's1', WorkoutStatus status = WorkoutStatus.running,
  int startTimeMs = 0,
}) => WorkoutSessionEntity(
      id: id, status: status, startTimeMs: startTimeMs, route: const [],
    );

LocationPointEntity _pt(double lat, int ts) =>
    LocationPointEntity(lat: lat, lng: 0.0, accuracy: 5.0, timestampMs: ts);

void main() {
  group('FinishSession', () {
    test('returns failure when session does not exist', () async {
      final uc = FinishSession(
        sessionRepo: _FakeSR(), pointsRepo: _FakePR(),
      );
      final r = await uc(sessionId: 'nonexistent');
      expect(r.success, isFalse);
      expect(r.metrics, isNull);
    });

    test('finishes session, returns metrics, sets status completed', () async {
      final sr = _FakeSR([_ses(id: 'r1', startTimeMs: 0)]);
      final pts = List.generate(
        6, (i) => _pt(i * 0.001, i * 10000),
      );
      final uc = FinishSession(
        sessionRepo: sr, pointsRepo: _FakePR({'r1': pts}),
      );
      final r = await uc(sessionId: 'r1', endTimeMs: 50000);
      expect(r.success, isTrue);
      expect(r.metrics, isNotNull);
      expect(r.metrics!.totalDistanceM, closeTo(555, 10));
      expect(r.metrics!.pointsCount, 6);
      expect(sr.lastUpdatedStatus, WorkoutStatus.completed);
    });

    test('persists metrics and endTimeMs to session repo', () async {
      final sr = _FakeSR([_ses(id: 'r1', startTimeMs: 0)]);
      final pts = [_pt(0.0, 0), _pt(0.001, 20000)];
      final uc = FinishSession(
        sessionRepo: sr, pointsRepo: _FakePR({'r1': pts}),
      );
      await uc(sessionId: 'r1', endTimeMs: 20000);
      expect(sr.lastUpdatedDistance, closeTo(111, 5));
      expect(sr.lastUpdatedMovingMs, 20000);
      expect(sr.lastUpdatedEndTimeMs, 20000);
    });

    test('uses last point timestamp when endTimeMs not provided', () async {
      final sr = _FakeSR([_ses(id: 'r1', startTimeMs: 0)]);
      final uc = FinishSession(
        sessionRepo: sr,
        pointsRepo: _FakePR({'r1': [_pt(0.0, 0), _pt(0.001, 45000)]}),
      );
      await uc(sessionId: 'r1');
      expect(sr.lastUpdatedEndTimeMs, 45000);
    });

    test('handles session with zero points', () async {
      final sr = _FakeSR([_ses(id: 'e1', startTimeMs: 1000)]);
      final uc = FinishSession(
        sessionRepo: sr, pointsRepo: _FakePR(),
      );
      final r = await uc(sessionId: 'e1', endTimeMs: 5000);
      expect(r.success, isTrue);
      expect(r.metrics!.totalDistanceM, 0.0);
      expect(r.metrics!.currentPaceSecPerKm, isNull);
      expect(r.metrics!.avgPaceSecPerKm, isNull);
      expect(r.metrics!.pointsCount, 0);
      expect(r.metrics!.elapsedMs, 4000);
    });

    test('calculates average pace from distance and moving time', () async {
      final sr = _FakeSR([_ses(id: 'r1', startTimeMs: 0)]);
      final uc = FinishSession(
        sessionRepo: sr,
        pointsRepo: _FakePR({'r1': [_pt(0.0, 0), _pt(0.001, 20000)]}),
      );
      final r = await uc(sessionId: 'r1', endTimeMs: 20000);
      expect(r.metrics!.avgPaceSecPerKm, isNotNull);
      expect(r.metrics!.avgPaceSecPerKm, closeTo(180, 5));
    });

    test('elapsed time is non-negative when endTime < startTime', () async {
      final sr = _FakeSR([_ses(id: 'r1', startTimeMs: 50000)]);
      final uc = FinishSession(
        sessionRepo: sr,
        pointsRepo: _FakePR({'r1': [_pt(0.0, 50000)]}),
      );
      final r = await uc(sessionId: 'r1', endTimeMs: 40000);
      expect(r.metrics!.elapsedMs, 0);
    });

    test('moving time excludes gaps >= 30s (pauses)', () async {
      final sr = _FakeSR([_ses(id: 'r1', startTimeMs: 0)]);
      final pts = [
        _pt(0.0, 0), _pt(0.001, 10000),
        _pt(0.002, 70000), // 60s gap (excluded)
        _pt(0.003, 80000), // 10s segment
      ];
      final uc = FinishSession(
        sessionRepo: sr, pointsRepo: _FakePR({'r1': pts}),
      );
      final r = await uc(sessionId: 'r1', endTimeMs: 80000);
      expect(r.metrics!.movingMs, 20000);
    });
  });
}
