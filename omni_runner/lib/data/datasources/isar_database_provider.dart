import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import 'package:omni_runner/data/models/isar/athlete_baseline_model.dart';
import 'package:omni_runner/data/models/isar/athlete_trend_model.dart';
import 'package:omni_runner/data/models/isar/coach_insight_model.dart';
import 'package:omni_runner/data/models/isar/badge_model.dart';
import 'package:omni_runner/data/models/isar/challenge_record.dart';
import 'package:omni_runner/data/models/isar/coaching_group_model.dart';
import 'package:omni_runner/data/models/isar/coaching_invite_model.dart';
import 'package:omni_runner/data/models/isar/coaching_member_model.dart';
import 'package:omni_runner/data/models/isar/coaching_ranking_entry_model.dart';
import 'package:omni_runner/data/models/isar/coaching_ranking_model.dart';
import 'package:omni_runner/data/models/isar/challenge_result_record.dart';
import 'package:omni_runner/data/models/isar/ledger_record.dart';
import 'package:omni_runner/data/models/isar/location_point_record.dart';
import 'package:omni_runner/data/models/isar/mission_model.dart';
import 'package:omni_runner/data/models/isar/progress_model.dart';
import 'package:omni_runner/data/models/isar/season_model.dart';
import 'package:omni_runner/data/models/isar/event_model.dart';
import 'package:omni_runner/data/models/isar/friendship_model.dart';
import 'package:omni_runner/data/models/isar/group_model.dart';
import 'package:omni_runner/data/models/isar/leaderboard_model.dart';
import 'package:omni_runner/data/models/isar/wallet_record.dart';
import 'package:omni_runner/data/models/isar/workout_session_record.dart';

/// Centralizes Isar database initialization.
///
/// Provides a single [Isar] instance for the entire app.
/// Must be initialized once at startup via [open].
///
/// Uses `path_provider` to resolve the app documents directory.
class IsarDatabaseProvider {
  Isar? _instance;

  /// Returns the open [Isar] instance.
  ///
  /// Throws [StateError] if [open] has not been called.
  Isar get instance {
    final db = _instance;
    if (db == null) {
      throw StateError(
        'Isar not initialized. Call IsarDatabaseProvider.open() first.',
      );
    }
    return db;
  }

  /// Opens (or returns) the Isar database.
  ///
  /// Safe to call multiple times — returns existing instance if already open.
  ///
  /// Registers both collections:
  /// - [LocationPointRecordSchema]
  /// - [WorkoutSessionRecordSchema]
  Future<Isar> open() async {
    if (_instance != null) return _instance!;

    final dir = await getApplicationDocumentsDirectory();

    _instance = await Isar.open(
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
        // Phase 15 — Social & Events
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

    return _instance!;
  }

  /// Closes the database. Mainly used for testing.
  Future<void> close() async {
    await _instance?.close();
    _instance = null;
  }
}
