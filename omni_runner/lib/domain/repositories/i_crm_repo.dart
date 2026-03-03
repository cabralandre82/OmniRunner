import 'package:omni_runner/domain/entities/coaching_tag_entity.dart';
import 'package:omni_runner/domain/entities/athlete_note_entity.dart';
import 'package:omni_runner/domain/entities/member_status_entity.dart';

/// Aggregated athlete view for CRM list with filters.
final class CrmAthleteView {
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final MemberStatusValue? status;
  final List<CoachingTagEntity> tags;
  final int attendanceCount;
  final bool hasActiveAlerts;

  const CrmAthleteView({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    this.status,
    this.tags = const [],
    this.attendanceCount = 0,
    this.hasActiveAlerts = false,
  });
}

abstract interface class ICrmRepo {
  // ── Tags ──
  Future<List<CoachingTagEntity>> listTags(String groupId);
  Future<CoachingTagEntity> createTag({
    required String groupId,
    required String name,
    String? color,
  });
  Future<void> deleteTag(String tagId);

  // ── Athlete Tags ──
  Future<List<CoachingTagEntity>> getAthleteTags({
    required String groupId,
    required String athleteUserId,
  });
  Future<void> assignTag({
    required String groupId,
    required String athleteUserId,
    required String tagId,
  });
  Future<void> removeTag({
    required String groupId,
    required String athleteUserId,
    required String tagId,
  });

  // ── Notes ──
  Future<List<AthleteNoteEntity>> listNotes({
    required String groupId,
    required String athleteUserId,
    int limit = 50,
    int offset = 0,
  });
  Future<AthleteNoteEntity> createNote({
    required String groupId,
    required String athleteUserId,
    required String note,
  });
  Future<void> deleteNote(String noteId);

  // ── Member Status ──
  Future<MemberStatusEntity?> getStatus({
    required String groupId,
    required String userId,
  });
  Future<MemberStatusEntity> upsertStatus({
    required String groupId,
    required String userId,
    required MemberStatusValue status,
  });

  // ── CRM List (aggregated) ──
  Future<List<CrmAthleteView>> listAthletes({
    required String groupId,
    List<String>? tagIds,
    MemberStatusValue? status,
    int limit = 50,
    int offset = 0,
  });
}
