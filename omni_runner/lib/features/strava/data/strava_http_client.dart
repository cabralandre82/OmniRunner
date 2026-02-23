import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:omni_runner/core/logging/logger.dart';
import 'package:http_parser/http_parser.dart' as http_parser;
import 'package:omni_runner/core/errors/strava_failures.dart';

/// Centralised HTTP client for all Strava API calls.
///
/// Responsibilities:
/// - Base URL management
/// - Authorization header injection
/// - Retry with exponential backoff for 5xx / network errors
/// - Rate-limit (429) detection and delayed retry
/// - Structured error mapping to [IntegrationFailure] subclasses
///
/// Does NOT own tokens — receives them via [accessToken] parameter
/// or the [getValidToken] callback.
class StravaHttpClient {
  /// Underlying HTTP client (injectable for tests).
  final http.Client _inner;

  static const _baseUrl = 'https://www.strava.com';
  static const _apiBase = '$_baseUrl/api/v3';
  static const _oauthBase = '$_baseUrl/oauth';

  /// Maximum retry attempts for retryable errors (5xx, network).
  static const _maxRetries = 5;

  /// Upload POST timeout (files can be large).
  static const _uploadTimeout = Duration(seconds: 60);

  /// Default timeout for other requests.
  static const _defaultTimeout = Duration(seconds: 15);

  /// Poll timeout.
  static const _pollTimeout = Duration(seconds: 10);

  static const _tag = 'StravaHTTP';

  StravaHttpClient({http.Client? client}) : _inner = client ?? http.Client();

  // ── OAuth Endpoints ───────────────────────────────────────────

  /// Build the full authorization URL for the OAuth2 consent page.
  Uri buildAuthorizationUrl({
    required String clientId,
    String redirectUri = 'omnirunner://strava/callback',
    String scope = 'activity:write',
  }) {
    return Uri.parse('$_oauthBase/mobile/authorize').replace(
      queryParameters: {
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'approval_prompt': 'auto',
        'scope': scope,
      },
    );
  }

  /// Exchange an authorization code for tokens.
  ///
  /// POST /oauth/token with grant_type=authorization_code.
  Future<Map<String, dynamic>> exchangeToken({
    required String clientId,
    required String clientSecret,
    required String code,
  }) async {
    final response = await _post(
      '$_oauthBase/token',
      body: {
        'client_id': clientId,
        'client_secret': clientSecret,
        'code': code,
        'grant_type': 'authorization_code',
      },
      timeout: _defaultTimeout,
      tag: 'TokenExchange',
    );
    return _decodeJsonMap(response);
  }

  /// Refresh the access token using a refresh token.
  ///
  /// POST /oauth/token with grant_type=refresh_token.
  Future<Map<String, dynamic>> refreshToken({
    required String clientId,
    required String clientSecret,
    required String refreshToken,
  }) async {
    final response = await _post(
      '$_oauthBase/token',
      body: {
        'client_id': clientId,
        'client_secret': clientSecret,
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
      },
      timeout: _defaultTimeout,
      tag: 'TokenRefresh',
    );
    return _decodeJsonMap(response);
  }

  /// Revoke access (disconnect).
  ///
  /// POST /oauth/deauthorize.
  Future<void> deauthorize({required String accessToken}) async {
    await _post(
      '$_oauthBase/deauthorize',
      headers: {'Authorization': 'Bearer $accessToken'},
      timeout: _defaultTimeout,
      tag: 'Deauthorize',
    );
  }

  // ── Upload Endpoints ──────────────────────────────────────────

  /// Upload a workout file via multipart POST with retry.
  ///
  /// POST /api/v3/uploads.
  /// Returns the parsed JSON response body.
  ///
  /// Retries on 5xx and network errors with exponential backoff.
  /// Does NOT retry on 4xx (client errors are not transient).
  /// Throws [TokenExpired] on 401 so the caller can refresh and replay.
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
    final contentType = _mimeTypeForDataType(dataType);

    AppLogger.info(
      'Upload POST ${fileBytes.length} bytes '
      '($dataType, external_id=$externalId, mime=$contentType)',
      tag: _tag,
    );

