// ignore_for_file: undefined_identifier, undefined_getter
// One-time Isar→Drift migrator. Schema identifiers require isar_generator.
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import 'package:omni_runner/data/models/isar/athlete_baseline_model.dart';
import 'package:omni_runner/data/models/isar/athlete_trend_model.dart';
import 'package:omni_runner/data/models/isar/badge_model.dart';
import 'package:omni_runner/data/models/isar/challenge_record.dart';
import 'package:omni_runner/data/models/isar/challenge_result_record.dart';
import 'package:omni_runner/data/models/isar/coach_insight_model.dart';
import 'package:omni_runner/data/models/isar/coaching_group_model.dart';
import 'package:omni_runner/data/models/isar/coaching_invite_model.dart';
import 'package:omni_runner/data/models/isar/coaching_member_model.dart';
import 'package:omni_runner/data/models/isar/coaching_ranking_entry_model.dart';
import 'package:omni_runner/data/models/isar/coaching_ranking_model.dart';
import 'package:omni_runner/data/models/isar/event_model.dart';
import 'package:omni_runner/data/models/isar/friendship_model.dart';
import 'package:omni_runner/data/models/isar/group_model.dart';
import 'package:omni_runner/data/models/isar/leaderboard_model.dart';
import 'package:omni_runner/data/models/isar/ledger_record.dart';
import 'package:omni_runner/data/models/isar/location_point_record.dart';
import 'package:omni_runner/data/models/isar/mission_model.dart';
import 'package:omni_runner/data/models/isar/progress_model.dart';
import 'package:omni_runner/data/models/isar/season_model.dart';
import 'package:omni_runner/data/models/isar/wallet_record.dart';
import 'package:omni_runner/data/models/isar/workout_session_record.dart';

import 'drift_database.dart';

/// Migrates all data from Isar to Drift (SQLite).
///
/// Idempotent: if Isar database files no longer exist on disk the migration
/// is a no-op. After a successful run the Isar files are deleted so
/// subsequent calls return immediately.
class IsarToDriftMigrator {
  final AppDatabase _db;

  static const _kBatchSize = 500;

  const IsarToDriftMigrator(this._db);

  /// Returns `true` when Isar database files still exist on disk.
  Future<bool> needsMigration() async {
    final dir = await getApplicationDocumentsDirectory();
    final isarFile = File('${dir.path}/omni_runner.isar');
    return isarFile.existsSync();
  }

  /// Runs the full migration. Safe to call multiple times.
  Future<void> migrate() async {
    if (!await needsMigration()) return;

    final dir = await getApplicationDocumentsDirectory();

    final isar = await Isar.open(
      [
        LocationPointRecordSchema,
        WorkoutSessionRecordSchema,
        ChallengeRecordSchema,
        ChallengeResultRecordSchema,
        WalletRecordSchema,
        LedgerRecordSchema,
        ProfileProgressRecordSchema,
        XpTransactionRecordSchema,
        BadgeAwardRecordSchema,
        MissionProgressRecordSchema,
        SeasonRecordSchema,
        SeasonProgressRecordSchema,
        CoachingGroupRecordSchema,
        CoachingMemberRecordSchema,
        CoachingInviteRecordSchema,
        CoachingRankingRecordSchema,
        CoachingRankingEntryRecordSchema,
        AthleteBaselineRecordSchema,
        AthleteTrendRecordSchema,
        CoachInsightRecordSchema,
        FriendshipRecordSchema,
        GroupRecordSchema,
        GroupMemberRecordSchema,
        GroupGoalRecordSchema,
        EventRecordSchema,
        EventParticipationRecordSchema,
        LeaderboardSnapshotRecordSchema,
        LeaderboardEntryRecordSchema,
      ],
      directory: dir.path,
      name: 'omni_runner',
    );

    try {
      await _migrateAll(isar);
      await isar.close(deleteFromDisk: true);
    } catch (_) {
      await isar.close();
      rethrow;
    }
  }

