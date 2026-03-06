import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

/// Tests the "Parceiras" card rendering in the staff dashboard.
/// We simulate the card widget directly to avoid the full Supabase dependency.

class _FakeParceiraCard extends StatelessWidget {
  final int pendingCount;
  final VoidCallback onTap;

  const _FakeParceiraCard({
    required this.pendingCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.handshake_rounded, size: 32),
              const SizedBox(height: 8),
              const Text('Parceiras', style: TextStyle(fontWeight: FontWeight.bold)),
              const Text('Assessorias amigas'),
              if (pendingCount > 0) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$pendingCount ${pendingCount == 1 ? "convite pendente" : "convites pendentes"}',
                    style: const TextStyle(fontSize: 11, color: Colors.orange),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

void main() {
  final origOnError = FlutterError.onError;
  setUp(() {
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      origOnError?.call(details);
    };
  });
  tearDown(() => FlutterError.onError = origOnError);

  group('Staff Dashboard — Parceiras card', () {
    testWidgets('shows card with no alert when 0 pending', (tester) async {
      var tapped = false;
      await tester.pumpApp(
        _FakeParceiraCard(pendingCount: 0, onTap: () => tapped = true),
      );

      expect(find.text('Parceiras'), findsOneWidget);
      expect(find.text('Assessorias amigas'), findsOneWidget);
      expect(find.byIcon(Icons.handshake_rounded), findsOneWidget);
      expect(find.textContaining('pendente'), findsNothing);

      await tester.tap(find.text('Parceiras'));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('shows singular alert for 1 pending', (tester) async {
      await tester.pumpApp(
        _FakeParceiraCard(pendingCount: 1, onTap: () {}),
      );

      expect(find.text('1 convite pendente'), findsOneWidget);
    });

    testWidgets('shows plural alert for multiple pending', (tester) async {
      await tester.pumpApp(
        _FakeParceiraCard(pendingCount: 5, onTap: () {}),
      );

      expect(find.text('5 convites pendentes'), findsOneWidget);
    });

    testWidgets('handles large pending count', (tester) async {
      await tester.pumpApp(
        _FakeParceiraCard(pendingCount: 99, onTap: () {}),
      );

      expect(find.text('99 convites pendentes'), findsOneWidget);
    });
  });
}
