import 'package:supabase_flutter/supabase_flutter.dart';

/// Maps the user's [coaching_members.role] to [support_messages.sender_role].
///
/// Requires the database to accept `'athlete'` (see repo supabase migration
/// `20260408130000_support_member_messages.sql`).
Future<String> resolveSupportMessageSenderRole({
  required SupabaseClient client,
  required String userId,
  required String groupId,
}) async {
  if (userId.isEmpty || groupId.isEmpty) return 'staff';
  final rows = await client
      .from('coaching_members')
      .select('role')
      .eq('user_id', userId)
      .eq('group_id', groupId)
      .limit(1);
  final list = (rows as List).cast<Map<String, dynamic>>();
  if (list.isEmpty) return 'athlete';
  final r = (list.first['role'] as String?)?.toLowerCase() ?? '';
  if (r == 'athlete' || r == 'atleta') return 'athlete';
  return 'staff';
}
