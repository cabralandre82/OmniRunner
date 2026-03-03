import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/entities/training_attendance_entity.dart';
import 'package:omni_runner/domain/entities/training_session_entity.dart';

sealed class TrainingDetailState extends Equatable {
  const TrainingDetailState();

  @override
  List<Object?> get props => [];
}

final class TrainingDetailInitial extends TrainingDetailState {
  const TrainingDetailInitial();
}

final class TrainingDetailLoading extends TrainingDetailState {
  const TrainingDetailLoading();
}

final class TrainingDetailLoaded extends TrainingDetailState {
  final TrainingSessionEntity session;
  final List<TrainingAttendanceEntity> attendance;
  final int attendanceCount;

  const TrainingDetailLoaded({
    required this.session,
    required this.attendance,
    required this.attendanceCount,
  });

  @override
  List<Object?> get props => [session, attendance, attendanceCount];
}

final class TrainingDetailError extends TrainingDetailState {
  final String message;

  const TrainingDetailError(this.message);

  @override
  List<Object?> get props => [message];
}