  Future<void> _migrateAll(Isar isar) async {
    // GPS & Workout
    await _migrateLocationPoints(isar);
    await _migrateWorkoutSessions(isar);
    // Challenges
    await _migrateChallenges(isar);
    await _migrateChallengeResults(isar);
    // Economy
    await _migrateWallets(isar);
    await _migrateLedgerEntries(isar);
    // Progression
    await _migrateProfileProgresses(isar);
    await _migrateXpTransactions(isar);
    // Badges & Missions
    await _migrateBadgeAwards(isar);
    await _migrateMissionProgresses(isar);
    // Seasons
    await _migrateSeasons(isar);
    await _migrateSeasonProgresses(isar);
    // Coaching
    await _migrateCoachingGroups(isar);
    await _migrateCoachingMembers(isar);
    await _migrateCoachingInvites(isar);
    await _migrateCoachingRankings(isar);
    await _migrateCoachingRankingEntries(isar);
    // Analytics
    await _migrateAthleteBaselines(isar);
    await _migrateAthleteTrends(isar);
    await _migrateCoachInsights(isar);
    // Social
    await _migrateFriendships(isar);
    await _migrateGroups(isar);
    await _migrateGroupMembers(isar);
    await _migrateGroupGoals(isar);
    // Events
    await _migrateEvents(isar);
    await _migrateEventParticipations(isar);
    // Leaderboards
    await _migrateLeaderboardSnapshots(isar);
    await _migrateLeaderboardEntries(isar);
  }

  // ─── GPS & Workout ─────────────────────────────────────────────────────

