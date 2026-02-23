import 'package:omni_runner/core/auth/auth_repository.dart';
import 'package:omni_runner/core/auth/auth_user.dart';

/// Provides the current user identity for the app.
///
/// Thin wrapper around [AuthRepository] that exposes the three properties
/// consumed by the rest of the codebase: [userId], [displayName], [isAnonymous].
///
/// Must call [init] once at startup (before any BLoC dispatches Load events).
class UserIdentityProvider {
  final AuthRepository _authRepo;

  UserIdentityProvider({required AuthRepository authRepo})
      : _authRepo = authRepo;

  AuthUser _user = const AuthUser(id: '', displayName: 'Runner');

  /// Current user ID. Never empty after [init].
  String get userId => _user.id;

  /// Display name for the current user.
  String get displayName => _user.displayName;

  /// Whether the current identity is a local anonymous UUID.
  bool get isAnonymous => _user.isAnonymous;

  /// The full [AuthUser] for consumers that need all fields.
  AuthUser get authUser => _user;

  /// The underlying repository for sign-in/sign-up/sign-out operations.
  AuthRepository get authRepository => _authRepo;

  /// Initialise identity. Call once at startup.
  Future<void> init() async {
    _user = await _authRepo.init();
  }

  /// Re-read the current user from the repository (e.g. after sign-in).
  void refresh() {
    final u = _authRepo.currentUser;
    if (u != null) _user = u;
  }
}
