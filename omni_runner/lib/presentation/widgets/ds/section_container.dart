import 'package:flutter/material.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

/// Section wrapper with optional title and action.
class SectionContainer extends StatelessWidget {
  final String? title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const SectionContainer({
    super.key,
    this.title,
    this.trailing,
    required this.child,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: padding ??
          const EdgeInsets.symmetric(horizontal: DesignTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title!,
                  style: TextStyle(
                    fontSize: DesignTokens.titleMediumSize,
                    fontWeight: DesignTokens.titleMediumWeight,
                    color: cs.onSurface,
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: DesignTokens.spacingSm),
          ],
          child,
        ],
      ),
    );
  }
}
