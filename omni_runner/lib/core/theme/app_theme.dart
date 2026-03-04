import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'design_tokens.dart';

/// Centralized theme configuration for Omni Runner.
///
/// All values derive from [DesignTokens]. Screens must use
/// `Theme.of(context).colorScheme.*` and `AppTheme.spacing*` —
/// never hardcoded Color() or EdgeInsets literals.
abstract final class AppTheme {
  // ── Re-export spacing tokens for backward compatibility ──
  static const spacing4 = DesignTokens.spacingXs;
  static const spacing8 = DesignTokens.spacingSm;
  static const spacing12 = 12.0;
  static const spacing16 = DesignTokens.spacingMd;
  static const spacing20 = 20.0;
  static const spacing24 = DesignTokens.spacingLg;
  static const spacing32 = DesignTokens.spacingXl;

  // ── Re-export semantic tokens ──
  static const spacingXs = DesignTokens.spacingXs;
  static const spacingSm = DesignTokens.spacingSm;
  static const spacingMd = DesignTokens.spacingMd;
  static const spacingLg = DesignTokens.spacingLg;
  static const spacingXl = DesignTokens.spacingXl;
  static const spacingXxl = DesignTokens.spacingXxl;

  static const radiusSm = DesignTokens.radiusSm;
  static const radiusMd = DesignTokens.radiusMd;
  static const radiusLg = DesignTokens.radiusLg;
  static const radiusXl = DesignTokens.radiusXl;

  // ── Brand colors (semantic, use via colorScheme when possible) ──
  static const brandBlue = DesignTokens.primary;
  static const brandGreen = DesignTokens.success;
  static const brandOrange = DesignTokens.warning;
  static const brandRed = DesignTokens.error;

  static const _pageTransitions = PageTransitionsTheme(
    builders: {
      TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    },
  );

  static TextTheme _textTheme(Brightness brightness) {
    final base = brightness == Brightness.light
        ? ThemeData.light().textTheme
        : ThemeData.dark().textTheme;
    return GoogleFonts.interTextTheme(base);
  }

  // ═══════════════════════════════════════════════════════════════
  // LIGHT THEME
  // ═══════════════════════════════════════════════════════════════

  static ThemeData light() {
    const colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: DesignTokens.primaryLight,
      onPrimary: Colors.white,
      primaryContainer: DesignTokens.primarySoftLight,
      onPrimaryContainer: DesignTokens.primaryLight,
      secondary: DesignTokens.textSecondaryLight,
      onSecondary: Colors.white,
      secondaryContainer: DesignTokens.bgSecondaryLight,
      onSecondaryContainer: DesignTokens.textPrimaryLight,
      tertiary: DesignTokens.info,
      onTertiary: Colors.white,
      surface: DesignTokens.surfaceLight,
      onSurface: DesignTokens.textPrimaryLight,
      surfaceContainerLow: DesignTokens.bgSecondaryLight,
      surfaceContainer: DesignTokens.bgPrimaryLight,
      surfaceContainerHigh: DesignTokens.bgSecondaryLight,
      error: DesignTokens.error,
      onError: Colors.white,
      outline: DesignTokens.borderLight,
      outlineVariant: DesignTokens.borderSubtleLight,
      shadow: Color(0x1A000000),
    );

    return _buildTheme(colorScheme, Brightness.light);
  }

  // ═══════════════════════════════════════════════════════════════
  // DARK THEME (Premium Dark)
  // ═══════════════════════════════════════════════════════════════

  static ThemeData dark() {
    const colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: DesignTokens.primary,
      onPrimary: Colors.white,
      primaryContainer: DesignTokens.primarySoft,
      onPrimaryContainer: DesignTokens.primary,
      secondary: DesignTokens.textSecondary,
      onSecondary: DesignTokens.bgPrimary,
      secondaryContainer: DesignTokens.surface,
      onSecondaryContainer: DesignTokens.textPrimary,
      tertiary: DesignTokens.info,
      onTertiary: DesignTokens.bgPrimary,
      surface: DesignTokens.bgSecondary,
      onSurface: DesignTokens.textPrimary,
      surfaceContainerLow: DesignTokens.bgPrimary,
      surfaceContainer: DesignTokens.surface,
      surfaceContainerHigh: DesignTokens.surfaceElevated,
      error: DesignTokens.error,
      onError: Colors.white,
      outline: DesignTokens.border,
      outlineVariant: DesignTokens.borderSubtle,
      shadow: Color(0x40000000),
    );

    return _buildTheme(colorScheme, Brightness.dark);
  }

  // ═══════════════════════════════════════════════════════════════
  // SHARED THEME BUILDER
  // ═══════════════════════════════════════════════════════════════

  static ThemeData _buildTheme(ColorScheme colorScheme, Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: brightness == Brightness.dark
          ? DesignTokens.bgPrimary
          : DesignTokens.bgPrimaryLight,
      textTheme: _textTheme(brightness),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        titleTextStyle: GoogleFonts.inter(
          fontSize: DesignTokens.titleMediumSize - 2,
          fontWeight: DesignTokens.titleMediumWeight,
          color: colorScheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(
              alpha: brightness == Brightness.dark ? 0.3 : 0.5,
            ),
          ),
        ),
        color: brightness == Brightness.dark
            ? DesignTokens.surface
            : colorScheme.surface,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spacingMd,
          vertical: 12,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spacingLg,
            vertical: 12,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          elevation: 0,
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spacingLg,
            vertical: 12,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spacingLg,
            vertical: 12,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spacingSm,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        type: BottomNavigationBarType.fixed,
        backgroundColor: brightness == Brightness.dark
            ? DesignTokens.bgSecondary
            : null,
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: colorScheme.onSurfaceVariant,
        showUnselectedLabels: true,
        selectedLabelStyle: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: GoogleFonts.inter(fontSize: 11),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXl),
        ),
        backgroundColor: brightness == Brightness.dark
            ? DesignTokens.surface
            : null,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        showDragHandle: true,
        backgroundColor: brightness == Brightness.dark
            ? DesignTokens.surface
            : null,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(DesignTokens.radiusXl),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        space: 1,
        color: colorScheme.outlineVariant.withValues(alpha: 0.3),
      ),
      pageTransitionsTheme: _pageTransitions,
    );
  }
}
