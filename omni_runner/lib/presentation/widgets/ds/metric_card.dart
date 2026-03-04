import 'package:flutter/material.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';
import 'package:omni_runner/presentation/widgets/ds/base_card.dart';

/// Card optimized for displaying a single metric with label.
class MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final IconData? icon;
  final Color? accentColor;
  final VoidCallback? onTap;

  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.icon,
    this.accentColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = accentColor ?? cs.primary;

    return BaseCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: accent),
                const SizedBox(width: DesignTokens.spacingSm),
              ],
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: DesignTokens.captionSize,
                    fontWeight: DesignTokens.labelWeight,
                    color: cs.onSurface.withValues(alpha: 0.6),
                    letterSpacing: 0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignTokens.spacingSm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: DesignTokens.titleLargeSize,
                  fontWeight: DesignTokens.displayLargeWeight,
                  color: cs.onSurface,
                  height: 1.1,
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: DesignTokens.spacingXs),
                Text(
                  unit!,
                  style: TextStyle(
                    fontSize: DesignTokens.captionSize,
                    fontWeight: DesignTokens.labelWeight,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
