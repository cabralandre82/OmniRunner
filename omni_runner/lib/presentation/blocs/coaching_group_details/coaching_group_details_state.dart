import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/usecases/coaching/get_coaching_group_details.dart';

sealed class CoachingGroupDetailsState extends Equatable {
  const CoachingGroupDetailsState();

  @override
  List<Object?> get props => [];
}

final class CoachingGroupDetailsInitial extends CoachingGroupDetailsState {
  const CoachingGroupDetailsInitial();
}

final class CoachingGroupDetailsLoading extends CoachingGroupDetailsState {
  const CoachingGroupDetailsLoading();
}

final class CoachingGroupDetailsLoaded extends CoachingGroupDetailsState {
  final CoachingGroupDetails details;
  final String callerUserId;

  const CoachingGroupDetailsLoaded({
    required this.details,
    required this.callerUserId,
  });

  @override
  List<Object?> get props => [details, callerUserId];
}

final class CoachingGroupDetailsError extends CoachingGroupDetailsState {
  final String message;
  const CoachingGroupDetailsError(this.message);

  @override
  List<Object?> get props => [message];
}
