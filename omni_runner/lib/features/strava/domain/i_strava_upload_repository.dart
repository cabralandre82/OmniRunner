import 'package:omni_runner/features/strava/domain/strava_upload_request.dart';
import 'package:omni_runner/features/strava/domain/strava_upload_status.dart';

/// Contract for uploading workouts to the Strava API.
///
/// Domain interface. Implementation lives in the data layer.
/// Uses [StravaUploadRequest] as input and [StravaUploadStatus] as output.
///
/// The implementation handles:
/// - Multipart file upload (POST /api/v3/uploads)
/// - Polling for upload completion (GET /api/v3/uploads/{id})
/// - Token management is delegated to [IStravaAuthRepository].
abstract interface class IStravaUploadRepository {
  /// Upload a workout file to Strava.
  ///
  /// Returns an initial [StravaUploadStatus] from the POST response.
  /// Typically [StravaUploadProcessing] if accepted (HTTP 201).
  ///
  /// Throws [IntegrationFailure] subclass on error.
  Future<StravaUploadStatus> uploadWorkout(StravaUploadRequest request);

  /// Poll the status of a previously submitted upload.
  ///
  /// Returns [StravaUploadReady] when complete,
  /// [StravaUploadProcessing] if still processing,
  /// [StravaUploadDuplicate] if duplicate detected, or
  /// [StravaUploadError] if Strava rejected the file.
  Future<StravaUploadStatus> pollUploadStatus(String uploadId);

  /// Upload and wait for completion (upload + poll loop).
  ///
  /// Combines [uploadWorkout] and [pollUploadStatus] with retry logic.
  /// Max 10 polls, 3s interval for first 5, then 5s.
  ///
  /// Returns the final [StravaUploadStatus].
  Future<StravaUploadStatus> uploadAndWait(StravaUploadRequest request);
}
