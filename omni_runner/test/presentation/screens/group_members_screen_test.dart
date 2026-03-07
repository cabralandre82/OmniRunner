import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/coaching_member_entity.dart';
import 'package:omni_runner/presentation/screens/group_members_screen.dart';

import '../../helpers/pump_app.dart';

final _coach = CoachingMemberEntity(
  id: 'm1',
  userId: 'u1',
  groupId: 'g1',
  displayName: 'Prof. Silva',
  role: CoachingRole.coach,
  joinedAtMs: DateTime(2025, 6, 1).millisecondsSinceEpoch,
);

final _athlete = CoachingMemberEntity(
  id: 'm2',
  userId: 'u2',
  groupId: 'g1',
  displayName: 'Carlos',
  role: CoachingRole.athlete,
  joinedAtMs: DateTime(2026, 1, 15).millisecondsSinceEpoch,
);

void main() {
  group('GroupMembersScreen', () {
    final origOnError = FlutterError.onError;
    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
    });
    tearDown(() => FlutterError.onError = origOnError);

    testWidgets('shows app bar with group name', (tester) async {
      await tester.pumpApp(
        const GroupMembersScreen(
          groupName: 'Team Run',
          members: [],
          currentUserId: 'u1',
        ),
        wrapScaffold: false,
      );

      expect(find.text('Membros · Team Run'), findsOneWidget);
    });

    testWidgets('shows empty message when no members', (tester) async {
      await tester.pumpApp(
        const GroupMembersScreen(
          groupName: 'Test',
          members: [],
          currentUserId: 'u1',
        ),
        wrapScaffold: false,
      );

      expect(find.text('Nenhum membro encontrado.'), findsOneWidget);
    });

    testWidgets('shows member list with role badges', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        GroupMembersScreen(
          groupName: 'Test',
          members: [_coach, _athlete],
          currentUserId: 'u1',
        ),
        wrapScaffold: false,
      );

      expect(find.text('Prof. Silva (você)'), findsOneWidget);
      expect(find.text('Carlos'), findsOneWidget);
      expect(find.text('Coach'), findsOneWidget);
      expect(find.text('Atleta'), findsOneWidget);
    });

    testWidgets('marks current user with (você)', (tester) async {
      await tester.pumpApp(
        GroupMembersScreen(
          groupName: 'Test',
          members: [_coach],
          currentUserId: 'u1',
        ),
        wrapScaffold: false,
      );

      expect(find.textContaining('(você)'), findsOneWidget);
    });
  });
}
