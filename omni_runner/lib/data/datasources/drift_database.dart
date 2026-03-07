import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'drift_converters.dart';

part 'drift_database.g.dart';

// ═══════════════════════════════════════════════════════════════════════════
// GPS & Workout
// ═══════════════════════════════════════════════════════════════════════════

@TableIndex(name: 'idx_location_session_time', columns: {#sessionId, #timestampMs})
class LocationPoints extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sessionId => text()();
  RealColumn get lat => real()();
  RealColumn get lng => real()();
  RealColumn get alt => real().nullable()();
  RealColumn get accuracy => real().nullable()();
  RealColumn get speed => real().nullable()();
  RealColumn get bearing => real().nullable()();
  IntColumn get timestampMs => integer()();
}

@TableIndex(name: 'idx_workout_status', columns: {#status})
@TableIndex(name: 'idx_workout_start_time', columns: {#startTimeMs})
@TableIndex(name: 'idx_workout_verified', columns: {#isVerified})
@TableIndex(name: 'idx_workout_synced', columns: {#isSynced})
class WorkoutSessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sessionUuid => text().unique()();
  TextColumn get userId => text().nullable()();
  IntColumn get status => integer()();
  IntColumn get startTimeMs => integer()();
  IntColumn get endTimeMs => integer().nullable()();
  RealColumn get totalDistanceM => real()();
  IntColumn get movingMs => integer()();
  BoolColumn get isVerified => boolean()();
  BoolColumn get isSynced => boolean()();
  TextColumn get ghostSessionId => text().nullable()();
  TextColumn get integrityFlags =>
      text().map(const StringListConverter()).withDefault(const Constant('[]'))();
  IntColumn get avgBpm => integer().nullable()();
  IntColumn get maxBpm => integer().nullable()();
  RealColumn get avgCadenceSpm => real().nullable()();
  TextColumn get source => text().withDefault(const Constant('app'))();
  TextColumn get deviceName => text().nullable()();
}

// ═══════════════════════════════════════════════════════════════════════════
// Challenges
// ═══════════════════════════════════════════════════════════════════════════

@TableIndex(name: 'idx_challenge_creator', columns: {#creatorUserId})
@TableIndex(name: 'idx_challenge_status', columns: {#status})
@TableIndex(name: 'idx_challenge_created_at', columns: {#createdAtMs})
class Challenges extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get challengeUuid => text().unique()();
  TextColumn get creatorUserId => text()();
  IntColumn get status => integer()();
  IntColumn get type => integer()();
  TextColumn get title => text().nullable()();
  IntColumn get metricOrdinal => integer()();
  RealColumn get target => real().nullable()();
  IntColumn get windowMs => integer()();
  IntColumn get startModeOrdinal => integer()();
  IntColumn get fixedStartMs => integer().nullable()();
  RealColumn get minSessionDistanceM => real()();
  IntColumn get antiCheatPolicyOrdinal => integer()();
  IntColumn get entryFeeCoins => integer()();
  IntColumn get createdAtMs => integer()();
  IntColumn get startsAtMs => integer().nullable()();
  IntColumn get endsAtMs => integer().nullable()();
  TextColumn get teamAGroupId => text().nullable()();
  TextColumn get teamBGroupId => text().nullable()();
  TextColumn get teamAGroupName => text().nullable()();
  TextColumn get teamBGroupName => text().nullable()();
  TextColumn get participantsJson =>
      text().map(const StringListConverter()).withDefault(const Constant('[]'))();
}

class ChallengeResults extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get challengeId => text().unique()();
  IntColumn get metricOrdinal => integer()();
  IntColumn get totalCoinsDistributed => integer()();
  IntColumn get calculatedAtMs => integer()();
  TextColumn get resultsJson =>
      text().map(const StringListConverter()).withDefault(const Constant('[]'))();
}

// ═══════════════════════════════════════════════════════════════════════════
// Economy
// ═══════════════════════════════════════════════════════════════════════════

class Wallets extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get userId => text().unique()();
  IntColumn get balanceCoins => integer()();
  IntColumn get pendingCoins => integer().withDefault(const Constant(0))();
  IntColumn get lifetimeEarnedCoins => integer()();
  IntColumn get lifetimeSpentCoins => integer()();
  IntColumn get lastReconciledAtMs => integer().nullable()();
}

@TableIndex(name: 'idx_ledger_user', columns: {#userId})
@TableIndex(name: 'idx_ledger_ref', columns: {#refId})
@TableIndex(name: 'idx_ledger_issuer', columns: {#issuerGroupId})
@TableIndex(name: 'idx_ledger_created_at', columns: {#createdAtMs})
@DataClassName('LedgerEntry')
class LedgerEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entryUuid => text().unique()();
  TextColumn get userId => text()();
  IntColumn get deltaCoins => integer()();
  IntColumn get reasonOrdinal => integer()();
  TextColumn get refId => text().nullable()();
  TextColumn get issuerGroupId => text().nullable()();
  IntColumn get createdAtMs => integer()();
}

// ═══════════════════════════════════════════════════════════════════════════
// Progression
// ═══════════════════════════════════════════════════════════════════════════

@DataClassName('ProfileProgress')
class ProfileProgresses extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get userId => text().unique()();
  IntColumn get totalXp => integer()();
  IntColumn get seasonXp => integer()();
  TextColumn get currentSeasonId => text().nullable()();
  IntColumn get dailyStreakCount => integer()();
  IntColumn get streakBest => integer()();
  IntColumn get lastStreakDayMs => integer().nullable()();
  BoolColumn get hasFreezeAvailable => boolean()();
  IntColumn get weeklySessionCount => integer()();
  IntColumn get monthlySessionCount => integer()();
  IntColumn get lifetimeSessionCount => integer()();
  RealColumn get lifetimeDistanceM => real()();
  IntColumn get lifetimeMovingMs => integer()();
}

@TableIndex(name: 'idx_xp_user', columns: {#userId})
@TableIndex(name: 'idx_xp_ref', columns: {#refId})
@TableIndex(name: 'idx_xp_created_at', columns: {#createdAtMs})
class XpTransactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get txUuid => text().unique()();
  TextColumn get userId => text()();
  IntColumn get xp => integer()();
  IntColumn get sourceOrdinal => integer()();
  TextColumn get refId => text().nullable()();
  IntColumn get createdAtMs => integer()();
}

// ═══════════════════════════════════════════════════════════════════════════
// Badges & Missions
// ═══════════════════════════════════════════════════════════════════════════

@TableIndex(name: 'idx_badge_user', columns: {#userId})
@TableIndex(name: 'idx_badge_badge', columns: {#badgeId})
class BadgeAwards extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get awardUuid => text().unique()();
  TextColumn get userId => text()();
  TextColumn get badgeId => text()();
  TextColumn get triggerSessionId => text().nullable()();
  IntColumn get unlockedAtMs => integer()();
  IntColumn get xpAwarded => integer()();
  IntColumn get coinsAwarded => integer()();
}

@TableIndex(name: 'idx_mission_user', columns: {#userId})
@TableIndex(name: 'idx_mission_id', columns: {#missionId})
@TableIndex(name: 'idx_mission_status', columns: {#statusOrdinal})
@DataClassName('MissionProgress')
class MissionProgresses extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get progressUuid => text().unique()();
  TextColumn get userId => text()();
  TextColumn get missionId => text()();
  IntColumn get statusOrdinal => integer()();
  RealColumn get currentValue => real()();
  RealColumn get targetValue => real()();
  IntColumn get assignedAtMs => integer()();
  IntColumn get completedAtMs => integer().nullable()();
  IntColumn get completionCount => integer()();
  TextColumn get contributingSessionIdsJson => text()();
}

// ═══════════════════════════════════════════════════════════════════════════
// Seasons
// ═══════════════════════════════════════════════════════════════════════════

@TableIndex(name: 'idx_season_status', columns: {#statusOrdinal})
class Seasons extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get seasonUuid => text().unique()();
  TextColumn get name => text()();
  IntColumn get statusOrdinal => integer()();
  IntColumn get startsAtMs => integer()();
  IntColumn get endsAtMs => integer()();
  TextColumn get passXpMilestonesStr => text()();
}

@TableIndex(name: 'idx_season_prog_user', columns: {#userId})
@TableIndex(name: 'idx_season_prog_season', columns: {#seasonId})
@DataClassName('SeasonProgress')
class SeasonProgresses extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get userId => text()();
  TextColumn get seasonId => text()();
  IntColumn get seasonXp => integer()();
  TextColumn get claimedMilestoneIndicesStr => text()();
  BoolColumn get endRewardsClaimed => boolean()();
}

// ═══════════════════════════════════════════════════════════════════════════
// Coaching
// ═══════════════════════════════════════════════════════════════════════════

@TableIndex(name: 'idx_cg_coach', columns: {#coachUserId})
class CoachingGroups extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get groupUuid => text().unique()();
  TextColumn get name => text()();
  TextColumn get logoUrl => text().nullable()();
  TextColumn get coachUserId => text()();
  TextColumn get description => text()();
  TextColumn get city => text()();
  TextColumn get inviteCode => text().nullable().unique()();
  BoolColumn get inviteEnabled => boolean()();
  IntColumn get createdAtMs => integer()();
}

@TableIndex(name: 'idx_cm_group', columns: {#groupId})
@TableIndex(name: 'idx_cm_user', columns: {#userId})
class CoachingMembers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get memberUuid => text().unique()();
  TextColumn get groupId => text()();
  TextColumn get userId => text()();
  TextColumn get displayName => text()();
  IntColumn get roleOrdinal => integer()();
  IntColumn get joinedAtMs => integer()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {groupId, userId},
      ];
}

@TableIndex(name: 'idx_ci_group', columns: {#groupId})
@TableIndex(name: 'idx_ci_invited', columns: {#invitedUserId})
@TableIndex(name: 'idx_ci_status', columns: {#statusOrdinal})
class CoachingInvites extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get inviteUuid => text().unique()();
  TextColumn get groupId => text()();
  TextColumn get invitedUserId => text()();
  TextColumn get invitedByUserId => text()();
  IntColumn get statusOrdinal => integer()();
  IntColumn get expiresAtMs => integer()();
  IntColumn get createdAtMs => integer()();
}

@TableIndex(name: 'idx_cr_group', columns: {#groupId})
@TableIndex(name: 'idx_cr_period_key', columns: {#periodKey})
class CoachingRankings extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get rankingUuid => text().unique()();
  TextColumn get groupId => text()();
  IntColumn get metricOrdinal => integer()();
  IntColumn get periodOrdinal => integer()();
  TextColumn get periodKey => text()();
  IntColumn get startsAtMs => integer()();
  IntColumn get endsAtMs => integer()();
  IntColumn get computedAtMs => integer()();
}

@TableIndex(name: 'idx_cre_ranking', columns: {#rankingId})
@TableIndex(name: 'idx_cre_user', columns: {#userId})
@DataClassName('CoachingRankingEntry')
class CoachingRankingEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get rankingId => text()();
  TextColumn get userId => text()();
  TextColumn get displayName => text()();
  RealColumn get value => real()();
  IntColumn get rank => integer()();
  IntColumn get sessionCount => integer()();
}

// ═══════════════════════════════════════════════════════════════════════════
// Coaching Analytics
// ═══════════════════════════════════════════════════════════════════════════

@TableIndex(name: 'idx_ab_user', columns: {#userId})
@TableIndex(name: 'idx_ab_group', columns: {#groupId})
class AthleteBaselines extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get baselineUuid => text().unique()();
  TextColumn get userId => text()();
  TextColumn get groupId => text()();
  IntColumn get metricOrdinal => integer()();
  RealColumn get value => real()();
  IntColumn get sampleSize => integer()();
  IntColumn get windowStartMs => integer()();
  IntColumn get windowEndMs => integer()();
  IntColumn get computedAtMs => integer()();
}

@TableIndex(name: 'idx_at_user', columns: {#userId})
@TableIndex(name: 'idx_at_group', columns: {#groupId})
@TableIndex(name: 'idx_at_direction', columns: {#directionOrdinal})
class AthleteTrends extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get trendUuid => text().unique()();
  TextColumn get userId => text()();
  TextColumn get groupId => text()();
  IntColumn get metricOrdinal => integer()();
  IntColumn get periodOrdinal => integer()();
  IntColumn get directionOrdinal => integer()();
  RealColumn get currentValue => real()();
  RealColumn get baselineValue => real()();
  RealColumn get changePercent => real()();
  IntColumn get dataPoints => integer()();
  TextColumn get latestPeriodKey => text()();
  IntColumn get analyzedAtMs => integer()();
}

@TableIndex(name: 'idx_insight_group', columns: {#groupId})
@TableIndex(name: 'idx_insight_target', columns: {#targetUserId})
@TableIndex(name: 'idx_insight_type', columns: {#typeOrdinal})
@TableIndex(name: 'idx_insight_priority', columns: {#priorityOrdinal})
@TableIndex(name: 'idx_insight_read', columns: {#readAtMs})
class CoachInsights extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get insightUuid => text().unique()();
  TextColumn get groupId => text()();
  TextColumn get targetUserId => text()();
  TextColumn get targetDisplayName => text()();
  IntColumn get typeOrdinal => integer()();
  IntColumn get priorityOrdinal => integer()();
  TextColumn get title => text()();
  TextColumn get message => text()();
  IntColumn get metricOrdinal => integer()();
  RealColumn get referenceValue => real()();
  RealColumn get changePercent => real()();
  TextColumn get relatedEntityId => text()();
  IntColumn get createdAtMs => integer()();
  IntColumn get readAtMs => integer()();
  BoolColumn get dismissed => boolean()();
}

// ═══════════════════════════════════════════════════════════════════════════
// Social — Friendships
// ═══════════════════════════════════════════════════════════════════════════

@TableIndex(name: 'idx_friend_b', columns: {#userIdB})
@TableIndex(name: 'idx_friend_status', columns: {#statusOrdinal})
class Friendships extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get friendshipUuid => text().unique()();
  TextColumn get userIdA => text()();
  TextColumn get userIdB => text()();
  IntColumn get statusOrdinal => integer()();
  IntColumn get createdAtMs => integer()();
  IntColumn get acceptedAtMs => integer().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {userIdA, userIdB},
      ];
}

// ═══════════════════════════════════════════════════════════════════════════
// Social — Groups
// ═══════════════════════════════════════════════════════════════════════════

@TableIndex(name: 'idx_group_creator', columns: {#createdByUserId})
class Groups extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get groupUuid => text().unique()();
  TextColumn get name => text()();
  TextColumn get description => text()();
  TextColumn get avatarUrl => text().nullable()();
  TextColumn get createdByUserId => text()();
  IntColumn get createdAtMs => integer()();
  IntColumn get privacyOrdinal => integer()();
  IntColumn get maxMembers => integer()();
  IntColumn get memberCount => integer()();
}

@TableIndex(name: 'idx_gm_group', columns: {#groupId})
@TableIndex(name: 'idx_gm_user', columns: {#userId})
@TableIndex(name: 'idx_gm_status', columns: {#statusOrdinal})
class GroupMembers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get memberUuid => text().unique()();
  TextColumn get groupId => text()();
  TextColumn get userId => text()();
  TextColumn get displayName => text()();
  IntColumn get roleOrdinal => integer()();
  IntColumn get statusOrdinal => integer()();
  IntColumn get joinedAtMs => integer()();
}

@TableIndex(name: 'idx_gg_group', columns: {#groupId})
@TableIndex(name: 'idx_gg_status', columns: {#statusOrdinal})
class GroupGoals extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get goalUuid => text().unique()();
  TextColumn get groupId => text()();
  TextColumn get title => text()();
  TextColumn get description => text()();
  RealColumn get targetValue => real()();
  RealColumn get currentValue => real()();
  IntColumn get metricOrdinal => integer()();
  IntColumn get startsAtMs => integer()();
  IntColumn get endsAtMs => integer()();
  TextColumn get createdByUserId => text()();
  IntColumn get statusOrdinal => integer()();
}

// ═══════════════════════════════════════════════════════════════════════════
// Events
// ═══════════════════════════════════════════════════════════════════════════

@TableIndex(name: 'idx_event_status', columns: {#statusOrdinal})
class Events extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get eventUuid => text().unique()();
  TextColumn get title => text()();
  TextColumn get description => text()();
  TextColumn get imageUrl => text().nullable()();
  IntColumn get typeOrdinal => integer()();
  IntColumn get metricOrdinal => integer()();
  RealColumn get targetValue => real().nullable()();
  IntColumn get startsAtMs => integer()();
  IntColumn get endsAtMs => integer()();
  IntColumn get maxParticipants => integer().nullable()();
  BoolColumn get createdBySystem => boolean()();
  TextColumn get creatorUserId => text().nullable()();
  IntColumn get rewardXpCompletion => integer()();
  IntColumn get rewardCoinsCompletion => integer()();
  IntColumn get rewardXpParticipation => integer()();
  TextColumn get rewardBadgeId => text().nullable()();
  IntColumn get statusOrdinal => integer()();
}

@TableIndex(name: 'idx_ep_user', columns: {#userId})
class EventParticipations extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get participationUuid => text().unique()();
  TextColumn get eventId => text()();
  TextColumn get userId => text()();
  TextColumn get displayName => text()();
  IntColumn get joinedAtMs => integer()();
  RealColumn get currentValue => real()();
  IntColumn get rank => integer().nullable()();
  BoolColumn get completed => boolean()();
  IntColumn get completedAtMs => integer().nullable()();
  IntColumn get contributingSessionCount => integer()();
  TextColumn get contributingSessionIdsCsv => text()();
  BoolColumn get rewardsClaimed => boolean()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {eventId, userId},
      ];
}

// ═══════════════════════════════════════════════════════════════════════════
// Leaderboards
// ═══════════════════════════════════════════════════════════════════════════

@TableIndex(name: 'idx_lb_period_key', columns: {#periodKey})
class LeaderboardSnapshots extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get snapshotUuid => text().unique()();
  IntColumn get scopeOrdinal => integer()();
  TextColumn get groupId => text().nullable()();
  IntColumn get periodOrdinal => integer()();
  IntColumn get metricOrdinal => integer()();
  TextColumn get periodKey => text()();
  IntColumn get computedAtMs => integer()();
  BoolColumn get isFinal => boolean()();
}

@TableIndex(name: 'idx_le_snapshot', columns: {#snapshotId})
@TableIndex(name: 'idx_le_user', columns: {#userId})
@DataClassName('LeaderboardEntry')
class LeaderboardEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get snapshotId => text()();
  TextColumn get userId => text()();
  TextColumn get displayName => text()();
  TextColumn get avatarUrl => text().nullable()();
  IntColumn get level => integer()();
  RealColumn get value => real()();
  IntColumn get rank => integer()();
  TextColumn get periodKey => text()();
}

// ═══════════════════════════════════════════════════════════════════════════
// Database
// ═══════════════════════════════════════════════════════════════════════════

@DriftDatabase(tables: [
  LocationPoints,
  WorkoutSessions,
  Challenges,
  ChallengeResults,
  Wallets,
  LedgerEntries,
  ProfileProgresses,
  XpTransactions,
  BadgeAwards,
  MissionProgresses,
  Seasons,
  SeasonProgresses,
  CoachingGroups,
  CoachingMembers,
  CoachingInvites,
  CoachingRankings,
  CoachingRankingEntries,
  AthleteBaselines,
  AthleteTrends,
  CoachInsights,
  Friendships,
  Groups,
  GroupMembers,
  GroupGoals,
  Events,
  EventParticipations,
  LeaderboardSnapshots,
  LeaderboardEntries,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 1;

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'omni_runner');
  }
}

// Lazy singleton
AppDatabase? _db;
AppDatabase getDatabase() => _db ??= AppDatabase();
