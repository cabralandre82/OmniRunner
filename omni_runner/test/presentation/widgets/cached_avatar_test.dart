import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/presentation/widgets/cached_avatar.dart';

import '../../helpers/pump_app.dart';

void main() {
  group('CachedAvatar', () {
    testWidgets('shows initials when url is null', (tester) async {
      await tester.pumpApp(
        const CachedAvatar(
          url: null,
          fallbackText: 'João Silva',
          radius: 24,
        ),
      );

      expect(find.text('JS'), findsOneWidget);
      expect(find.byType(CircleAvatar), findsOneWidget);
    });

    testWidgets('shows initials when url is empty', (tester) async {
      await tester.pumpApp(
        const CachedAvatar(
          url: '',
          fallbackText: 'Maria',
          radius: 24,
        ),
      );

      expect(find.text('M'), findsOneWidget);
    });

    testWidgets('shows single letter for single name', (tester) async {
      await tester.pumpApp(
        const CachedAvatar(
          url: null,
          fallbackText: 'Ana',
          radius: 20,
        ),
      );

      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('shows ? for empty fallbackText', (tester) async {
      await tester.pumpApp(
        const CachedAvatar(
          url: null,
          fallbackText: '',
          radius: 20,
        ),
      );

      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('uses correct radius', (tester) async {
      await tester.pumpApp(
        const CachedAvatar(
          url: null,
          fallbackText: 'Test',
          radius: 40,
        ),
      );

      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.radius, 40);
    });
  });

  group('CachedAvatar._initials', () {
    test('extracts two initials from full name', () {
      expect(CachedAvatar.initialsOf('João Silva'), 'JS');
    });

    test('extracts single initial from first name only', () {
      expect(CachedAvatar.initialsOf('Ana'), 'A');
    });

    test('returns ? for empty string', () {
      expect(CachedAvatar.initialsOf(''), '?');
    });

    test('handles multiple spaces', () {
      expect(CachedAvatar.initialsOf('  Maria   Costa  '), 'MC');
    });
  });
}
