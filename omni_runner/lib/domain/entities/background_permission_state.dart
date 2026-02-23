/// Represents the state of the background location permission flow.
///
/// Android 11+ (API 30+) requires a separate request for background location
/// AFTER foreground location is already granted. The user must be shown a
/// rationale explaining why background access is needed before the request.
///
/// Flow: [notNeeded] -> [rationaleRequired] -> [requesting] -> [granted] / [denied]
enum BackgroundPermissionState {
  /// Foreground permission not yet granted. Background request is premature.
  notNeeded,

  /// Foreground granted. Must show rationale UI before requesting background.
  rationaleRequired,

  /// Rationale shown. System dialog is being displayed.
  requesting,

  /// Background location permission granted.
  granted,

  /// Background location permission denied by user.
  denied,
}
