import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:omni_runner/core/auth/auth_user.dart';
import 'package:omni_runner/core/auth/i_auth_datasource.dart';
import 'package:omni_runner/core/storage/preferences_keys.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/utils/generate_uuid_v4.dart';
import 'package:omni_runner/domain/failures/auth_failure.dart';

/// Offline-only auth datasource that persists a local anonymous UUID.
///
/// Sign-up / sign-in / sign-out are no-ops that throw [AuthNotConfigured].
class MockAuthDataSource implements IAuthDataSource {
  static const _tag = 'MockAuth';

  AuthUser? _current;
  final _controller = StreamController<AuthUser?>.broadcast();

  @override
  Future<AuthUser> init() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(PreferencesKeys.omniLocalUserId);
    final String id;
    if (existing != null && existing.isNotEmpty) {
      id = existing;
      AppLogger.info('Loaded local userId: $id', tag: _tag);
    } else {
      id = generateUuidV4();
      await prefs.setString(PreferencesKeys.omniLocalUserId, id);
      AppLogger.info('Generated new local userId: $id', tag: _tag);
    }
    _current = AuthUser(id: id, displayName: 'Runner', isAnonymous: true);
    _controller.add(_current);
    return _current!;
  }

  @override
  AuthUser? currentUser() => _current;

  @override
  Stream<AuthUser?> authStateChanges() => _controller.stream;

  @override
  Future<AuthUser> signUp({
    required String email,
    required String password,
  }) async {
    throw const AuthNotConfigured();
  }

  @override
  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    throw const AuthNotConfigured();
  }

  @override
  Future<AuthUser> signInWithGoogle() async {
    throw const AuthNotConfigured();
  }

  @override
  Future<AuthUser> signInWithApple() async {
    throw const AuthNotConfigured();
  }

  @override
  Future<AuthUser> signInWithInstagram() async {
    throw const AuthNotConfigured();
  }

  @override
  Future<AuthUser> signInWithTikTok() async {
    throw const AuthNotConfigured();
  }

  @override
  Future<void> resetPassword({required String email}) async {
    throw const AuthNotConfigured();
  }

  @override
  Future<void> signOut() async {
    throw const AuthNotConfigured();
  }
}
