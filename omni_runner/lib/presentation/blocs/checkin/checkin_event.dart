import 'package:equatable/equatable.dart';

sealed class CheckinEvent extends Equatable {
  const CheckinEvent();

  @override
  List<Object?> get props => [];
}

final class GenerateCheckinQr extends CheckinEvent {
  final String sessionId;

  const GenerateCheckinQr({required this.sessionId});

  @override
  List<Object?> get props => [sessionId];
}

final class ConsumeCheckinQr extends CheckinEvent {
  final String rawPayload;

  const ConsumeCheckinQr({required this.rawPayload});

  @override
  List<Object?> get props => [rawPayload];
}

final class ResetCheckin extends CheckinEvent {
  const ResetCheckin();
}
