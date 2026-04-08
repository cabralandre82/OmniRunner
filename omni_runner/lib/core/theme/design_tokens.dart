import 'package:flutter/material.dart';

/// Global Design Tokens — Single source of truth for all visual properties.
///
/// These tokens are consumed by [AppTheme] and should be the ONLY place
/// where raw color/spacing/radius values are defined. Screens and widgets
/// must never use hardcoded Color() or EdgeInsets literals.
///
/// Portal counterpart: portal/src/styles/tokens.css
abstract final class DesignTokens {
  // ═══════════════════════════════════════════════════════════════
  // 1. PALETTE — Premium Dark
  // ═══════════════════════════════════════════════════════════════

  static const bgPrimary = Color(0xFF0A0E17);
  static const bgSecondary = Color(0xFF111827);
  static const surface = Color(0xFF1E293B);
  static const surfaceElevated = Color(0xFF283548);

  static const primary = Color(0xFF3B82F6);
  static const brand = primary;
  static const primarySoft = Color(0xFF1E3A5F);
  static const primaryGlow = Color(0x333B82F6);

  static const textPrimary = Color(0xFFF1F5F9);
  static const textSecondary = Color(0xFF94A3B8);
  static const textMuted = Color(0xFF64748B);

  static const success = Color(0xFF10B981);
  static const warning = Color(0xFFF59E0B);
  static const error = Color(0xFFEF4444);
  static const info = Color(0xFF38BDF8);

  // Semantic aliases used by specific UI patterns
  static const border = Color(0xFF334155);
  static const borderSubtle = Color(0xFF1E293B);
  static const overlay = Color(0xCC000000);

  // ═══════════════════════════════════════════════════════════════
  // 1b. PALETTE — Light (for light mode)
  // ═══════════════════════════════════════════════════════════════

  static const bgPrimaryLight = Color(0xFFF8FAFC);
  static const bgSecondaryLight = Color(0xFFF1F5F9);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const surfaceElevatedLight = Color(0xFFFFFFFF);

  static const primaryLight = Color(0xFF2563EB);
  static const primarySoftLight = Color(0xFFDBEAFE);
  static const primaryGlowLight = Color(0x1A2563EB);

  static const textPrimaryLight = Color(0xFF0F172A);
  static const textSecondaryLight = Color(0xFF475569);
  static const textMutedLight = Color(0xFF94A3B8);

  static const borderLight = Color(0xFFE2E8F0);
  static const borderSubtleLight = Color(0xFFF1F5F9);

  // ═══════════════════════════════════════════════════════════════
  // 2. TYPOGRAPHY
  // ═══════════════════════════════════════════════════════════════

  static const fontFamily = 'Inter';

  static const displayLargeSize = 32.0;
  static const displayLargeWeight = FontWeight.w700;

  static const displayMediumSize = 28.0;
  static const displayMediumWeight = FontWeight.w700;

  static const titleLargeSize = 24.0;
  static const titleLargeWeight = FontWeight.w600;

  static const titleMediumSize = 20.0;
  static const titleMediumWeight = FontWeight.w600;

  static const bodySize = 16.0;
  static const bodyWeight = FontWeight.w400;

  static const captionSize = 12.0;
  static const captionWeight = FontWeight.w400;

  static const labelSize = 14.0;
  static const labelWeight = FontWeight.w500;

  // ═══════════════════════════════════════════════════════════════
  // 3. SPACING
  // ═══════════════════════════════════════════════════════════════

  static const spacingXs = 4.0;
  static const spacingSm = 8.0;
  static const spacingMd = 16.0;
  static const spacingLg = 24.0;
  static const spacingXl = 32.0;
  static const spacingXxl = 48.0;

  // ═══════════════════════════════════════════════════════════════
  // 4. BORDER RADIUS
  // ═══════════════════════════════════════════════════════════════

  static const radiusSm = 8.0;
  static const radiusMd = 12.0;
  static const radiusLg = 16.0;
  static const radiusXl = 24.0;
  static const radiusFull = 999.0;

  // ═══════════════════════════════════════════════════════════════
  // 5. ELEVATION / SHADOWS
  // ═══════════════════════════════════════════════════════════════

  static final shadowSm = [
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: 0.15),
      blurRadius: 4,
      offset: const Offset(0, 1),
    ),
  ];

  static final shadowMd = [
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: 0.2),
      blurRadius: 8,
      offset: const Offset(0, 4),
    ),
  ];

  static final shadowLg = [
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: 0.25),
      blurRadius: 16,
      offset: const Offset(0, 8),
    ),
  ];

  static final glowPrimary = [
    BoxShadow(
      color: primary.withValues(alpha: 0.3),
      blurRadius: 16,
      spreadRadius: -2,
    ),
  ];

  // ═══════════════════════════════════════════════════════════════
  // 6. ANIMATION DURATIONS
  // ═══════════════════════════════════════════════════════════════

  static const durationFast = Duration(milliseconds: 150);
  static const durationNormal = Duration(milliseconds: 250);
  static const durationSlow = Duration(milliseconds: 400);

  // ═══════════════════════════════════════════════════════════════
  // 7. STATES (opacity multipliers)
  // ═══════════════════════════════════════════════════════════════

  static const opacityHover = 0.08;
  static const opacityPressed = 0.12;
  static const opacityDisabled = 0.38;
  static const opacityFocus = 0.12;
}
