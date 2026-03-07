import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/group_entity.dart';
import 'package:omni_runner/domain/entities/group_member_entity.dart';
import 'package:omni_runner/presentation/screens/group_details_screen.dart';

import '../../helpers/pump_app.dart';

final _group = GroupEntity(
  id: 'g1',
  name: 'Grupo Corrida Leve',
  description: 'Um grupo para iniciantes',
  createdByUserId: 'u1',
  createdAtMs: 0,
  privacy: GroupPrivacy.open,
  memberCount: 5,
);

final _member = GroupMemberEntity(
  id: 'm1',
  groupId: 'g1',
  userId: 'u1',
  displayName: 'Maria',
  role: GroupRole.admin,
  joinedAtMs: 0,
);

final _goal = GroupGoalEntity(
  id: 'goal1',
  groupId: 'g1',
  title: '500 km em março',
  targetValue: 500000,
  currentValue: 250000,
  metric: GoalMetric.distance,
  startsAtMs: 0,
  endsAtMs: 1000000,
  createdByUserId: 'u1',
);

void main() {
  group('GroupDetailsScreen', () {
    final origOnError = FlutterError.onError;
    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
    });
    tearDown(() => FlutterError.onError = origOnError);

    testWidgets('renders group name in app bar', (tester) async {
      await tester.pumpApp(
        GroupDetailsScreen(group: _group),
        wrapScaffold: false,
      );

      expect(find.text('Grupo Corrida Leve'), findsWidgets);
    });

    testWidgets('shows description and privacy label', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        GroupDetailsScreen(group: _group),
        wrapScaffold: false,
      );

      expect(find.text('Um grupo para iniciantes'), findsOneWidget);
      expect(find.textContaining('Aberto'), findsOneWidget);
    });

    testWidgets('shows members section with empty state', (tester) async {
      await tester.pumpApp(
        GroupDetailsScreen(group: _group, members: const []),
        wrapScaffold: false,
      );

      expect(find.textContaining('Membros (0)'), findsOneWidget);
      expect(find.text('Nenhum membro carregado.'), findsOneWidget);
    });

    testWidgets('shows member tiles when provided', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        GroupDetailsScreen(group: _group, members: [_member]),
        wrapScaffold: false,
      );

      expect(find.text('Maria'), findsOneWidget);
      expect(find.text('Admin'), findsOneWidget);
    });

    testWidgets('shows goals when provided', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        GroupDetailsScreen(group: _group, goals: [_goal]),
        wrapScaffold: false,
      );

      expect(find.text('Metas ativas'), findsOneWidget);
      expect(find.text('500 km em março'), findsOneWidget);
    });
  });
}
