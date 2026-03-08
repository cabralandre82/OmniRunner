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
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: DesignTokens.spacingMd),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface,
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
