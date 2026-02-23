import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal smoke test for OmniRunnerApp.
///
/// Full app cannot be pumped in test environment because it depends
/// on platform plugins (geolocator, permission_handler) via service locator.
/// Real UI tests will use widget_test with mocked DI in Phase 04+.
///
/// Domain/UseCase tests are in test/domain/.
void main() {
  testWidgets('MaterialApp can be created with title', (
    WidgetTester tester,
  ) async {
    // Arrange & Act — create a minimal MaterialApp (no platform deps).
    await tester.pumpWidget(
      const MaterialApp(
        title: 'Omni Runner',
        home: Scaffold(
          body: Center(child: Text('Omni Runner Debug')),
        ),
      ),
    );

    // Assert — app renders with expected text.
    expect(find.text('Omni Runner Debug'), findsOneWidget);
  });
}
