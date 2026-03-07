import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';
import 'package:omni_runner/domain/repositories/i_points_repo.dart';
import 'package:omni_runner/domain/repositories/i_session_repo.dart';
import 'package:omni_runner/domain/usecases/discard_session.dart';

// ── Fakes ──

final class _FakeSR implements ISessionRepo {
  final Map<String, WorkoutSessionEntity> _store = {};
  final List<String> deletedIds = [];

  _FakeSR([List<WorkoutSessionEntity>? sessions]) {
    for (final s in sessions ?? <WorkoutSessionEntity>[]) {
      _store[s.id] = s;
    }
  }

  @override
  Future<WorkoutSessionEntity?> getById(String id) async => _store[id];
  @override
  Future<void> deleteById(String id) async {
    _store.remove(id);
    deletedIds.add(id);
  }
  @override
  Future<void> save(WorkoutSessionEntity session) async {
    _store[session.id] = session;
  }
  @override
  Future<List<WorkoutSessionEntity>> getAll() async =>
      _store.values.toList();
  @override
  Future<List<WorkoutSessionEntity>> getByStatus(WorkoutStatus status) async =>
      _store.values.where((s) => s.status == status).toList();
  @override
  Future<bool> updateStatus(String id, WorkoutStatus status) async => false;
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

  bool contains(String id) => _store.containsKey(id);
}

final class _FakePR implements IPointsRepo {
  final Map<String, List<LocationPointEntity>> _store = {};
  final List<String> deletedSessionIds = [];

  _FakePR([Map<String, List<LocationPointEntity>>? pts]) {
    if (pts != null) _store.addAll(pts);
  }

  @override
  Future<void> deleteBySessionId(String id) async {
    _store.remove(id);
    deletedSessionIds.add(id);
  }
  @override
  Future<List<LocationPointEntity>> getBySessionId(String id) async =>
      _store[id] ?? [];
  @override
  Future<void> savePoint(String id, LocationPointEntity pt) async {}
  @override
  Future<void> savePoints(String id, List<LocationPointEntity> pts) async {}
  @override
  Future<int> countBySessionId(String id) async => _store[id]?.length ?? 0;

  bool containsSession(String id) => _store.containsKey(id);
}

// ── Helpers ──

WorkoutSessionEntity _ses({
  String id = 's1', WorkoutStatus status = WorkoutStatus.running,
}) => WorkoutSessionEntity(
      id: id, status: status, startTimeMs: 1000, route: const [],
    );

LocationPointEntity _pt(int ts) =>
    LocationPointEntity(lat: 0.0, lng: 0.0, timestampMs: ts);

void main() {
  group('DiscardSession', () {
    test('returns false when session does not exist', () async {
      final sr = _FakeSR();
      final pr = _FakePR();
      final uc = DiscardSession(sessionRepo: sr, pointsRepo: pr);

      expect(await uc('nonexistent'), isFalse);
      expect(sr.deletedIds, isEmpty);
      expect(pr.deletedSessionIds, isEmpty);
    });

    test('returns true and deletes session + points', () async {
      final sr = _FakeSR([_ses(id: 'r1')]);
      final pr = _FakePR({'r1': [_pt(1000), _pt(2000)]});
      final uc = DiscardSession(sessionRepo: sr, pointsRepo: pr);

      expect(await uc('r1'), isTrue);
      expect(sr.contains('r1'), isFalse);
      expect(pr.containsSession('r1'), isFalse);
    });

    test('deletes points before session (children first)', () async {
      final sr = _FakeSR([_ses(id: 'r1')]);
      final pr = _FakePR({'r1': [_pt(1000)]});
      final uc = DiscardSession(sessionRepo: sr, pointsRepo: pr);

      await uc('r1');

      expect(pr.deletedSessionIds, ['r1']);
      expect(sr.deletedIds, ['r1']);
    });

    test('deletes session even with zero points', () async {
      final sr = _FakeSR([_ses(id: 'e1')]);
      final pr = _FakePR();
      final uc = DiscardSession(sessionRepo: sr, pointsRepo: pr);

      expect(await uc('e1'), isTrue);
      expect(sr.contains('e1'), isFalse);
    });

    test('handles session with many points', () async {
      final pts = List.generate(1000, (i) => _pt(i * 1000));
      final sr = _FakeSR([_ses(id: 'big')]);
      final pr = _FakePR({'big': pts});
      final uc = DiscardSession(sessionRepo: sr, pointsRepo: pr);

      expect(await uc('big'), isTrue);
      expect(pr.containsSession('big'), isFalse);
    });

    test('does not affect other sessions', () async {
      final sr = _FakeSR([_ses(id: 'keep'), _ses(id: 'del')]);
      final pr = _FakePR({
        'keep': [_pt(1000)],
        'del': [_pt(2000)],
      });
      final uc = DiscardSession(sessionRepo: sr, pointsRepo: pr);

      await uc('del');

      expect(sr.contains('keep'), isTrue);
      expect(sr.contains('del'), isFalse);
      expect(pr.containsSession('keep'), isTrue);
      expect(pr.containsSession('del'), isFalse);
    });

    test('works with any session status', () async {
      for (final status in WorkoutStatus.values) {
        final id = 'test-${status.name}';
        final sr = _FakeSR([_ses(id: id, status: status)]);
        final pr = _FakePR({id: [_pt(1000)]});
        final uc = DiscardSession(sessionRepo: sr, pointsRepo: pr);

        expect(await uc(id), isTrue, reason: 'Failed for ${status.name}');
      }
    });
  });
}
