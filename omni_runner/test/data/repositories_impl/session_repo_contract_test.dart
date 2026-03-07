import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';
import 'package:omni_runner/domain/repositories/i_session_repo.dart';

final class InMemorySessionRepo implements ISessionRepo {
  final _store = <String, WorkoutSessionEntity>{};

  @override
  Future<void> save(WorkoutSessionEntity session) async {
    _store[session.id] = session;
  }

  @override
  Future<WorkoutSessionEntity?> getById(String id) async => _store[id];

  @override
  Future<List<WorkoutSessionEntity>> getAll() async {
    final list = _store.values.toList()
      ..sort((a, b) => b.startTimeMs.compareTo(a.startTimeMs));
    return list;
  }

  @override
  Future<List<WorkoutSessionEntity>> getByStatus(WorkoutStatus status) async {
    return _store.values
        .where((s) => s.status == status)
        .toList()
      ..sort((a, b) => b.startTimeMs.compareTo(a.startTimeMs));
  }

  @override
  Future<void> deleteById(String id) async {
    _store.remove(id);
  }

  @override
  Future<bool> updateStatus(String id, WorkoutStatus status) async {
    final s = _store[id];
    if (s == null) return false;
    _store[id] = WorkoutSessionEntity(
      id: s.id,
      userId: s.userId,
      status: status,
      startTimeMs: s.startTimeMs,
      endTimeMs: s.endTimeMs,
      totalDistanceM: s.totalDistanceM,
      route: s.route,
      ghostSessionId: s.ghostSessionId,
      isVerified: s.isVerified,
      integrityFlags: s.integrityFlags,
      isSynced: s.isSynced,
      avgBpm: s.avgBpm,
      maxBpm: s.maxBpm,
    );
    return true;
  }

  @override
  Future<bool> updateMetrics({
    required String id,
    required double totalDistanceM,
    required int movingMs,
    int? endTimeMs,
  }) async {
    final s = _store[id];
    if (s == null) return false;
    _store[id] = WorkoutSessionEntity(
      id: s.id,
      userId: s.userId,
      status: s.status,
      startTimeMs: s.startTimeMs,
      endTimeMs: endTimeMs ?? s.endTimeMs,
      totalDistanceM: totalDistanceM,
      route: s.route,
      isVerified: s.isVerified,
      integrityFlags: s.integrityFlags,
      isSynced: s.isSynced,
    );
    return true;
  }

  @override
  Future<bool> updateGhostSessionId(String id, String ghostSessionId) async {
    final s = _store[id];
    if (s == null) return false;
    _store[id] = WorkoutSessionEntity(
      id: s.id,
      userId: s.userId,
      status: s.status,
      startTimeMs: s.startTimeMs,
      endTimeMs: s.endTimeMs,
      totalDistanceM: s.totalDistanceM,
      route: s.route,
      ghostSessionId: ghostSessionId,
      isVerified: s.isVerified,
      integrityFlags: s.integrityFlags,
      isSynced: s.isSynced,
    );
    return true;
  }

  @override
  Future<bool> updateIntegrityFlags(
    String id, {
    required bool isVerified,
    required List<String> flags,
  }) async {
    final s = _store[id];
    if (s == null) return false;
    _store[id] = WorkoutSessionEntity(
      id: s.id,
      userId: s.userId,
      status: s.status,
      startTimeMs: s.startTimeMs,
      endTimeMs: s.endTimeMs,
      totalDistanceM: s.totalDistanceM,
      route: s.route,
      isVerified: isVerified,
      integrityFlags: flags,
      isSynced: s.isSynced,
    );
    return true;
  }

  @override
  Future<bool> updateHrMetrics(
    String id, {
    required int avgBpm,
    required int maxBpm,
  }) async {
    final s = _store[id];
    if (s == null) return false;
    _store[id] = WorkoutSessionEntity(
      id: s.id,
      userId: s.userId,
      status: s.status,
      startTimeMs: s.startTimeMs,
      endTimeMs: s.endTimeMs,
      totalDistanceM: s.totalDistanceM,
      route: s.route,
      isVerified: s.isVerified,
      integrityFlags: s.integrityFlags,
      isSynced: s.isSynced,
      avgBpm: avgBpm,
      maxBpm: maxBpm,
    );
    return true;
  }

  @override
  Future<List<WorkoutSessionEntity>> getUnsyncedCompleted() async {
    return _store.values
        .where((s) => s.status == WorkoutStatus.completed && !s.isSynced)
        .toList();
  }

