/// Barrel file unifying both failure hierarchies.
///
/// The project has two failure directories for historical reasons:
///   - `core/errors/` — domain-specific failures (coaching, gamification, social, etc.)
///   - `domain/failures/` — infrastructure failures (auth, BLE, health, location, sync)
///
/// Import this single file to access all failure types:
/// ```dart
/// import 'package:omni_runner/core/errors/failures.dart';
/// ```
library;

// ── core/errors ──
export 'coaching_failures.dart';
export 'gamification_failures.dart';
export 'health_export_failures.dart';
export 'integrations_failures.dart';
export 'social_failures.dart';

// ── domain/failures ──
export 'package:omni_runner/domain/failures/auth_failure.dart';
export 'package:omni_runner/domain/failures/ble_failure.dart';
export 'package:omni_runner/domain/failures/health_failure.dart';
export 'package:omni_runner/domain/failures/location_failure.dart';
export 'package:omni_runner/domain/failures/sync_failure.dart';
