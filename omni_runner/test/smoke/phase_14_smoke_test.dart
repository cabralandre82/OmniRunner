/// Phase 14 — Smoke tests for Integrations (Export + Strava + Auth Store).
///
/// All tests run in-memory with fakes. No network, no disk, no flakiness.
/// Purpose: catch regressions across the integration boundary quickly.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:omni_runner/core/errors/health_export_failures.dart';
import 'package:omni_runner/core/errors/integrations_failures.dart';
import 'package:omni_runner/domain/entities/health_hr_sample.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/entities/workout_export_result.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';
import 'package:omni_runner/features/health_export/domain/i_health_export_service.dart';
import 'package:omni_runner/features/health_export/presentation/health_export_controller.dart';
import 'package:omni_runner/features/integrations_export/data/export_service_impl.dart';
import 'package:omni_runner/features/integrations_export/data/gpx/gpx_encoder.dart';
import 'package:omni_runner/features/integrations_export/data/tcx/tcx_encoder.dart';
import 'package:omni_runner/features/integrations_export/domain/export_format.dart';
import 'package:omni_runner/features/integrations_export/domain/export_request.dart';
import 'package:omni_runner/features/strava/data/strava_http_client.dart';
import 'package:omni_runner/features/strava/data/strava_upload_repository_impl.dart';
import 'package:omni_runner/features/strava/domain/i_strava_auth_repository.dart';
import 'package:omni_runner/features/strava/domain/strava_auth_state.dart';
import 'package:omni_runner/features/strava/domain/strava_upload_request.dart';
import 'package:omni_runner/features/strava/domain/strava_upload_status.dart';
import 'package:omni_runner/features/wearables_ble/heart_rate_sample.dart';

// =============================================================================
// Shared test data
// =============================================================================

WorkoutSessionEntity _session({
  String id = 'smoke-session-001',
  int startMs = 1708160400000, // 2024-02-17 06:00:00 UTC
  int endMs = 1708164000000, // 2024-02-17 07:00:00 UTC
  double distanceM = 10000.0,
  int avgBpm = 145,
  int maxBpm = 175,
}) =>
    WorkoutSessionEntity(
      id: id,
      status: WorkoutStatus.completed,
      startTimeMs: startMs,
      endTimeMs: endMs,
      totalDistanceM: distanceM,
      route: const [],
      avgBpm: avgBpm,
      maxBpm: maxBpm,
    );

List<LocationPointEntity> _route({int count = 5}) => List.generate(
      count,
      (i) => LocationPointEntity(
        lat: -23.55 + i * 0.001,
        lng: -46.63 + i * 0.001,
        alt: 760.0 + i,
        accuracy: 5.0,
        speed: 3.0,
        timestampMs: 1708160400000 + i * 10000,
      ),
    );

List<HeartRateSample> _hr({int count = 5}) => List.generate(
      count,
      (i) => HeartRateSample(
        bpm: 130 + i * 5,
        timestampMs: 1708160400000 + i * 10000,
      ),
    );

// =============================================================================
// Fakes — no I/O, no network
// =============================================================================

final class _FakeAuthRepo implements IStravaAuthRepository {
  String validToken = 'fake_access_token';
  int refreshCount = 0;

  @override
  Future<StravaAuthState> getAuthState() async => StravaConnected(
        athleteId: 42,
        athleteName: 'Smoke Tester',
        expiresAt: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
      );

  @override
  Future<StravaConnected> authenticate() async =>
      throw const AuthCancelled();

  @override
  Future<StravaConnected> exchangeCode(String code) async =>
      throw const AuthFailed('not implemented');

  @override
  Future<StravaConnected> refreshToken() async {
    refreshCount++;
    validToken = 'refreshed_$refreshCount';
    return StravaConnected(
      athleteId: 42,
      athleteName: 'Smoke Tester',
      expiresAt: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
    );
  }

  @override
  Future<StravaDisconnected> disconnect() async =>
      const StravaDisconnected();

  @override
  Future<String> getValidAccessToken() async => validToken;
}

final class _FakeStravaHttpClient implements StravaHttpClient {
  Map<String, dynamic> uploadResponse = {
    'id': 12345,
    'id_str': '12345',
    'external_id': 'smoke-session-001.gpx',
    'error': null,
    'status': 'Your activity is still being processed.',
    'activity_id': null,
  };

