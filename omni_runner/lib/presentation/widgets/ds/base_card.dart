import 'package:flutter/material.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

/// Premium dark card with optional border, glow, and press feedback.
class BaseCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final bool elevated;
  final bool glow;

  const BaseCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.elevated = false,
    this.glow = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bg = elevated
        ? (isDark ? DesignTokens.surfaceElevated : cs.surface)
        : (isDark ? DesignTokens.surface : cs.surface);

    final borderColor = isDark
        ? DesignTokens.border.withValues(alpha: 0.4)
        : cs.outlineVariant.withValues(alpha: 0.5);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        splashColor: cs.primary.withValues(alpha: DesignTokens.opacityPressed),
        highlightColor: cs.primary.withValues(alpha: DesignTokens.opacityHover),
        child: AnimatedContainer(
          duration: DesignTokens.durationFast,
          padding: padding ??
              const EdgeInsets.all(DesignTokens.spacingMd),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
            border: Border.all(color: borderColor, width: 1),
            boxShadow: glow ? DesignTokens.glowPrimary : null,
          ),
          child: child,
        ),
      ),
    );
  }
}
