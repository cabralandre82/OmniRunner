import 'package:get_it/get_it.dart';

import 'package:omni_runner/core/push/notification_rules_service.dart';
import 'package:omni_runner/data/repositories_impl/supabase_challenges_remote_source.dart';
import 'package:omni_runner/data/repositories_impl/supabase_wallet_remote_source.dart';
import 'package:omni_runner/data/repositories_impl/supabase_progression_remote_source.dart';
import 'package:omni_runner/data/repositories_impl/supabase_badges_remote_source.dart';
import 'package:omni_runner/data/repositories_impl/supabase_missions_remote_source.dart';
import 'package:omni_runner/data/repositories_impl/supabase_my_assessoria_remote_source.dart';

import 'package:omni_runner/domain/repositories/i_challenges_remote_source.dart';
import 'package:omni_runner/domain/repositories/i_wallet_remote_source.dart';
import 'package:omni_runner/domain/repositories/i_progression_remote_source.dart';
import 'package:omni_runner/domain/repositories/i_badges_remote_source.dart';
import 'package:omni_runner/domain/repositories/i_missions_remote_source.dart';
import 'package:omni_runner/domain/repositories/i_my_assessoria_remote_source.dart';
import 'package:omni_runner/domain/repositories/i_verification_remote_source.dart';
import 'package:omni_runner/domain/usecases/gamification/cancel_challenge.dart';
import 'package:omni_runner/domain/usecases/gamification/create_challenge.dart';
import 'package:omni_runner/domain/usecases/gamification/join_challenge.dart';
import 'package:omni_runner/domain/usecases/gamification/start_challenge.dart';
import 'package:omni_runner/domain/usecases/gamification/evaluate_challenge.dart';
import 'package:omni_runner/domain/usecases/gamification/settle_challenge.dart';
import 'package:omni_runner/domain/usecases/coaching/get_coaching_group_details.dart';
import 'package:omni_runner/domain/usecases/coaching/switch_assessoria.dart';
import 'package:omni_runner/domain/usecases/training/list_training_sessions.dart';
import 'package:omni_runner/domain/usecases/training/list_attendance.dart';
import 'package:omni_runner/domain/usecases/training/cancel_training_session.dart';
import 'package:omni_runner/domain/usecases/training/issue_checkin_token.dart';
import 'package:omni_runner/domain/usecases/training/mark_attendance.dart';
import 'package:omni_runner/domain/usecases/crm/list_crm_athletes.dart';
import 'package:omni_runner/domain/usecases/crm/manage_tags.dart';
import 'package:omni_runner/domain/usecases/crm/manage_notes.dart';
import 'package:omni_runner/domain/usecases/crm/manage_member_status.dart';
import 'package:omni_runner/domain/usecases/announcements/list_announcements.dart';
import 'package:omni_runner/domain/usecases/announcements/mark_announcement_read.dart';
import 'package:omni_runner/domain/usecases/social/send_friend_invite.dart';
import 'package:omni_runner/domain/usecases/social/accept_friend.dart';
import 'package:omni_runner/domain/repositories/i_challenge_repo.dart';
import 'package:omni_runner/domain/repositories/i_coaching_group_repo.dart';
import 'package:omni_runner/domain/repositories/i_coaching_member_repo.dart';
import 'package:omni_runner/domain/repositories/i_coaching_ranking_repo.dart';
import 'package:omni_runner/domain/repositories/i_crm_repo.dart';
import 'package:omni_runner/domain/repositories/i_feed_remote_source.dart';
import 'package:omni_runner/domain/repositories/i_leaderboard_repo.dart';
import 'package:omni_runner/domain/repositories/i_token_intent_repo.dart';
import 'package:omni_runner/domain/repositories/i_training_session_repo.dart';
import 'package:omni_runner/domain/repositories/i_workout_repo.dart';
import 'package:omni_runner/domain/repositories/i_wallet_repo.dart';
import 'package:omni_runner/domain/repositories/i_ledger_repo.dart';
import 'package:omni_runner/domain/repositories/i_announcement_repo.dart';
import 'package:omni_runner/domain/repositories/i_coach_insight_repo.dart';
import 'package:omni_runner/domain/repositories/i_athlete_baseline_repo.dart';
import 'package:omni_runner/domain/repositories/i_athlete_trend_repo.dart';
import 'package:omni_runner/domain/repositories/i_friendship_repo.dart';
import 'package:omni_runner/domain/repositories/i_profile_progress_repo.dart';
import 'package:omni_runner/domain/repositories/i_xp_transaction_repo.dart';
import 'package:omni_runner/domain/repositories/i_badge_award_repo.dart';
import 'package:omni_runner/domain/repositories/i_mission_progress_repo.dart';

