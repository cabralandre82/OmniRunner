import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/entities/plan_workout_entity.dart';

abstract class TrainingFeedState extends Equatable {
  const TrainingFeedState();
  @override
  List<Object?> get props => [];
}

class TrainingFeedInitial extends TrainingFeedState {
  const TrainingFeedInitial();
}

class TrainingFeedLoading extends TrainingFeedState {
  const TrainingFeedLoading();
}

class TrainingFeedLoaded extends TrainingFeedState {
  const TrainingFeedLoaded({
    required this.workoutsByDate,
    required this.selectedDate,
    this.isSyncing = false,
    this.lastSyncAt,
  });

  final Map<String, List<PlanWorkoutEntity>> workoutsByDate;
  final DateTime selectedDate;
  final bool isSyncing;
  final DateTime? lastSyncAt;

  List<PlanWorkoutEntity> get workoutsForSelectedDate =>
      workoutsByDate[_dateKey(selectedDate)] ?? [];

  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  TrainingFeedLoaded copyWith({
    Map<String, List<PlanWorkoutEntity>>? workoutsByDate,
    DateTime? selectedDate,
    bool? isSyncing,
    DateTime? lastSyncAt,
  }) =>
      TrainingFeedLoaded(
        workoutsByDate: workoutsByDate ?? this.workoutsByDate,
        selectedDate:   selectedDate   ?? this.selectedDate,
        isSyncing:      isSyncing      ?? this.isSyncing,
        lastSyncAt:     lastSyncAt     ?? this.lastSyncAt,
      );

  @override
  List<Object?> get props => [workoutsByDate, selectedDate, isSyncing, lastSyncAt];
}

class TrainingFeedError extends TrainingFeedState {
  const TrainingFeedError(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}
