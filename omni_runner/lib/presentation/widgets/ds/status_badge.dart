import 'package:flutter/material.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

enum BadgeVariant { success, warning, error, info, neutral }

/// Compact status badge with color-coded background.
class StatusBadge extends StatelessWidget {
  final String label;
  final BadgeVariant variant;
  final IconData? icon;

  const StatusBadge({
    super.key,
    required this.label,
    this.variant = BadgeVariant.neutral,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (bgColor, fgColor) = _colors(cs);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacingSm + 2,
        vertical: DesignTokens.spacingXs,
      ),
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        border: Border.all(color: bgColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fgColor),
            const SizedBox(width: DesignTokens.spacingXs),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: DesignTokens.captionSize,
              fontWeight: DesignTokens.labelWeight,
              color: fgColor,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  (Color bg, Color fg) _colors(ColorScheme cs) => switch (variant) {
        BadgeVariant.success => (DesignTokens.success, DesignTokens.success),
        BadgeVariant.warning => (DesignTokens.warning, DesignTokens.warning),
        BadgeVariant.error => (DesignTokens.error, DesignTokens.error),
        BadgeVariant.info => (DesignTokens.info, DesignTokens.info),
        BadgeVariant.neutral => (cs.outline, cs.onSurface),
      };
}
