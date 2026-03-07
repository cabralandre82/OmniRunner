import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/coaching_member_entity.dart';
import 'package:omni_runner/presentation/screens/staff_qr_hub_screen.dart';

import '../../helpers/pump_app.dart';

const _staffMember = CoachingMemberEntity(
  id: 'm1',
  userId: 'u1',
  groupId: 'g1',
  displayName: 'Staff User',
  role: CoachingRole.adminMaster,
  joinedAtMs: 0,
);

const _athleteMember = CoachingMemberEntity(
  id: 'm2',
  userId: 'u2',
  groupId: 'g1',
  displayName: 'Athlete User',
  role: CoachingRole.athlete,
  joinedAtMs: 0,
);

void main() {
  group('StaffQrHubScreen', () {
    final origOnError = FlutterError.onError;
    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
    });
    tearDown(() => FlutterError.onError = origOnError);

    testWidgets('renders without crash for staff member', (tester) async {
      await tester.pumpApp(
        const StaffQrHubScreen(membership: _staffMember),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows AppBar with correct title', (tester) async {
      await tester.pumpApp(
        const StaffQrHubScreen(membership: _staffMember),
        wrapScaffold: false,
      );

      expect(find.text('Operações QR'), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows operation cards for staff', (tester) async {
      await tester.pumpApp(
        const StaffQrHubScreen(membership: _staffMember),
        wrapScaffold: false,
      );

      expect(find.text('Emitir OmniCoins'), findsOneWidget);
      expect(find.text('Recolher OmniCoins'), findsOneWidget);
      expect(find.text('Ativar Badge de Campeonato'), findsOneWidget);
      expect(find.text('Ler QR Code'), findsOneWidget);
    });

    testWidgets('shows access denied for non-staff', (tester) async {
      await tester.pumpApp(
        const StaffQrHubScreen(membership: _athleteMember),
        wrapScaffold: false,
      );

      expect(find.text('Acesso Restrito'), findsOneWidget);
    });
  });
}
