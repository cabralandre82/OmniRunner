/// Lightweight, backend-agnostic representation of the signed-in user.
///
/// Both [RemoteAuthDataSource] and [MockAuthDataSource] produce this.
class AuthUser {
  final String id;
  final String? email;
  final String displayName;
  final bool isAnonymous;

  const AuthUser({
    required this.id,
    this.email,
    this.displayName = 'Runner',
    this.isAnonymous = true,
  });

  @override
  String toString() =>
      'AuthUser(id: $id, email: $email, anonymous: $isAnonymous)';
}
