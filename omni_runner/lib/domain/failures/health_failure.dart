/// Failures related to platform health data access (HealthKit / Health Connect).
///
/// Sealed class hierarchy — no exceptions thrown in domain.
/// Used as typed error returns (null = success, non-null = failure).
sealed class HealthFailure {
  const HealthFailure();
}

/// The platform health service is not available on this device.
///
/// Examples: iPod Touch without Health app, Android without Health Connect.
final class HealthNotAvailable extends HealthFailure {
  const HealthNotAvailable();
}

/// Health permissions were denied by the user.
final class HealthPermissionDenied extends HealthFailure {
  const HealthPermissionDenied();
}

/// Health permissions were only partially granted.
///
/// The user authorized some types but not all requested types.
/// [grantedTypes] lists what was actually authorized.
final class HealthPermissionPartial extends HealthFailure {
  final List<String> grantedTypes;
  const HealthPermissionPartial({this.grantedTypes = const []});
}

/// An unexpected error occurred while accessing health data.
final class HealthUnknownError extends HealthFailure {
  final String message;
  const HealthUnknownError(this.message);
}
