import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/training_session_entity.dart';
import 'package:omni_runner/domain/entities/training_attendance_entity.dart';

void main() {
  group('TrainingSessionEntity', () {
    final now = DateTime(2026, 4, 1, 8, 0);

    TrainingSessionEntity baseSession() => TrainingSessionEntity(
          id: 's1',
          groupId: 'g1',
          createdBy: 'c1',
          title: 'Treino 5km',
          startsAt: now,
          createdAt: now,
          updatedAt: now,
          distanceTargetM: 5000,
          paceMinSecKm: 270,
          paceMaxSecKm: 360,
        );

    test('stores workout params', () {
      final s = baseSession();
      expect(s.distanceTargetM, 5000);
      expect(s.paceMinSecKm, 270);
      expect(s.paceMaxSecKm, 360);
    });

    test('copyWith preserves workout params when not overridden', () {
      final s = baseSession();
      final copy = s.copyWith(title: 'Novo titulo');
      expect(copy.title, 'Novo titulo');
      expect(copy.distanceTargetM, 5000);
      expect(copy.paceMinSecKm, 270);
      expect(copy.paceMaxSecKm, 360);
    });

    test('copyWith overrides workout params', () {
      final s = baseSession();
      final copy = s.copyWith(distanceTargetM: 10000, paceMinSecKm: 300);
      expect(copy.distanceTargetM, 10000);
      expect(copy.paceMinSecKm, 300);
      expect(copy.paceMaxSecKm, 360);
    });

    test('workout params included in props for equality', () {
      final s1 = baseSession();
      final s2 = baseSession();
      expect(s1, equals(s2));

      final s3 = s1.copyWith(distanceTargetM: 8000);
      expect(s1, isNot(equals(s3)));
    });

    test('null workout params by default', () {
      final s = TrainingSessionEntity(
        id: 's2',
        groupId: 'g1',
        createdBy: 'c1',
        title: 'Livre',
        startsAt: now,
        createdAt: now,
        updatedAt: now,
      );
      expect(s.distanceTargetM, isNull);
      expect(s.paceMinSecKm, isNull);
      expect(s.paceMaxSecKm, isNull);
    });
  });

  group('TrainingSessionStatus', () {
    test('fromString parses all values', () {
      expect(trainingStatusFromString('scheduled'), TrainingSessionStatus.scheduled);
      expect(trainingStatusFromString('cancelled'), TrainingSessionStatus.cancelled);
      expect(trainingStatusFromString('done'), TrainingSessionStatus.done);
    });

    test('fromString defaults to scheduled for unknown', () {
      expect(trainingStatusFromString('invalid'), TrainingSessionStatus.scheduled);
    });

    test('toString round-trips all values', () {
      for (final s in TrainingSessionStatus.values) {
        expect(trainingStatusFromString(trainingStatusToString(s)), s);
      }
    });
  });

  group('AttendanceStatus', () {
    test('fromString parses all values including new ones', () {
      expect(attendanceStatusFromString('present'), AttendanceStatus.present);
      expect(attendanceStatusFromString('late'), AttendanceStatus.late_);
      expect(attendanceStatusFromString('excused'), AttendanceStatus.excused);
      expect(attendanceStatusFromString('absent'), AttendanceStatus.absent);
      expect(attendanceStatusFromString('completed'), AttendanceStatus.completed);
      expect(attendanceStatusFromString('partial'), AttendanceStatus.partial);
    });

    test('fromString defaults to present for unknown', () {
      expect(attendanceStatusFromString('xxx'), AttendanceStatus.present);
    });

    test('toString round-trips all values', () {
      for (final s in AttendanceStatus.values) {
        expect(attendanceStatusFromString(attendanceStatusToString(s)), s);
      }
    });

    test('label returns correct Portuguese labels', () {
      expect(attendanceStatusLabel(AttendanceStatus.present), 'Presente');
      expect(attendanceStatusLabel(AttendanceStatus.late_), 'Atrasado');
      expect(attendanceStatusLabel(AttendanceStatus.excused), 'Justificado');
      expect(attendanceStatusLabel(AttendanceStatus.absent), 'Ausente');
      expect(attendanceStatusLabel(AttendanceStatus.completed), 'Concluído');
      expect(attendanceStatusLabel(AttendanceStatus.partial), 'Parcial');
    });
  });

  group('CheckinMethod', () {
    test('enum has auto value', () {
      expect(CheckinMethod.values, contains(CheckinMethod.auto));
      expect(CheckinMethod.values, contains(CheckinMethod.qr));
      expect(CheckinMethod.values, contains(CheckinMethod.manual));
    });
  });

  group('TrainingAttendanceEntity', () {
    final now = DateTime(2026, 4, 1, 9, 0);

    test('supports nullable checkedBy for auto method', () {
      final att = TrainingAttendanceEntity(
        id: 'a1',
        groupId: 'g1',
        sessionId: 's1',
        athleteUserId: 'u1',
        checkedBy: null,
        checkedAt: now,
        status: AttendanceStatus.completed,
        method: CheckinMethod.auto,
        matchedRunId: 'run-1',
      );

      expect(att.checkedBy, isNull);
      expect(att.method, CheckinMethod.auto);
      expect(att.status, AttendanceStatus.completed);
      expect(att.matchedRunId, 'run-1');
    });

    test('matchedRunId included in props', () {
      final a1 = TrainingAttendanceEntity(
        id: 'a1',
        groupId: 'g1',
        sessionId: 's1',
        athleteUserId: 'u1',
        checkedAt: now,
        status: AttendanceStatus.completed,
        method: CheckinMethod.auto,
        matchedRunId: 'run-1',
      );
      final a2 = TrainingAttendanceEntity(
        id: 'a1',
        groupId: 'g1',
        sessionId: 's1',
        athleteUserId: 'u1',
        checkedAt: now,
        status: AttendanceStatus.completed,
        method: CheckinMethod.auto,
        matchedRunId: 'run-2',
      );
      expect(a1, isNot(equals(a2)));
    });

    test('partial status supported', () {
      final att = TrainingAttendanceEntity(
        id: 'a2',
        groupId: 'g1',
        sessionId: 's1',
        athleteUserId: 'u1',
        checkedAt: now,
        status: AttendanceStatus.partial,
        method: CheckinMethod.auto,
      );
      expect(att.status, AttendanceStatus.partial);
    });

    test('absent status supported', () {
      final att = TrainingAttendanceEntity(
        id: 'a3',
        groupId: 'g1',
        sessionId: 's1',
        athleteUserId: 'u1',
        checkedAt: now,
        status: AttendanceStatus.absent,
        method: CheckinMethod.auto,
      );
      expect(att.status, AttendanceStatus.absent);
    });
  });
}