  Future<void> _migrateLocationPoints(Isar isar) async {
    final records = await isar.locationPointRecords.where().findAll();
    for (var i = 0; i < records.length; i += _kBatchSize) {
      final chunk = records.skip(i).take(_kBatchSize);
      await _db.batch((b) {
        for (final r in chunk) {
          b.insert(
            _db.locationPoints,
            LocationPointsCompanion(
              sessionId: Value(r.sessionId),
              lat: Value(r.lat),
              lng: Value(r.lng),
              alt: Value(r.alt),
              accuracy: Value(r.accuracy),
              speed: Value(r.speed),
              bearing: Value(r.bearing),
              timestampMs: Value(r.timestampMs),
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      });
    }
  }

  Future<void> _migrateWorkoutSessions(Isar isar) async {
    final records = await isar.workoutSessionRecords.where().findAll();
    for (var i = 0; i < records.length; i += _kBatchSize) {
      final chunk = records.skip(i).take(_kBatchSize);
      await _db.batch((b) {
        for (final r in chunk) {
          b.insert(
            _db.workoutSessions,
            WorkoutSessionsCompanion(
              sessionUuid: Value(r.sessionUuid),
              userId: Value(r.userId),
              status: Value(r.status),
              startTimeMs: Value(r.startTimeMs),
              endTimeMs: Value(r.endTimeMs),
              totalDistanceM: Value(r.totalDistanceM),
              movingMs: Value(r.movingMs),
              isVerified: Value(r.isVerified),
              isSynced: Value(r.isSynced),
              ghostSessionId: Value(r.ghostSessionId),
              integrityFlags: Value(r.integrityFlags),
              avgBpm: Value(r.avgBpm),
              maxBpm: Value(r.maxBpm),
              avgCadenceSpm: Value(r.avgCadenceSpm),
              source: Value(r.source),
              deviceName: Value(r.deviceName),
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      });
    }
  }

  // ─── Challenges ────────────────────────────────────────────────────────

  Future<void> _migrateChallenges(Isar isar) async {
    final records = await isar.challengeRecords.where().findAll();
    for (var i = 0; i < records.length; i += _kBatchSize) {
      final chunk = records.skip(i).take(_kBatchSize);
      await _db.batch((b) {
        for (final r in chunk) {
          b.insert(
            _db.challenges,
            ChallengesCompanion(
              challengeUuid: Value(r.challengeUuid),
              creatorUserId: Value(r.creatorUserId),
              status: Value(r.status),
              type: Value(r.type),
              title: Value(r.title),
              metricOrdinal: Value(r.metricOrdinal),
              target: Value(r.target),
              windowMs: Value(r.windowMs),
              startModeOrdinal: Value(r.startModeOrdinal),
              fixedStartMs: Value(r.fixedStartMs),
              minSessionDistanceM: Value(r.minSessionDistanceM),
              antiCheatPolicyOrdinal: Value(r.antiCheatPolicyOrdinal),
              entryFeeCoins: Value(r.entryFeeCoins),
              createdAtMs: Value(r.createdAtMs),
              startsAtMs: Value(r.startsAtMs),
              endsAtMs: Value(r.endsAtMs),
              teamAGroupId: Value(r.teamAGroupId),
              teamBGroupId: Value(r.teamBGroupId),
              teamAGroupName: Value(r.teamAGroupName),
              teamBGroupName: Value(r.teamBGroupName),
              participantsJson: Value(r.participantsJson),
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      });
    }
  }

  Future<void> _migrateChallengeResults(Isar isar) async {
    final records = await isar.challengeResultRecords.where().findAll();
    for (var i = 0; i < records.length; i += _kBatchSize) {
      final chunk = records.skip(i).take(_kBatchSize);
      await _db.batch((b) {
        for (final r in chunk) {
          b.insert(
            _db.challengeResults,
            ChallengeResultsCompanion(
              challengeId: Value(r.challengeId),
              metricOrdinal: Value(r.metricOrdinal),
              totalCoinsDistributed: Value(r.totalCoinsDistributed),
              calculatedAtMs: Value(r.calculatedAtMs),
              resultsJson: Value(r.resultsJson),
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      });
    }
  }

  // ─── Economy ───────────────────────────────────────────────────────────

  Future<void> _migrateWallets(Isar isar) async {
    final records = await isar.walletRecords.where().findAll();
    for (var i = 0; i < records.length; i += _kBatchSize) {
      final chunk = records.skip(i).take(_kBatchSize);
      await _db.batch((b) {
        for (final r in chunk) {
          b.insert(
            _db.wallets,
            WalletsCompanion(
              userId: Value(r.userId),
              balanceCoins: Value(r.balanceCoins),
              pendingCoins: Value(r.pendingCoins),
              lifetimeEarnedCoins: Value(r.lifetimeEarnedCoins),
              lifetimeSpentCoins: Value(r.lifetimeSpentCoins),
              lastReconciledAtMs: Value(r.lastReconciledAtMs),
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      });
    }
  }

  Future<void> _migrateLedgerEntries(Isar isar) async {
    final records = await isar.ledgerRecords.where().findAll();
    for (var i = 0; i < records.length; i += _kBatchSize) {
      final chunk = records.skip(i).take(_kBatchSize);
      await _db.batch((b) {
        for (final r in chunk) {
          b.insert(
            _db.ledgerEntries,
            LedgerEntriesCompanion(
              entryUuid: Value(r.entryUuid),
              userId: Value(r.userId),
              deltaCoins: Value(r.deltaCoins),
              reasonOrdinal: Value(r.reasonOrdinal),
              refId: Value(r.refId),
              issuerGroupId: Value(r.issuerGroupId),
              createdAtMs: Value(r.createdAtMs),
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      });
    }
  }

  // ─── Progression ───────────────────────────────────────────────────────

  Future<void> _migrateProfileProgresses(Isar isar) async {
    final records = await isar.profileProgressRecords.where().findAll();
    for (var i = 0; i < records.length; i += _kBatchSize) {
      final chunk = records.skip(i).take(_kBatchSize);
      await _db.batch((b) {
        for (final r in chunk) {
          b.insert(
            _db.profileProgresses,
            ProfileProgressesCompanion(
              userId: Value(r.userId),
              totalXp: Value(r.totalXp),
              seasonXp: Value(r.seasonXp),
              currentSeasonId: Value(r.currentSeasonId),
              dailyStreakCount: Value(r.dailyStreakCount),
              streakBest: Value(r.streakBest),
              lastStreakDayMs: Value(r.lastStreakDayMs),
              hasFreezeAvailable: Value(r.hasFreezeAvailable),
              weeklySessionCount: Value(r.weeklySessionCount),
              monthlySessionCount: Value(r.monthlySessionCount),
              lifetimeSessionCount: Value(r.lifetimeSessionCount),
              lifetimeDistanceM: Value(r.lifetimeDistanceM),
              lifetimeMovingMs: Value(r.lifetimeMovingMs),
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      });
    }
  }

  Future<void> _migrateXpTransactions(Isar isar) async {
    final records = await isar.xpTransactionRecords.where().findAll();
    for (var i = 0; i < records.length; i += _kBatchSize) {
      final chunk = records.skip(i).take(_kBatchSize);
      await _db.batch((b) {
        for (final r in chunk) {
          b.insert(
            _db.xpTransactions,
            XpTransactionsCompanion(
              txUuid: Value(r.txUuid),
              userId: Value(r.userId),
              xp: Value(r.xp),
              sourceOrdinal: Value(r.sourceOrdinal),
              refId: Value(r.refId),
              createdAtMs: Value(r.createdAtMs),
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      });
    }
  }

  // ─── Badges & Missions ────────────────────────────────────────────────

  Future<void> _migrateBadgeAwards(Isar isar) async {
    final records = await isar.badgeAwardRecords.where().findAll();
    for (var i = 0; i < records.length; i += _kBatchSize) {
      final chunk = records.skip(i).take(_kBatchSize);
      await _db.batch((b) {
        for (final r in chunk) {
          b.insert(
            _db.badgeAwards,
            BadgeAwardsCompanion(
              awardUuid: Value(r.awardUuid),
              userId: Value(r.userId),
              badgeId: Value(r.badgeId),
              triggerSessionId: Value(r.triggerSessionId),
              unlockedAtMs: Value(r.unlockedAtMs),
              xpAwarded: Value(r.xpAwarded),
              coinsAwarded: Value(r.coinsAwarded),
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      });
    }
  }

  Future<void> _migrateMissionProgresses(Isar isar) async {
    final records = await isar.missionProgressRecords.where().findAll();
    for (var i = 0; i < records.length; i += _kBatchSize) {
      final chunk = records.skip(i).take(_kBatchSize);
      await _db.batch((b) {
        for (final r in chunk) {
          b.insert(
            _db.missionProgresses,
            MissionProgressesCompanion(
              progressUuid: Value(r.progressUuid),
              userId: Value(r.userId),
              missionId: Value(r.missionId),
              statusOrdinal: Value(r.statusOrdinal),
              currentValue: Value(r.currentValue),
              targetValue: Value(r.targetValue),
              assignedAtMs: Value(r.assignedAtMs),
              completedAtMs: Value(r.completedAtMs),
              completionCount: Value(r.completionCount),
              contributingSessionIdsJson: Value(r.contributingSessionIdsJson),
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      });
    }
  }

  // ─── Seasons ───────────────────────────────────────────────────────────

  Future<void> _migrateSeasons(Isar isar) async {
    final records = await isar.seasonRecords.where().findAll();
    for (var i = 0; i < records.length; i += _kBatchSize) {
      final chunk = records.skip(i).take(_kBatchSize);
      await _db.batch((b) {
        for (final r in chunk) {
          b.insert(
            _db.seasons,
            SeasonsCompanion(
              seasonUuid: Value(r.seasonUuid),
              name: Value(r.name),
              statusOrdinal: Value(r.statusOrdinal),
              startsAtMs: Value(r.startsAtMs),
              endsAtMs: Value(r.endsAtMs),
              passXpMilestonesStr: Value(r.passXpMilestonesStr),
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      });
    }
  }

  Future<void> _migrateSeasonProgresses(Isar isar) async {
    final records = await isar.seasonProgressRecords.where().findAll();
    for (var i = 0; i < records.length; i += _kBatchSize) {
      final chunk = records.skip(i).take(_kBatchSize);
      await _db.batch((b) {
        for (final r in chunk) {
          b.insert(
            _db.seasonProgresses,
            SeasonProgressesCompanion(
              userId: Value(r.userId),
              seasonId: Value(r.seasonId),
              seasonXp: Value(r.seasonXp),
              claimedMilestoneIndicesStr: Value(r.claimedMilestoneIndicesStr),
              endRewardsClaimed: Value(r.endRewardsClaimed),
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      });
    }
  }

  // ─── Coaching ──────────────────────────────────────────────────────────

  Future<void> _migrateCoachingGroups(Isar isar) async {
    final records = await isar.coachingGroupRecords.where().findAll();
    for (var i = 0; i < records.length; i += _kBatchSize) {
      final chunk = records.skip(i).take(_kBatchSize);
      await _db.batch((b) {
        for (final r in chunk) {
          b.insert(
            _db.coachingGroups,
            CoachingGroupsCompanion(
              groupUuid: Value(r.groupUuid),
              name: Value(r.name),
              logoUrl: Value(r.logoUrl),
              coachUserId: Value(r.coachUserId),
              description: Value(r.description),
              city: Value(r.city),
              inviteCode: Value(r.inviteCode),
              inviteEnabled: Value(r.inviteEnabled),
              createdAtMs: Value(r.createdAtMs),
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      });
    }
  }

  Future<void> _migrateCoachingMembers(Isar isar) async {
    final records = await isar.coachingMemberRecords.where().findAll();
    for (var i = 0; i < records.length; i += _kBatchSize) {
      final chunk = records.skip(i).take(_kBatchSize);
      await _db.batch((b) {
        for (final r in chunk) {
          b.insert(
            _db.coachingMembers,
            CoachingMembersCompanion(
              memberUuid: Value(r.memberUuid),
              groupId: Value(r.groupId),
              userId: Value(r.userId),
              displayName: Value(r.displayName),
              roleOrdinal: Value(r.roleOrdinal),
              joinedAtMs: Value(r.joinedAtMs),
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      });
    }
  }

  Future<void> _migrateCoachingInvites(Isar isar) async {
    final records = await isar.coachingInviteRecords.where().findAll();
    for (var i = 0; i < records.length; i += _kBatchSize) {
      final chunk = records.skip(i).take(_kBatchSize);
      await _db.batch((b) {
        for (final r in chunk) {
          b.insert(
            _db.coachingInvites,
            CoachingInvitesCompanion(
              inviteUuid: Value(r.inviteUuid),
              groupId: Value(r.groupId),
              invitedUserId: Value(r.invitedUserId),
              invitedByUserId: Value(r.invitedByUserId),
              statusOrdinal: Value(r.statusOrdinal),
              expiresAtMs: Value(r.expiresAtMs),
              createdAtMs: Value(r.createdAtMs),
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      });
    }
  }

  Future<void> _migrateCoachingRankings(Isar isar) async {
    final records = await isar.coachingRankingRecords.where().findAll();
    for (var i = 0; i < records.length; i += _kBatchSize) {
      final chunk = records.skip(i).take(_kBatchSize);
      await _db.batch((b) {
        for (final r in chunk) {
          b.insert(
            _db.coachingRankings,
            CoachingRankingsCompanion(
              rankingUuid: Value(r.rankingUuid),
              groupId: Value(r.groupId),
              metricOrdinal: Value(r.metricOrdinal),
              periodOrdinal: Value(r.periodOrdinal),
              periodKey: Value(r.periodKey),
              startsAtMs: Value(r.startsAtMs),
              endsAtMs: Value(r.endsAtMs),
              computedAtMs: Value(r.computedAtMs),
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      });
    }
  }

  Future<void> _migrateCoachingRankingEntries(Isar isar) async {
    final records = await isar.coachingRankingEntryRecords.where().findAll();
    for (var i = 0; i < records.length; i += _kBatchSize) {
      final chunk = records.skip(i).take(_kBatchSize);
      await _db.batch((b) {
        for (final r in chunk) {
          b.insert(
            _db.coachingRankingEntries,
            CoachingRankingEntriesCompanion(
              rankingId: Value(r.rankingId),
              userId: Value(r.userId),
              displayName: Value(r.displayName),
              value: Value(r.value),
              rank: Value(r.rank),
              sessionCount: Value(r.sessionCount),
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      });
    }
  }

  // ─── Analytics ─────────────────────────────────────────────────────────

  Future<void> _migrateAthleteBaselines(Isar isar) async {
    final records = await isar.athleteBaselineRecords.where().findAll();
    for (var i = 0; i < records.length; i += _kBatchSize) {
      final chunk = records.skip(i).take(_kBatchSize);
      await _db.batch((b) {
        for (final r in chunk) {
          b.insert(
            _db.athleteBaselines,
            AthleteBaselinesCompanion(
              baselineUuid: Value(r.baselineUuid),
              userId: Value(r.userId),
              groupId: Value(r.groupId),
              metricOrdinal: Value(r.metricOrdinal),
              value: Value(r.value),
              sampleSize: Value(r.sampleSize),
              windowStartMs: Value(r.windowStartMs),
              windowEndMs: Value(r.windowEndMs),
              computedAtMs: Value(r.computedAtMs),
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      });
    }
  }

  Future<void> _migrateAthleteTrends(Isar isar) async {
    final records = await isar.athleteTrendRecords.where().findAll();
    for (var i = 0; i < records.length; i += _kBatchSize) {
      final chunk = records.skip(i).take(_kBatchSize);
      await _db.batch((b) {
        for (final r in chunk) {
          b.insert(
            _db.athleteTrends,
            AthleteTrendsCompanion(
              trendUuid: Value(r.trendUuid),
              userId: Value(r.userId),
              groupId: Value(r.groupId),
              metricOrdinal: Value(r.metricOrdinal),
              periodOrdinal: Value(r.periodOrdinal),
              directionOrdinal: Value(r.directionOrdinal),
              currentValue: Value(r.currentValue),
              baselineValue: Value(r.baselineValue),
              changePercent: Value(r.changePercent),
              dataPoints: Value(r.dataPoints),
              latestPeriodKey: Value(r.latestPeriodKey),
              analyzedAtMs: Value(r.analyzedAtMs),
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      });
    }
  }

  Future<void> _migrateCoachInsights(Isar isar) async {
    final records = await isar.coachInsightRecords.where().findAll();
    for (var i = 0; i < records.length; i += _kBatchSize) {
      final chunk = records.skip(i).take(_kBatchSize);
      await _db.batch((b) {
        for (final r in chunk) {
          b.insert(
            _db.coachInsights,
            CoachInsightsCompanion(
              insightUuid: Value(r.insightUuid),
              groupId: Value(r.groupId),
              targetUserId: Value(r.targetUserId),
              targetDisplayName: Value(r.targetDisplayName),
              typeOrdinal: Value(r.typeOrdinal),
              priorityOrdinal: Value(r.priorityOrdinal),
              title: Value(r.title),
              message: Value(r.message),
              metricOrdinal: Value(r.metricOrdinal),
              referenceValue: Value(r.referenceValue),
              changePercent: Value(r.changePercent),
              relatedEntityId: Value(r.relatedEntityId),
              createdAtMs: Value(r.createdAtMs),
              readAtMs: Value(r.readAtMs),
              dismissed: Value(r.dismissed),
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      });
    }
  }

  // ─── Social ────────────────────────────────────────────────────────────

  Future<void> _migrateFriendships(Isar isar) async {
    final records = await isar.friendshipRecords.where().findAll();
    for (var i = 0; i < records.length; i += _kBatchSize) {
      final chunk = records.skip(i).take(_kBatchSize);
      await _db.batch((b) {
        for (final r in chunk) {
          b.insert(
            _db.friendships,
            FriendshipsCompanion(
              friendshipUuid: Value(r.friendshipUuid),
              userIdA: Value(r.userIdA),
              userIdB: Value(r.userIdB),
              statusOrdinal: Value(r.statusOrdinal),
              createdAtMs: Value(r.createdAtMs),
              acceptedAtMs: Value(r.acceptedAtMs),
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      });
    }
  }

  Future<void> _migrateGroups(Isar isar) async {
    final records = await isar.groupRecords.where().findAll();
    for (var i = 0; i < records.length; i += _kBatchSize) {
      final chunk = records.skip(i).take(_kBatchSize);
      await _db.batch((b) {
        for (final r in chunk) {
          b.insert(
            _db.groups,
            GroupsCompanion(
              groupUuid: Value(r.groupUuid),
              name: Value(r.name),
              description: Value(r.description),
              avatarUrl: Value(r.avatarUrl),
              createdByUserId: Value(r.createdByUserId),
              createdAtMs: Value(r.createdAtMs),
              privacyOrdinal: Value(r.privacyOrdinal),
              maxMembers: Value(r.maxMembers),
              memberCount: Value(r.memberCount),
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      });
    }
  }

  Future<void> _migrateGroupMembers(Isar isar) async {
    final records = await isar.groupMemberRecords.where().findAll();
    for (var i = 0; i < records.length; i += _kBatchSize) {
      final chunk = records.skip(i).take(_kBatchSize);
      await _db.batch((b) {
        for (final r in chunk) {
          b.insert(
            _db.groupMembers,
            GroupMembersCompanion(
              memberUuid: Value(r.memberUuid),
              groupId: Value(r.groupId),
              userId: Value(r.userId),
              displayName: Value(r.displayName),
              roleOrdinal: Value(r.roleOrdinal),
              statusOrdinal: Value(r.statusOrdinal),
              joinedAtMs: Value(r.joinedAtMs),
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      });
    }
  }

  Future<void> _migrateGroupGoals(Isar isar) async {
    final records = await isar.groupGoalRecords.where().findAll();
    for (var i = 0; i < records.length; i += _kBatchSize) {
      final chunk = records.skip(i).take(_kBatchSize);
      await _db.batch((b) {
        for (final r in chunk) {
          b.insert(
            _db.groupGoals,
            GroupGoalsCompanion(
              goalUuid: Value(r.goalUuid),
              groupId: Value(r.groupId),
              title: Value(r.title),
              description: Value(r.description),
              targetValue: Value(r.targetValue),
              currentValue: Value(r.currentValue),
              metricOrdinal: Value(r.metricOrdinal),
              startsAtMs: Value(r.startsAtMs),
              endsAtMs: Value(r.endsAtMs),
              createdByUserId: Value(r.createdByUserId),
              statusOrdinal: Value(r.statusOrdinal),
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      });
    }
  }

  // ─── Events ────────────────────────────────────────────────────────────

  Future<void> _migrateEvents(Isar isar) async {
    final records = await isar.eventRecords.where().findAll();
    for (var i = 0; i < records.length; i += _kBatchSize) {
      final chunk = records.skip(i).take(_kBatchSize);
      await _db.batch((b) {
        for (final r in chunk) {
          b.insert(
            _db.events,
            EventsCompanion(
              eventUuid: Value(r.eventUuid),
              title: Value(r.title),
              description: Value(r.description),
              imageUrl: Value(r.imageUrl),
              typeOrdinal: Value(r.typeOrdinal),
              metricOrdinal: Value(r.metricOrdinal),
              targetValue: Value(r.targetValue),
              startsAtMs: Value(r.startsAtMs),
              endsAtMs: Value(r.endsAtMs),
              maxParticipants: Value(r.maxParticipants),
              createdBySystem: Value(r.createdBySystem),
              creatorUserId: Value(r.creatorUserId),
              rewardXpCompletion: Value(r.rewardXpCompletion),
              rewardCoinsCompletion: Value(r.rewardCoinsCompletion),
              rewardXpParticipation: Value(r.rewardXpParticipation),
              rewardBadgeId: Value(r.rewardBadgeId),
              statusOrdinal: Value(r.statusOrdinal),
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      });
    }
  }

  Future<void> _migrateEventParticipations(Isar isar) async {
    final records = await isar.eventParticipationRecords.where().findAll();
    for (var i = 0; i < records.length; i += _kBatchSize) {
      final chunk = records.skip(i).take(_kBatchSize);
      await _db.batch((b) {
        for (final r in chunk) {
          b.insert(
            _db.eventParticipations,
            EventParticipationsCompanion(
              participationUuid: Value(r.participationUuid),
              eventId: Value(r.eventId),
              userId: Value(r.userId),
              displayName: Value(r.displayName),
              joinedAtMs: Value(r.joinedAtMs),
              currentValue: Value(r.currentValue),
              rank: Value(r.rank),
              completed: Value(r.completed),
              completedAtMs: Value(r.completedAtMs),
              contributingSessionCount: Value(r.contributingSessionCount),
              contributingSessionIdsCsv: Value(r.contributingSessionIdsCsv),
              rewardsClaimed: Value(r.rewardsClaimed),
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      });
    }
  }

  // ─── Leaderboards ─────────────────────────────────────────────────────

  Future<void> _migrateLeaderboardSnapshots(Isar isar) async {
    final records = await isar.leaderboardSnapshotRecords.where().findAll();
    for (var i = 0; i < records.length; i += _kBatchSize) {
      final chunk = records.skip(i).take(_kBatchSize);
      await _db.batch((b) {
        for (final r in chunk) {
          b.insert(
            _db.leaderboardSnapshots,
            LeaderboardSnapshotsCompanion(
              snapshotUuid: Value(r.snapshotUuid),
              scopeOrdinal: Value(r.scopeOrdinal),
              groupId: Value(r.groupId),
              periodOrdinal: Value(r.periodOrdinal),
              metricOrdinal: Value(r.metricOrdinal),
              periodKey: Value(r.periodKey),
              computedAtMs: Value(r.computedAtMs),
              isFinal: Value(r.isFinal),
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      });
    }
  }

  Future<void> _migrateLeaderboardEntries(Isar isar) async {
    final records = await isar.leaderboardEntryRecords.where().findAll();
    for (var i = 0; i < records.length; i += _kBatchSize) {
      final chunk = records.skip(i).take(_kBatchSize);
      await _db.batch((b) {
        for (final r in chunk) {
          b.insert(
            _db.leaderboardEntries,
            LeaderboardEntriesCompanion(
              snapshotId: Value(r.snapshotId),
              userId: Value(r.userId),
              displayName: Value(r.displayName),
              avatarUrl: Value(r.avatarUrl),
              level: Value(r.level),
              value: Value(r.value),
              rank: Value(r.rank),
              periodKey: Value(r.periodKey),
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      });
    }
  }
}
