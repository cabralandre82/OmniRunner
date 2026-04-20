import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/analytics/product_event_tracker.dart';
import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/core/service_locator.dart';

// ─── Recording fakes ────────────────────────────────────────────────────────

class _RecordedCall {
  _RecordedCall(this.kind, this.payload, this.options);
  final String kind; // 'insert' | 'upsert'
  final Object payload;
  final Map<String, Object?> options;
}

class _RecordingFilterBuilder<T>
    implements PostgrestFilterBuilder<T>, Future<T> {
  _RecordingFilterBuilder(this._value);
  final T _value;
  late final Future<T> _future = Future<T>.value(_value);

  @override
  Stream<T> asStream() => _future.asStream();
  @override
  Future<T> catchError(Function onError,
          {bool Function(Object error)? test}) =>
      _future.catchError(onError, test: test);
  @override
  Future<R> then<R>(FutureOr<R> Function(T value) onValue,
          {Function? onError}) =>
      _future.then(onValue, onError: onError);
  @override
  Future<T> timeout(Duration timeLimit, {FutureOr<T> Function()? onTimeout}) =>
      _future.timeout(timeLimit, onTimeout: onTimeout);
  @override
  Future<T> whenComplete(FutureOr<void> Function() action) =>
      _future.whenComplete(action);

  @override
  dynamic noSuchMethod(Invocation invocation, {Object? returnValue}) => this;
}

class _RecordingQueryBuilder extends Fake implements SupabaseQueryBuilder {
  _RecordingQueryBuilder(this.calls);
  final List<_RecordedCall> calls;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> insert(
    Object values, {
    bool defaultToNull = true,
  }) {
    calls.add(_RecordedCall('insert', values, const <String, Object?>{}));
    return _RecordingFilterBuilder<List<Map<String, dynamic>>>(
      const <Map<String, dynamic>>[],
    );
  }

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> upsert(
    Object values, {
    String? onConflict,
    bool ignoreDuplicates = false,
    bool defaultToNull = true,
    CountOption? count,
  }) {
    calls.add(_RecordedCall('upsert', values, <String, Object?>{
      'onConflict': onConflict,
      'ignoreDuplicates': ignoreDuplicates,
    }));
    return _RecordingFilterBuilder<List<Map<String, dynamic>>>(
      const <Map<String, dynamic>>[],
    );
  }
}

class _StubGoTrueClient extends Fake implements GoTrueClient {
  _StubGoTrueClient(this._uid);
  final String? _uid;
  @override
  User? get currentUser =>
      _uid == null ? null : User(id: _uid, appMetadata: const {}, userMetadata: const {}, aud: 'authenticated', createdAt: DateTime.now().toIso8601String());
}

class _RecordingSupabaseClient extends Fake implements SupabaseClient {
  _RecordingSupabaseClient({required String? userId}) : _auth = _StubGoTrueClient(userId);
  final _StubGoTrueClient _auth;
  final List<_RecordedCall> calls = <_RecordedCall>[];

  @override
  GoTrueClient get auth => _auth;

  @override
  SupabaseQueryBuilder from(String table) {
    return _RecordingQueryBuilder(calls);
  }
}

// ─── Test setup ─────────────────────────────────────────────────────────────

void _resetSl() {
  if (sl.isRegistered<SupabaseClient>()) {
    sl.unregister<SupabaseClient>();
  }
}

_RecordingSupabaseClient _registerClient({String? userId = 'u-test'}) {
  _resetSl();
  final client = _RecordingSupabaseClient(userId: userId);
  sl.registerLazySingleton<SupabaseClient>(() => client);
  // Fake "Supabase initialised" so AppConfig.isSupabaseReady returns true
  // and ProductEventTracker._userId proceeds to read the auth user.
  AppConfig.markSupabaseReady();
  return client;
}

