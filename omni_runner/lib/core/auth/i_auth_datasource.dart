import 'package:omni_runner/core/auth/auth_user.dart';

/// Adapter interface for authentication backends.
///
/// Two implementations:
/// - [RemoteAuthDataSource] — delegates to Supabase Auth
/// - [MockAuthDataSource]   — local UUID, no network
abstract interface class IAuthDataSource {
  /// Sign up with email + password. Returns the new user.
  Future<AuthUser> signUp({required String email, required String password});

  /// Sign in with email + password. Returns the authenticated user.
  Future<AuthUser> signIn({required String email, required String password});

  /// Sign in with Google OAuth. Returns the authenticated user.
  Future<AuthUser> signInWithGoogle();

  /// Sign in with Apple OAuth. Returns the authenticated user.
  Future<AuthUser> signInWithApple();

  /// Sign in with Instagram (via Meta/Facebook OAuth). Returns the user.
  Future<AuthUser> signInWithInstagram();

  /// Sign in with TikTok (custom OAuth via Edge Function). Returns the user.
  Future<AuthUser> signInWithTikTok();

  /// Sign out the current user.
  Future<void> signOut();

  /// Current user, or `null` if not signed in.
  AuthUser? currentUser();

  /// Reactive stream of auth state changes.
  Stream<AuthUser?> authStateChanges();

  /// Initialise the datasource (restore session, generate local id, etc.).
  Future<AuthUser> init();
}
