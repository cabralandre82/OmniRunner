import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';
import 'package:omni_runner/domain/repositories/i_points_repo.dart';
import 'package:omni_runner/domain/repositories/i_session_repo.dart';
import 'package:omni_runner/domain/usecases/recover_active_session.dart';

// ── Fakes (implement all methods, only getByStatus/getBySessionId used) ──

final class _FakeSR implements ISessionRepo {
  final Map<WorkoutStatus, List<WorkoutSessionEntity>> _s;
  _FakeSR([Map<WorkoutStatus, List<WorkoutSessionEntity>>? s]) : _s = s ?? {};
  @override
  Future<List<WorkoutSessionEntity>> getByStatus(WorkoutStatus st) async =>
      _s[st] ?? [];
  @override
  Future<void> save(WorkoutSessionEntity s) async {}
  @override
  Future<WorkoutSessionEntity?> getById(String id) async => null;
  @override
  Future<List<WorkoutSessionEntity>> getAll() async => [];
  @override
  Future<void> deleteById(String id) async {}
  @override
  Future<bool> updateStatus(String id, WorkoutStatus s) async => false;
  @override
  Future<bool> updateMetrics({
    required String id, required double totalDistanceM,
    required int movingMs, int? endTimeMs,
  }) async => false;
  @override
  Future<bool> updateGhostSessionId(String id, String ghostSessionId) async => false;
  @override
  Future<bool> updateIntegrityFlags(String id, {required bool isVerified, required List<String> flags}) async => false;
  @override
  Future<bool> updateHrMetrics(String id, {required int avgBpm, required int maxBpm}) async => false;
  @override
  Future<List<WorkoutSessionEntity>> getUnsyncedCompleted() async => [];
  @override
  Future<void> markSynced(String id) async {}
}

final class _FakePR implements IPointsRepo {
  final Map<String, List<LocationPointEntity>> _p;
  _FakePR([Map<String, List<LocationPointEntity>>? p]) : _p = p ?? {};
  @override
  Future<List<LocationPointEntity>> getBySessionId(String id) async =>
      _p[id] ?? [];
  @override
  Future<void> savePoint(String id, LocationPointEntity pt) async {}
  @override
  Future<void> savePoints(String id, List<LocationPointEntity> pts) async {}
  @override
  Future<void> deleteBySessionId(String id) async {}
  @override
  Future<int> countBySessionId(String id) async => _p[id]?.length ?? 0;
}

LocationPointEntity _pt({
  required double lat, double accuracy = 5.0, required int timestampMs,
}) => LocationPointEntity(
      lat: lat, lng: 0.0, accuracy: accuracy, timestampMs: timestampMs,
    );

WorkoutSessionEntity _ses({
  String id = 's1', WorkoutStatus status = WorkoutStatus.running,
  int startTimeMs = 0, int? endTimeMs,
}) => WorkoutSessionEntity(
      id: id, status: status, startTimeMs: startTimeMs,
      endTimeMs: endTimeMs, route: const [],
    );

/// 6 points × ~111m segments, 30s apart → ~555m total, ~270 sec/km pace.
List<LocationPointEntity> _runPts() => List.generate(
      6, (i) => _pt(lat: i * 0.001, timestampMs: i * 30000),
    );

