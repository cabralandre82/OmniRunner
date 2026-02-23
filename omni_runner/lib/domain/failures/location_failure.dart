/// Failures related to location services and permissions.
///
/// Sealed class hierarchy. No exceptions thrown in domain.
/// Used as Left side of Either returns.
sealed class LocationFailure {
  const LocationFailure();
}

/// GPS/location permission was denied by the user.
final class LocationPermissionDenied extends LocationFailure {
  const LocationPermissionDenied();
}

/// GPS/location permission was permanently denied (requires app settings).
final class LocationPermissionPermanentlyDenied extends LocationFailure {
  const LocationPermissionPermanentlyDenied();
}

/// Device location services (GPS) are disabled at system level.
final class LocationServiceDisabled extends LocationFailure {
  const LocationServiceDisabled();
}

/// GPS signal unavailable or timed out.
final class LocationUnavailable extends LocationFailure {
  const LocationUnavailable();
}
