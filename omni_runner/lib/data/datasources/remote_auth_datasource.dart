import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

import 'package:omni_runner/core/auth/auth_user.dart' as app;
import 'package:omni_runner/core/auth/i_auth_datasource.dart';
import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/failures/auth_failure.dart';

/// Auth datasource backed by Supabase GoTrueClient.
///
/// Wraps every Supabase call in try/catch and maps exceptions to
/// [AuthFailure] subtypes so callers never see raw [AuthException].
class RemoteAuthDataSource implements IAuthDataSource {
  static const _tag = 'RemoteAuth';

  GoTrueClient get _auth => Supabase.instance.client.auth;

  // ── Helpers ──────────────────────────────────────────────────────────────

  app.AuthUser _map(User u) => app.AuthUser(
        id: u.id,
        email: u.email,
        displayName:
            u.userMetadata?['full_name'] as String? ??
            u.userMetadata?['name'] as String? ??
            u.email ??
            'Runner',
        isAnonymous: u.isAnonymous,
      );

  Never _rethrow(Object e) {
    if (e is AuthException) {
      final msg = e.message.toLowerCase();
      if (msg.contains('invalid login') || msg.contains('invalid email or password')) {
        throw const AuthInvalidCredentials();
      }
      if (msg.contains('already registered') || msg.contains('already been registered')) {
        throw const AuthEmailAlreadyInUse();
      }
      if (msg.contains('weak password') || msg.contains('at least')) {
        throw const AuthWeakPassword();
      }
      throw AuthUnknownError(e.message);
    }
    if (e is Exception && e.toString().contains('SocketException')) {
      throw const AuthNetworkError();
    }
    throw AuthUnknownError(e.toString());
  }