void main() {
  group('RecoverActiveSession', () {
    test('returns null when no active sessions exist', () async {
      final r = await RecoverActiveSession(
        sessionRepo: _FakeSR(), pointsRepo: _FakePR(),
      )();
      expect(r, isNull);
    });

    test('returns null when only completed sessions exist', () async {
      final r = await RecoverActiveSession(
        sessionRepo: _FakeSR({
          WorkoutStatus.completed: [_ses(status: WorkoutStatus.completed)],
        }),
        pointsRepo: _FakePR(),
      )();
      expect(r, isNull);
    });

    test('recovers RUNNING session with route populated', () async {
      final r = await RecoverActiveSession(
        sessionRepo: _FakeSR({
          WorkoutStatus.running: [_ses(id: 'r1', startTimeMs: 1000)],
        }),
        pointsRepo: _FakePR({
          'r1': [_pt(lat: 0.0, timestampMs: 1000), _pt(lat: 0.001, timestampMs: 31000)],
        }),
      )();
      expect(r, isNotNull);
      expect(r!.session.id, 'r1');
      expect(r.session.status, WorkoutStatus.running);
      expect(r.rawPoints, hasLength(2));
      expect(r.session.route, hasLength(2));
    });

    test('recovers PAUSED when no RUNNING, prioritizes RUNNING', () async {
      // PAUSED only
      var r = await RecoverActiveSession(
        sessionRepo: _FakeSR({
          WorkoutStatus.paused: [_ses(id: 'p1', status: WorkoutStatus.paused)],
        }),
        pointsRepo: _FakePR({'p1': [_pt(lat: 0.0, timestampMs: 0)]}),
      )();
      expect(r!.session.status, WorkoutStatus.paused);

      // RUNNING + PAUSED → RUNNING wins
      r = await RecoverActiveSession(
        sessionRepo: _FakeSR({
          WorkoutStatus.running: [_ses(id: 'r1', startTimeMs: 2000)],
          WorkoutStatus.paused: [_ses(id: 'p1', status: WorkoutStatus.paused)],
        }),
        pointsRepo: _FakePR({
          'r1': [_pt(lat: 0.0, timestampMs: 2000)],
          'p1': [_pt(lat: 0.0, timestampMs: 0)],
        }),
      )();
      expect(r!.session.id, 'r1');
    });

    test('recalculates distance and pace from recovered points', () async {
      final r = await RecoverActiveSession(
        sessionRepo: _FakeSR({
          WorkoutStatus.running: [_ses(id: 'r1')],
        }),
        pointsRepo: _FakePR({'r1': _runPts()}),
      )();
      expect(r!.metrics.totalDistanceM, closeTo(555, 10));
      expect(r.metrics.currentPaceSecPerKm, isNotNull);
      expect(r.metrics.currentPaceSecPerKm, closeTo(270, 5));
      expect(r.metrics.pointsCount, 6);
    });

    test('recovers session with zero points', () async {
      final r = await RecoverActiveSession(
        sessionRepo: _FakeSR({
          WorkoutStatus.running: [_ses(id: 'r1', startTimeMs: 1000)],
        }),
        pointsRepo: _FakePR(),
      )();
      expect(r, isNotNull);
      expect(r!.rawPoints, isEmpty);
      expect(r.metrics.totalDistanceM, 0.0);
      expect(r.metrics.currentPaceSecPerKm, isNull);
      expect(r.metrics.pointsCount, 0);
    });

    test('filtered points exclude bad accuracy', () async {
      final r = await RecoverActiveSession(
        sessionRepo: _FakeSR({
          WorkoutStatus.running: [_ses(id: 'r1')],
        }),
        pointsRepo: _FakePR({
          'r1': [
            _pt(lat: 0.0, accuracy: 5.0, timestampMs: 0),
            _pt(lat: 0.001, accuracy: 50.0, timestampMs: 30000),
            _pt(lat: 0.002, accuracy: 5.0, timestampMs: 60000),
          ],
        }),
      )();
      expect(r!.rawPoints, hasLength(3));
      expect(r.filteredPoints, hasLength(2));
    });

    test('moving time calculated from consecutive point gaps', () async {
      final r = await RecoverActiveSession(
        sessionRepo: _FakeSR({
          WorkoutStatus.running: [_ses(id: 'r1')],
        }),
        pointsRepo: _FakePR({
          'r1': [
            _pt(lat: 0.0, timestampMs: 0),
            _pt(lat: 0.001, timestampMs: 10000),
            _pt(lat: 0.002, timestampMs: 20000),
            _pt(lat: 0.003, timestampMs: 30000),
          ],
        }),
      )();
      expect(r!.metrics.movingMs, 30000);
    });
  });
}
