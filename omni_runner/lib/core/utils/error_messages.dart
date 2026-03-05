/// User-friendly error messages for display in the UI.
/// Converts technical error strings to human-readable Portuguese messages.
class ErrorMessages {
  static String humanize(Object error) {
    final msg = error.toString().toLowerCase();
    if (msg.contains('network') ||
        msg.contains('socket') ||
        msg.contains('connection refused') ||
        msg.contains('clientexception')) {
      return 'Sem conexão com a internet. Tente novamente.';
    }
    if (msg.contains('timeout')) {
      return 'A operação demorou muito. Tente novamente.';
    }
    if (msg.contains('permission') ||
        msg.contains('forbidden') ||
        msg.contains('403')) {
      return 'Você não tem permissão para esta ação.';
    }
    if (msg.contains('401') || msg.contains('unauthorized')) {
      return 'Sua sessão expirou. Faça login novamente.';
    }
    if (msg.contains('not found') || msg.contains('404')) {
      return 'Funcionalidade temporariamente indisponível. Tente novamente mais tarde.';
    }
    if (msg.contains('duplicate') || msg.contains('already exists')) {
      return 'Este item já existe.';
    }
    if (msg.contains('500') || msg.contains('internal server')) {
      return 'Erro no servidor. Tente novamente em alguns minutos.';
    }
    return 'Algo deu errado. Tente novamente.';
  }
}
