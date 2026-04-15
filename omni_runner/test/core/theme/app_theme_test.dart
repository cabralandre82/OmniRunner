import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/core/theme/app_theme.dart';

void main() {
  group('AppTheme design tokens', () {
    test('spacing tokens are correct', () {
      expect(AppTheme.spacing4, 4.0);
      expect(AppTheme.spacing8, 8.0);
      expect(AppTheme.spacing12, 12.0);
      expect(AppTheme.spacing16, 16.0);
      expect(AppTheme.spacing20, 20.0);
      expect(AppTheme.spacing24, 24.0);
      expect(AppTheme.spacing32, 32.0);
    });

    test('radius tokens are correct', () {
      expect(AppTheme.radiusSm, 8.0);
      expect(AppTheme.radiusMd, 12.0);
      expect(AppTheme.radiusLg, 16.0);
      expect(AppTheme.radiusXl, 24.0);
    });

    test('brand colors are defined correctly', () {
      expect(AppTheme.brandBlue, const Color(0xFF3B82F6));
      expect(AppTheme.brandGreen, const Color(0xFF10B981));
      expect(AppTheme.brandOrange, const Color(0xFFF59E0B));
      expect(AppTheme.brandRed, const Color(0xFFEF4444));
    });
  });

  group('AppTheme contrast', () {
    test('M3 light color scheme meets WCAG AA (4.5:1) for primary/error/surface',
        () {
      final cs = ColorScheme.fromSeed(
        seedColor: AppTheme.brandBlue,
        brightness: Brightness.light,
      );

      expect(_cr(cs.primary, cs.onPrimary), greaterThanOrEqualTo(4.5));
      expect(_cr(cs.error, cs.onError), greaterThanOrEqualTo(4.5));
      expect(_cr(cs.surface, cs.onSurface), greaterThanOrEqualTo(4.5));
    });

    test('M3 dark color scheme meets WCAG AA (4.5:1) for primary/error/surface',
        () {
      final cs = ColorScheme.fromSeed(
        seedColor: AppTheme.brandBlue,
        brightness: Brightness.dark,
      );

      expect(_cr(cs.primary, cs.onPrimary), greaterThanOrEqualTo(4.5));
      expect(_cr(cs.error, cs.onError), greaterThanOrEqualTo(4.5));
      expect(_cr(cs.surface, cs.onSurface), greaterThanOrEqualTo(4.5));
    });

    test('light secondary container meets WCAG AA', () {
      final cs = ColorScheme.fromSeed(
        seedColor: AppTheme.brandBlue,
        brightness: Brightness.light,
      );
      expect(
        _cr(cs.secondaryContainer, cs.onSecondaryContainer),
        greaterThanOrEqualTo(4.5),
      );
    });
  });
}

double _cr(Color a, Color b) {
  final l1 = _lum(a);
  final l2 = _lum(b);
  final lighter = l1 > l2 ? l1 : l2;
  final darker = l1 > l2 ? l2 : l1;
  return (lighter + 0.05) / (darker + 0.05);
}

double _lum(Color c) {
  double ch(int v) {
    final s = v / 255.0;
    return s <= 0.04045 ? s / 12.92 : _pow((s + 0.055) / 1.055, 2.4);
  }

  int comp(double channel01) =>
      (channel01 * 255.0).round().clamp(0, 255).toInt();

  return 0.2126 * ch(comp(c.r)) +
      0.7152 * ch(comp(c.g)) +
      0.0722 * ch(comp(c.b));
}

double _pow(double base, double exp) {
  // Use dart:math for precision
  return base <= 0 ? 0 : _exp(exp * _ln(base));
}

double _ln(double x) {
  if (x <= 0) return double.negativeInfinity;
  double result = 0;
  while (x > 2) { x /= 2.718281828; result += 1; }
  while (x < 0.5) { x *= 2.718281828; result -= 1; }
  final y = x - 1;
  double term = y, sum = y;
  for (int n = 2; n <= 20; n++) {
    term *= -y * (n - 1) / n;
    sum += term / n;
  }
  return result + sum;
}

double _exp(double x) {
  double sum = 1, term = 1;
  for (int n = 1; n <= 30; n++) {
    term *= x / n;
    sum += term;
  }
  return sum;
}
