import 'dart:typed_data';

import 'package:omni_runner/core/errors/integrations_failures.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/features/wearables_ble/heart_rate_sample.dart';

/// Generates a Garmin FIT (Flexible and Interoperable Data Transfer) file.
///
/// FIT is a binary protocol with CRC checksums. It supports the richest
/// set of workout data (GPS, HR, pace, cadence, calories, device info,
/// laps, sessions, etc.).
///
/// **STATUS: NOT YET IMPLEMENTED.**
///
/// FIT encoding is significantly more complex than GPX/TCX:
/// - Binary format with protocol-buffer-like message definitions
/// - CRC-16 checksums per message and for the entire file
/// - Coordinates in semicircles: `lat * (2^31 / 180)`
/// - Timestamps in Garmin epoch: seconds since 1989-12-31T00:00:00Z
/// - Requires a definition message before each data message type
///
/// Options for implementation (Sprint 14.2.3):
/// 1. Use `fit_tool` package (if available and maintained)
/// 2. Manual binary encoding (ByteData + Endian.little)
/// 3. Generate via a Dart port of the FIT SDK
///
/// For now, callers should catch [ExportNotImplemented] and fall back
/// to GPX or TCX.
///
/// TODO(Sprint 14.2.3): Implement FIT binary encoding.
final class FitEncoder {
  const FitEncoder();

  /// Encode a workout session into FIT binary format.
  ///
  /// **Throws [ExportNotImplemented]** — FIT encoding is not yet available.
  Uint8List encode({
    required WorkoutSessionEntity session,
    required List<LocationPointEntity> route,
    List<HeartRateSample> hrSamples = const [],
    String activityName = 'Omni Runner',
  }) {
    throw const ExportNotImplemented('FIT');
  }
}
