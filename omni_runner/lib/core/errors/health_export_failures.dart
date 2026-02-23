/// Failures specific to the health export bridge (HealthKit / Health Connect).
///
/// Sealed hierarchy — enables exhaustive pattern matching in controllers.
/// Distinct from [HealthFailure] (low-level permission/availability) because
/// these describe export-specific scenarios the presentation layer must handle.
sealed class HealthExportFailure {
  const HealthExportFailure();
}

/// The platform health service is not available (device unsupported).
final class HealthExportNotAvailable extends HealthExportFailure {
  final String reason;
  const HealthExportNotAvailable(this.reason);
}

/// Health Connect is installed but requires an update before writing.
///
/// Android only. The user should be prompted to update via Play Store.
final class HealthExportNeedsUpdate extends HealthExportFailure {
  const HealthExportNeedsUpdate();
}

/// Write permissions were not granted by the user.
///
/// The controller should display a message guiding the user to grant
/// the required permissions in Settings (iOS) or Health Connect app (Android).
final class HealthExportPermissionDenied extends HealthExportFailure {
  final List<String> missingScopes;
  const HealthExportPermissionDenied({this.missingScopes = const []});
}

/// The workout record was written but the GPS route could not be attached.
///
/// Partial success — the workout exists in the health store without route data.
final class HealthExportRouteAttachFailed extends HealthExportFailure {
  final String reason;
  const HealthExportRouteAttachFailed(this.reason);
}

/// The workout export failed entirely due to a platform error.
final class HealthExportWriteFailed extends HealthExportFailure {
  final String reason;
  const HealthExportWriteFailed(this.reason);
}

/// HR sample writing failed (workout was saved, but HR data was not).
///
/// Android only — iOS auto-correlates HR from Apple Watch.
final class HealthExportHrWriteFailed extends HealthExportFailure {
  final int attempted;
  final int written;
  const HealthExportHrWriteFailed({
    required this.attempted,
    required this.written,
  });
}
