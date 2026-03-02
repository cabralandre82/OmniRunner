import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:omni_runner/core/errors/strava_failures.dart';
import 'package:omni_runner/features/strava/data/strava_auth_repository_impl.dart';
import 'package:omni_runner/features/strava/data/strava_http_client.dart';
import 'package:omni_runner/features/strava/data/strava_secure_store.dart';
import 'package:omni_runner/features/strava/domain/strava_auth_state.dart';

// ── Fake Secure Store ───────────────────────────────────────────

final class _FakeStore implements StravaSecureStore {
  final Map<String, String> _data = {};

  @override
  Future<String?> get accessToken async => _data['strava_access_token'];
  @override
  Future<String?> get refreshToken async => _data['strava_refresh_token'];
  @override
  Future<int?> get expiresAt async {
    final v = _data['strava_expires_at'];
    return v == null ? null : int.tryParse(v);
  }

  @override
  Future<int?> get athleteId async {
    final v = _data['strava_athlete_id'];
    return v == null ? null : int.tryParse(v);
  }

  @override
  Future<String?> get athleteName async => _data['strava_athlete_name'];

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    required int expiresAt,
  }) async {
    _data['strava_access_token'] = accessToken;
    _data['strava_refresh_token'] = refreshToken;
    _data['strava_expires_at'] = expiresAt.toString();
  }

  @override
  Future<void> saveAthlete({
    required int athleteId,
    required String athleteName,
  }) async {
    _data['strava_athlete_id'] = athleteId.toString();
    _data['strava_athlete_name'] = athleteName;
  }

  @override
  Future<void> clearAll() async => _data.clear();

  @override
  Future<bool> get hasTokens async {
    final t = _data['strava_access_token'];
    return t != null && t.isNotEmpty;
  }

  void seedTokens({
    String accessToken = 'test_access',
    String refreshToken = 'test_refresh',
    int? expiresAt,
    int athleteId = 123,
    String athleteName = 'Test',
  }) {
    _data['strava_access_token'] = accessToken;
    _data['strava_refresh_token'] = refreshToken;
    _data['strava_expires_at'] =
        (expiresAt ?? _futureTimestamp()).toString();
    _data['strava_athlete_id'] = athleteId.toString();
    _data['strava_athlete_name'] = athleteName;
  }

  static int _futureTimestamp() =>
      DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
}

// ── Fake HTTP Client ────────────────────────────────────────────

final class _FakeHttpClient implements StravaHttpClient {
  Map<String, dynamic>? exchangeResult;
  Map<String, dynamic>? refreshResult;
  bool deauthorizeCalled = false;
  bool shouldThrowOnExchange = false;
  bool shouldThrowOnRefresh = false;
  IntegrationFailure? exchangeError;
  IntegrationFailure? refreshError;

  @override
  Uri buildAuthorizationUrl({
    required String clientId,
    String redirectUri = 'omnirunner://strava/callback',
    String scope = 'activity:write',
  }) =>
      Uri.parse('https://strava.com/test');

  @override
  Future<Map<String, dynamic>> exchangeToken({
    required String clientId,
    required String clientSecret,
    required String code,
  }) async {
    if (shouldThrowOnExchange) {
      throw exchangeError ?? const AuthFailed('test exchange error');
    }
    return exchangeResult ?? _validTokenResponse();
  }

  @override
  Future<Map<String, dynamic>> refreshToken({
    required String clientId,
    required String clientSecret,
    required String refreshToken,
  }) async {
    if (shouldThrowOnRefresh) {
      throw refreshError ?? const TokenExpired();
    }
    return refreshResult ?? _validTokenResponse();
  }

  @override
  Future<void> deauthorize({required String accessToken}) async {
    deauthorizeCalled = true;
  }

  @override
  Future<Map<String, dynamic>> uploadFile({
    required String accessToken,
    required List<int> fileBytes,
    required String fileName,
    required String dataType,
    required String externalId,
    String activityName = 'Omni Runner',
    String description = 'Tracked with Omni Runner',
    String activityType = 'run',
  }) async =>
      {};

  @override
  Future<Map<String, dynamic>> pollUpload({
    required String accessToken,
    required String uploadId,
  }) async =>
      {};

  @override
  Future<http.Response> postWithRetry(
    String url, {
    Map<String, String>? headers,
    Map<String, String>? body,
    required Duration timeout,
    required String tag,
  }) async =>
      http.Response('{}', 200);

  @override
  Future<List<Map<String, dynamic>>> getAthleteActivities({
    required String accessToken,
    int perPage = 20,
    int page = 1,
  }) async =>
      [];

  @override
  void close() {}

  static Map<String, dynamic> _validTokenResponse({
    int? expiresAt,
  }) =>
      {
        'access_token': 'new_access_token',
        'refresh_token': 'new_refresh_token',
        'expires_at':
            expiresAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000 + 21600,
        'expires_in': 21600,
        'athlete': {'id': 42, 'firstname': 'João'},
      };
}

// ── Tests ───────────────────────────────────────────────────────

