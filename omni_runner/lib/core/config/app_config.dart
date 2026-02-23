/// Centralised app configuration read from compile-time environment.
///
/// Values are injected via `--dart-define-from-file`:
/// ```
/// flutter run --flavor dev  --dart-define-from-file=.env.dev
/// flutter run --flavor prod --dart-define-from-file=.env.prod
/// ```
///
/// Or individually via `--dart-define`:
/// ```
/// flutter run --dart-define=APP_ENV=dev \
///   --dart-define=SUPABASE_URL=https://xyz.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=eyJ...
/// ```
abstract final class AppConfig {
  // ── Environment ──

  /// Current environment: `dev` (default) or `prod`.
  static const appEnv = String.fromEnvironment('APP_ENV', defaultValue: 'dev');

  /// `true` when running in development mode.
  static bool get isDev => appEnv == 'dev';

  /// `true` when running in production mode.
  static bool get isProd => appEnv == 'prod';

  // ── Supabase ──

  /// Supabase project URL (e.g. `https://xyz.supabase.co`).
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// Supabase anonymous (public) key.
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Whether both Supabase env vars are present at compile time.
  static bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Runtime flag set to `true` only after [Supabase.initialize] succeeds.
  /// Use this (not [isSupabaseConfigured]) before accessing `Supabase.instance`.
  static bool get isSupabaseReady => _supabaseInitOk;
  static bool _supabaseInitOk = false;

  /// Called once from `_bootstrap` after a successful [Supabase.initialize].
  static void markSupabaseReady() => _supabaseInitOk = true;

  /// `'remote'` when Supabase initialised successfully, `'mock'` otherwise.
  static String get backendMode => _supabaseInitOk ? 'remote' : 'mock';

  // ── Portal ──

  /// B2B billing portal URL (opened in external browser).
  /// Never load checkout inside the app — App Store / Play Store safe.
  static const portalUrl = String.fromEnvironment(
    'PORTAL_URL',
    defaultValue: 'https://portal.omnirunner.app',
  );

  // ── MapTiler ──

  /// MapTiler API key for map tiles.
  static const mapTilerApiKey = String.fromEnvironment('MAPTILER_API_KEY');

  // ── Google Sign-In ──

  /// Google OAuth Web Client ID (from Firebase or GCP console).
  /// Passed to GoogleSignIn(serverClientId:) for native ID-token auth.
  static const googleWebClientId =
      String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  // ── Sentry ──

  /// Sentry DSN for crash reporting (DECISAO 011).
  static const sentryDsn = String.fromEnvironment('SENTRY_DSN');

  /// Whether Sentry is configured.
  static bool get isSentryConfigured => sentryDsn.isNotEmpty;

  /// Sentry environment tag (mirrors [appEnv]).
  static String get sentryEnvironment => appEnv;
}
