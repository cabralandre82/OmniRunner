import 'package:flutter_test/flutter_test.dart';

/// FriendsActivityFeedScreen calls Supabase.instance.client directly in
/// initState, which throws a fatal assertion in the test environment.
/// Widget-level tests require Supabase to be initialised or the screen to
/// accept an injectable client.
void main() {
  group('FriendsActivityFeedScreen', () {
    test('requires Supabase initialisation — skipped', () {}, skip: true);
  });
}
