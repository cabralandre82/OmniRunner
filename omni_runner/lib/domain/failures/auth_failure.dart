/// Failures related to authentication.
///
/// Sealed class hierarchy — no exceptions thrown in domain.
sealed class AuthFailure {
  final String message;
  const AuthFailure(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

final class AuthInvalidCredentials extends AuthFailure {
  const AuthInvalidCredentials()
      : super('E-mail ou senha inválidos.');
}

final class AuthEmailAlreadyInUse extends AuthFailure {
  const AuthEmailAlreadyInUse()
      : super('Já existe uma conta com este e-mail.');
}

final class AuthWeakPassword extends AuthFailure {
  const AuthWeakPassword()
      : super('Senha muito fraca (mínimo 6 caracteres).');
}

final class AuthNetworkError extends AuthFailure {
  const AuthNetworkError()
      : super('Erro de rede — verifique sua conexão.');
}

final class AuthNotConfigured extends AuthFailure {
  const AuthNotConfigured()
      : super('Autenticação indisponível no modo offline.');
}

final class AuthSocialCancelled extends AuthFailure {
  const AuthSocialCancelled()
      : super('Login cancelado.');
}

final class AuthProviderNotConfigured extends AuthFailure {
  final String provider;
  const AuthProviderNotConfigured(this.provider)
      : super('Login com Instagram ainda não está disponível. '
              'Use Google ou e-mail para entrar.');
}

final class AuthUnknownError extends AuthFailure {
  const AuthUnknownError([super.detail = 'Erro inesperado.']);
}
