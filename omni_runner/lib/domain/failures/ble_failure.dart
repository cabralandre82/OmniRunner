/// Failures related to Bluetooth Low Energy permissions and adapter state.
///
/// Sealed class hierarchy — no exceptions thrown in domain.
/// Used as typed error returns (null = success, non-null = failure).
sealed class BleFailure {
  const BleFailure();
}

/// Bluetooth scan permission was denied by the user.
final class BleScanPermissionDenied extends BleFailure {
  const BleScanPermissionDenied();
}

/// Bluetooth connect permission was denied by the user.
final class BleConnectPermissionDenied extends BleFailure {
  const BleConnectPermissionDenied();
}

/// Bluetooth permission was permanently denied (requires app settings).
final class BlePermissionPermanentlyDenied extends BleFailure {
  const BlePermissionPermanentlyDenied();
}

/// The device's Bluetooth adapter is turned off at system level.
final class BleAdapterOff extends BleFailure {
  const BleAdapterOff();
}

/// The device does not support Bluetooth Low Energy.
final class BleNotSupported extends BleFailure {
  const BleNotSupported();
}
