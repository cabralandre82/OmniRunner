import 'package:flutter/material.dart';

import 'package:omni_runner/core/theme/design_tokens.dart';

/// Reusable loading state widget.
///
/// Shows a centered [CircularProgressIndicator] with optional message.
/// Use when fetching data from API, Supabase, or during async operations.
class AppLoadingState extends StatelessWidget {
  const AppLoadingState({
    super.key,
    this.message,
  });

  /// Optional text shown below the spinner.
  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            if ((message ?? '').isNotEmpty) ...[
              const SizedBox(height: DesignTokens.spacingLg),
              Text(
                message ?? '',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: DesignTokens.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Reusable error state widget.
///
/// Shows error icon, message, and retry button.
/// Use when API calls fail, Supabase errors occur, or data loading fails.
@Deprecated('Use ErrorState from error_state.dart instead — it includes humanize() and a11y support')
class AppErrorState extends StatelessWidget {
  const AppErrorState({
    super.key,
    required this.message,
    required this.onRetry,
    this.iconSize = 48,
  });

  /// Error message to display.
  final String message;

  /// Called when user taps retry button.
  final VoidCallback onRetry;

  /// Size of the error icon. Defaults to 48.
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: iconSize,
              color: cs.error,
            ),
            const SizedBox(height: DesignTokens.spacingMd),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: cs.error,
              ),
            ),
            const SizedBox(height: DesignTokens.spacingLg),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
              style: FilledButton.styleFrom(
                backgroundColor: DesignTokens.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reusable empty state widget.
///
/// Shows empty icon, message, and optional action button.
/// Use when a list has no items, search returns nothing, or no data to display.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.iconSize = 64,
    this.actionLabel,
    this.onAction,
  });

  /// Message to display when there's no data.
  final String message;

  /// Icon to show. Defaults to inbox_outlined.
  final IconData icon;

  /// Size of the icon. Defaults to 64.
  final double iconSize;

  /// Optional label for action button.
  final String? actionLabel;

  /// Optional callback when action button is pressed.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: iconSize,
              color: DesignTokens.textMuted.withValues(alpha: 0.6),
            ),
            const SizedBox(height: DesignTokens.spacingMd),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: DesignTokens.textPrimary,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: DesignTokens.spacingLg),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add, size: 20),
                label: Text(actionLabel ?? ''),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
