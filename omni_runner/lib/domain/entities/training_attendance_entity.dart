import 'package:equatable/equatable.dart';

enum AttendanceStatus { present, late_, excused, absent, completed, partial }

AttendanceStatus attendanceStatusFromString(String value) => switch (value) {
      'present' => AttendanceStatus.present,
      'late' => AttendanceStatus.late_,
      'excused' => AttendanceStatus.excused,
      'absent' => AttendanceStatus.absent,
      'completed' => AttendanceStatus.completed,
      'partial' => AttendanceStatus.partial,
      _ => AttendanceStatus.present,
    };

String attendanceStatusToString(AttendanceStatus s) => switch (s) {
      AttendanceStatus.present => 'present',
      AttendanceStatus.late_ => 'late',
      AttendanceStatus.excused => 'excused',
      AttendanceStatus.absent => 'absent',
      AttendanceStatus.completed => 'completed',
      AttendanceStatus.partial => 'partial',
    };

String attendanceStatusLabel(AttendanceStatus s) => switch (s) {
      AttendanceStatus.present => 'Presente',
      AttendanceStatus.late_ => 'Atrasado',
      AttendanceStatus.excused => 'Justificado',
      AttendanceStatus.absent => 'Ausente',
      AttendanceStatus.completed => 'Concluído',
      AttendanceStatus.partial => 'Parcial',
    };

enum CheckinMethod { qr, manual, auto }

final class TrainingAttendanceEntity extends Equatable {
  final String id;
  final String groupId;
  final String sessionId;
  final String athleteUserId;
  final String? checkedBy;
  final DateTime checkedAt;
  final AttendanceStatus status;
  final CheckinMethod method;
  final String? matchedRunId;

  final String? athleteDisplayName;
  final String? sessionTitle;
  final DateTime? sessionStartsAt;

  const TrainingAttendanceEntity({
    required this.id,
    required this.groupId,
    required this.sessionId,
    required this.athleteUserId,
    this.checkedBy,
    required this.checkedAt,
    this.status = AttendanceStatus.present,
    this.method = CheckinMethod.qr,
    this.matchedRunId,
    this.athleteDisplayName,
    this.sessionTitle,
    this.sessionStartsAt,
  });

  @override
  List<Object?> get props => [
        id, groupId, sessionId, athleteUserId,
        checkedBy, checkedAt, status, method, matchedRunId,
      ];
}
