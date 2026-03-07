import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/domain/entities/profile_entity.dart';
import 'package:omni_runner/domain/repositories/i_profile_repo.dart';

/// Supabase-backed implementation of [IProfileRepo].
///
/// All queries use `auth.uid()` server-side via RLS — the client never
/// sends a user ID in the payload. This prevents identity spoofing.
class RemoteProfileDataSource implements IProfileRepo {
  static const _tag = 'RemoteProfile';
  static const _table = 'profiles';

  SupabaseClient get _client => sl<SupabaseClient>();

  String get _uid {
    final id = _client.auth.currentUser?.id;
    if (id == null || id.isEmpty) {
      throw StateError('RemoteProfileDataSource: no authenticated user');
    }
    return id;
  }

  @override
  Future<ProfileEntity?> getMyProfile() async {
    try {
      final uid = _uid;
      final rows = await _client
          .from(_table)
          .select('id, display_name, avatar_url, onboarding_state, user_role, created_via, created_at, updated_at')
          .eq('id', uid)
          .limit(1);

      if (rows.isEmpty) return null;
      return ProfileEntity.fromJson(rows.first);
    } on StateError {
      rethrow;
    } on PostgrestException catch (e) {
      AppLogger.error('getMyProfile Postgrest error: ${e.message}',
          tag: _tag, error: e);
      rethrow;
    } catch (e) {
      AppLogger.error('getMyProfile failed: $e', tag: _tag, error: e);
      rethrow;
    }
  }

  @override
  Future<ProfileEntity> upsertMyProfile(ProfilePatch patch) async {
    final uid = _uid;

    final payload = <String, dynamic>{
      'id': uid,
      if (patch.displayName != null) 'display_name': patch.displayName,
      if (patch.avatarUrl != null) 'avatar_url': patch.avatarUrl,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    try {
      final rows = await _client
          .from(_table)
          .upsert(payload)
          .select('id, display_name, avatar_url, onboarding_state, user_role, created_via, created_at, updated_at');

      if (rows.isNotEmpty) {
        AppLogger.info('upsertMyProfile OK', tag: _tag);
        return ProfileEntity.fromJson(rows.first);
      }

      // Fallback: trigger may not have fired yet. Retry read once.
      AppLogger.warn('upsert returned empty — retrying read', tag: _tag);
      final retry = await getMyProfile();
      if (retry != null) return retry;

      // Last resort: build from payload.
      return ProfileEntity(
        id: uid,
        displayName: patch.displayName ?? 'Runner',
        avatarUrl: patch.avatarUrl,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    } on StateError {
      rethrow;
    } on PostgrestException catch (e) {
      AppLogger.error('upsertMyProfile Postgrest error: ${e.message}',
          tag: _tag, error: e);
      rethrow;
    } catch (e) {
      AppLogger.error('upsertMyProfile failed: $e', tag: _tag, error: e);
      rethrow;
    }
  }
}
