import 'package:omni_runner/core/errors/strava_failures.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/features/strava/data/strava_http_client.dart';
import 'package:omni_runner/features/strava/domain/i_strava_auth_repository.dart';
import 'package:omni_runner/features/strava/domain/i_strava_upload_repository.dart';
import 'package:omni_runner/features/strava/domain/strava_upload_request.dart';
import 'package:omni_runner/features/strava/domain/strava_upload_status.dart';

/// Concrete implementation of [IStravaUploadRepository].
///
/// Uses [StravaHttpClient] for HTTP and [IStravaAuthRepository] for
/// obtaining valid access tokens (with automatic refresh).
///
/// Upload flow:
///   1. POST multipart file → receive upload ID (queued)
///   2. Poll GET /uploads/{id} until ready, error, or timeout
///
/// Error handling:
///   - 401 → refresh token once, replay request
///   - 429 → throw [UploadRateLimited] with retry-after seconds
///   - 5xx → [StravaHttpClient] retries with exponential backoff
///   - Network → [StravaHttpClient] retries with exponential backoff
///   - 400 → throw [UploadRejected] (no retry)
final class StravaUploadRepositoryImpl implements IStravaUploadRepository {
  final StravaHttpClient _httpClient;
  final IStravaAuthRepository _authRepo;

  /// Max polling attempts before declaring timeout.
  static const _maxPolls = 10;

  /// Polling interval for the first 5 attempts (3s).
  static const _earlyPollInterval = Duration(seconds: 3);

  /// Polling interval for attempts 6–10 (5s).
  static const _latePollInterval = Duration(seconds: 5);

  static const _tag = 'StravaUpload';

  StravaUploadRepositoryImpl({
    required StravaHttpClient httpClient,
    required IStravaAuthRepository authRepo,
  })  : _httpClient = httpClient,
        _authRepo = authRepo;

  // ── IStravaUploadRepository ───────────────────────────────────

  @override
  Future<StravaUploadStatus> uploadWorkout(
    StravaUploadRequest request,
  ) async {
    AppLogger.info(
      'Uploading session=${request.sessionId} '
      'format=${request.format.label} '
      'size=${request.fileBytes.length} bytes',
      tag: _tag,
    );

    final json = await _uploadWithTokenRetry(request);
    final status = _parseUploadResponse(json, isInitialPost: true);

    AppLogger.info(
      'Upload accepted: ${status.runtimeType} '
      '(uploadId=${_uploadIdOf(status)})',
      tag: _tag,
    );

    return status;
  }

  @override
  Future<StravaUploadStatus> pollUploadStatus(String uploadId) async {
    final json = await _pollWithTokenRetry(uploadId);
    return _parseUploadResponse(json, isInitialPost: false);
  }

  @override
  Future<StravaUploadStatus> uploadAndWait(
    StravaUploadRequest request,
  ) async {
    var status = await uploadWorkout(request);

    // Poll until terminal state or timeout
    for (var i = 0; i < _maxPolls; i++) {
      if (status.isTerminal) break;

      final interval = i < 5 ? _earlyPollInterval : _latePollInterval;
      final currentUploadId = _uploadIdOf(status);

      AppLogger.debug(
        'Poll ${i + 1}/$_maxPolls '
        '(upload=$currentUploadId) — waiting ${interval.inSeconds}s',
        tag: _tag,
      );

      await Future<void>.delayed(interval);

      status = await pollUploadStatus(currentUploadId);
    }

    // If still non-terminal after max polls → timeout
    if (!status.isTerminal) {
      final id = _uploadIdOf(status);
      AppLogger.warn(
        'Processing timeout after $_maxPolls polls for upload $id',
        tag: _tag,
      );
      throw UploadProcessingTimeout(id);
    }

    // Log the final outcome
    switch (status) {
      case StravaUploadReady(:final activityId):
        AppLogger.info('Success! activity_id=$activityId', tag: _tag);
      case StravaUploadDuplicate(:final message):
        AppLogger.info('Duplicate (treated as success): $message', tag: _tag);
      case StravaUploadError(:final error):
        AppLogger.warn('Strava processing error: $error', tag: _tag);
      case StravaUploadQueued() || StravaUploadProcessing():
        break; // impossible — we checked isTerminal above
    }

    return status;
  }

