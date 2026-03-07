import 'dart:async';

import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/config/feature_flags.dart';
import 'package:omni_runner/core/service_locator.dart';

class _StubGoTrueClient extends Fake implements GoTrueClient {
  @override
  User? get currentUser => null;

  @override
  Session? get currentSession => null;

  @override
  Stream<AuthState> get onAuthStateChange => const Stream.empty();
}

class _NoOpFunctionsClient extends Fake implements FunctionsClient {
  @override
  Future<FunctionResponse> invoke(
    String functionName, {
    Map<String, String>? headers,
    Object? body,
    Iterable<dynamic>? files,
    Map<String, dynamic>? queryParameters,
    HttpMethod method = HttpMethod.post,
    String? region,
  }) async {
    return FunctionResponse(status: 200, data: <String, dynamic>{});
  }
}

/// Implements Future<T> by delegating to a completed Future.
class _FutureFilterBuilder<T>
    implements PostgrestFilterBuilder<T>, Future<T> {
  final T _value;
  late final Future<T> _future = Future<T>.value(_value);

  _FutureFilterBuilder(this._value);

  // ── Future<T> implementation ──
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

  // ── Chainable filter/transform methods return this ──
  @override
  dynamic noSuchMethod(Invocation invocation, {Object? returnValue}) => this;

  @override
  PostgrestTransformBuilder<Map<String, dynamic>> single() =>
      _FutureFilterBuilder<Map<String, dynamic>>(<String, dynamic>{});

  @override
  PostgrestTransformBuilder<Map<String, dynamic>?> maybeSingle() =>
      _FutureFilterBuilder<Map<String, dynamic>?>(null);
}

/// A SupabaseQueryBuilder stub whose chains all resolve to empty results.
class _StubQueryBuilder extends Fake implements SupabaseQueryBuilder {
  static final _listFilter =
      _FutureFilterBuilder<List<Map<String, dynamic>>>([]);

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> select([String c = '*']) =>
      _listFilter;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> insert(Object values,
          {bool defaultToNull = true}) =>
      _listFilter;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> update(
          Map values) =>
      _listFilter;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> upsert(Object values,
          {String? onConflict,
          bool ignoreDuplicates = false,
          bool defaultToNull = true,
          CountOption? count}) =>
      _listFilter;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> delete(
          {CountOption? count}) =>
      _listFilter;

  @override
  dynamic noSuchMethod(Invocation invocation, {Object? returnValue}) =>
      _listFilter;
}

class FakeSupabaseClient extends Fake implements SupabaseClient {
  @override
  GoTrueClient get auth => _StubGoTrueClient();

  @override
  FunctionsClient get functions => _NoOpFunctionsClient();

  @override
  SupabaseQueryBuilder from(String table) => _StubQueryBuilder();

  @override
  dynamic noSuchMethod(Invocation invocation, {Object? returnValue}) =>
      _FutureFilterBuilder<List<Map<String, dynamic>>>([]);
}

class _StubFeatureFlagService extends FeatureFlagService {
  _StubFeatureFlagService() : super(userId: 'test-user');

  @override
  bool isEnabled(String key) => false;

  @override
  Future<void> refresh() async {}

  @override
  Future<void> load() async {}
}

void ensureSupabaseClientRegistered() {
  if (!sl.isRegistered<SupabaseClient>()) {
    sl.registerLazySingleton<SupabaseClient>(() => FakeSupabaseClient());
  }
  if (!sl.isRegistered<FeatureFlagService>()) {
    sl.registerLazySingleton<FeatureFlagService>(
      () => _StubFeatureFlagService(),
    );
  }
}
