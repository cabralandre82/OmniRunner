import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:omni_runner/core/utils/safe_enum.dart';
import 'package:omni_runner/data/datasources/drift_database.dart';
import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_participant_entity.dart';
import 'package:omni_runner/domain/entities/challenge_result_entity.dart';
import 'package:omni_runner/domain/entities/challenge_rules_entity.dart';
import 'package:omni_runner/domain/repositories/i_challenge_repo.dart';

/// Drift implementation of [IChallengeRepo].
///
/// Participants and results are stored as JSON-encoded strings
/// because Drift tables use flat columns.
final class DriftChallengeRepo implements IChallengeRepo {
  final AppDatabase _db;

  const DriftChallengeRepo(this._db);

  // ── Challenge CRUD ──

  @override
  Future<void> save(ChallengeEntity challenge) async {
    await _db
        .into(_db.challenges)
        .insertOnConflictUpdate(_toCompanion(challenge));
  }

  @override
  Future<ChallengeEntity?> getById(String id) async {
    final query = _db.select(_db.challenges)
      ..where((t) => t.challengeUuid.equals(id));
    final row = await query.getSingleOrNull();
    return row != null ? _toEntity(row) : null;
  }

  @override
  Future<List<ChallengeEntity>> getByUserId(String userId) async {
    final thirtyDaysAgoMs = DateTime.now()
        .subtract(const Duration(days: 30))
        .millisecondsSinceEpoch;

    final activeQuery = _db.select(_db.challenges)
      ..where((t) =>
          t.status.equals(ChallengeStatus.pending.name) |
          t.status.equals(ChallengeStatus.active.name) |
          t.status.equals(ChallengeStatus.completing.name))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAtMs)]);
    final activeRows = await activeQuery.get();

    final completedQuery = _db.select(_db.challenges)
      ..where((t) =>
          t.status.equals(ChallengeStatus.completed.name) &
          t.createdAtMs.isBiggerThanValue(thirtyDaysAgoMs))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAtMs)]);
    final completedRows = await completedQuery.get();

    final allRows = [...activeRows, ...completedRows];

    return allRows
        .map(_toEntity)
        .where((c) => c.participants.any((p) => p.userId == userId))
        .toList();
  }

  @override
  Future<List<ChallengeEntity>> getByStatus(ChallengeStatus status) async {
    final query = _db.select(_db.challenges)
      ..where((t) => t.status.equals(status.name))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAtMs)]);
    final rows = await query.get();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<void> update(ChallengeEntity challenge) async {
    await _db
        .into(_db.challenges)
        .insertOnConflictUpdate(_toCompanion(challenge));
  }

  @override
  Future<void> deleteById(String id) async {
    await (_db.delete(_db.challenges)
          ..where((t) => t.challengeUuid.equals(id)))
        .go();
  }

  // ── Challenge Results ──

  @override
  Future<void> saveResult(ChallengeResultEntity result) async {
    await _db
        .into(_db.challengeResults)
        .insertOnConflictUpdate(_resultToCompanion(result));
  }

  @override
  Future<ChallengeResultEntity?> getResultByChallengeId(
    String challengeId,
  ) async {
    final query = _db.select(_db.challengeResults)
      ..where((t) => t.challengeId.equals(challengeId));
    final row = await query.getSingleOrNull();
    return row != null ? _resultToEntity(row) : null;
  }

  // ── Challenge Mappers ──

  static ChallengesCompanion _toCompanion(ChallengeEntity e) {
    return ChallengesCompanion.insert(
      challengeUuid: e.id,
      creatorUserId: e.creatorUserId,
      status: e.status.name,
      type: e.type.name,
      title: Value(e.title),
      metricOrdinal: e.rules.goal.name,
      target: Value(e.rules.target),
      windowMs: e.rules.windowMs,
      startModeOrdinal: e.rules.startMode.name,
      fixedStartMs: Value(e.rules.fixedStartMs),
      minSessionDistanceM: e.rules.minSessionDistanceM,
      antiCheatPolicyOrdinal: e.rules.antiCheatPolicy.name,
      entryFeeCoins: e.rules.entryFeeCoins,
      createdAtMs: e.createdAtMs,
      startsAtMs: Value(e.startsAtMs),
      endsAtMs: Value(e.endsAtMs),
      acceptDeadlineMs: Value(e.acceptDeadlineMs),
      participantsJson:
          Value(e.participants.map(_participantToJson).toList()),
    );
  }

  static ChallengeEntity _toEntity(Challenge r) {
    return ChallengeEntity(
      id: r.challengeUuid,
      creatorUserId: r.creatorUserId,
      status: safeByName(ChallengeStatus.values, r.status, fallback: ChallengeStatus.pending),
      type: safeByName(ChallengeType.values, r.type, fallback: ChallengeType.oneVsOne),
      rules: ChallengeRulesEntity(
        goal: _goalFromOrdinal(r.metricOrdinal),
        target: r.target,
        windowMs: r.windowMs,
        startMode: safeByName(ChallengeStartMode.values, r.startModeOrdinal, fallback: ChallengeStartMode.onAccept),
        fixedStartMs: r.fixedStartMs,
        minSessionDistanceM: r.minSessionDistanceM,
        antiCheatPolicy:
            safeByName(ChallengeAntiCheatPolicy.values, r.antiCheatPolicyOrdinal, fallback: ChallengeAntiCheatPolicy.standard),
        entryFeeCoins: r.entryFeeCoins,
      ),
      participants:
          r.participantsJson.map(_participantFromJson).toList(),
      createdAtMs: r.createdAtMs,
      startsAtMs: r.startsAtMs,
      endsAtMs: r.endsAtMs,
      title: r.title,
      acceptDeadlineMs: r.acceptDeadlineMs,
    );
  }

  static ChallengeGoal _goalFromOrdinal(String ordinal) =>
      safeByName(ChallengeGoal.values, ordinal, fallback: ChallengeGoal.mostDistance);

  // ── Participant JSON serialization ──

  static String _participantToJson(ChallengeParticipantEntity p) =>
      jsonEncode({
        'userId': p.userId,
        'displayName': p.displayName,
        'status': p.status.name,
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
      status: safeByName(ParticipantStatus.values, m['status'] as String, fallback: ParticipantStatus.invited),
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

  static ChallengeResultsCompanion _resultToCompanion(
    ChallengeResultEntity e,
  ) {
    return ChallengeResultsCompanion.insert(
      challengeId: e.challengeId,
      metricOrdinal: e.goal.name,
      totalCoinsDistributed: e.totalCoinsDistributed,
      calculatedAtMs: e.calculatedAtMs,
      resultsJson: Value(e.results.map(_prToJson).toList()),
    );
  }

  static ChallengeResultEntity _resultToEntity(ChallengeResult r) {
    return ChallengeResultEntity(
      challengeId: r.challengeId,
      goal: _goalFromOrdinal(r.metricOrdinal),
      results: r.resultsJson.map(_prFromJson).toList(),
      totalCoinsDistributed: r.totalCoinsDistributed,
      calculatedAtMs: r.calculatedAtMs,
    );
  }

  static String _prToJson(ParticipantResult pr) => jsonEncode({
        'userId': pr.userId,
        'finalValue': pr.finalValue,
        'rank': pr.rank,
        'outcome': pr.outcome.name,
        'coinsEarned': pr.coinsEarned,
        'sessionIds': pr.sessionIds,
      });

  static ParticipantResult _prFromJson(String json) {
    final m = jsonDecode(json) as Map<String, dynamic>;
    return ParticipantResult(
      userId: m['userId'] as String,
      finalValue: (m['finalValue'] as num).toDouble(),
      rank: m['rank'] as int?,
      outcome: safeByName(ParticipantOutcome.values, m['outcome'] as String, fallback: ParticipantOutcome.lost),
      coinsEarned: m['coinsEarned'] as int,
      sessionIds: (m['sessionIds'] as List<dynamic>).cast<String>(),
    );
  }

}