  // ── Token-retry wrappers ──────────────────────────────────────

  /// Upload with automatic token refresh on 401.
  ///
  /// If the upload POST returns 401, refresh the token once and replay.
  /// Any other error propagates immediately.
  Future<Map<String, dynamic>> _uploadWithTokenRetry(
    StravaUploadRequest request,
  ) async {
    var accessToken = await _authRepo.getValidAccessToken();

    try {
      return await _doUpload(accessToken, request);
    } on TokenExpired {
      AppLogger.debug('401 on upload — refreshing token and retrying', tag: _tag);
      await _authRepo.refreshToken();
      accessToken = await _authRepo.getValidAccessToken();
      return _doUpload(accessToken, request);
    }
  }

  /// Poll with automatic token refresh on 401.
  Future<Map<String, dynamic>> _pollWithTokenRetry(String uploadId) async {
    var accessToken = await _authRepo.getValidAccessToken();

    try {
      return await _httpClient.pollUpload(
        accessToken: accessToken,
        uploadId: uploadId,
      );
    } on TokenExpired {
      AppLogger.debug('401 on poll — refreshing token and retrying', tag: _tag);
      await _authRepo.refreshToken();
      accessToken = await _authRepo.getValidAccessToken();
      return _httpClient.pollUpload(
        accessToken: accessToken,
        uploadId: uploadId,
      );
    }
  }

  /// Execute the actual upload call.
  Future<Map<String, dynamic>> _doUpload(
    String accessToken,
    StravaUploadRequest request,
  ) {
    return _httpClient.uploadFile(
      accessToken: accessToken,
      fileBytes: request.fileBytes,
      fileName: '${request.sessionId}${request.format.extension}',
      dataType: _dataType(request),
      externalId: request.sessionId,
      activityName: request.activityName,
      description: request.description,
    );
  }

  // ── Parsing ───────────────────────────────────────────────────

  /// Map ExportFormat to the Strava `data_type` string.
  String _dataType(StravaUploadRequest request) =>
      switch (request.format.label) {
        'GPX' => 'gpx',
        'TCX' => 'tcx',
        'FIT' => 'fit',
        _ => 'gpx',
      };

  /// Parse Strava upload/poll JSON into a [StravaUploadStatus].
  ///
  /// [isInitialPost] distinguishes the POST response (→ Queued)
  /// from poll responses (→ Processing).
  StravaUploadStatus _parseUploadResponse(
    Map<String, dynamic> json, {
    required bool isInitialPost,
  }) {
    final uploadId = (json['id'] ?? json['id_str'] ?? '').toString();
    final error = json['error'] as String?;
    final activityId = json['activity_id'] as int?;

    // ── Error states ──
    if (error != null && error.isNotEmpty) {
      if (error.contains('duplicate')) {
        return StravaUploadDuplicate(uploadId: uploadId, message: error);
      }
      return StravaUploadError(uploadId: uploadId, error: error);
    }

    // ── Complete ──
    if (activityId != null && activityId > 0) {
      return StravaUploadReady(uploadId: uploadId, activityId: activityId);
    }

    // ── Queued (initial POST) vs Processing (poll) ──
    if (isInitialPost) {
      return StravaUploadQueued(uploadId: uploadId);
    }
    return StravaUploadProcessing(uploadId: uploadId);
  }

  /// Extract the uploadId from any status subtype.
  String _uploadIdOf(StravaUploadStatus status) => switch (status) {
        StravaUploadQueued(:final uploadId) => uploadId,
        StravaUploadProcessing(:final uploadId) => uploadId,
        StravaUploadReady(:final uploadId) => uploadId,
        StravaUploadDuplicate(:final uploadId) => uploadId,
        StravaUploadError(:final uploadId) => uploadId,
      };
}