  Map<String, dynamic> pollResponse = {
    'id': 12345,
    'id_str': '12345',
    'error': null,
    'status': 'Your activity is ready.',
    'activity_id': 98765,
  };

  String? capturedAccessToken;
  String? capturedDataType;
  String? capturedExternalId;
  String? capturedFileName;
  List<int>? capturedFileBytes;
  String? capturedActivityType;

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
    capturedAccessToken = accessToken;
    capturedDataType = dataType;
    capturedExternalId = externalId;
    capturedFileName = fileName;
    capturedFileBytes = fileBytes;
    capturedActivityType = activityType;
    return uploadResponse;
  }

  @override
  Future<Map<String, dynamic>> pollUpload({
    required String accessToken,
    required String uploadId,
  }) async =>
      pollResponse;

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
  Future<List<Map<String, dynamic>>> getAthleteActivities({
    required String accessToken,
    int perPage = 20,
    int page = 1,
  }) async =>
      [];

  @override
  void close() {}
}

/// Fake in-memory auth store (mirrors StravaSecureStore interface).
final class _InMemoryAuthStore {
  final Map<String, String> _data = {};

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    required int expiresAt,
  }) async {
    _data['access_token'] = accessToken;
    _data['refresh_token'] = refreshToken;
    _data['expires_at'] = expiresAt.toString();
  }

  Future<void> saveAthlete({
    required int athleteId,
    required String athleteName,
  }) async {
    _data['athlete_id'] = athleteId.toString();
    _data['athlete_name'] = athleteName;
  }

  Future<String?> readAccessToken() async => _data['access_token'];
  Future<String?> readRefreshToken() async => _data['refresh_token'];
  Future<int?> readExpiresAt() async {
    final v = _data['expires_at'];
    return v == null ? null : int.tryParse(v);
  }

  Future<int?> readAthleteId() async {
    final v = _data['athlete_id'];
    return v == null ? null : int.tryParse(v);
  }

  Future<String?> readAthleteName() async => _data['athlete_name'];

  Future<void> clearAll() async => _data.clear();
  bool get isEmpty => _data.isEmpty;
  int get length => _data.length;
}

/// Fake for IHealthExportService.
final class _FakeHealthExportService implements IHealthExportService {
  bool supportedResult = true;
  WorkoutExportResult exportResult = const WorkoutExportResult(
    workoutSaved: true,
    routeAttached: true,
    routePointCount: 5,
    message: 'OK',
  );
  HealthExportFailure? exportError;

  @override
  Future<bool> isSupported() async => supportedResult;

  @override
  Future<bool> ensurePermissions({bool requestIfMissing = true}) async => true;

  @override
  Future<WorkoutExportResult> exportWorkout({
    required String sessionId,
    required int startMs,
    required int endMs,
    required double totalDistanceM,
    int? totalCalories,
    int? avgBpm,
    int? maxBpm,
    List<HealthHrSample> hrSamples = const [],
  }) async {
    if (exportError != null) throw exportError!;
    return exportResult;
  }
}

// =============================================================================
// SMOKE TESTS
// =============================================================================

