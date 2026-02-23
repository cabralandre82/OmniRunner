import 'dart:async';

import 'package:omni_runner/core/auth/auth_user.dart';
import 'package:omni_runner/core/auth/i_auth_datasource.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/failures/auth_failure.dart';

/// Routes auth calls to the active [IAuthDataSource] (remote or mock).
///
/// Every public method catches all exceptions and maps them to [AuthFailure]
/// so callers never see raw exceptions. The only exception is [init], which
/// returns [AuthUser] directly since it is called during bootstrap before
/// any UI exists to display failures.
class AuthRepository {
  static const _tag = 'AuthRepo';

  final IAuthDataSource _ds;

  AuthRepository({required IAuthDataSource datasource}) : _ds = datasource;

  // ── Bootstrap ───────────────────────────────────────────────────────────

  /// Initialise the underlying datasource. Called once at startup.
  Future<AuthUser> init() => _ds.init();

  // ── Queries ─────────────────────────────────────────────────────────────

  AuthUser? get currentUser => _ds.currentUser();

  bool get isSignedIn => _ds.currentUser() != null;

  Stream<AuthUser?> get authStateChanges => _ds.authStateChanges();

  // ── Commands (return AuthFailure? — null means success) ─────────────────

  Future<({AuthUser? user, AuthFailure? failure})> signUp({
    required String email,
    required String password,
  }) async {
    try {
      final user = await _ds.signUp(email: email, password: password);
      AppLogger.info('signUp success: ${user.id}', tag: _tag);
      return (user: user, failure: null);
    } on AuthFailure catch (f) {
      AppLogger.warn('signUp failed: $f', tag: _tag);
      return (user: null, failure: f);
    } catch (e) {
      AppLogger.error('signUp unexpected: $e', tag: _tag, error: e);
      return (user: null, failure: AuthUnknownError(e.toString()));
    }
  }

  Future<({AuthUser? user, AuthFailure? failure})> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final user = await _ds.signIn(email: email, password: password);
      AppLogger.info('signIn success: ${user.id}', tag: _tag);
      return (user: user, failure: null);
    } on AuthFailure catch (f) {
      AppLogger.warn('signIn failed: $f', tag: _tag);
      return (user: null, failure: f);
    } catch (e) {
      AppLogger.error('signIn unexpected: $e', tag: _tag, error: e);
      return (user: null, failure: AuthUnknownError(e.toString()));
    }
  }

  Future<({AuthUser? user, AuthFailure? failure})> signInWithGoogle() async {
    try {
      final user = await _ds.signInWithGoogle();
      AppLogger.info('signInWithGoogle success: ${user.id}', tag: _tag);
      return (user: user, failure: null);
    } on AuthFailure catch (f) {
      AppLogger.warn('signInWithGoogle failed: $f', tag: _tag);
      return (user: null, failure: f);
    } catch (e) {
      AppLogger.error('signInWithGoogle unexpected: $e', tag: _tag, error: e);
      return (user: null, failure: AuthUnknownError(e.toString()));
    }
  }

  Future<({AuthUser? user, AuthFailure? failure})> signInWithApple() async {
    try {
      final user = await _ds.signInWithApple();
      AppLogger.info('signInWithApple success: ${user.id}', tag: _tag);
      return (user: user, failure: null);
    } on AuthFailure catch (f) {
      AppLogger.warn('signInWithApple failed: $f', tag: _tag);
      return (user: null, failure: f);
    } catch (e) {
      AppLogger.error('signInWithApple unexpected: $e', tag: _tag, error: e);
      return (user: null, failure: AuthUnknownError(e.toString()));
    }
  }

  Future<({AuthUser? user, AuthFailure? failure})> signInWithInstagram() async {
    try {
      final user = await _ds.signInWithInstagram();
      AppLogger.info('signInWithInstagram success: ${user.id}', tag: _tag);
      return (user: user, failure: null);
    } on AuthFailure catch (f) {
      AppLogger.warn('signInWithInstagram failed: $f', tag: _tag);
      return (user: null, failure: f);
    } catch (e) {
      AppLogger.error('signInWithInstagram unexpected: $e', tag: _tag, error: e);
      return (user: null, failure: AuthUnknownError(e.toString()));
    }
  }

  Future<({AuthUser? user, AuthFailure? failure})> signInWithTikTok() async {
    try {
      final user = await _ds.signInWithTikTok();
      AppLogger.info('signInWithTikTok success: ${user.id}', tag: _tag);
      return (user: user, failure: null);
    } on AuthFailure catch (f) {
      AppLogger.warn('signInWithTikTok failed: $f', tag: _tag);
      return (user: null, failure: f);
    } catch (e) {
      AppLogger.error('signInWithTikTok unexpected: $e', tag: _tag, error: e);
      return (user: null, failure: AuthUnknownError(e.toString()));
    }
  }

  Future<AuthFailure?> signOut() async {
    try {
      await _ds.signOut();
      AppLogger.info('signOut success', tag: _tag);
      return null;
    } on AuthFailure catch (f) {
      AppLogger.warn('signOut failed: $f', tag: _tag);
      return f;
    } catch (e) {
      AppLogger.error('signOut unexpected: $e', tag: _tag, error: e);
      return AuthUnknownError(e.toString());
    }
  }
}
