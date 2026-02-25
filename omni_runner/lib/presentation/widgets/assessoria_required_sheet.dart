import 'package:flutter/material.dart';

import 'package:omni_runner/presentation/screens/join_assessoria_screen.dart';

/// Bottom sheet shown when an athlete without an assessoria tries to access
/// any challenge-related feature (create, join, matchmaking).
///
/// Usage:
/// ```dart
/// if (AssessoriaRequiredSheet.guard(context, hasAssessoria: _hasAssessoria)) return;
/// ```
class AssessoriaRequiredSheet extends StatelessWidget {
  const AssessoriaRequiredSheet({super.key});

  /// Returns `true` (and shows the sheet) if the athlete has no assessoria.
  /// Returns `false` if they do — caller should proceed.
  static bool guard(BuildContext context, {required bool hasAssessoria}) {
    if (hasAssessoria) return false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const AssessoriaRequiredSheet(),
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
              Icons.groups_rounded,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Entre em uma assessoria primeiro',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Para criar, participar ou buscar desafios, '
              'você precisa estar vinculado a uma assessoria esportiva.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Peça o código de convite ao seu professor ou treinador.',
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
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => JoinAssessoriaScreen(
                        onComplete: () => Navigator.of(context).pop(),
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.group_add_rounded),
                label: const Text('Entrar em assessoria'),
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
