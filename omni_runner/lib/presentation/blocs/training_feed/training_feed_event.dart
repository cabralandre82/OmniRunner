import 'package:equatable/equatable.dart';

abstract class TrainingFeedEvent extends Equatable {
  const TrainingFeedEvent();
  @override
  List<Object?> get props => [];
}

class LoadTrainingFeed extends TrainingFeedEvent {
  const LoadTrainingFeed({this.focusDate});
  final DateTime? focusDate;
  @override
  List<Object?> get props => [focusDate];
}

class RefreshTrainingFeed extends TrainingFeedEvent {
  const RefreshTrainingFeed();
}

class SyncTrainingFeed extends TrainingFeedEvent {
  const SyncTrainingFeed();
}

class SelectFeedDate extends TrainingFeedEvent {
  const SelectFeedDate(this.date);
  final DateTime date;
  @override
  List<Object?> get props => [date];
}