  @override
  Future<void> markSynced(String id) async {
    final s = _store[id];
    if (s == null) return;
    _store[id] = WorkoutSessionEntity(
      id: s.id,
      userId: s.userId,
      status: s.status,
      startTimeMs: s.startTimeMs,
      endTimeMs: s.endTimeMs,
      totalDistanceM: s.totalDistanceM,
      route: s.route,
      ghostSessionId: s.ghostSessionId,
      isVerified: s.isVerified,
      integrityFlags: s.integrityFlags,
      isSynced: true,
      avgBpm: s.avgBpm,
      maxBpm: s.maxBpm,
    );
  }
}

WorkoutSessionEntity _session({
  String id = 's1',
  WorkoutStatus status = WorkoutStatus.running,
  int startTimeMs = 1000,
}) =>
    WorkoutSessionEntity(
      id: id,
      userId: 'user1',
      status: status,
      startTimeMs: startTimeMs,
      route: const [],
    );

void main() {
  late InMemorySessionRepo repo;

  setUp(() => repo = InMemorySessionRepo());

  group('ISessionRepo contract', () {
    test('save and getById round-trip', () async {
      final s = _session();
      await repo.save(s);
      final found = await repo.getById('s1');
      expect(found, equals(s));
    });

    test('getById returns null for missing id', () async {
      expect(await repo.getById('nope'), isNull);
    });

    test('getAll returns sessions ordered newest first', () async {
      await repo.save(_session(id: 'a', startTimeMs: 100));
      await repo.save(_session(id: 'b', startTimeMs: 300));
      await repo.save(_session(id: 'c', startTimeMs: 200));

      final all = await repo.getAll();
      expect(all.map((s) => s.id).toList(), ['b', 'c', 'a']);
    });

    test('getByStatus filters correctly', () async {
      await repo.save(_session(id: 'r1', status: WorkoutStatus.running));
      await repo.save(_session(id: 'c1', status: WorkoutStatus.completed));
      await repo.save(_session(id: 'r2', status: WorkoutStatus.running));

      final running = await repo.getByStatus(WorkoutStatus.running);
      expect(running.length, 2);
      expect(running.every((s) => s.status == WorkoutStatus.running), isTrue);

      final completed = await repo.getByStatus(WorkoutStatus.completed);
      expect(completed.length, 1);
    });

    test('deleteById removes session', () async {
      await repo.save(_session());
      await repo.deleteById('s1');
      expect(await repo.getById('s1'), isNull);
    });

    test('deleteById is no-op for missing id', () async {
      await repo.deleteById('nope');
      expect(await repo.getAll(), isEmpty);
    });

    test('updateStatus changes status and returns true', () async {
      await repo.save(_session(status: WorkoutStatus.running));
      final ok = await repo.updateStatus('s1', WorkoutStatus.completed);
      expect(ok, isTrue);

      final s = await repo.getById('s1');
      expect(s!.status, WorkoutStatus.completed);
    });

    test('updateStatus returns false for missing session', () async {
      final ok = await repo.updateStatus('nope', WorkoutStatus.completed);
      expect(ok, isFalse);
    });

    test('updateMetrics updates distance and moving time', () async {
      await repo.save(_session());
      final ok = await repo.updateMetrics(
        id: 's1',
        totalDistanceM: 5000.0,
        movingMs: 1800000,
        endTimeMs: 9999,
      );
      expect(ok, isTrue);

      final s = await repo.getById('s1');
      expect(s!.totalDistanceM, 5000.0);
      expect(s.endTimeMs, 9999);
    });

    test('updateGhostSessionId stores ghost reference', () async {
      await repo.save(_session());
      await repo.updateGhostSessionId('s1', 'ghost-42');

      final s = await repo.getById('s1');
      expect(s!.ghostSessionId, 'ghost-42');
    });

    test('updateIntegrityFlags stores verification result', () async {
      await repo.save(_session());
      await repo.updateIntegrityFlags(
        's1',
        isVerified: false,
        flags: ['SPEED_EXCEEDED', 'TELEPORT_DETECTED'],
      );

      final s = await repo.getById('s1');
      expect(s!.isVerified, isFalse);
      expect(s.integrityFlags, ['SPEED_EXCEEDED', 'TELEPORT_DETECTED']);
    });

    test('updateHrMetrics stores HR data', () async {
      await repo.save(_session());
      await repo.updateHrMetrics('s1', avgBpm: 155, maxBpm: 185);

      final s = await repo.getById('s1');
      expect(s!.avgBpm, 155);
      expect(s.maxBpm, 185);
    });

    test('save overwrites existing session with same id', () async {
      await repo.save(_session(status: WorkoutStatus.running));
      await repo.save(_session(status: WorkoutStatus.completed));

      final all = await repo.getAll();
      expect(all.length, 1);
      expect(all.first.status, WorkoutStatus.completed);
    });
  });
}