void main() {
  setUpAll(() {
    AppConfig.markSupabaseReady();
  });

  group('ProductEventTracker — happy path', () {
    test('track() inserts a valid event with the canonical payload', () async {
      final client = _registerClient();

      ProductEventTracker().track(ProductEvents.flowAbandoned, {
        'flow': 'onboarding',
        'step': 'join',
        'reason': 'skipped',
      });

      // track is fire-and-forget — give the microtask a tick to flush.
      await Future<void>.delayed(Duration.zero);

      expect(client.calls, hasLength(1));
      expect(client.calls.first.kind, 'insert');
      final payload = client.calls.first.payload as Map<String, dynamic>;
      expect(payload['user_id'], 'u-test');
      expect(payload['event_name'], ProductEvents.flowAbandoned);
      expect(payload['properties'], {
        'flow': 'onboarding',
        'step': 'join',
        'reason': 'skipped',
      });
    });

    test('trackOnce() uses plain insert (idempotency comes from the unique '
        'partial index, not from upsert — PostgREST cannot pass the '
        'predicate)', () async {
      final client = _registerClient();

      ProductEventTracker().trackOnce(ProductEvents.firstChallengeCreated, {
        'type': 'DISTANCE',
        'goal': '5K',
      });
      await Future<void>.delayed(Duration.zero);

      expect(client.calls, hasLength(1));
      expect(client.calls.first.kind, 'insert',
          reason: 'L08-01: trackOnce must NOT use upsert because '
              'PostgREST cannot attach the partial-index predicate to '
              'the ON CONFLICT clause; it relies on the index to raise '
              '23505 and on _insert to swallow it.');
    });

    test('trackOnce() with onboarding_completed (non first_* one-shot) also '
        'uses insert', () async {
      final client = _registerClient();

      ProductEventTracker().trackOnce(ProductEvents.onboardingCompleted, {
        'role': 'ATLETA',
        'method': 'accept_invite',
      });
      await Future<void>.delayed(Duration.zero);

      expect(client.calls, hasLength(1));
      expect(client.calls.first.kind, 'insert');
    });
  });

  group('ProductEventTracker — L08-01 concurrency', () {
    test('10 concurrent trackOnce calls all dispatch (DB enforces uniqueness)',
        () async {
      // Without the unique partial index, this is exactly the TOCTOU
      // pattern that inflated the funnel. With it, each parallel insert
      // is dispatched optimistically; the second..Nth get 23505 from
      // the DB and _insert swallows it. End-state in the DB: 1 row.
      // (The integration test asserts the post-DB single-row state.)
      final client = _registerClient();

      await Future.wait(List.generate(10, (_) async {
        ProductEventTracker()
            .trackOnce(ProductEvents.firstChampionshipLaunched, {
          'metric': 'distance',
          'template_id': 'tpl-1',
        });
      }));
      await Future<void>.delayed(Duration.zero);

      expect(client.calls, hasLength(10));
      for (final call in client.calls) {
        expect(call.kind, 'insert');
      }
    });

    test('trackOnce called with a non-one-shot event falls back to insert '
        'and warns (no silent unique-violation surprise)', () async {
      final client = _registerClient();

      ProductEventTracker().trackOnce(ProductEvents.flowAbandoned, {
        'flow': 'a',
        'step': '1',
      });
      await Future<void>.delayed(Duration.zero);

      expect(client.calls, hasLength(1));
      expect(client.calls.first.kind, 'insert',
          reason: 'flow_abandoned is not in the one-shot family — must '
              'not silently turn into an upsert.');
    });
  });

  group('ProductEventTracker — L08-02 schema validation', () {
    test('drops events with unknown event_name (PE001 mirror)', () async {
      final client = _registerClient();

      ProductEventTracker().track('totally_made_up_event', {});
      await Future<void>.delayed(Duration.zero);

      expect(client.calls, isEmpty,
          reason: 'unknown event must never reach Supabase');
    });

    test('drops events with unknown property key (PE002 mirror)', () async {
      final client = _registerClient();

      ProductEventTracker().track(ProductEvents.flowAbandoned, {
        'flow': 'onboarding',
        'email': 'leak@example.com', // <-- PII smuggling attempt
      });
      await Future<void>.delayed(Duration.zero);

      expect(client.calls, isEmpty,
          reason: 'L08-02: free-text PII keys must never reach Supabase');
    });

    test('drops events with nested-object value (PE003 mirror)', () async {
      final client = _registerClient();

      ProductEventTracker().track(ProductEvents.flowAbandoned, {
        'flow': {'nested': 'oops'},
      });
      await Future<void>.delayed(Duration.zero);

      expect(client.calls, isEmpty);
    });

    test('drops events with array value (PE003 mirror)', () async {
      final client = _registerClient();

      ProductEventTracker().track(ProductEvents.flowAbandoned, {
        'flow': [1, 2, 3],
      });
      await Future<void>.delayed(Duration.zero);

      expect(client.calls, isEmpty);
    });

    test('drops events with oversize string value (PE004 mirror)', () async {
      final client = _registerClient();

      ProductEventTracker().track(ProductEvents.flowAbandoned, {
        'flow': 'x' * (ProductEvents.maxStringValueLength + 1),
      });
      await Future<void>.delayed(Duration.zero);

      expect(client.calls, isEmpty);
    });

    test('accepts string at exactly the max length (boundary)', () async {
      final client = _registerClient();

      ProductEventTracker().track(ProductEvents.flowAbandoned, {
        'flow': 'x' * ProductEvents.maxStringValueLength,
      });
      await Future<void>.delayed(Duration.zero);

      expect(client.calls, hasLength(1));
    });
  });

  group('ProductEvents — schema mirror of Postgres trigger', () {
    test('every real call site in the mobile codebase passes validation', () {
      final realCallSites = <(String, Map<String, dynamic>)>[
        // staff_setup_screen.dart
        (ProductEvents.onboardingCompleted,
            {'role': 'ASSESSORIA_STAFF', 'method': 'create_assessoria'}),
        (ProductEvents.onboardingCompleted,
            {'role': 'ASSESSORIA_STAFF', 'method': 'request_join_professor'}),
        // join_assessoria_screen.dart
        (ProductEvents.onboardingCompleted,
            {'role': 'ATLETA', 'method': 'request_join'}),
        (ProductEvents.onboardingCompleted,
            {'role': 'ATLETA', 'method': 'accept_invite'}),
        (ProductEvents.onboardingCompleted,
            {'role': 'ATLETA', 'method': 'skip'}),
        (ProductEvents.flowAbandoned, {
          'flow': 'onboarding',
          'step': 'join_assessoria',
          'reason': 'skipped',
        }),
        // challenge_create_screen.dart
        (ProductEvents.flowAbandoned, {
          'flow': 'challenge_create',
          'step': 'form',
        }),
        (ProductEvents.firstChallengeCreated, {
          'type': 'DISTANCE',
          'goal': 'PR',
        }),
        // staff_championship_templates_screen.dart
        (ProductEvents.firstChampionshipLaunched, {
          'metric': 'distance',
          'template_id': 'tpl-1',
        }),
      ];
      for (final (name, props) in realCallSites) {
        expect(ProductEvents.validate(name, props), isNull,
            reason: 'real call site rejected: $name $props');
      }
    });

    test('whitelists are in alphabetical order (diff hygiene)', () {
      final names = ProductEvents.allowedNames.toList();
      final sortedNames = List<String>.from(names)..sort();
      expect(names, sortedNames,
          reason: 'ProductEvents.allowedNames must stay alphabetical to '
              'minimise diff churn vs. fn_validate_product_event()');

      final keys = ProductEvents.allowedPropertyKeys.toList();
      final sortedKeys = List<String>.from(keys)..sort();
      expect(keys, sortedKeys,
          reason: 'ProductEvents.allowedPropertyKeys must stay alphabetical');
    });

    test('null and bool values pass (primitives allowed)', () {
      expect(
          ProductEvents.validate(ProductEvents.flowAbandoned, {'flow': null}),
          isNull);
      expect(
          ProductEvents.validate(
              ProductEvents.flowAbandoned, {'flow': 'a', 'count': 0}),
          isNull);
    });
  });
}