  /// Generates a random nonce string for Apple Sign-In PKCE flow.
  String _generateNonce([int length = 32]) {
    const chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => chars[random.nextInt(chars.length)]).join();
  }

  /// SHA-256 hash of [input], returned as hex string.
  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Calls the complete-social-profile Edge Function to ensure the profile
  /// row exists and has the correct created_via. Retries up to 2 times on
  /// transient network errors. Failures are logged but do not block sign-in
  /// (the DB trigger also creates profiles as a fallback).
  Future<void> _completeSocialProfile() async {
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        final response = await Supabase.instance.client.functions.invoke(
          'complete-social-profile',
          body: {},
        );
        final data = response.data as Map<String, dynamic>? ?? {};
        if (data['ok'] == true) {
          AppLogger.info('complete-social-profile OK', tag: _tag);
        } else {
          AppLogger.warn('complete-social-profile returned ok=false: $data', tag: _tag);
        }
        return;
      } catch (e) {
        AppLogger.warn(
          'complete-social-profile attempt $attempt/3 failed: $e',
          tag: _tag,
        );
        if (attempt < 3) {
          await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
        }
      }
    }
  }

  // ── IAuthDataSource ────────────────────────────────────────────────────

  @override
  Future<app.AuthUser> init() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        AppLogger.info('No Supabase session — user will see login screen', tag: _tag);
        return const app.AuthUser(id: '', displayName: 'Runner', isAnonymous: true);
      }
      final mapped = _map(user);
      AppLogger.info(
        'Auth init OK: ${mapped.id} (${mapped.email ?? "anonymous"})',
        tag: _tag,
      );
      return mapped;
    } on AuthFailure {
      rethrow;
    } catch (e) {
      AppLogger.warn('Auth init failed: $e', tag: _tag);
      _rethrow(e);
    }
  }

  @override
  Future<app.AuthUser> signUp({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _auth.signUp(email: email, password: password);
      final user = res.user;
      if (user == null) throw const AuthUnknownError('signUp returned null user');
      AppLogger.info('SignUp OK: ${user.id}', tag: _tag);
      return _map(user);
    } on AuthFailure {
      rethrow;
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<app.AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _auth.signInWithPassword(email: email, password: password);
      final user = res.user;
      if (user == null) throw const AuthUnknownError('signIn returned null user');
      AppLogger.info('SignIn OK: ${user.id}', tag: _tag);
      return _map(user);
    } on AuthFailure {
      rethrow;
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<app.AuthUser> signInWithGoogle() async {
    try {
      final googleSignIn = GoogleSignIn(
        scopes: ['email'],
        serverClientId: AppConfig.googleWebClientId.isNotEmpty
            ? AppConfig.googleWebClientId
            : null,
      );
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        throw const AuthSocialCancelled();
      }

      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;
      if (idToken == null) {
        throw const AuthUnknownError('Google Sign-In returned no ID token');
      }

      final res = await _auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      final user = res.user;
      if (user == null) {
        throw const AuthUnknownError('signInWithIdToken(google) returned null user');
      }

      AppLogger.info('Google SignIn OK: ${user.id}', tag: _tag);
      final mapped = _map(user);
      await _completeSocialProfile();
      return mapped;
    } on AuthFailure {
      rethrow;
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<app.AuthUser> signInWithApple() async {
    try {
      final rawNonce = _generateNonce();
      final hashedNonce = _sha256ofString(rawNonce);

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final idToken = credential.identityToken;
      if (idToken == null) {
        throw const AuthUnknownError('Apple Sign-In returned no identity token');
      }

      final res = await _auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );

      final user = res.user;
      if (user == null) {
        throw const AuthUnknownError('signInWithIdToken(apple) returned null user');
      }

      AppLogger.info('Apple SignIn OK: ${user.id}', tag: _tag);
      final mapped = _map(user);
      await _completeSocialProfile();
      return mapped;
    } on AuthFailure {
      rethrow;
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw const AuthSocialCancelled();
      }
      throw AuthUnknownError('Apple Sign-In error: ${e.message}');
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<app.AuthUser> signInWithInstagram() async {
    try {
      final completer = Completer<User>();
      StreamSubscription<AuthState>? sub;

      sub = _auth.onAuthStateChange.listen((event) {
        if (event.event == AuthChangeEvent.signedIn) {
          final user = event.session?.user;
          if (user != null && !completer.isCompleted) {
            sub?.cancel();
            completer.complete(user);
          }
        }
      });

      final launched = await _auth.signInWithOAuth(
        OAuthProvider.facebook,
        redirectTo: 'omnirunner://auth-callback',
        scopes: 'email,public_profile',
      );

      if (!launched) {
        sub.cancel();
        throw const AuthUnknownError('Could not open Instagram login');
      }

      final User user;
      try {
        user = await completer.future.timeout(const Duration(minutes: 5));
      } on TimeoutException {
        sub.cancel();
        throw const AuthSocialCancelled();
      }

      AppLogger.info('Instagram SignIn OK: ${user.id}', tag: _tag);
      final mapped = _map(user);
      await _completeSocialProfile();
      return mapped;
    } on AuthFailure {
      rethrow;
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<app.AuthUser> signInWithTikTok() async {
    try {
      final initResponse = await Supabase.instance.client.functions.invoke(
        'validate-social-login',
        body: {'provider': 'tiktok', 'action': 'init'},
      );

      final initData = initResponse.data as Map<String, dynamic>? ?? {};
      if (initData['ok'] != true) {
        throw AuthUnknownError(
          initData['error']?.toString() ?? 'TikTok login is not available yet',
        );
      }

      final authUrl = initData['auth_url'] as String?;
      if (authUrl == null) {
        throw const AuthUnknownError('TikTok auth URL not returned');
      }

      final completer = Completer<User>();
      StreamSubscription<AuthState>? sub;

      sub = _auth.onAuthStateChange.listen((event) {
        if (event.event == AuthChangeEvent.signedIn) {
          final user = event.session?.user;
          if (user != null && !completer.isCompleted) {
            sub?.cancel();
            completer.complete(user);
          }
        }
      });

      final launched = await launcher.launchUrl(
        Uri.parse(authUrl),
        mode: launcher.LaunchMode.externalApplication,
      );

      if (!launched) {
        sub.cancel();
        throw const AuthUnknownError('Could not open TikTok login');
      }

      final User user;
      try {
        user = await completer.future.timeout(const Duration(minutes: 5));
      } on TimeoutException {
        sub.cancel();
        throw const AuthSocialCancelled();
      }

      AppLogger.info('TikTok SignIn OK: ${user.id}', tag: _tag);
      final mapped = _map(user);
      await _completeSocialProfile();
      return mapped;
    } on AuthFailure {
      rethrow;
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<void> resetPassword({required String email}) async {
    try {
      await _auth.resetPasswordForEmail(email);
      AppLogger.info('Password reset email sent to $email', tag: _tag);
    } on AuthException catch (e) {
      throw AuthUnknownError(e.message);
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      try { await GoogleSignIn().signOut(); } catch (_) {}
      await _auth.signOut();
      AppLogger.info('SignOut OK', tag: _tag);
    } on AuthFailure {
      rethrow;
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  app.AuthUser? currentUser() {
    try {
      final u = _auth.currentUser;
      return u == null ? null : _map(u);
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<app.AuthUser?> authStateChanges() {
    return _auth.onAuthStateChange.map((event) {
      final user = event.session?.user;
      return user == null ? null : _map(user);
    });
  }
}
