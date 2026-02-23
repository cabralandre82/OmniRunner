/// Rationale text constants for location permission requests.
///
/// These are domain-defined strings that the presentation layer
/// displays to the user before requesting permissions.
///
/// Android 11+ (API 30+) REQUIRES showing a rationale before
/// requesting background location. Apple requires meaningful
/// descriptions in Info.plist (already configured in Sprint 2.3).
abstract final class LocationRationale {
  /// Title for the background location rationale dialog.
  static const backgroundTitle = 'Background Location Needed';

  /// Body text explaining why background location is required.
  ///
  /// Shown to user before requesting ACCESS_BACKGROUND_LOCATION.
  /// Must clearly explain the benefit to the user.
  static const backgroundBody =
      'Omni Runner needs to track your location in the background '
      'to keep recording your run when the screen is off or you '
      'switch to another app.\n\n'
      'This ensures your route, distance, and pace are accurately '
      'captured for the entire run.\n\n'
      'On the next screen, please select "Allow all the time".';

  /// Button text to proceed with background permission request.
  static const backgroundProceed = 'Continue';

  /// Button text to skip background permission (foreground-only mode).
  static const backgroundSkip = 'Not Now';
}