    var attempt = 0;
    while (true) {
      try {
        return await _sendMultipart(
          accessToken: accessToken,
          fileBytes: fileBytes,
          fileName: fileName,
          dataType: dataType,
          externalId: externalId,
          activityName: activityName,
          description: description,
          activityType: activityType,
          contentType: contentType,
        );
      } on UploadServerError catch (e) {
        attempt++;
        if (attempt >= _maxRetries) rethrow;
        final delay = Duration(seconds: 1 << attempt);
        AppLogger.warn(
          'UploadPOST ${e.statusCode} server error, '
          'retry $attempt/$_maxRetries in ${delay.inSeconds}s',
          tag: _tag,
        );
        await Future<void>.delayed(delay);
      } on UploadNetworkError {
        attempt++;
        if (attempt >= _maxRetries) rethrow;
        final delay = Duration(seconds: 1 << attempt);
        AppLogger.warn(
          'UploadPOST network error, '
          'retry $attempt/$_maxRetries in ${delay.inSeconds}s',
          tag: _tag,
        );
        await Future<void>.delayed(delay);
      }
      // TokenExpired, UploadRejected, UploadRateLimited → no retry, rethrow
    }
  }

  /// Internal: send a single multipart request (no retry).
  Future<Map<String, dynamic>> _sendMultipart({
    required String accessToken,
    required List<int> fileBytes,
    required String fileName,
    required String dataType,
    required String externalId,
    required String activityName,
    required String description,
    required String activityType,
    required String contentType,
  }) async {
    final uri = Uri.parse('$_apiBase/uploads');

    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $accessToken'
      ..fields['data_type'] = dataType
      ..fields['external_id'] = externalId
      ..fields['name'] = activityName
      ..fields['description'] = description
      ..fields['activity_type'] = activityType
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: fileName,
        contentType: _parseMediaType(contentType),
      ));

    try {
      final streamed = await _inner.send(request).timeout(_uploadTimeout);
      final response = await http.Response.fromStream(streamed);

      _logResponse('UploadPOST', response);
      _throwOnError(response, tag: 'UploadPOST');

      return _decodeJsonMap(response);
    } on IntegrationFailure {
      rethrow;
    } on Exception catch (e) {
      throw UploadNetworkError('Upload failed: $e');
    }
  }

  /// Map Strava `data_type` to the appropriate content type.
  static String _mimeTypeForDataType(String dataType) => switch (dataType) {
        'gpx' => 'application/gpx+xml',
        'tcx' => 'application/vnd.garmin.tcx+xml',
        'fit' => 'application/vnd.ant.fit',
        _ => 'application/octet-stream',
      };

  /// Parse a MIME string into a [MediaType] for the multipart file.
  static http_parser.MediaType _parseMediaType(String mime) {
    final parts = mime.split('/');
    return http_parser.MediaType(
      parts.first,
      parts.length > 1 ? parts.sublist(1).join('/') : '',
    );
  }

  /// Poll upload status.
  ///
  /// GET /api/v3/uploads/{uploadId}.
  Future<Map<String, dynamic>> pollUpload({
    required String accessToken,
    required String uploadId,
  }) async {
    final response = await _get(
      '$_apiBase/uploads/$uploadId',
      headers: {'Authorization': 'Bearer $accessToken'},
      timeout: _pollTimeout,
      tag: 'UploadPoll',
    );
    return _decodeJsonMap(response);
  }

  // ── Internal HTTP helpers ─────────────────────────────────────

  Future<http.Response> _get(
    String url, {
    Map<String, String>? headers,
    required Duration timeout,
    required String tag,
  }) async {
    final uri = Uri.parse(url);
    try {
      final response =
          await _inner.get(uri, headers: headers).timeout(timeout);
      _logResponse(tag, response);
      _throwOnError(response, tag: tag);
      return response;
    } on IntegrationFailure {
      rethrow;
    } on Exception catch (e) {
      throw UploadNetworkError('$tag network error: $e');
    }
  }

  Future<http.Response> _post(
    String url, {
    Map<String, String>? headers,
    Map<String, String>? body,
    required Duration timeout,
    required String tag,
  }) async {
    final uri = Uri.parse(url);
    try {
      final response = await _inner
          .post(uri, headers: headers, body: body)
          .timeout(timeout);
      _logResponse(tag, response);
      _throwOnError(response, tag: tag);
      return response;
    } on IntegrationFailure {
      rethrow;
    } on Exception catch (e) {
      throw UploadNetworkError('$tag network error: $e');
    }
  }

  /// POST with exponential backoff for retryable errors.
  ///
  /// Used for upload and other write operations where transient
  /// failures should be retried automatically.
  Future<http.Response> postWithRetry(
    String url, {
    Map<String, String>? headers,
    Map<String, String>? body,
    required Duration timeout,
    required String tag,
  }) async {
    var attempt = 0;
    while (true) {
      try {
        return await _post(url, headers: headers, body: body,
            timeout: timeout, tag: tag);
      } on UploadServerError {
        attempt++;
        if (attempt >= _maxRetries) rethrow;
        final delay = Duration(seconds: 1 << attempt);
        AppLogger.warn(
          '$tag server error, retry $attempt/$_maxRetries in ${delay.inSeconds}s',
          tag: _tag,
        );
        await Future<void>.delayed(delay);
      } on UploadNetworkError {
        attempt++;
        if (attempt >= _maxRetries) rethrow;
        final delay = Duration(seconds: 1 << attempt);
        AppLogger.warn(
          '$tag network error, retry $attempt/$_maxRetries in ${delay.inSeconds}s',
          tag: _tag,
        );
        await Future<void>.delayed(delay);
      }
    }
  }

  // ── Response handling ─────────────────────────────────────────

  void _throwOnError(http.Response response, {required String tag}) {
    final code = response.statusCode;

    if (code >= 200 && code < 300) return;

    if (code == 401) {
      throw const TokenExpired();
    }

    if (code == 429) {
      final retryAfter = int.tryParse(
            response.headers['retry-after'] ?? '',
          ) ??
          60;
      throw UploadRateLimited(retryAfter);
    }

    if (code >= 400 && code < 500) {
      throw UploadRejected(code, _bodySnippet(response));
    }

    if (code >= 500) {
      throw UploadServerError(code);
    }
  }

  Map<String, dynamic> _decodeJsonMap(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      throw const AuthFailed('Unexpected response format');
    } on FormatException {
      throw AuthFailed('Invalid JSON response: ${_bodySnippet(response)}');
    }
  }

  void _logResponse(String logTag, http.Response response) {
    AppLogger.debug(
      '$logTag ${response.statusCode} (${response.body.length} bytes)',
      tag: _tag,
    );
  }

  String _bodySnippet(http.Response response) {
    final body = response.body;
    return body.length > 200 ? '${body.substring(0, 200)}...' : body;
  }

  /// Close the underlying client. Call on app dispose.
  void close() => _inner.close();
}
