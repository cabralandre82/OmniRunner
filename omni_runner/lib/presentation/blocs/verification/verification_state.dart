import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/entities/athlete_verification_entity.dart';

sealed class VerificationState extends Equatable {
  const VerificationState();

  @override
  List<Object?> get props => [];
}

final class VerificationInitial extends VerificationState {
  const VerificationInitial();
}

final class VerificationLoading extends VerificationState {
  const VerificationLoading();
}

final class VerificationLoaded extends VerificationState {
  final AthleteVerificationEntity verification;

  const VerificationLoaded(this.verification);

  @override
  List<Object?> get props => [verification];
}

/// Evaluation is in progress (triggered by user tap on "Reavaliar").
final class VerificationEvaluating extends VerificationState {
  final AthleteVerificationEntity? previous;

  const VerificationEvaluating({this.previous});

  @override
  List<Object?> get props => [previous];
}

final class VerificationError extends VerificationState {
  final String message;

  const VerificationError(this.message);

  @override
  List<Object?> get props => [message];
}
