import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/presentation/widgets/staggered_list.dart';

import '../../helpers/pump_app.dart';

void main() {
  group('StaggeredList', () {
    testWidgets('renders all children', (tester) async {
      await tester.pumpApp(
        const StaggeredList(
          children: [
            Text('Item 1'),
            Text('Item 2'),
            Text('Item 3'),
          ],
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Item 1'), findsOneWidget);
      expect(find.text('Item 2'), findsOneWidget);
      expect(find.text('Item 3'), findsOneWidget);
    });

    testWidgets('renders empty list without error', (tester) async {
      await tester.pumpApp(
        const StaggeredList(children: []),
      );

      await tester.pumpAndSettle();
      expect(find.byType(StaggeredList), findsOneWidget);
    });

    testWidgets('children become visible after animation', (tester) async {
      await tester.pumpApp(
        const StaggeredList(
          staggerDelay: Duration(milliseconds: 10),
          itemDuration: Duration(milliseconds: 50),
          children: [
            Text('Animated'),
          ],
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Animated'), findsOneWidget);
    });

    testWidgets('uses Column with crossAxisAlignment.stretch', (tester) async {
      await tester.pumpApp(
        const StaggeredList(
          children: [Text('A')],
        ),
      );

      final column = tester.widget<Column>(
        find.descendant(
          of: find.byType(StaggeredList),
          matching: find.byType(Column).first,
        ),
      );
      expect(column.crossAxisAlignment, CrossAxisAlignment.stretch);

      await tester.pumpAndSettle();
    });
  });
}