import 'package:omni_runner/presentation/blocs/announcement_feed/announcement_feed_bloc.dart';
import 'package:omni_runner/presentation/blocs/announcement_detail/announcement_detail_bloc.dart';
import 'package:omni_runner/presentation/blocs/assessoria_feed/assessoria_feed_bloc.dart';
import 'package:omni_runner/presentation/blocs/athlete_evolution/athlete_evolution_bloc.dart';
import 'package:omni_runner/presentation/blocs/athlete_profile/athlete_profile_bloc.dart';
import 'package:omni_runner/presentation/blocs/badges/badges_bloc.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_bloc.dart';
import 'package:omni_runner/presentation/blocs/checkin/checkin_bloc.dart';
import 'package:omni_runner/presentation/blocs/coach_insights/coach_insights_bloc.dart';
import 'package:omni_runner/presentation/blocs/coaching_group_details/coaching_group_details_bloc.dart';
import 'package:omni_runner/presentation/blocs/coaching_groups/coaching_groups_bloc.dart';
import 'package:omni_runner/presentation/blocs/coaching_rankings/coaching_rankings_bloc.dart';
import 'package:omni_runner/presentation/blocs/crm_list/crm_list_bloc.dart';
import 'package:omni_runner/presentation/blocs/friends/friends_bloc.dart';
import 'package:omni_runner/presentation/blocs/group_evolution/group_evolution_bloc.dart';
import 'package:omni_runner/presentation/blocs/leaderboards/leaderboards_bloc.dart';
import 'package:omni_runner/presentation/blocs/missions/missions_bloc.dart';
import 'package:omni_runner/presentation/blocs/my_assessoria/my_assessoria_bloc.dart';
import 'package:omni_runner/presentation/blocs/progression/progression_bloc.dart';
import 'package:omni_runner/presentation/blocs/staff_qr/staff_qr_bloc.dart';
import 'package:omni_runner/presentation/blocs/training_detail/training_detail_bloc.dart';
import 'package:omni_runner/presentation/blocs/training_list/training_list_bloc.dart';
import 'package:omni_runner/presentation/blocs/verification/verification_bloc.dart';
import 'package:omni_runner/presentation/blocs/wallet/wallet_bloc.dart';
import 'package:omni_runner/presentation/blocs/workout_assignments/workout_assignments_bloc.dart';
import 'package:omni_runner/presentation/blocs/workout_builder/workout_builder_bloc.dart';
import 'package:omni_runner/presentation/blocs/training_feed/training_feed_bloc.dart';
import 'package:omni_runner/domain/repositories/i_training_plan_repo.dart';
import 'package:omni_runner/data/services/training_sync_service.dart';