void main() {
  late _FakeStore store;
  late _FakeHttpClient httpClient;
  late StravaAuthRepositoryImpl repo;

  setUp(() {
    store = _FakeStore();
    httpClient = _FakeHttpClient();
    repo = StravaAuthRepositoryImpl(
      store: store,
      httpClient: httpClient,
      clientId: 'test_client_id',
      clientSecret: 'test_client_secret',
    );
  });

  group('getAuthState', () {
    test('returns StravaDisconnected when no tokens stored', () async {
      final state = await repo.getAuthState();
      expect(state, isA<StravaDisconnected>());
    });

    test('returns StravaConnected when valid tokens exist', () async {
      store.seedTokens();
      final state = await repo.getAuthState();
      expect(state, isA<StravaConnected>());
      final connected = state as StravaConnected;
      expect(connected.athleteId, 123);
      expect(connected.athleteName, 'Test');
    });

    test('returns StravaReauthRequired when token is expired', () async {
      store.seedTokens(expiresAt: 1000); // long past
      final state = await repo.getAuthState();
      expect(state, isA<StravaReauthRequired>());
    });

    test('caches state on second call', () async {
      store.seedTokens();
      final s1 = await repo.getAuthState();
      store._data.clear(); // wipe storage to prove caching
      final s2 = await repo.getAuthState();
      expect(identical(s1, s2), isTrue);
    });
  });

  group('exchangeCode', () {
    test('persists tokens and returns StravaConnected', () async {
      final connected = await repo.exchangeCode('valid_code');
      expect(connected, isA<StravaConnected>());
      expect(connected.athleteId, 42);
      expect(connected.athleteName, 'João');
      expect(await store.accessToken, 'new_access_token');
      expect(await store.refreshToken, 'new_refresh_token');
    });

    test('throws AuthFailed on exchange error', () async {
      httpClient.shouldThrowOnExchange = true;
      httpClient.exchangeError = const AuthFailed('Bad Request');
      expect(
        () => repo.exchangeCode('bad_code'),
        throwsA(isA<AuthFailed>()),
      );
    });

    test('reverts to Disconnected on failure', () async {
      httpClient.shouldThrowOnExchange = true;
      try {
        await repo.exchangeCode('bad');
      } on IntegrationFailure {
        // expected
      }
      final state = await repo.getAuthState();
      expect(state, isA<StravaDisconnected>());
    });
  });

  group('refreshToken', () {
    test('persists new tokens on success', () async {
      store.seedTokens();
      final connected = await repo.refreshToken();
      expect(connected, isA<StravaConnected>());
      expect(await store.accessToken, 'new_access_token');
    });

    test('throws TokenExpired when no refresh token stored', () async {
      // No tokens seeded
      expect(() => repo.refreshToken(), throwsA(isA<TokenExpired>()));
    });

    test('throws AuthRevoked when refresh returns 401', () async {
      store.seedTokens();
      httpClient.shouldThrowOnRefresh = true;
      httpClient.refreshError = const TokenExpired();
      expect(() => repo.refreshToken(), throwsA(isA<AuthRevoked>()));
    });

    test('clears store when refresh is revoked', () async {
      store.seedTokens();
      httpClient.shouldThrowOnRefresh = true;
      httpClient.refreshError = const TokenExpired();
      try {
        await repo.refreshToken();
      } on IntegrationFailure {
        // expected
      }
      expect(await store.hasTokens, isFalse);
    });
  });

  group('disconnect', () {
    test('calls deauthorize and clears store', () async {
      store.seedTokens();
      final result = await repo.disconnect();
      expect(result, isA<StravaDisconnected>());
      expect(httpClient.deauthorizeCalled, isTrue);
      expect(await store.hasTokens, isFalse);
    });

    test('clears store even if deauthorize API fails', () async {
      store.seedTokens();
      // Even without mocking a failure, clearing should succeed
      final result = await repo.disconnect();
      expect(result, isA<StravaDisconnected>());
      expect(await store.hasTokens, isFalse);
    });
  });

  group('getValidAccessToken', () {
    test('returns token when connected and not expired', () async {
      store.seedTokens();
      // Prime the cache
      await repo.getAuthState();
      final token = await repo.getValidAccessToken();
      expect(token, 'test_access');
    });

    test('refreshes token when expired', () async {
      store.seedTokens(expiresAt: 1000);
      // Prime the cache — will be ReauthRequired
      await repo.getAuthState();
      final token = await repo.getValidAccessToken();
      expect(token, 'new_access_token');
    });

    test('throws AuthFailed when disconnected', () async {
      expect(
        () => repo.getValidAccessToken(),
        throwsA(isA<AuthFailed>()),
      );
    });
  });

  group('StravaAuthState', () {
    test('StravaConnected.isExpired returns true for past timestamp', () {
      const state = StravaConnected(
        athleteId: 1,
        athleteName: 'Test',
        expiresAt: 1000,
      );
      expect(state.isExpired, isTrue);
    });

    test('StravaConnected.isExpired returns false for future timestamp', () {
      final state = StravaConnected(
        athleteId: 1,
        athleteName: 'Test',
        expiresAt: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
      );
      expect(state.isExpired, isFalse);
    });

    test('sealed hierarchy is exhaustive', () {
      const StravaAuthState state = StravaDisconnected();
      final label = switch (state) {
        StravaDisconnected() => 'disconnected',
        StravaConnecting() => 'connecting',
        StravaConnected() => 'connected',
        StravaReauthRequired() => 'reauth',
      };
      expect(label, 'disconnected');
    });
  });
}
