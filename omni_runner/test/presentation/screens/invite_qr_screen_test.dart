import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/presentation/screens/invite_qr_screen.dart';

import '../../helpers/pump_app.dart';

void main() {
  group('InviteQrScreen', () {
    final origOnError = FlutterError.onError;
    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        if (msg.contains('Supabase')) return;
        origOnError?.call(details);
      };
    });
    tearDown(() => FlutterError.onError = origOnError);

    testWidgets('renders without crash and has AppBar', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        const InviteQrScreen(
          inviteCode: 'TEST123',
          groupName: 'Assessoria Teste',
        ),
        wrapScaffold: false,
      );

      expect(find.byType(InviteQrScreen), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Convite da Assessoria'), findsOneWidget);
    });

    testWidgets('shows group name', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        const InviteQrScreen(
          inviteCode: 'TEST123',
          groupName: 'Assessoria Teste',
        ),
        wrapScaffold: false,
      );

      expect(find.text('Assessoria Teste'), findsOneWidget);
    });

    testWidgets('shows invite code', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        const InviteQrScreen(
          inviteCode: 'TEST123',
          groupName: 'Assessoria Teste',
        ),
        wrapScaffold: false,
      );

      expect(find.text('TEST123'), findsOneWidget);
    });

    testWidgets('shows copy and share buttons', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        const InviteQrScreen(
          inviteCode: 'TEST123',
          groupName: 'Assessoria Teste',
        ),
        wrapScaffold: false,
      );

      expect(find.text('Copiar link'), findsOneWidget);
      expect(find.text('Compartilhar'), findsOneWidget);
    });

    testWidgets('shows group icon', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        const InviteQrScreen(
          inviteCode: 'TEST123',
          groupName: 'Assessoria Teste',
        ),
        wrapScaffold: false,
      );

      expect(find.byIcon(Icons.group_add_rounded), findsOneWidget);
    });
  });
}
