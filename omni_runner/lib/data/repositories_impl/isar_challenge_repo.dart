import 'dart:convert';

import 'package:isar/isar.dart';

import 'package:omni_runner/data/models/isar/challenge_record.dart';
import 'package:omni_runner/data/models/isar/challenge_result_record.dart';
import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_participant_entity.dart';
import 'package:omni_runner/domain/entities/challenge_result_entity.dart';
import 'package:omni_runner/domain/entities/challenge_rules_entity.dart';
import 'package:omni_runner/domain/repositories/i_challenge_repo.dart';

/// Isar implementation of [IChallengeRepo].
///
/// Participants and results are stored as JSON-encoded strings
/// because Isar 3.x does not support nested object collections.
final class IsarChallengeRepo implements IChallengeRepo {
  final Isar _isar;

  const IsarChallengeRepo(this._isar);

  // ── Challenge CRUD ──

  @override
  Future<void> save(ChallengeEntity challenge) async {
    await _isar.writeTxn(() async {
      await _isar.challengeRecords.put(_toRecord(challenge));
    });
  }

  @override
  Future<ChallengeEntity?> getById(String id) async {
    final record = await _isar.challengeRecords
        .where()
        .challengeUuidEqualTo(id)
        .findFirst();
    return record != null ? _toEntity(record) : null;
  }

  @override
  Future<List<ChallengeEntity>> getByUserId(String userId) async {
    final thirtyDaysAgoMs = DateTime.now()
        .subtract(const Duration(days: 30))
        .millisecondsSinceEpoch;

    final activeRecords = await _isar.challengeRecords
        .where()
        .statusEqualTo(0) // pending
        .or()
        .statusEqualTo(1) // active
        .or()
        .statusEqualTo(2) // completing
        .sortByCreatedAtMsDesc()
        .findAll();

    final completedRecords = await _isar.challengeRecords
        .where()
        .statusEqualTo(3) // completed
        .filter()
        .createdAtMsGreaterThan(thirtyDaysAgoMs)
        .sortByCreatedAtMsDesc()
        .findAll();

    final allRecords = [...activeRecords, ...completedRecords];

    return allRecords
        .map(_toEntity)
        .where((c) => c.participants.any((p) => p.userId == userId))
        .toList();
  }

  @override
  Future<List<ChallengeEntity>> getByStatus(ChallengeStatus status) async {
    final records = await _isar.challengeRecords
        .where()
        .statusEqualTo(_challengeStatusToInt(status))
        .sortByCreatedAtMsDesc()
        .findAll();
    return records.map(_toEntity).toList();
  }

  @override
  Future<void> update(ChallengeEntity challenge) async {
    await _isar.writeTxn(() async {
      final existing = await _isar.challengeRecords
          .where()
          .challengeUuidEqualTo(challenge.id)
          .findFirst();

      final record = _toRecord(challenge);
      if (existing != null) record.isarId = existing.isarId;

      await _isar.challengeRecords.put(record);
    });
  }

  @override
  Future<void> deleteById(String id) async {
    await _isar.writeTxn(() async {
      await _isar.challengeRecords
          .where()
          .challengeUuidEqualTo(id)
          .deleteAll();
    });
  }

  // ── Challenge Results ──

  @override
  Future<void> saveResult(ChallengeResultEntity result) async {
    await _isar.writeTxn(() async {
      await _isar.challengeResultRecords.put(_resultToRecord(result));
    });
  }

  @override
  Future<ChallengeResultEntity?> getResultByChallengeId(
    String challengeId,
  ) async {
    final record = await _isar.challengeResultRecords
        .where()
        .challengeIdEqualTo(challengeId)
        .findFirst();
    return record != null ? _resultToEntity(record) : null;
  }

  // ── Challenge Mappers ──

  ChallengeRecord _toRecord(ChallengeEntity e) => ChallengeRecord()
    ..challengeUuid = e.id
    ..creatorUserId = e.creatorUserId
    ..status = _challengeStatusToInt(e.status)
    ..type = e.type.index
    ..title = e.title
    ..metricOrdinal = e.rules.goal.index
    ..target = e.rules.target
    ..windowMs = e.rules.windowMs
    ..startModeOrdinal = e.rules.startMode.index
    ..fixedStartMs = e.rules.fixedStartMs
    ..minSessionDistanceM = e.rules.minSessionDistanceM
    ..antiCheatPolicyOrdinal = e.rules.antiCheatPolicy.index
    ..entryFeeCoins = e.rules.entryFeeCoins
    ..createdAtMs = e.createdAtMs
    ..startsAtMs = e.startsAtMs
    ..endsAtMs = e.endsAtMs
    ..participantsJson = e.participants.map(_participantToJson).toList();

