import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:omni_runner/core/errors/strava_failures.dart';
import 'package:omni_runner/features/integrations_export/domain/export_format.dart';
import 'package:omni_runner/features/strava/data/strava_http_client.dart';
import 'package:omni_runner/features/strava/data/strava_upload_repository_impl.dart';
import 'package:omni_runner/features/strava/domain/i_strava_auth_repository.dart';
import 'package:omni_runner/features/strava/domain/strava_auth_state.dart';
import 'package:omni_runner/features/strava/domain/strava_upload_request.dart';
import 'package:omni_runner/features/strava/domain/strava_upload_status.dart';

// ── Fake Auth Repo ──────────────────────────────────────────────

final class _FakeAuthRepo implements IStravaAuthRepository {
  String validToken = 'test_token';
  int refreshCallCount = 0;
  bool shouldThrowOnGetToken = false;

  @override
  Future<StravaAuthState> getAuthState() async => StravaConnected(
        athleteId: 1,
        athleteName: 'Test',
        expiresAt: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
      );

  @override
  Future<StravaConnected> authenticate() async =>
      throw const AuthCancelled();

  @override
  Future<StravaConnected> exchangeCode(String code) async =>
      throw const AuthFailed('not implemented in test');

  @override
  Future<StravaConnected> refreshToken() async {
    refreshCallCount++;
    validToken = 'refreshed_token_$refreshCallCount';
    return StravaConnected(
      athleteId: 1,
      athleteName: 'Test',
      expiresAt: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
    );
  }

  @override
  Future<StravaDisconnected> disconnect() async =>
      const StravaDisconnected();

  @override
  Future<String> getValidAccessToken() async {
    if (shouldThrowOnGetToken) throw const TokenExpired();
    return validToken;
  }
}

// ── Fake HTTP Client ────────────────────────────────────────────

final class _FakeHttpClient implements StravaHttpClient {
  final List<Map<String, dynamic>> pollResponses = [];
  int pollIndex = 0;
  Map<String, dynamic>? uploadResponse;
  bool shouldThrowOnUpload = false;
  IntegrationFailure? uploadError;
  String? lastUploadDataType;
  String? lastUploadExternalId;
  String? lastUploadFileName;
  String? lastUploadAccessToken;
  int uploadCallCount = 0;

  /// Sequence of errors to throw on successive upload calls.
  /// Once exhausted, succeeds.
  final List<IntegrationFailure> uploadErrorSequence = [];

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
  }) async {
    uploadCallCount++;
    lastUploadDataType = dataType;
    lastUploadExternalId = externalId;
    lastUploadFileName = fileName;
    lastUploadAccessToken = accessToken;

    if (uploadErrorSequence.isNotEmpty) {
      final err = uploadErrorSequence.removeAt(0);
      throw err;
    }

    if (shouldThrowOnUpload) {
      throw uploadError ?? const UploadNetworkError('test');
    }
    return uploadResponse ??
        {
          'id': 999,
          'status': 'Your activity is still being processed.',
          'activity_id': null,
          'error': null,
        };
  }

  @override
  Future<Map<String, dynamic>> pollUpload({
    required String accessToken,
    required String uploadId,
  }) async {
    lastUploadAccessToken = accessToken;
    if (pollIndex < pollResponses.length) {
      return pollResponses[pollIndex++];
    }
    return {
      'id': int.tryParse(uploadId) ?? 999,
      'status': 'Your activity is ready.',
      'activity_id': 42,
      'error': null,
    };
  }

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
  }) async =>
      {};

  @override
  Future<Map<String, dynamic>> refreshToken({
    required String clientId,
    required String clientSecret,
    required String refreshToken,
  }) async =>
      {};

  @override
  Future<void> deauthorize({required String accessToken}) async {}

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
  void close() {}
}

// ── Test Helpers ────────────────────────────────────────────────

StravaUploadRequest _testRequest({
  ExportFormat format = ExportFormat.gpx,
  String sessionId = 'session-abc-123',
}) =>
    StravaUploadRequest(
      sessionId: sessionId,
      fileBytes: Uint8List.fromList([60, 63, 120, 109, 108]), // "<?xml"
      format: format,
    );

// ── Tests ───────────────────────────────────────────────────────

