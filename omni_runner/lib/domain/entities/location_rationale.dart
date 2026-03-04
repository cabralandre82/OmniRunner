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
  static const backgroundTitle = 'Localização em segundo plano';

  /// Body text explaining why background location is required.
  ///
  /// Shown to user before requesting ACCESS_BACKGROUND_LOCATION.
  /// Must clearly explain the benefit to the user.
  static const backgroundBody =
      'O Omni Runner precisa de acesso à localização em segundo plano '
      'para rastrear suas corridas mesmo quando o app não está em '
      'primeiro plano.\n\n'
      'Isso garante que sua rota, distância e pace sejam registrados '
      'com precisão durante toda a corrida.\n\n'
      'Na próxima tela, selecione "Permitir o tempo todo".';

  /// Button text to proceed with background permission request.
  static const backgroundProceed = 'Continuar';

  /// Button text to skip background permission (foreground-only mode).
  static const backgroundSkip = 'Agora não';
}
