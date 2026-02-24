import 'package:equatable/equatable.dart';

sealed class VerificationEvent extends Equatable {
  const VerificationEvent();

  @override
  List<Object?> get props => [];
}

/// Load current verification state from server RPC.
final class LoadVerificationState extends VerificationEvent {
  const LoadVerificationState();
}

/// Trigger server-side re-evaluation via Edge Function.
final class RequestEvaluation extends VerificationEvent {
  const RequestEvaluation();
}
