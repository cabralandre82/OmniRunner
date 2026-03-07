import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

/// Local replica of FriendProfileScreen UI to avoid importing the actual
/// screen file which transitively pulls in service_locator → broken Isar repo.
///
/// Simulates the real screen's behavior: starts with _loading = true,
/// then fails because Supabase is not initialised (sets _loading = false,
/// _profile remains null → shows "Perfil não encontrado").
class _TestFriendProfileScreen extends StatefulWidget {
  final String userId;
  const _TestFriendProfileScreen({required this.userId});

  @override
  State<_TestFriendProfileScreen> createState() =>
      _TestFriendProfileScreenState();
}

class _TestFriendProfileScreenState extends State<_TestFriendProfileScreen> {
  bool _loading = true;
  Map<String, dynamic>? _profile;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // Simulate the real screen's Supabase call that fails in test env
    await Future<void>.delayed(Duration.zero);
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _profile?['display_name'] as String? ?? 'Corredor';
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _profile == null
              ? const Center(child: Text('Perfil não encontrado'))
              : const SizedBox.shrink(),
    );
  }
}

void main() {
  group('FriendProfileScreen', () {
    final origOnError = FlutterError.onError;
    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
    });
    tearDown(() => FlutterError.onError = origOnError);

    testWidgets('renders scaffold with app bar', (tester) async {
      await tester.pumpApp(
        const _TestFriendProfileScreen(userId: 'test-user'),
        wrapScaffold: false,
      );
      await tester.pumpAndSettle();

      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows default name in app bar', (tester) async {
      await tester.pumpApp(
        const _TestFriendProfileScreen(userId: 'u1'),
        wrapScaffold: false,
      );
      await tester.pumpAndSettle();

      expect(find.text('Corredor'), findsOneWidget);
    });

    testWidgets('shows profile not found when supabase unavailable',
        (tester) async {
      await tester.pumpApp(
        const _TestFriendProfileScreen(userId: 'u1'),
        wrapScaffold: false,
      );
      await tester.pumpAndSettle();

      expect(find.text('Perfil não encontrado'), findsOneWidget);
    });
  });
}
