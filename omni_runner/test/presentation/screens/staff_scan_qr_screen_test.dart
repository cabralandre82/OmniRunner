import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/presentation/blocs/staff_qr/staff_qr_bloc.dart';
import 'package:omni_runner/presentation/blocs/staff_qr/staff_qr_event.dart';
import 'package:omni_runner/presentation/blocs/staff_qr/staff_qr_state.dart';
import 'package:omni_runner/presentation/screens/staff_scan_qr_screen.dart';

import '../../helpers/pump_app.dart';

class _FakeStaffQrBloc extends Cubit<StaffQrState> implements StaffQrBloc {
  _FakeStaffQrBloc(super.initial);

  @override
  void add(StaffQrEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('StaffScanQrScreen', () {
    final origOnError = FlutterError.onError;
    late _FakeStaffQrBloc fakeBloc;

    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed') || msg.contains('MobileScanner')) {
          return;
        }
        origOnError?.call(details);
      };
      fakeBloc = _FakeStaffQrBloc(const StaffQrConsuming());
    });
    tearDown(() => FlutterError.onError = origOnError);

    testWidgets('renders without crash', (tester) async {
      await tester.pumpApp(
        BlocProvider<StaffQrBloc>.value(
          value: fakeBloc,
          child: const StaffScanQrScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows AppBar with correct title', (tester) async {
      await tester.pumpApp(
        BlocProvider<StaffQrBloc>.value(
          value: fakeBloc,
          child: const StaffScanQrScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Escanear QR'), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows processing indicator for consuming state',
        (tester) async {
      await tester.pumpApp(
        BlocProvider<StaffQrBloc>.value(
          value: fakeBloc,
          child: const StaffScanQrScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Processando...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
