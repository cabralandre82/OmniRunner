import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/presentation/widgets/shimmer_loading.dart';

import '../../helpers/pump_app.dart';

void main() {
  group('SkeletonTile', () {
    testWidgets('renders placeholder containers', (tester) async {
      await tester.pumpApp(const SkeletonTile());

      final containers = find.byType(Container);
      expect(containers, findsWidgets);
    });
  });

  group('SkeletonCard', () {
    testWidgets('renders card placeholder', (tester) async {
      await tester.pumpApp(
        const SizedBox(
          width: 200,
          height: 200,
          child: SkeletonCard(),
        ),
      );

      expect(find.byType(SkeletonCard), findsOneWidget);
    });
  });

  group('ShimmerListLoader', () {
    testWidgets('renders correct number of skeleton tiles', (tester) async {
      await tester.pumpApp(
        const ShimmerListLoader(itemCount: 3),
      );

      expect(find.byType(SkeletonTile), findsNWidgets(3));
    });

    testWidgets('defaults to 6 items', (tester) async {
      await tester.pumpApp(
        const ShimmerListLoader(),
      );

      expect(find.byType(SkeletonTile), findsNWidgets(6));
    });

    testWidgets('has Semantics wrapper', (tester) async {
      await tester.pumpApp(
        const ShimmerListLoader(),
      );

      expect(find.byType(Semantics), findsWidgets);
    });
  });

  group('ShimmerLoading', () {
    testWidgets('wraps child with animation', (tester) async {
      await tester.pumpApp(
        const ShimmerLoading(
          child: SizedBox(width: 100, height: 20),
        ),
      );

      expect(find.byType(ShaderMask), findsOneWidget);
      expect(find.byType(ShimmerLoading), findsOneWidget);
    });

    testWidgets('disposes animation controller', (tester) async {
      await tester.pumpApp(
        const ShimmerLoading(child: Text('Loading')),
      );

      expect(find.text('Loading'), findsOneWidget);

      // Pump a new widget tree to trigger dispose
      await tester.pumpApp(const Text('Done'));
    });
  });
}
