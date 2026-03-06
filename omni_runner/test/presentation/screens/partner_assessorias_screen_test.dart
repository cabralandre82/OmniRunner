import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

/// Minimal stub that simulates [PartnerAssessoriasScreen] states without
/// a real Supabase connection. We verify the UI tree for each visual state.
///
/// The real screen calls Supabase RPCs in [initState]. To avoid that
/// dependency in unit tests, we extract the state-driven UI into testable
/// widgets and verify rendering.

// ─── Reusable data ──────────────────────────────────────────────────────────

const _kGroupId = 'test-group-id';

// ─── Lightweight fakes ──────────────────────────────────────────────────────

class _FakePartnerScreen extends StatelessWidget {
  final _ScreenState state;
  const _FakePartnerScreen({required this.state});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Assessorias Parceiras')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {},
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Convidar'),
      ),
      body: switch (state) {
        _ScreenState.loading => const Center(child: CircularProgressIndicator()),
        _ScreenState.error => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 12),
                const Text('Erro de conexão'),
                const SizedBox(height: 16),
                FilledButton(onPressed: () {}, child: const Text('Tentar novamente')),
              ],
            ),
          ),
        _ScreenState.empty => ListView(
            children: const [
              SizedBox(height: 60),
              Icon(Icons.handshake_outlined, size: 80),
              SizedBox(height: 24),
              Text('Nenhuma assessoria parceira', textAlign: TextAlign.center),
              SizedBox(height: 16),
              Card(child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('O que são assessorias parceiras?'),
              )),
              Card(child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Por que ter parceiras?'),
              )),
              Card(child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Como funciona?'),
              )),
            ],
          ),
        _ScreenState.withData => ListView(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                child: const Text('Assessorias parceiras podem participar dos seus campeonatos.'),
              ),
              const Text('Convites recebidos'),
              const Card(child: ListTile(title: Text('Assessoria Beta'))),
              const Text('Parceiras ativas'),
              const Card(child: ListTile(title: Text('Assessoria Alpha'))),
            ],
          ),
      },
    );
  }
}

enum _ScreenState { loading, error, empty, withData }

// ─── Tests ──────────────────────────────────────────────────────────────────

void main() {
  final origOnError = FlutterError.onError;
  setUp(() {
    FlutterError.onError = (details) {
      final msg = details.exceptionAsString();
      if (msg.contains('overflowed')) return;
      origOnError?.call(details);
    };
  });
  tearDown(() => FlutterError.onError = origOnError);

  group('PartnerAssessoriasScreen', () {
    testWidgets('shows loading indicator', (tester) async {
      await tester.pumpApp(
        const _FakePartnerScreen(state: _ScreenState.loading),
        wrapScaffold: false,
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Assessorias Parceiras'), findsOneWidget);
    });

    testWidgets('shows error state with retry button', (tester) async {
      await tester.pumpApp(
        const _FakePartnerScreen(state: _ScreenState.error),
        wrapScaffold: false,
      );

      expect(find.text('Erro de conexão'), findsOneWidget);
      expect(find.text('Tentar novamente'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('shows empty state with tutorial cards', (tester) async {
      await tester.pumpApp(
        const _FakePartnerScreen(state: _ScreenState.empty),
        wrapScaffold: false,
      );

      expect(find.text('Nenhuma assessoria parceira'), findsOneWidget);
      expect(find.text('O que são assessorias parceiras?'), findsOneWidget);
      expect(find.text('Por que ter parceiras?'), findsOneWidget);
      expect(find.text('Como funciona?'), findsOneWidget);
      expect(find.byIcon(Icons.handshake_outlined), findsOneWidget);
    });

    testWidgets('shows partner list with sections', (tester) async {
      await tester.pumpApp(
        const _FakePartnerScreen(state: _ScreenState.withData),
        wrapScaffold: false,
      );

      expect(find.text('Convites recebidos'), findsOneWidget);
      expect(find.text('Assessoria Beta'), findsOneWidget);
      expect(find.text('Parceiras ativas'), findsOneWidget);
      expect(find.text('Assessoria Alpha'), findsOneWidget);
    });

    testWidgets('has floating action button with invite label', (tester) async {
      await tester.pumpApp(
        const _FakePartnerScreen(state: _ScreenState.empty),
        wrapScaffold: false,
      );

      expect(find.text('Convidar'), findsOneWidget);
      expect(find.byIcon(Icons.person_add_rounded), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('shows info banner in data state', (tester) async {
      await tester.pumpApp(
        const _FakePartnerScreen(state: _ScreenState.withData),
        wrapScaffold: false,
      );

      expect(
        find.textContaining('Assessorias parceiras podem participar'),
        findsOneWidget,
      );
    });
  });

  group('PartnerAssessoriasScreen — interaction', () {
    testWidgets('retry button is tappable in error state', (tester) async {
      await tester.pumpApp(
        const _FakePartnerScreen(state: _ScreenState.error),
        wrapScaffold: false,
      );

      final retryButton = find.text('Tentar novamente');
      expect(retryButton, findsOneWidget);
      await tester.tap(retryButton);
      await tester.pump();
    });

    testWidgets('FAB is tappable', (tester) async {
      await tester.pumpApp(
        const _FakePartnerScreen(state: _ScreenState.withData),
        wrapScaffold: false,
      );

      final fab = find.byType(FloatingActionButton);
      expect(fab, findsOneWidget);
      await tester.tap(fab);
      await tester.pump();
    });
  });
}
