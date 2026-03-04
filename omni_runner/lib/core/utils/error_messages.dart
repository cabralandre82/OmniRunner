/// User-friendly error messages for display in the UI.
/// Converts technical error strings to human-readable Portuguese messages.
class ErrorMessages {
  static String humanize(Object error) {
    final msg = error.toString().toLowerCase();
    if (msg.contains('network') ||
        msg.contains('socket') ||
        msg.contains('connection')) {
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
    if (msg.contains('not found') || msg.contains('404')) {
      return 'Recurso não encontrado.';
    }
    if (msg.contains('duplicate') || msg.contains('already exists')) {
      return 'Este item já existe.';
    }
    return 'Algo deu errado. Tente novamente.';
  }
}
