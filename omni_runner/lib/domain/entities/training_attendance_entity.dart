import 'package:equatable/equatable.dart';

enum AttendanceStatus { present, late_, excused, absent }

AttendanceStatus attendanceStatusFromString(String value) => switch (value) {
      'present' => AttendanceStatus.present,
      'late' => AttendanceStatus.late_,
      'excused' => AttendanceStatus.excused,
      'absent' => AttendanceStatus.absent,
      _ => AttendanceStatus.present,
    };

String attendanceStatusToString(AttendanceStatus s) => switch (s) {
      AttendanceStatus.present => 'present',
      AttendanceStatus.late_ => 'late',
      AttendanceStatus.excused => 'excused',
      AttendanceStatus.absent => 'absent',
    };

enum CheckinMethod { qr, manual }

final class TrainingAttendanceEntity extends Equatable {
  final String id;
  final String groupId;
  final String sessionId;
  final String athleteUserId;
  final String checkedBy;
  final DateTime checkedAt;
  final AttendanceStatus status;
  final CheckinMethod method;

  /// Display name, populated from joins (not stored in attendance table).
  final String? athleteDisplayName;

  /// Session title, populated from joins when listing by athlete.
  final String? sessionTitle;

  /// Session start time, populated from joins when listing by athlete.
  final DateTime? sessionStartsAt;

  const TrainingAttendanceEntity({
    required this.id,
    required this.groupId,
    required this.sessionId,
    required this.athleteUserId,
    required this.checkedBy,
    required this.checkedAt,
    this.status = AttendanceStatus.present,
    this.method = CheckinMethod.qr,
    this.athleteDisplayName,
    this.sessionTitle,
    this.sessionStartsAt,
  });

  @override
  List<Object?> get props => [
        id, groupId, sessionId, athleteUserId,
        checkedBy, checkedAt, status, method,
      ];
}
