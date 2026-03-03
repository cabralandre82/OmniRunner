import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/repositories/i_training_attendance_repo.dart';

sealed class CheckinState extends Equatable {
  const CheckinState();

  @override
  List<Object?> get props => [];
}

final class CheckinInitial extends CheckinState {
  const CheckinInitial();
}

final class CheckinGenerating extends CheckinState {
  const CheckinGenerating();
}

final class CheckinQrReady extends CheckinState {
  final CheckinToken token;
  final String encodedPayload;

  const CheckinQrReady({
    required this.token,
    required this.encodedPayload,
  });

  @override
  List<Object?> get props => [token, encodedPayload];
}

final class CheckinConsuming extends CheckinState {
  const CheckinConsuming();
}

final class CheckinSuccess extends CheckinState {
  final String status;

  const CheckinSuccess({required this.status});

  @override
  List<Object?> get props => [status];
}

final class CheckinError extends CheckinState {
  final String message;

  const CheckinError(this.message);

  @override
  List<Object?> get props => [message];
}
