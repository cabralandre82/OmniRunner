import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/presentation/widgets/error_state.dart';

import '../../helpers/pump_app.dart';

void main() {
  group('ErrorState', () {
    testWidgets('renders friendly message and retry button', (tester) async {
      var retried = false;

      await tester.pumpApp(
        ErrorState(
          message: 'SocketException: connection refused',
          onRetry: () => retried = true,
        ),
      );

      expect(find.textContaining('Sem conexão'), findsOneWidget);
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);

      await tester.tap(find.byType(OutlinedButton));
      expect(retried, isTrue);
    });

    testWidgets('hides retry button when onRetry is null', (tester) async {
      await tester.pumpApp(
        const ErrorState(message: 'Something failed'),
      );

      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('renders error icon', (tester) async {
      await tester.pumpApp(
        const ErrorState(message: 'Error'),
      );

      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
    });
  });

  group('ErrorState.humanize', () {
    test('returns friendly message for SocketException', () {
      final result = ErrorState.humanize('SocketException: connection refused');
      expect(result, contains('Sem conexão'));
    });

    test('returns friendly message for timeout', () {
      final result = ErrorState.humanize('TimeoutException after 30s');
      expect(result, contains('demorou'));
    });

    test('returns friendly message for 401', () {
      final result = ErrorState.humanize('401 Unauthorized');
      expect(result, contains('sessão expirou'));
    });

    test('returns friendly message for 403', () {
      final result = ErrorState.humanize('403 Forbidden');
      expect(result, contains('permissão'));
    });

    test('returns friendly message for 404', () {
      final result = ErrorState.humanize('404 Not Found');
      expect(result, contains('não foi encontrado'));
    });

    test('returns friendly message for 500', () {
      final result = ErrorState.humanize('500 Internal Server Error');
      expect(result, contains('servidor'));
    });

    test('truncates very long messages', () {
      final long = 'x' * 200;
      final result = ErrorState.humanize(long);
      expect(result, contains('Algo deu errado'));
    });

    test('returns raw message for short unknown errors', () {
      final result = ErrorState.humanize('Custom error');
      expect(result, 'Custom error');
    });
  });
}
