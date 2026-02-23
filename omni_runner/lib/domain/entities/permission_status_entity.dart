/// Represents the current state of a system permission.
///
/// Platform-agnostic. No dependency on any permission library.
enum PermissionStatusEntity {
  /// Permission has not been requested yet.
  notDetermined,

  /// Permission has been granted by the user.
  granted,

  /// Permission has been denied by the user (can be re-requested).
  denied,

  /// Permission has been permanently denied (must open app settings).
  permanentlyDenied,

  /// Permission is restricted by system policy (e.g. parental controls).
  restricted,
}
