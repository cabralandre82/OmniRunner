import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/presentation/screens/athlete_delivery_screen.dart';

import '../../helpers/pump_app.dart';

/// Widget tests for AthleteDeliveryScreen.
///
/// The screen depends on:
/// - sl<UserIdentityProvider>().userId
/// - Supabase.instance.client
///
/// To run real tests, use mocktail to mock the Supabase client and register
/// a fake UserIdentityProvider in the service locator before pumping.
void main() {
  group('AthleteDeliveryScreen', () {
    testWidgets('renders app bar title', (tester) async {
      // Note: This will fail without Supabase mock, but demonstrates structure.
      // Real test would need mocktail to mock Supabase client and a fake
      // UserIdentityProvider in the service locator.
      // Until then, we verify the screen builds (app bar title is "Entregas Pendentes").
      await tester.pumpApp(const AthleteDeliveryScreen(), wrapScaffold: false);
      await tester.pump(); // Allow async initState to complete
      expect(find.text('Entregas Pendentes'), findsOneWidget);
    }, skip: true); // Requires Supabase and UserIdentityProvider mocks
  });
}