/// Registers BLoCs and their remote data sources.
void registerPresentationModule(GetIt sl) {
  sl.registerLazySingleton<IChallengesRemoteSource>(
    SupabaseChallengesRemoteSource.new,
  );
  sl.registerFactory<ChallengesBloc>(
    () => ChallengesBloc(
      challengeRepo: sl<IChallengeRepo>(),
      remote: sl<IChallengesRemoteSource>(),
      createChallenge: sl<CreateChallenge>(),
      joinChallenge: sl<JoinChallenge>(),
      cancelChallenge: sl<CancelChallenge>(),
      startChallenge: sl<StartChallenge>(),
      evaluateChallenge: sl<EvaluateChallenge>(),
      settleChallenge: sl<SettleChallenge>(),
    ),
  );

  sl.registerLazySingleton<IWalletRemoteSource>(
    SupabaseWalletRemoteSource.new,
  );
  sl.registerFactory<WalletBloc>(
    () => WalletBloc(
      walletRepo: sl<IWalletRepo>(),
      ledgerRepo: sl<ILedgerRepo>(),
      remote: sl<IWalletRemoteSource>(),
    ),
  );

  sl.registerLazySingleton<IProgressionRemoteSource>(
    SupabaseProgressionRemoteSource.new,
  );
  sl.registerFactory<ProgressionBloc>(
    () => ProgressionBloc(
      profileRepo: sl<IProfileProgressRepo>(),
      xpRepo: sl<IXpTransactionRepo>(),
      remote: sl<IProgressionRemoteSource>(),
    ),
  );

  sl.registerLazySingleton<IBadgesRemoteSource>(
    SupabaseBadgesRemoteSource.new,
  );
  sl.registerFactory<BadgesBloc>(
    () => BadgesBloc(
      awardRepo: sl<IBadgeAwardRepo>(),
      remote: sl<IBadgesRemoteSource>(),
    ),
  );

  sl.registerLazySingleton<IMissionsRemoteSource>(
    SupabaseMissionsRemoteSource.new,
  );
  sl.registerFactory<MissionsBloc>(
    () => MissionsBloc(
      progressRepo: sl<IMissionProgressRepo>(),
      remote: sl<IMissionsRemoteSource>(),
    ),
  );

  sl.registerFactory<CoachingGroupsBloc>(
    () => CoachingGroupsBloc(
      groupRepo: sl<ICoachingGroupRepo>(),
      memberRepo: sl<ICoachingMemberRepo>(),
    ),
  );
  sl.registerFactory<CoachingGroupDetailsBloc>(
    () => CoachingGroupDetailsBloc(
      getDetails: sl<GetCoachingGroupDetails>(),
    ),
  );
  sl.registerFactory<CoachingRankingsBloc>(
    () => CoachingRankingsBloc(
      rankingRepo: sl<ICoachingRankingRepo>(),
    ),
  );
  sl.registerLazySingleton<IMyAssessoriaRemoteSource>(
    SupabaseMyAssessoriaRemoteSource.new,
  );
  sl.registerFactory<MyAssessoriaBloc>(
    () => MyAssessoriaBloc(
      groupRepo: sl<ICoachingGroupRepo>(),
      memberRepo: sl<ICoachingMemberRepo>(),
      remote: sl<IMyAssessoriaRemoteSource>(),
      switchAssessoria: sl<SwitchAssessoria>(),
    ),
  );
  sl.registerFactory<StaffQrBloc>(
    () => StaffQrBloc(repo: sl<ITokenIntentRepo>()),
  );

  sl.registerFactory<TrainingListBloc>(
    () => TrainingListBloc(listSessions: sl<ListTrainingSessions>()),
  );
  sl.registerFactory<TrainingDetailBloc>(
    () => TrainingDetailBloc(
      sessionRepo: sl<ITrainingSessionRepo>(),
      listAttendance: sl<ListAttendance>(),
      cancelTrainingSession: sl<CancelTrainingSession>(),
    ),
  );
  sl.registerFactory<CheckinBloc>(
    () => CheckinBloc(
      issueToken: sl<IssueCheckinToken>(),
      markAttendance: sl<MarkAttendance>(),
    ),
  );

  sl.registerFactory<CrmListBloc>(
    () => CrmListBloc(
      listCrmAthletes: sl<ListCrmAthletes>(),
      manageTags: sl<ManageTags>(),
    ),
  );
  sl.registerFactory<AthleteProfileBloc>(
    () => AthleteProfileBloc(
      manageTags: sl<ManageTags>(),
      manageNotes: sl<ManageNotes>(),
      manageMemberStatus: sl<ManageMemberStatus>(),
      crmRepo: sl<ICrmRepo>(),
    ),
  );

  sl.registerFactory<AnnouncementFeedBloc>(
    () => AnnouncementFeedBloc(
      listAnnouncements: sl<ListAnnouncements>(),
      markAnnouncementRead: sl<MarkAnnouncementRead>(),
    ),
  );
  sl.registerFactory<AnnouncementDetailBloc>(
    () => AnnouncementDetailBloc(
      repo: sl<IAnnouncementRepo>(),
      markAnnouncementRead: sl<MarkAnnouncementRead>(),
    ),
  );

  sl.registerFactory<CoachInsightsBloc>(
    () => CoachInsightsBloc(repo: sl<ICoachInsightRepo>()),
  );

  sl.registerFactory<AthleteEvolutionBloc>(
    () => AthleteEvolutionBloc(
      trendRepo: sl<IAthleteTrendRepo>(),
      baselineRepo: sl<IAthleteBaselineRepo>(),
    ),
  );
  sl.registerFactory<GroupEvolutionBloc>(
    () => GroupEvolutionBloc(trendRepo: sl<IAthleteTrendRepo>()),
  );

  sl.registerFactory<FriendsBloc>(
    () => FriendsBloc(
      friendshipRepo: sl<IFriendshipRepo>(),
      sendInvite: sl<SendFriendInvite>(),
      acceptFriend: sl<AcceptFriend>(),
      notifyRules: sl<NotificationRulesService>(),
    ),
  );

  sl.registerFactory<LeaderboardsBloc>(
    () => LeaderboardsBloc(repo: sl<ILeaderboardRepo>()),
  );

  sl.registerFactory<AssessoriaFeedBloc>(
    () => AssessoriaFeedBloc(remote: sl<IFeedRemoteSource>()),
  );

  sl.registerFactory<VerificationBloc>(
    () => VerificationBloc(remote: sl<IVerificationRemoteSource>()),
  );

  sl.registerFactory<WorkoutBuilderBloc>(
    () => WorkoutBuilderBloc(repo: sl<IWorkoutRepo>()),
  );
  sl.registerFactory<WorkoutAssignmentsBloc>(
    () => WorkoutAssignmentsBloc(repo: sl<IWorkoutRepo>()),
  );

  sl.registerFactory<TrainingFeedBloc>(
    () => TrainingFeedBloc(
      repo: sl<ITrainingPlanRepo>(),
      syncService: sl<TrainingSyncService>(),
    ),
  );
}
