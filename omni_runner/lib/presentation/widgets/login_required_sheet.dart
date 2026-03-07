import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/router/app_router.dart';
import 'package:omni_runner/core/service_locator.dart';

/// Bottom sheet shown when an anonymous user taps a feature that requires
/// a real account (assessoria, desafios, campeonatos, tokens, etc.).
///
/// Usage:
/// ```dart
/// if (LoginRequiredSheet.guard(context)) return; // blocked — sheet shown
/// // … continue with navigation
/// ```
class LoginRequiredSheet extends StatelessWidget {
  final String feature;
  const LoginRequiredSheet({super.key, required this.feature});

  /// Returns `true` (and shows the sheet) if the current user is anonymous.
  /// Returns `false` if the user is authenticated — caller should proceed.
  static bool guard(BuildContext context, {String feature = ''}) {
    if (!sl<UserIdentityProvider>().isAnonymous) return false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => LoginRequiredSheet(feature: feature),
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Icon(
              Icons.lock_open_rounded,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Crie sua conta para continuar',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              feature.isEmpty
                  ? 'Essa funcionalidade requer uma conta. '
                    'É rápido — basta entrar com Google ou Apple.'
                  : '$feature requer uma conta. '
                    'É rápido — basta entrar com Google ou Apple.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Suas corridas locais serão preservadas.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.go(AppRoutes.root);
                },
                icon: const Icon(Icons.login_rounded),
                label: const Text('Criar conta / Entrar'),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Agora não'),
            ),
          ],
        ),
      ),
    );
  }
}
