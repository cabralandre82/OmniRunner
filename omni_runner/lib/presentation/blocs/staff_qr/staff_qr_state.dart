import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/entities/token_intent_entity.dart';

sealed class StaffQrState extends Equatable {
  const StaffQrState();

  @override
  List<Object?> get props => [];
}

final class StaffQrInitial extends StaffQrState {
  const StaffQrInitial();
}

final class StaffQrGenerating extends StaffQrState {
  const StaffQrGenerating();
}

/// QR code generated successfully — ready to display.
final class StaffQrGenerated extends StaffQrState {
  final StaffQrPayload payload;

  const StaffQrGenerated(this.payload);

  @override
  List<Object?> get props => [payload];
}

final class StaffQrConsuming extends StaffQrState {
  const StaffQrConsuming();
}

/// Intent consumed successfully.
final class StaffQrConsumed extends StaffQrState {
  final TokenIntentType type;

  const StaffQrConsumed(this.type);

  @override
  List<Object?> get props => [type];
}

final class StaffQrError extends StaffQrState {
  final String message;

  const StaffQrError(this.message);

  @override
  List<Object?> get props => [message];
}