  ChallengeEntity _toEntity(ChallengeRecord r) {
    // 0=oneVsOne, 1=group, 2=team
    final typeIndex = r.type.clamp(0, 2);

    return ChallengeEntity(
      id: r.challengeUuid,
      creatorUserId: r.creatorUserId,
      status: _challengeStatusFromInt(r.status),
      type: ChallengeType.values[typeIndex],
      rules: ChallengeRulesEntity(
        goal: _goalFromOrdinal(r.metricOrdinal),
        target: r.target,
        windowMs: r.windowMs,
        startMode: ChallengeStartMode.values[r.startModeOrdinal],
        fixedStartMs: r.fixedStartMs,
        minSessionDistanceM: r.minSessionDistanceM,
        antiCheatPolicy:
            ChallengeAntiCheatPolicy.values[r.antiCheatPolicyOrdinal],
        entryFeeCoins: r.entryFeeCoins,
      ),
      participants:
          r.participantsJson.map(_participantFromJson).toList(),
      createdAtMs: r.createdAtMs,
      startsAtMs: r.startsAtMs,
      endsAtMs: r.endsAtMs,
      title: r.title,
    );
  }

  /// Map ordinal to ChallengeGoal, handling legacy values gracefully.
  static ChallengeGoal _goalFromOrdinal(int ordinal) => switch (ordinal) {
        0 => ChallengeGoal.fastestAtDistance,
        1 => ChallengeGoal.mostDistance,
        2 => ChallengeGoal.bestPaceAtDistance,
        3 => ChallengeGoal.collectiveDistance,
        _ => ChallengeGoal.mostDistance,
      };

  // ── Participant JSON serialization ──

  static String _participantToJson(ChallengeParticipantEntity p) =>
      jsonEncode({
        'userId': p.userId,
        'displayName': p.displayName,
        'status': p.status.index,
        'respondedAtMs': p.respondedAtMs,
        'progressValue': p.progressValue,
        'sessionIds': p.contributingSessionIds,
        'lastSubmittedAtMs': p.lastSubmittedAtMs,
        'groupId': p.groupId,
        'team': p.team,
      });

  static ChallengeParticipantEntity _participantFromJson(String json) {
    final m = jsonDecode(json) as Map<String, dynamic>;
    return ChallengeParticipantEntity(
      userId: m['userId'] as String,
      displayName: m['displayName'] as String,
      status: ParticipantStatus.values[m['status'] as int],
      respondedAtMs: m['respondedAtMs'] as int?,
      progressValue: (m['progressValue'] as num).toDouble(),
      contributingSessionIds:
          (m['sessionIds'] as List<dynamic>).cast<String>(),
      lastSubmittedAtMs: m['lastSubmittedAtMs'] as int?,
      groupId: m['groupId'] as String?,
      team: m['team'] as String?,
    );
  }

  // ── Result Mappers ──

  static ChallengeResultRecord _resultToRecord(
    ChallengeResultEntity e,
  ) =>
      ChallengeResultRecord()
        ..challengeId = e.challengeId
        ..metricOrdinal = e.goal.index
        ..totalCoinsDistributed = e.totalCoinsDistributed
        ..calculatedAtMs = e.calculatedAtMs
        ..resultsJson = e.results.map(_prToJson).toList();

  static ChallengeResultEntity _resultToEntity(
    ChallengeResultRecord r,
  ) =>
      ChallengeResultEntity(
        challengeId: r.challengeId,
        goal: _goalFromOrdinal(r.metricOrdinal),
        results: r.resultsJson.map(_prFromJson).toList(),
        totalCoinsDistributed: r.totalCoinsDistributed,
        calculatedAtMs: r.calculatedAtMs,
      );

  static String _prToJson(ParticipantResult pr) => jsonEncode({
        'userId': pr.userId,
        'finalValue': pr.finalValue,
        'rank': pr.rank,
        'outcome': pr.outcome.index,
        'coinsEarned': pr.coinsEarned,
        'sessionIds': pr.sessionIds,
      });

  static ParticipantResult _prFromJson(String json) {
    final m = jsonDecode(json) as Map<String, dynamic>;
    return ParticipantResult(
      userId: m['userId'] as String,
      finalValue: (m['finalValue'] as num).toDouble(),
      rank: m['rank'] as int?,
      outcome: ParticipantOutcome.values[m['outcome'] as int],
      coinsEarned: m['coinsEarned'] as int,
      sessionIds: (m['sessionIds'] as List<dynamic>).cast<String>(),
    );
  }

  // ── Status mapping ──

  static int _challengeStatusToInt(ChallengeStatus s) => switch (s) {
        ChallengeStatus.pending => 0,
        ChallengeStatus.active => 1,
        ChallengeStatus.completing => 2,
        ChallengeStatus.completed => 3,
        ChallengeStatus.cancelled => 4,
        ChallengeStatus.expired => 5,
      };

  static ChallengeStatus _challengeStatusFromInt(int v) => switch (v) {
        0 => ChallengeStatus.pending,
        1 => ChallengeStatus.active,
        2 => ChallengeStatus.completing,
        3 => ChallengeStatus.completed,
        4 => ChallengeStatus.cancelled,
        5 => ChallengeStatus.expired,
        _ => ChallengeStatus.pending,
      };
}