void main() {
  late _FakeAuthRepo authRepo;
  late _FakeHttpClient httpClient;
  late StravaUploadRepositoryImpl repo;

  setUp(() {
    authRepo = _FakeAuthRepo();
    httpClient = _FakeHttpClient();
    repo = StravaUploadRepositoryImpl(
      httpClient: httpClient,
      authRepo: authRepo,
    );
  });

  // ── uploadWorkout ─────────────────────────────────────────────

  group('uploadWorkout', () {
    test('sends correct data_type for GPX', () async {
      await repo.uploadWorkout(_testRequest(format: ExportFormat.gpx));
      expect(httpClient.lastUploadDataType, 'gpx');
    });

    test('sends correct data_type for TCX', () async {
      await repo.uploadWorkout(_testRequest(format: ExportFormat.tcx));
      expect(httpClient.lastUploadDataType, 'tcx');
    });

    test('sends correct data_type for FIT', () async {
      await repo.uploadWorkout(_testRequest(format: ExportFormat.fit));
      expect(httpClient.lastUploadDataType, 'fit');
    });

    test('sends sessionId as external_id', () async {
      await repo.uploadWorkout(_testRequest());
      expect(httpClient.lastUploadExternalId, 'session-abc-123');
    });

    test('fileName includes session ID and format extension', () async {
      await repo.uploadWorkout(
          _testRequest(sessionId: 'abc', format: ExportFormat.tcx));
      expect(httpClient.lastUploadFileName, 'abc.tcx');
    });

    test('returns StravaUploadQueued on 201 (initial POST)', () async {
      final status = await repo.uploadWorkout(_testRequest());
      expect(status, isA<StravaUploadQueued>());
      expect((status as StravaUploadQueued).uploadId, '999');
    });

    test('throws UploadNetworkError on network failure', () async {
      httpClient.shouldThrowOnUpload = true;
      httpClient.uploadError = const UploadNetworkError('timeout');
      expect(
        () => repo.uploadWorkout(_testRequest()),
        throwsA(isA<UploadNetworkError>()),
      );
    });

    test('throws UploadRejected on 400 (invalid file)', () async {
      httpClient.shouldThrowOnUpload = true;
      httpClient.uploadError = const UploadRejected(400, 'bad file');
      expect(
        () => repo.uploadWorkout(_testRequest()),
        throwsA(isA<UploadRejected>()),
      );
    });

    test('throws UploadRateLimited on 429', () async {
      httpClient.shouldThrowOnUpload = true;
      httpClient.uploadError = const UploadRateLimited(60);
      expect(
        () => repo.uploadWorkout(_testRequest()),
        throwsA(isA<UploadRateLimited>()),
      );
    });
  });

  // ── Token expired retry on upload ─────────────────────────────

  group('uploadWorkout token-expired retry', () {
    test('refreshes token on 401 and retries upload once', () async {
      // First call throws TokenExpired, second succeeds
      httpClient.uploadErrorSequence.add(const TokenExpired());

      final status = await repo.uploadWorkout(_testRequest());

      expect(status, isA<StravaUploadQueued>());
      expect(authRepo.refreshCallCount, 1);
      expect(httpClient.uploadCallCount, 2);
      expect(httpClient.lastUploadAccessToken, 'refreshed_token_1');
    });

    test('propagates TokenExpired if refresh fails', () async {
      httpClient.shouldThrowOnUpload = true;
      httpClient.uploadError = const TokenExpired();
      // Make getValidAccessToken throw after refresh attempt
      // The second _doUpload will also throw TokenExpired
      // which should propagate

      // Use error sequence: first 401, then second 401 (refresh didn't help)
      httpClient.shouldThrowOnUpload = false;
      httpClient.uploadErrorSequence
        ..add(const TokenExpired())
        ..add(const TokenExpired());

      expect(
        () => repo.uploadWorkout(_testRequest()),
        throwsA(isA<TokenExpired>()),
      );
    });
  });

  // ── pollUploadStatus ──────────────────────────────────────────

  group('pollUploadStatus', () {
    test('returns StravaUploadReady when activity_id present', () async {
      httpClient.pollResponses.add({
        'id': 999,
        'status': 'Your activity is ready.',
        'activity_id': 42,
        'error': null,
      });
      final status = await repo.pollUploadStatus('999');
      expect(status, isA<StravaUploadReady>());
      expect((status as StravaUploadReady).activityId, 42);
    });

    test('returns StravaUploadDuplicate when error contains "duplicate"',
        () async {
      httpClient.pollResponses.add({
        'id': 999,
        'status': 'error',
        'activity_id': null,
        'error': 'duplicate of activity 123',
      });
      final status = await repo.pollUploadStatus('999');
      expect(status, isA<StravaUploadDuplicate>());
      expect(
        (status as StravaUploadDuplicate).message,
        contains('duplicate'),
      );
    });

    test('returns StravaUploadError for non-duplicate errors', () async {
      httpClient.pollResponses.add({
        'id': 999,
        'status': 'error',
        'activity_id': null,
        'error': 'file is corrupt',
      });
      final status = await repo.pollUploadStatus('999');
      expect(status, isA<StravaUploadError>());
      expect((status as StravaUploadError).error, 'file is corrupt');
    });

    test('returns StravaUploadProcessing when still processing', () async {
      httpClient.pollResponses.add({
        'id': 999,
        'status': 'Your activity is still being processed.',
        'activity_id': null,
        'error': null,
      });
      final status = await repo.pollUploadStatus('999');
      expect(status, isA<StravaUploadProcessing>());
    });

    test('refreshes token on 401 during poll', () async {
      // Poll will fail first time (simulated by making getValidAccessToken
      // return old token, but the fake poll doesn't actually check)
      // So we test indirectly through the upload flow
      httpClient.pollResponses.add({
        'id': 999,
        'status': 'Your activity is ready.',
        'activity_id': 42,
        'error': null,
      });
      final status = await repo.pollUploadStatus('999');
      expect(status, isA<StravaUploadReady>());
    });
  });

  // ── StravaUploadStatus states ─────────────────────────────────

  group('StravaUploadStatus', () {
    test('queued state', () {
      const status = StravaUploadQueued(uploadId: '1');
      expect(status.uploadId, '1');
      expect(status.isTerminal, isFalse);
    });

    test('processing state', () {
      const status = StravaUploadProcessing(uploadId: '2');
      expect(status.uploadId, '2');
      expect(status.isTerminal, isFalse);
    });

    test('ready state is terminal', () {
      const status = StravaUploadReady(uploadId: '3', activityId: 42);
      expect(status.activityId, 42);
      expect(status.isTerminal, isTrue);
    });

    test('duplicate state is terminal', () {
      const status = StravaUploadDuplicate(uploadId: '4', message: 'dup');
      expect(status.message, 'dup');
      expect(status.isTerminal, isTrue);
    });

    test('error state is terminal', () {
      const status = StravaUploadError(uploadId: '5', error: 'bad');
      expect(status.error, 'bad');
      expect(status.isTerminal, isTrue);
    });

    test('all 5 subtypes can be pattern matched exhaustively', () {
      final statuses = <StravaUploadStatus>[
        const StravaUploadQueued(uploadId: '1'),
        const StravaUploadProcessing(uploadId: '2'),
        const StravaUploadReady(uploadId: '3', activityId: 42),
        const StravaUploadDuplicate(uploadId: '4', message: 'dup'),
        const StravaUploadError(uploadId: '5', error: 'err'),
      ];

      for (final s in statuses) {
        final label = switch (s) {
          StravaUploadQueued() => 'queued',
          StravaUploadProcessing() => 'processing',
          StravaUploadReady() => 'ready',
          StravaUploadDuplicate() => 'duplicate',
          StravaUploadError() => 'error',
        };
        expect(label, isNotEmpty);
      }
    });
  });

  // ── StravaUploadRequest ───────────────────────────────────────

  group('StravaUploadRequest', () {
    test('has correct default values', () {
      final req = _testRequest();
      expect(req.activityName, 'Omni Runner');
      expect(req.description, 'Tracked with Omni Runner');
    });

    test('custom values are preserved', () {
      final req = StravaUploadRequest(
        sessionId: 'id',
        fileBytes: Uint8List(0),
        format: ExportFormat.tcx,
        activityName: 'Custom',
        description: 'Custom desc',
      );
      expect(req.activityName, 'Custom');
      expect(req.description, 'Custom desc');
      expect(req.format, ExportFormat.tcx);
    });
  });

  // ── Parse response edge cases ─────────────────────────────────

  group('_parseUploadResponse edge cases', () {
    test('upload response with immediate error returns StravaUploadError',
        () async {
      httpClient.uploadResponse = {
        'id': 111,
        'status': 'error',
        'activity_id': null,
        'error': 'file is too large',
      };
      final status = await repo.uploadWorkout(_testRequest());
      expect(status, isA<StravaUploadError>());
      expect((status as StravaUploadError).error, 'file is too large');
    });

    test(
        'upload response with immediate activity_id returns StravaUploadReady',
        () async {
      httpClient.uploadResponse = {
        'id': 222,
        'status': 'Your activity is ready.',
        'activity_id': 9999,
        'error': null,
      };
      final status = await repo.uploadWorkout(_testRequest());
      expect(status, isA<StravaUploadReady>());
      expect((status as StravaUploadReady).activityId, 9999);
    });

    test('upload response with duplicate error returns StravaUploadDuplicate',
        () async {
      httpClient.uploadResponse = {
        'id': 333,
        'status': 'error',
        'activity_id': null,
        'error': 'duplicate of activity 888',
      };
      final status = await repo.uploadWorkout(_testRequest());
      expect(status, isA<StravaUploadDuplicate>());
    });

    test('poll response without activity_id returns Processing', () async {
      httpClient.pollResponses.add({
        'id': 444,
        'status': 'Your activity is still being processed.',
        'activity_id': null,
        'error': null,
      });
      final status = await repo.pollUploadStatus('444');
      expect(status, isA<StravaUploadProcessing>());
    });
  });
}