void main() {
  // --------------------------------------------------------------------------
  // GROUP 1: Export produces non-empty bytes + valid XML header (GPX/TCX)
  // --------------------------------------------------------------------------
  group('Export: GPX produces non-empty bytes + valid XML', () {
    const gpx = GpxEncoder();
    const tcx = TcxEncoder();
    const service = ExportServiceImpl();

    test('GPX encoder returns non-empty Uint8List', () {
      final bytes = gpx.encode(
        session: _session(),
        route: _route(),
        hrSamples: _hr(),
      );
      expect(bytes, isNotEmpty);
      expect(bytes, isA<Uint8List>());
    });

    test('GPX starts with XML declaration', () {
      final bytes = gpx.encode(session: _session(), route: _route());
      final xml = utf8.decode(bytes);
      expect(xml, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
    });

    test('GPX contains valid gpx root element with 1.1 namespace', () {
      final bytes = gpx.encode(session: _session(), route: _route());
      final xml = utf8.decode(bytes);
      expect(xml, contains('<gpx'));
      expect(xml, contains('version="1.1"'));
      expect(xml, contains('xmlns="http://www.topografix.com/GPX/1/1"'));
      expect(xml, contains('</gpx>'));
    });

    test('GPX contains trkpt elements matching route count', () {
      final route = _route(count: 7);
      final bytes = gpx.encode(session: _session(), route: route);
      final xml = utf8.decode(bytes);
      expect(RegExp('<trkpt ').allMatches(xml).length, 7);
    });

    test('GPX includes Garmin HR extension when HR samples provided', () {
      final bytes = gpx.encode(
        session: _session(),
        route: _route(count: 3),
        hrSamples: _hr(count: 3),
      );
      final xml = utf8.decode(bytes);
      expect(xml, contains('gpxtpx:TrackPointExtension'));
      expect(xml, contains('<gpxtpx:hr>'));
    });

    test('TCX encoder returns non-empty Uint8List', () {
      final bytes = tcx.encode(
        session: _session(),
        route: _route(),
        hrSamples: _hr(),
      );
      expect(bytes, isNotEmpty);
      expect(bytes, isA<Uint8List>());
    });

    test('TCX starts with XML declaration', () {
      final bytes = tcx.encode(session: _session(), route: _route());
      final xml = utf8.decode(bytes);
      expect(xml, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
    });

    test('TCX contains valid TrainingCenterDatabase root with namespace', () {
      final bytes = tcx.encode(session: _session(), route: _route());
      final xml = utf8.decode(bytes);
      expect(xml, contains('<TrainingCenterDatabase'));
      expect(
        xml,
        contains(
          'xmlns="http://www.garmin.com/xmlschemas/'
          'TrainingCenterDatabase/v2"',
        ),
      );
      expect(xml, contains('</TrainingCenterDatabase>'));
    });

    test('TCX contains Trackpoint elements matching route count', () {
      final route = _route(count: 4);
      final bytes = tcx.encode(session: _session(), route: route);
      final xml = utf8.decode(bytes);
      expect(RegExp('<Trackpoint>').allMatches(xml).length, 4);
    });

    test('TCX includes HeartRateBpm in trackpoints when HR provided', () {
      final bytes = tcx.encode(
        session: _session(),
        route: _route(count: 2),
        hrSamples: _hr(count: 2),
      );
      final xml = utf8.decode(bytes);
      expect(xml, contains('<HeartRateBpm>'));
    });

    test('ExportServiceImpl.exportWorkout returns GPX with correct metadata',
        () async {
      final request = ExportRequest(
        session: _session(),
        route: _route(),
        hrSamples: _hr(),
        format: ExportFormat.gpx,
        activityName: 'Smoke Test Run',
      );
      final result = await service.exportWorkout(request);

      expect(result.bytes, isNotEmpty);
      expect(result.format, ExportFormat.gpx);
      expect(result.mimeType, 'application/gpx+xml');
      expect(result.filename, endsWith('.gpx'));
      expect(result.filename, startsWith('run_'));

      final xml = utf8.decode(result.bytes);
      expect(xml, contains('Smoke Test Run'));
    });

    test('ExportServiceImpl.exportWorkout returns TCX with correct metadata',
        () async {
      final request = ExportRequest(
        session: _session(),
        route: _route(),
        format: ExportFormat.tcx,
      );
      final result = await service.exportWorkout(request);

      expect(result.bytes, isNotEmpty);
      expect(result.format, ExportFormat.tcx);
      expect(result.mimeType, 'application/vnd.garmin.tcx+xml');
      expect(result.filename, endsWith('.tcx'));
    });

    test('ExportServiceImpl.exportWorkout produces valid FIT binary',
        () async {
      final request = ExportRequest(
        session: _session(),
        route: _route(),
        format: ExportFormat.fit,
      );
      final result = await service.exportWorkout(request);

      expect(result.bytes, isNotEmpty);
      expect(result.format, ExportFormat.fit);
      expect(result.mimeType, 'application/vnd.ant.fit');
      expect(result.filename, endsWith('.fit'));
      // Verify .FIT signature at offset 8
      expect(String.fromCharCodes(result.bytes.sublist(8, 12)), '.FIT');
    });
  });

  // --------------------------------------------------------------------------
  // GROUP 2: Strava upload request builder sets correct multipart fields
  // --------------------------------------------------------------------------
  group('Strava: upload request builder sets correct multipart fields', () {
    late _FakeAuthRepo authRepo;
    late _FakeStravaHttpClient httpClient;
    late StravaUploadRepositoryImpl uploadRepo;

    setUp(() {
      authRepo = _FakeAuthRepo();
      httpClient = _FakeStravaHttpClient();
      uploadRepo = StravaUploadRepositoryImpl(
        httpClient: httpClient,
        authRepo: authRepo,
      );
    });

    test('uploadWorkout passes access token from auth repo', () async {
      authRepo.validToken = 'my_special_token';
      await uploadRepo.uploadWorkout(StravaUploadRequest(
        sessionId: 'sess-abc',
        fileBytes: Uint8List.fromList([1, 2, 3]),
        format: ExportFormat.gpx,
      ));

      expect(httpClient.capturedAccessToken, 'my_special_token');
    });

    test('uploadWorkout sets data_type=gpx for GPX format', () async {
      await uploadRepo.uploadWorkout(StravaUploadRequest(
        sessionId: 'sess-1',
        fileBytes: Uint8List.fromList([1]),
        format: ExportFormat.gpx,
      ));

      expect(httpClient.capturedDataType, 'gpx');
    });

    test('uploadWorkout sets data_type=tcx for TCX format', () async {
      await uploadRepo.uploadWorkout(StravaUploadRequest(
        sessionId: 'sess-2',
        fileBytes: Uint8List.fromList([1]),
        format: ExportFormat.tcx,
      ));

      expect(httpClient.capturedDataType, 'tcx');
    });

    test('uploadWorkout sets data_type=fit for FIT format', () async {
      await uploadRepo.uploadWorkout(StravaUploadRequest(
        sessionId: 'sess-3',
        fileBytes: Uint8List.fromList([1]),
        format: ExportFormat.fit,
      ));

      expect(httpClient.capturedDataType, 'fit');
    });

    test('uploadWorkout uses sessionId as external_id', () async {
      await uploadRepo.uploadWorkout(StravaUploadRequest(
        sessionId: 'unique-uuid-12345',
        fileBytes: Uint8List.fromList([1]),
        format: ExportFormat.gpx,
      ));

      expect(httpClient.capturedExternalId, 'unique-uuid-12345');
    });

    test('uploadWorkout sets fileName as sessionId + extension', () async {
      await uploadRepo.uploadWorkout(StravaUploadRequest(
        sessionId: 'sess-fn',
        fileBytes: Uint8List.fromList([1]),
        format: ExportFormat.gpx,
      ));
      expect(httpClient.capturedFileName, 'sess-fn.gpx');

      await uploadRepo.uploadWorkout(StravaUploadRequest(
        sessionId: 'sess-fn',
        fileBytes: Uint8List.fromList([1]),
        format: ExportFormat.tcx,
      ));
      expect(httpClient.capturedFileName, 'sess-fn.tcx');
    });

    test('uploadWorkout passes file bytes untouched', () async {
      final bytes = Uint8List.fromList([10, 20, 30, 40, 50]);
      await uploadRepo.uploadWorkout(StravaUploadRequest(
        sessionId: 'sess-bytes',
        fileBytes: bytes,
        format: ExportFormat.gpx,
      ));

      expect(httpClient.capturedFileBytes, [10, 20, 30, 40, 50]);
    });

    test('uploadWorkout sets activityType to run', () async {
      await uploadRepo.uploadWorkout(StravaUploadRequest(
        sessionId: 'sess-type',
        fileBytes: Uint8List.fromList([1]),
        format: ExportFormat.gpx,
      ));

      expect(httpClient.capturedActivityType, 'run');
    });

    test('uploadWorkout returns StravaUploadQueued on initial POST', () async {
      httpClient.uploadResponse = {
        'id': 99999,
        'id_str': '99999',
        'error': null,
        'status': 'Your activity is still being processed.',
        'activity_id': null,
      };

      final status = await uploadRepo.uploadWorkout(StravaUploadRequest(
        sessionId: 'sess-status',
        fileBytes: Uint8List.fromList([1]),
        format: ExportFormat.gpx,
      ));

      expect(status, isA<StravaUploadQueued>());
      expect((status as StravaUploadQueued).uploadId, '99999');
    });

    test('uploadAndWait polls until Ready', () async {
      httpClient.uploadResponse = {
        'id': 55555,
        'id_str': '55555',
        'error': null,
        'status': 'Your activity is still being processed.',
        'activity_id': null,
      };
      httpClient.pollResponse = {
        'id': 55555,
        'id_str': '55555',
        'error': null,
        'status': 'Your activity is ready.',
        'activity_id': 77777,
      };

      final status = await uploadRepo.uploadAndWait(StravaUploadRequest(
        sessionId: 'sess-wait',
        fileBytes: Uint8List.fromList([1]),
        format: ExportFormat.gpx,
      ));

      expect(status, isA<StravaUploadReady>());
      expect((status as StravaUploadReady).activityId, 77777);
    });
  });

  // --------------------------------------------------------------------------
  // GROUP 3: Auth store read/write works (in-memory mirror)
  // --------------------------------------------------------------------------
  group('Auth store: read/write/clear works', () {
    late _InMemoryAuthStore store;

    setUp(() {
      store = _InMemoryAuthStore();
    });

    test('store starts empty', () {
      expect(store.isEmpty, isTrue);
    });

    test('saveTokens persists access_token, refresh_token, expires_at',
        () async {
      await store.saveTokens(
        accessToken: 'at_123',
        refreshToken: 'rt_456',
        expiresAt: 1700000000,
      );

      expect(await store.readAccessToken(), 'at_123');
      expect(await store.readRefreshToken(), 'rt_456');
      expect(await store.readExpiresAt(), 1700000000);
    });

    test('saveAthlete persists athleteId and athleteName', () async {
      await store.saveAthlete(athleteId: 42, athleteName: 'João Runner');

      expect(await store.readAthleteId(), 42);
      expect(await store.readAthleteName(), 'João Runner');
    });

    test('overwrite tokens replaces old values', () async {
      await store.saveTokens(
        accessToken: 'old_at',
        refreshToken: 'old_rt',
        expiresAt: 100,
      );
      await store.saveTokens(
        accessToken: 'new_at',
        refreshToken: 'new_rt',
        expiresAt: 200,
      );

      expect(await store.readAccessToken(), 'new_at');
      expect(await store.readRefreshToken(), 'new_rt');
      expect(await store.readExpiresAt(), 200);
    });

    test('clearAll removes all data', () async {
      await store.saveTokens(
        accessToken: 'at',
        refreshToken: 'rt',
        expiresAt: 100,
      );
      await store.saveAthlete(athleteId: 1, athleteName: 'Test');

      expect(store.isEmpty, isFalse);
      expect(store.length, 5);

      await store.clearAll();

      expect(store.isEmpty, isTrue);
      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
      expect(await store.readExpiresAt(), isNull);
      expect(await store.readAthleteId(), isNull);
      expect(await store.readAthleteName(), isNull);
    });

    test('reading from empty store returns null for all fields', () async {
      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
      expect(await store.readExpiresAt(), isNull);
      expect(await store.readAthleteId(), isNull);
      expect(await store.readAthleteName(), isNull);
    });

    test('expiresAt is stored and read as int (not string)', () async {
      await store.saveTokens(
        accessToken: 'x',
        refreshToken: 'y',
        expiresAt: 1708164000,
      );

      final result = await store.readExpiresAt();
      expect(result, isA<int>());
      expect(result, 1708164000);
    });
  });

  // --------------------------------------------------------------------------
  // GROUP 4: HealthExport controller smoke test
  // --------------------------------------------------------------------------
  group('HealthExport: controller smoke', () {
    late _FakeHealthExportService fakeService;
    late HealthExportController controller;

    setUp(() {
      fakeService = _FakeHealthExportService();
      controller = HealthExportController(service: fakeService);
    });

    test('isPlatformSupported delegates to service', () async {
      fakeService.supportedResult = true;
      expect(await controller.isPlatformSupported(), isTrue);

      fakeService.supportedResult = false;
      expect(await controller.isPlatformSupported(), isFalse);
    });

    test('exportWorkout success returns PT-BR message with rota', () async {
      final result = await controller.exportWorkout(
        sessionId: 'smoke-1',
        startMs: 1708160400000,
        endMs: 1708164000000,
        totalDistanceM: 5000,
      );

      expect(result.success, isTrue);
      expect(result.message, contains('rota GPS'));
    });

    test('exportWorkout permission denied returns actionable message',
        () async {
      fakeService.exportError = const HealthExportPermissionDenied(
        missingScopes: ['writeWorkout'],
      );

      final result = await controller.exportWorkout(
        sessionId: 'smoke-2',
        startMs: 1000,
        endMs: 2000,
        totalDistanceM: 100,
      );

      expect(result.success, isFalse);
      expect(result.message, contains('Permissão'));
    });

    test('exportWorkout NeedsUpdate mentions Google Play', () async {
      fakeService.exportError = const HealthExportNeedsUpdate();

      final result = await controller.exportWorkout(
        sessionId: 'smoke-3',
        startMs: 1000,
        endMs: 2000,
        totalDistanceM: 100,
      );

      expect(result.success, isFalse);
      expect(result.message, contains('Google Play'));
    });
  });

  // --------------------------------------------------------------------------
  // GROUP 5: Cross-cutting: sealed classes are exhaustive
  // --------------------------------------------------------------------------
  group('Sealed classes: exhaustive pattern matching', () {
    test('IntegrationFailure covers all subtypes', () {
      const failures = <IntegrationFailure>[
        AuthCancelled(),
        AuthFailed('test'),
        TokenExpired(),
        AuthRevoked(),
        UploadRejected(400, 'bad'),
        UploadNetworkError('net'),
        UploadServerError(500),
        UploadRateLimited(60),
        UploadProcessingTimeout('id'),
        ExportGenerationFailed('gpx', 'reason'),
        ExportWriteFailed('/tmp', 'reason'),
        ExportNotImplemented('FIT'),
      ];

      for (final f in failures) {
        // If this compiles, the switch is exhaustive.
        final label = switch (f) {
          AuthCancelled() => 'cancelled',
          AuthFailed() => 'failed',
          TokenExpired() => 'expired',
          AuthRevoked() => 'revoked',
          UploadRejected() => 'rejected',
          UploadNetworkError() => 'network',
          UploadServerError() => 'server',
          UploadRateLimited() => 'rate',
          UploadProcessingTimeout() => 'timeout',
          ExportGenerationFailed() => 'gen',
          ExportWriteFailed() => 'write',
          ExportNotImplemented() => 'not_impl',
        };
        expect(label, isNotEmpty);
      }
    });

    test('HealthExportFailure covers all subtypes', () {
      const failures = <HealthExportFailure>[
        HealthExportNotAvailable('test'),
        HealthExportNeedsUpdate(),
        HealthExportPermissionDenied(),
        HealthExportRouteAttachFailed('test'),
        HealthExportWriteFailed('test'),
        HealthExportHrWriteFailed(attempted: 10, written: 5),
      ];

      for (final f in failures) {
        final label = switch (f) {
          HealthExportNotAvailable() => 'a',
          HealthExportNeedsUpdate() => 'b',
          HealthExportPermissionDenied() => 'c',
          HealthExportRouteAttachFailed() => 'd',
          HealthExportWriteFailed() => 'e',
          HealthExportHrWriteFailed() => 'f',
        };
        expect(label, isNotEmpty);
      }
    });

    test('StravaUploadStatus covers all 5 subtypes with isTerminal', () {
      const statuses = <StravaUploadStatus>[
        StravaUploadQueued(uploadId: '1'),
        StravaUploadProcessing(uploadId: '2'),
        StravaUploadReady(uploadId: '3', activityId: 100),
        StravaUploadDuplicate(uploadId: '4', message: 'dup'),
        StravaUploadError(uploadId: '5', error: 'err'),
      ];

      expect(statuses[0].isTerminal, isFalse); // Queued
      expect(statuses[1].isTerminal, isFalse); // Processing
      expect(statuses[2].isTerminal, isTrue); // Ready
      expect(statuses[3].isTerminal, isTrue); // Duplicate
      expect(statuses[4].isTerminal, isTrue); // Error
    });
  });
}
