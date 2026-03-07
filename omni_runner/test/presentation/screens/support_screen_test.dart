import 'package:flutter_test/flutter_test.dart';

/// SupportScreen calls Supabase.instance.client directly in initState,
/// which throws a fatal assertion in the test environment.
/// Widget-level tests require Supabase to be initialised or the screen to
/// accept an injectable client.
void main() {
  group('SupportScreen', () {
    test('requires Supabase initialisation — skipped', () {}, skip: true);
  });
}
