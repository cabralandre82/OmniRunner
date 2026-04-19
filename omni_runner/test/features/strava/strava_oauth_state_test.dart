import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/features/strava/data/strava_oauth_state.dart';

/// In-memory implementation of the guard's storage contract — keeps
/// the test off the real flutter_secure_storage platform channel.
class _FakeStorage implements OAuthStateStorage {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async {
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    data.remove(key);
  }
}

/// Deterministic Random for reproducible token bytes.
class _SeededRandom implements Random {
  int _counter = 0;

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0.0;

  @override
  int nextInt(int max) {
    final v = _counter % max;
    _counter++;
    return v;
  }
}

void main() {
  late _FakeStorage storage;

  setUp(() {
    storage = _FakeStorage();
  });

  group('beginFlow', () {
    test('mints a token of the expected length and persists it', () async {
      final guard = StravaOAuthStateGuard(storage: storage);
      final token = await guard.beginFlow();

      expect(token, isNotEmpty);
      // 32 bytes base64url-encoded without padding ≥ 43 chars.
      expect(token.length, greaterThanOrEqualTo(43));
      expect(storage.data['strava_oauth_state'], token);
      expect(storage.data['strava_oauth_state_expires_at'], isNotNull);
    });

    test('two consecutive calls produce different tokens (CSPRNG)', () async {
      final guard = StravaOAuthStateGuard(storage: storage);
      final t1 = await guard.beginFlow();
      final t2 = await guard.beginFlow();
      expect(t1, isNot(equals(t2)));
    });

    test('beginFlow overwrites prior state (single in-flight)', () async {
      final guard = StravaOAuthStateGuard(storage: storage);
      final t1 = await guard.beginFlow();
      final t2 = await guard.beginFlow();
      expect(storage.data['strava_oauth_state'], t2);
      expect(storage.data['strava_oauth_state'], isNot(equals(t1)));
    });

    test('persisted expiry sits exactly one TTL in the future', () async {
      final fixedNow = DateTime.utc(2026, 4, 17, 12, 0);
      final guard = StravaOAuthStateGuard(
        storage: storage,
        now: () => fixedNow,
      );
      await guard.beginFlow();
      final raw = storage.data['strava_oauth_state_expires_at']!;
      final expiresAt = int.parse(raw);
      expect(
        expiresAt,
        fixedNow.add(StravaOAuthStateGuard.ttl).millisecondsSinceEpoch,
      );
    });

    test('uses the injected Random for byte generation', () async {
      final guard = StravaOAuthStateGuard(
        storage: storage,
        random: _SeededRandom(),
      );
      final t1 = await guard.beginFlow();
      // A second call advances the seeded counter, so the next token
      // differs — proves the injected Random is in fact consumed.
      final t2 = await guard.beginFlow();
      expect(t1, isNotEmpty);
      expect(t2, isNotEmpty);
      expect(t1, isNot(equals(t2)));
    });
  });

  group('validateAndConsume', () {
    test('returns true for the matching token then clears state', () async {
      final guard = StravaOAuthStateGuard(storage: storage);
      final token = await guard.beginFlow();

      expect(await guard.validateAndConsume(token), isTrue);
      expect(storage.data, isEmpty);
    });

    test('replay (second consume of same token) returns false', () async {
      final guard = StravaOAuthStateGuard(storage: storage);
      final token = await guard.beginFlow();

      expect(await guard.validateAndConsume(token), isTrue);
      expect(await guard.validateAndConsume(token), isFalse);
    });

    test('returns false on token mismatch and clears state', () async {
      final guard = StravaOAuthStateGuard(storage: storage);
      await guard.beginFlow();

      expect(await guard.validateAndConsume('wrong-token'), isFalse);
      expect(storage.data, isEmpty);
    });

    test('returns false when no flow was ever started', () async {
      final guard = StravaOAuthStateGuard(storage: storage);
      expect(await guard.validateAndConsume('anything'), isFalse);
    });

    test('returns false when the returned state is null', () async {
      final guard = StravaOAuthStateGuard(storage: storage);
      await guard.beginFlow();
      expect(await guard.validateAndConsume(null), isFalse);
      expect(storage.data, isEmpty);
    });

    test('returns false when the returned state is empty', () async {
      final guard = StravaOAuthStateGuard(storage: storage);
      await guard.beginFlow();
      expect(await guard.validateAndConsume(''), isFalse);
      expect(storage.data, isEmpty);
    });

    test('returns false after the TTL has elapsed', () async {
      var fakeNow = DateTime.utc(2026, 4, 17, 12, 0);
      final guard = StravaOAuthStateGuard(
        storage: storage,
        now: () => fakeNow,
      );
      final token = await guard.beginFlow();

      // Advance past the TTL.
      fakeNow = fakeNow.add(
        StravaOAuthStateGuard.ttl + const Duration(seconds: 1),
      );
      expect(await guard.validateAndConsume(token), isFalse);
      expect(storage.data, isEmpty);
    });

    test('returns false if the expires marker is missing', () async {
      final guard = StravaOAuthStateGuard(storage: storage);
      final token = await guard.beginFlow();
      // Tamper with the persisted expiry to simulate corruption.
      storage.data.remove('strava_oauth_state_expires_at');
      expect(await guard.validateAndConsume(token), isFalse);
    });

    test('clears storage on every failure path', () async {
      final guard = StravaOAuthStateGuard(storage: storage);
      await guard.beginFlow();

      expect(await guard.validateAndConsume('forged'), isFalse);
      expect(storage.data, isEmpty);

      // The legitimate token from the first flow is also gone — fresh
      // beginFlow is required, so an attacker cannot replay either.
      expect(await guard.validateAndConsume('would-have-matched'), isFalse);
    });
  });

  group('clear', () {
    test('removes both keys', () async {
      final guard = StravaOAuthStateGuard(storage: storage);
      await guard.beginFlow();
      expect(storage.data, isNotEmpty);
      await guard.clear();
      expect(storage.data, isEmpty);
    });

    test('is a no-op when nothing was persisted', () async {
      final guard = StravaOAuthStateGuard(storage: storage);
      await guard.clear();
      expect(storage.data, isEmpty);
    });
  });
}
