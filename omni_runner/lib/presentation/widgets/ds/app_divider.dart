import 'package:flutter/material.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

/// Themed divider that respects the design system.
class AppDivider extends StatelessWidget {
  final double? indent;
  final double? endIndent;
  final double height;

  const AppDivider({
    super.key,
    this.indent,
    this.endIndent,
    this.height = DesignTokens.spacingMd,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Divider(
      height: height,
      thickness: 1,
      indent: indent,
      endIndent: endIndent,
      color: isDark
          ? DesignTokens.border.withValues(alpha: 0.3)
          : DesignTokens.borderLight.withValues(alpha: 0.5),
    );
  }
}
