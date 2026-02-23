import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/data/models/proto/workout_proto_mapper.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';

/// Low-level datasource for Supabase sync operations.
///
/// Handles connectivity checks, Storage uploads, and Postgres upserts.
/// Queue/orchestration logic lives in [SyncRepo].
class SyncService {
  static const _bucket = 'session-points';
  static const _table = 'sessions';
  static const _tag = 'SyncService';

  final Connectivity _connectivity;
  SyncService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  /// Whether Supabase was successfully initialised at runtime.
  bool get isConfigured => AppConfig.isSupabaseReady;

  /// Returns the current Supabase user ID, or `null` if not authenticated.
  String? get userId {
    if (!isConfigured) return null;
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } on Exception {
      return null;
    }
  }

  /// Check device connectivity. Returns `true` if any connection exists.
  Future<bool> hasConnection() async {
    final result = await _connectivity.checkConnectivity();
    return result.any((r) => r != ConnectivityResult.none);
  }

  /// Check if connected via Wi-Fi specifically.
  Future<bool> isWifi() async {
    final result = await _connectivity.checkConnectivity();
    return result.contains(ConnectivityResult.wifi);
  }

  /// Upload points JSON to Supabase Storage.
  ///
  /// Path: `{userId}/{sessionId}.json` inside bucket [_bucket].
  /// Returns the storage path on success.
  /// Throws [StateError] if Supabase is not ready.
  Future<String> uploadPoints({
    required String userId,
    required String sessionId,
    required List<LocationPointEntity> points,
  }) async {
    if (!isConfigured) {
      throw StateError('SyncService: Supabase not initialised');
    }
    final path = '$userId/$sessionId.json';
    final bytes = WorkoutProtoMapper.pointsToBytes(points);
    AppLogger.info('Uploading ${points.length} points (${bytes.length} B) to $path', tag: _tag);
    final client = Supabase.instance.client;
    await client.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'application/json',
            upsert: true,
          ),
        );
    AppLogger.info('Upload OK: $path', tag: _tag);
    return path;
  }

  /// Upsert session metadata into Postgres table.
  /// Throws [StateError] if Supabase is not ready.
  Future<void> upsertSession(Map<String, Object?> payload) async {
    if (!isConfigured) {
      throw StateError('SyncService: Supabase not initialised');
    }
    AppLogger.debug('Upsert session: ${payload['id']}', tag: _tag);
    final client = Supabase.instance.client;
    await client.from(_table).upsert(payload);
    AppLogger.info('Upsert OK: ${payload['id']}', tag: _tag);
  }
}
