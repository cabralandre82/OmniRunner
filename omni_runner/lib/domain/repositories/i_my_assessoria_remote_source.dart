import 'package:omni_runner/domain/entities/coaching_group_entity.dart';
import 'package:omni_runner/domain/entities/coaching_member_entity.dart';

/// Remote data source for assessoria membership and group data.
///
/// Abstracts Supabase queries so the BLoC can be tested without a backend.
abstract interface class IMyAssessoriaRemoteSource {
  /// Fetches all coaching memberships for [userId].
  Future<List<CoachingMemberEntity>> fetchMemberships(String userId);

  /// Fetches a coaching group by [groupId]. Returns `null` if not found.
  Future<CoachingGroupEntity?> fetchGroup(String groupId);
}
