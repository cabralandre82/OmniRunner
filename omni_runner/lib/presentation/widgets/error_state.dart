import 'package:flutter/material.dart';

/// Reusable error state widget with friendly message and retry button.
class ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const ErrorState({
    super.key,
    required this.message,
    this.onRetry,
  });

  /// Converts raw exception text to a user-friendly message.
  static String humanize(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('socketexception') ||
        lower.contains('clientexception') ||
        lower.contains('connection') ||
        lower.contains('network')) {
      return 'Sem conexão com a internet. Verifique sua rede e tente novamente.';
    }
    if (lower.contains('timeout')) {
      return 'A requisição demorou demais. Tente novamente.';
    }
    if (lower.contains('401') || lower.contains('unauthorized')) {
      return 'Sua sessão expirou. Faça login novamente.';
    }
    if (lower.contains('403') || lower.contains('forbidden')) {
      return 'Você não tem permissão para esta ação.';
    }
    if (lower.contains('404') || lower.contains('not found')) {
      return 'O conteúdo não foi encontrado.';
    }
    if (lower.contains('500') || lower.contains('internal')) {
      return 'Erro no servidor. Tente novamente em alguns minutos.';
    }
    if (raw.length > 100) {
      return 'Algo deu errado. Tente novamente.';
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final friendly = humanize(message);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.cloud_off_rounded,
                size: 40,
                color: theme.colorScheme.error.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              friendly,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tentar novamente'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
