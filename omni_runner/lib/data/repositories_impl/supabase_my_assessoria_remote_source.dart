import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/domain/entities/coaching_group_entity.dart';
import 'package:omni_runner/domain/entities/coaching_member_entity.dart';
import 'package:omni_runner/domain/repositories/i_my_assessoria_remote_source.dart';

class SupabaseMyAssessoriaRemoteSource implements IMyAssessoriaRemoteSource {
  @override
  Future<List<CoachingMemberEntity>> fetchMemberships(String userId) async {
    final rows = await Supabase.instance.client
        .from('coaching_members')
        .select('id, user_id, group_id, display_name, role, joined_at_ms')
        .eq('user_id', userId);

    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map((r) => CoachingMemberEntity(
              id: r['id'] as String,
              userId: r['user_id'] as String,
              groupId: r['group_id'] as String,
              displayName: (r['display_name'] as String?) ?? '',
              role: coachingRoleFromString(r['role'] as String? ?? ''),
              joinedAtMs: (r['joined_at_ms'] as num?)?.toInt() ?? 0,
            ))
        .toList();
  }

  @override
  Future<CoachingGroupEntity?> fetchGroup(String groupId) async {
    final row = await Supabase.instance.client
        .from('coaching_groups')
        .select()
        .eq('id', groupId)
        .maybeSingle();

    if (row == null) return null;

    return CoachingGroupEntity(
      id: row['id'] as String,
      name: (row['name'] as String?) ?? 'Assessoria',
      logoUrl: row['logo_url'] as String?,
      coachUserId: (row['coach_user_id'] as String?) ?? '',
      description: (row['description'] as String?) ?? '',
      city: (row['city'] as String?) ?? '',
      inviteCode: row['invite_code'] as String?,
      inviteEnabled: (row['invite_enabled'] as bool?) ?? true,
      createdAtMs: (row['created_at_ms'] as num?)?.toInt() ?? 0,
    );
  }
}
