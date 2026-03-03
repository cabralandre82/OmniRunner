import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/training_attendance_entity.dart';
import 'package:omni_runner/domain/repositories/i_training_attendance_repo.dart';
import 'package:omni_runner/domain/usecases/training/mark_attendance.dart';

class _FakeAttendanceRepo implements ITrainingAttendanceRepo {
  final Set<String> _marked = {};
  String? lastSessionId;
  String? lastAthleteUserId;
  String? lastNonce;

  @override
  Future<MarkAttendanceResult> markAttendance({
    required String sessionId,
    required String athleteUserId,
    String? nonce,
  }) async {
    lastSessionId = sessionId;
    lastAthleteUserId = athleteUserId;
    lastNonce = nonce;
    final key = '$sessionId:$athleteUserId';
    if (_marked.contains(key)) {
      return const AttendanceAlreadyPresent();
    }
    _marked.add(key);
    return AttendanceInserted('att-${_marked.length}');
  }

  @override
  Future<CheckinToken> issueCheckinToken({
    required String sessionId,
    int ttlSeconds = 120,
  }) async =>
      CheckinToken(
        sessionId: sessionId,
        athleteUserId: 'a',
        groupId: 'g',
        nonce: 'n',
        expiresAtMs: DateTime.now().millisecondsSinceEpoch + ttlSeconds * 1000,
      );

  @override
  Future<List<TrainingAttendanceEntity>> listBySession(
          String sessionId) async =>
      [];
  @override
  Future<List<TrainingAttendanceEntity>> listByAthlete({
    required String groupId,
    required String athleteUserId,
    int limit = 50,
    int offset = 0,
  }) async =>
      [];
  @override
  Future<int> countBySession(String sessionId) async => 0;
}

void main() {
  late _FakeAttendanceRepo repo;
  late MarkAttendance usecase;

  setUp(() {
    repo = _FakeAttendanceRepo();
    usecase = MarkAttendance(repo: repo);
  });

  test('marks attendance and returns inserted result', () async {
    final result = await usecase.call(
      sessionId: 'sess-1',
      athleteUserId: 'athlete-1',
    );

    expect(result, isA<AttendanceInserted>());
    expect((result as AttendanceInserted).attendanceId, 'att-1');
    expect(repo.lastSessionId, 'sess-1');
    expect(repo.lastAthleteUserId, 'athlete-1');
  });

  test('returns already present for duplicate attendance', () async {
    await usecase.call(sessionId: 'sess-1', athleteUserId: 'athlete-1');
    final result = await usecase.call(
      sessionId: 'sess-1',
      athleteUserId: 'athlete-1',
    );

    expect(result, isA<AttendanceAlreadyPresent>());
  });

  test('passes nonce to repo', () async {
    await usecase.call(
      sessionId: 'sess-1',
      athleteUserId: 'athlete-1',
      nonce: 'token-abc',
    );

    expect(repo.lastNonce, 'token-abc');
  });

  test('different athletes can mark same session', () async {
    final r1 = await usecase.call(
        sessionId: 'sess-1', athleteUserId: 'athlete-1');
    final r2 = await usecase.call(
        sessionId: 'sess-1', athleteUserId: 'athlete-2');

    expect(r1, isA<AttendanceInserted>());
    expect(r2, isA<AttendanceInserted>());
  });
}
