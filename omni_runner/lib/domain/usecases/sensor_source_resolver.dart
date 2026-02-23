import 'dart:io' show Platform;

import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/entities/sensor_resolution.dart';
import 'package:omni_runner/domain/repositories/i_health_provider.dart';
import 'package:omni_runner/features/wearables_ble/i_heart_rate_source.dart';

const String _tag = 'SensorResolver';

/// Resolves which data sources to use for HR and Steps.
///
/// **HR priority** (highest first):
///   1. BLE external HR monitor (Polar, Garmin, Wahoo, etc.)
///   2. Platform health service (HealthKit on iOS, Health Connect on Android)
///   3. None
///
/// **Steps priority**:
///   1. Platform health service (HealthKit / Health Connect)
///   2. None
///
/// BLE is preferred for HR because it delivers real-time beat-by-beat data
/// at ~1 Hz, while platform health APIs return batched historical data with
/// latency. For Steps, only platform health APIs provide reliable data.
///
/// Conforms to [O4]: single `call()` method.
final class SensorSourceResolver {
  final IHeartRateSource? _bleHr;
  final IHealthProvider? _healthProvider;

  const SensorSourceResolver({
    IHeartRateSource? bleHr,
    IHealthProvider? healthProvider,
  })  : _bleHr = bleHr,
        _healthProvider = healthProvider;

  /// Evaluate all sources and return a [SensorResolution] with the best
  /// combination for the current device state.
  ///
  /// This is async because it queries BLE connection state and health
  /// provider availability.
  Future<SensorResolution> call() async {
    final hr = await _resolveHr();
    final steps = await _resolveSteps();

    final resolution = SensorResolution(
      hrSource: hr.$1,
      hrReason: hr.$2,
      stepsSource: steps.$1,
      stepsReason: steps.$2,
    );

    AppLogger.info(resolution.toString(), tag: _tag);
    return resolution;
  }

  // ---------------------------------------------------------------------------
  // HR resolution — BLE > Platform Health > None
  // ---------------------------------------------------------------------------

  Future<(SensorSourceType, String)> _resolveHr() async {
    // Priority 1: BLE HR monitor
    final ble = _bleHr;
    if (ble != null) {
      if (ble.isConnected) {
        final name = ble.connectedDeviceName ?? 'unknown';
        return (SensorSourceType.ble, 'BLE connected: $name');
      }

      final lastId = await _safeLastKnownId(ble);
      if (lastId != null) {
        final lastName = await _safeLastKnownName(ble) ?? lastId;
        return (SensorSourceType.ble, 'BLE last known: $lastName (auto-connect)');
      }
    }

    // Priority 2: Platform health service
    final healthHr = await _resolveHealthHr();
    if (healthHr != null) return healthHr;

    // Priority 3: None
    return (SensorSourceType.none, 'No HR source available');
  }

  Future<(SensorSourceType, String)?> _resolveHealthHr() async {
    final provider = _healthProvider;
    if (provider == null) return null;

    final available = await provider.isAvailable();
    if (!available) return null;

    final hasPerm = await provider.hasPermissions([
      HealthPermissionScope.readHeartRate,
    ]);
    if (!hasPerm) return null;

    final source = _platformHealthType();
    return (source, '${source.name}: HR read permission granted');
  }

  // ---------------------------------------------------------------------------
  // Steps resolution — Platform Health > None
  // ---------------------------------------------------------------------------

  Future<(SensorSourceType, String)> _resolveSteps() async {
    final provider = _healthProvider;
    if (provider == null) {
      return (SensorSourceType.none, 'No health provider registered');
    }

    final available = await provider.isAvailable();
    if (!available) {
      return (SensorSourceType.none, 'Health service unavailable');
    }

    final hasPerm = await provider.hasPermissions([
      HealthPermissionScope.readSteps,
    ]);
    if (!hasPerm) {
      return (SensorSourceType.none, 'Steps read permission not granted');
    }

    final source = _platformHealthType();
    return (source, '${source.name}: steps read permission granted');
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Returns the platform-specific health source type.
  static SensorSourceType _platformHealthType() {
    return Platform.isIOS
        ? SensorSourceType.healthKit
        : SensorSourceType.healthConnect;
  }

  static Future<String?> _safeLastKnownId(IHeartRateSource ble) async {
    try {
      return await ble.lastKnownDeviceId;
    } on Exception {
      return null;
    }
  }

  static Future<String?> _safeLastKnownName(IHeartRateSource ble) async {
    try {
      return await ble.lastKnownDeviceName;
    } on Exception {
      return null;
    }
  }
}
