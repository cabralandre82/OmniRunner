import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/entities/token_intent_entity.dart';

sealed class StaffQrEvent extends Equatable {
  const StaffQrEvent();

  @override
  List<Object?> get props => [];
}

/// Staff generates a QR code for a token operation.
final class GenerateQr extends StaffQrEvent {
  final TokenIntentType type;
  final String groupId;
  final int amount;
  final String? championshipId;

  const GenerateQr({
    required this.type,
    required this.groupId,
    required this.amount,
    this.championshipId,
  });

  @override
  List<Object?> get props => [type, groupId, amount, championshipId];
}

/// Athlete (or staff acting on behalf) scans a QR and consumes the intent.
final class ConsumeScannedQr extends StaffQrEvent {
  final String encodedPayload;

  const ConsumeScannedQr(this.encodedPayload);

  @override
  List<Object?> get props => [encodedPayload];
}

/// Load the group's current emission capacity from inventory.
final class LoadEmissionCapacity extends StaffQrEvent {
  final String groupId;

  const LoadEmissionCapacity(this.groupId);

  @override
  List<Object?> get props => [groupId];
}

/// Reset to initial state (e.g. after a successful operation).
final class ResetStaffQr extends StaffQrEvent {
  const ResetStaffQr();
}
