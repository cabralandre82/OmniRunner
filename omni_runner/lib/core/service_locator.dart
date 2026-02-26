import 'package:get_it/get_it.dart';
import 'package:isar/isar.dart';

import 'package:omni_runner/core/analytics/product_event_tracker.dart';
import 'package:omni_runner/core/auth/auth_repository.dart';
import 'package:omni_runner/core/push/notification_rules_service.dart';
import 'package:omni_runner/core/push/push_notification_service.dart';
import 'package:omni_runner/core/auth/i_auth_datasource.dart';
import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/core/deep_links/deep_link_handler.dart';
import 'package:omni_runner/data/datasources/analytics_sync_service.dart';
import 'package:omni_runner/data/datasources/mock_auth_datasource.dart';
import 'package:omni_runner/data/datasources/mock_profile_datasource.dart';
import 'package:omni_runner/data/datasources/remote_auth_datasource.dart';
import 'package:omni_runner/data/datasources/remote_profile_datasource.dart';
import 'package:omni_runner/data/repositories_impl/profile_repo.dart';
import 'package:omni_runner/domain/repositories/i_profile_repo.dart';
import 'package:omni_runner/data/datasources/audio_coach_service.dart';
import 'package:omni_runner/data/datasources/ble_permission_service.dart';
import 'package:omni_runner/data/datasources/geolocator_location_stream.dart';
import 'package:omni_runner/data/datasources/health_platform_service.dart';
import 'package:omni_runner/features/wearables_ble/ble_heart_rate_source.dart';
import 'package:omni_runner/features/wearables_ble/i_heart_rate_source.dart';
import 'package:omni_runner/data/datasources/isar_database_provider.dart';
import 'package:omni_runner/data/datasources/location_permission_service.dart';
import 'package:omni_runner/data/repositories_impl/audio_coach_repo.dart';
import 'package:omni_runner/data/repositories_impl/ble_permission_repo.dart';
import 'package:omni_runner/data/datasources/sync_service.dart';
import 'package:omni_runner/data/repositories_impl/coach_settings_repo.dart';
import 'package:omni_runner/data/repositories_impl/isar_challenge_repo.dart';
import 'package:omni_runner/data/repositories_impl/isar_badge_award_repo.dart';
import 'package:omni_runner/data/repositories_impl/isar_ledger_repo.dart';
import 'package:omni_runner/data/repositories_impl/isar_mission_progress_repo.dart';
import 'package:omni_runner/data/repositories_impl/isar_profile_progress_repo.dart';
import 'package:omni_runner/data/repositories_impl/isar_points_repo.dart';
import 'package:omni_runner/data/repositories_impl/isar_session_repo.dart';
import 'package:omni_runner/data/repositories_impl/isar_wallet_repo.dart';
import 'package:omni_runner/data/repositories_impl/isar_xp_transaction_repo.dart';
import 'package:omni_runner/data/repositories_impl/location_permission_repo.dart';
import 'package:omni_runner/data/repositories_impl/location_stream_repo.dart';
import 'package:omni_runner/data/repositories_impl/sync_repo.dart';
import 'package:omni_runner/domain/repositories/i_audio_coach.dart';
import 'package:omni_runner/domain/repositories/i_ble_permission.dart';
import 'package:omni_runner/domain/repositories/i_coach_settings_repo.dart';
import 'package:omni_runner/domain/repositories/i_location_permission.dart';
import 'package:omni_runner/domain/repositories/i_location_stream.dart';
import 'package:omni_runner/domain/repositories/i_points_repo.dart';
import 'package:omni_runner/domain/repositories/i_badge_award_repo.dart';
import 'package:omni_runner/domain/repositories/i_mission_progress_repo.dart';
import 'package:omni_runner/domain/repositories/i_profile_progress_repo.dart';
import 'package:omni_runner/domain/repositories/i_session_repo.dart';
import 'package:omni_runner/domain/repositories/i_sync_repo.dart';
import 'package:omni_runner/domain/repositories/i_xp_transaction_repo.dart';
import 'package:omni_runner/domain/repositories/i_challenge_repo.dart';
import 'package:omni_runner/domain/repositories/i_athlete_baseline_repo.dart';
import 'package:omni_runner/domain/repositories/i_athlete_trend_repo.dart';
import 'package:omni_runner/domain/repositories/i_coach_insight_repo.dart';
import 'package:omni_runner/domain/repositories/i_coaching_group_repo.dart';
import 'package:omni_runner/domain/repositories/i_coaching_invite_repo.dart';
import 'package:omni_runner/domain/repositories/i_coaching_member_repo.dart';
import 'package:omni_runner/domain/repositories/i_coaching_ranking_repo.dart';
// TODO(phase-15): re-add when Isar impls are registered:
// import 'package:omni_runner/domain/repositories/i_event_repo.dart';
// import 'package:omni_runner/domain/repositories/i_friendship_repo.dart';
// import 'package:omni_runner/domain/repositories/i_group_repo.dart';
// TODO(sprint-16.5+): re-add when Isar impls are registered:
// import 'package:omni_runner/domain/repositories/i_race_event_repo.dart';
// import 'package:omni_runner/domain/repositories/i_race_participation_repo.dart';
// import 'package:omni_runner/domain/repositories/i_race_result_repo.dart';
import 'package:omni_runner/domain/repositories/i_wallet_repo.dart';
import 'package:omni_runner/domain/repositories/i_ledger_repo.dart';
import 'package:omni_runner/data/repositories_impl/isar_coaching_group_repo.dart';
import 'package:omni_runner/data/repositories_impl/isar_coaching_invite_repo.dart';
import 'package:omni_runner/data/repositories_impl/isar_coaching_member_repo.dart';
import 'package:omni_runner/data/repositories_impl/isar_athlete_baseline_repo.dart';
import 'package:omni_runner/data/repositories_impl/isar_coach_insight_repo.dart';
import 'package:omni_runner/data/repositories_impl/isar_athlete_trend_repo.dart';
import 'package:omni_runner/data/repositories_impl/isar_coaching_ranking_repo.dart';
import 'package:omni_runner/domain/usecases/accumulate_distance.dart';
import 'package:omni_runner/domain/usecases/auto_pause_detector.dart';
import 'package:omni_runner/domain/usecases/calculate_ghost_delta.dart';
import 'package:omni_runner/domain/usecases/calculate_pace.dart';
import 'package:omni_runner/domain/usecases/discard_session.dart';
import 'package:omni_runner/domain/repositories/i_health_provider.dart';
import 'package:omni_runner/domain/usecases/ensure_ble_ready.dart';
import 'package:omni_runner/domain/usecases/ensure_health_ready.dart';
import 'package:omni_runner/domain/usecases/ensure_location_ready.dart';
import 'package:omni_runner/data/datasources/activity_recognition_service.dart';
import 'package:omni_runner/data/datasources/health_steps_source.dart';
import 'package:omni_runner/domain/usecases/integrity_detect_vehicle.dart';
import 'package:omni_runner/domain/usecases/export_workout_to_health.dart';
import 'package:omni_runner/domain/usecases/sensor_source_resolver.dart';
import 'package:omni_runner/features/watch_bridge/process_watch_session.dart';
import 'package:omni_runner/features/watch_bridge/watch_bridge.dart';
import 'package:omni_runner/features/health_export/data/health_export_service_impl.dart';
import 'package:omni_runner/features/health_export/domain/i_health_export_service.dart';
import 'package:omni_runner/features/health_export/presentation/health_export_controller.dart';
import 'package:omni_runner/features/integrations_export/data/export_service_impl.dart';
import 'package:omni_runner/features/integrations_export/domain/i_export_service.dart';
import 'package:omni_runner/features/integrations_export/presentation/export_sheet_controller.dart';
import 'package:omni_runner/features/strava/data/strava_auth_repository_impl.dart';
import 'package:omni_runner/features/strava/data/strava_http_client.dart';
import 'package:omni_runner/features/strava/data/strava_secure_store.dart';
import 'package:omni_runner/features/strava/data/strava_upload_repository_impl.dart';
import 'package:omni_runner/features/strava/domain/i_strava_auth_repository.dart';
import 'package:omni_runner/features/strava/domain/i_strava_upload_repository.dart';
import 'package:omni_runner/features/strava/presentation/strava_connect_controller.dart';
import 'package:omni_runner/domain/usecases/filter_location_points.dart';
import 'package:omni_runner/domain/usecases/finish_session.dart';
import 'package:omni_runner/domain/usecases/ghost_position_at.dart';
import 'package:omni_runner/domain/usecases/integrity_detect_speed.dart';
import 'package:omni_runner/domain/usecases/integrity_detect_teleport.dart';
import 'package:omni_runner/domain/usecases/load_ghost_from_session.dart';
import 'package:omni_runner/domain/usecases/recover_active_session.dart';
import 'package:omni_runner/domain/usecases/gamification/cancel_challenge.dart';
import 'package:omni_runner/domain/usecases/gamification/create_challenge.dart';
import 'package:omni_runner/domain/usecases/gamification/join_challenge.dart';
import 'package:omni_runner/domain/usecases/gamification/start_challenge.dart';
import 'package:omni_runner/domain/usecases/gamification/evaluate_challenge.dart';
import 'package:omni_runner/domain/usecases/gamification/settle_challenge.dart';
import 'package:omni_runner/domain/usecases/gamification/post_session_challenge_dispatcher.dart';
import 'package:omni_runner/domain/usecases/gamification/reward_session_coins.dart';
import 'package:omni_runner/domain/usecases/gamification/submit_run_to_challenge.dart';
import 'package:omni_runner/domain/usecases/progression/award_xp_for_workout.dart';
import 'package:omni_runner/domain/usecases/progression/claim_rewards.dart';
import 'package:omni_runner/domain/usecases/progression/create_daily_missions.dart';
import 'package:omni_runner/domain/usecases/progression/evaluate_badges.dart';
import 'package:omni_runner/domain/usecases/progression/post_session_progression.dart';
import 'package:omni_runner/domain/usecases/progression/update_mission_progress.dart';
import 'package:omni_runner/domain/usecases/coaching/accept_coaching_invite.dart';
import 'package:omni_runner/domain/usecases/coaching/create_coaching_group.dart';
import 'package:omni_runner/domain/usecases/coaching/get_coaching_group_details.dart';
import 'package:omni_runner/domain/usecases/coaching/get_coaching_members.dart';
import 'package:omni_runner/domain/usecases/coaching/invite_user_to_group.dart';
import 'package:omni_runner/domain/usecases/coaching/remove_coaching_member.dart';
import 'package:omni_runner/domain/usecases/coaching/switch_assessoria.dart';
import 'package:omni_runner/domain/repositories/i_switch_assessoria_repo.dart';
import 'package:omni_runner/data/repositories_impl/stub_switch_assessoria_repo.dart';
import 'package:omni_runner/data/repositories_impl/remote_switch_assessoria_repo.dart';
import 'package:omni_runner/domain/repositories/i_token_intent_repo.dart';
import 'package:omni_runner/data/repositories_impl/stub_token_intent_repo.dart';
import 'package:omni_runner/data/repositories_impl/remote_token_intent_repo.dart';
import 'package:omni_runner/presentation/blocs/athlete_evolution/athlete_evolution_bloc.dart';
import 'package:omni_runner/presentation/blocs/badges/badges_bloc.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_bloc.dart';
import 'package:omni_runner/presentation/blocs/coaching_group_details/coaching_group_details_bloc.dart';
import 'package:omni_runner/presentation/blocs/my_assessoria/my_assessoria_bloc.dart';
import 'package:omni_runner/presentation/blocs/staff_qr/staff_qr_bloc.dart';
import 'package:omni_runner/presentation/blocs/coaching_groups/coaching_groups_bloc.dart';
import 'package:omni_runner/presentation/blocs/coaching_rankings/coaching_rankings_bloc.dart';
// TODO(phase-15): re-add when Social repos are registered:
// import 'package:omni_runner/presentation/blocs/events/events_bloc.dart';
// import 'package:omni_runner/presentation/blocs/friends/friends_bloc.dart';
import 'package:omni_runner/presentation/blocs/group_evolution/group_evolution_bloc.dart';
import 'package:omni_runner/presentation/blocs/coach_insights/coach_insights_bloc.dart';
// TODO(phase-15): re-add when Social repos are registered:
// import 'package:omni_runner/presentation/blocs/groups/groups_bloc.dart';
// TODO(sprint-16.5+): re-add when Race Event repos are registered:
// import 'package:omni_runner/presentation/blocs/race_event_details/race_event_details_bloc.dart';
// import 'package:omni_runner/presentation/blocs/race_events/race_events_bloc.dart';
import 'package:omni_runner/presentation/blocs/leaderboards/leaderboards_bloc.dart';
import 'package:omni_runner/presentation/blocs/missions/missions_bloc.dart';
import 'package:omni_runner/presentation/blocs/progression/progression_bloc.dart';
import 'package:omni_runner/presentation/blocs/tracking/tracking_bloc.dart';
import 'package:omni_runner/presentation/blocs/wallet/wallet_bloc.dart';

final GetIt sl = GetIt.instance;

Future<void> setupServiceLocator() async {
  // --- Deep Link Handler ---
  sl.registerSingleton<DeepLinkHandler>(DeepLinkHandler());

  // --- Auth Datasource (adapter pattern: remote vs mock) ---
  final IAuthDataSource authDs = AppConfig.isSupabaseReady
      ? RemoteAuthDataSource()
      : MockAuthDataSource();
  sl.registerSingleton<IAuthDataSource>(authDs);

  final authRepo = AuthRepository(datasource: authDs);
  sl.registerSingleton<AuthRepository>(authRepo);

  // --- User Identity ---
  final userIdentity = UserIdentityProvider(authRepo: authRepo);
  await userIdentity.init();
  sl.registerSingleton<UserIdentityProvider>(userIdentity);

  // --- Profile (first real Supabase table with RLS) ---
  final IProfileRepo profileDs = AppConfig.isSupabaseReady
      ? RemoteProfileDataSource()
      : MockProfileDataSource(identity: userIdentity);
  sl.registerLazySingleton<IProfileRepo>(
    () => ProfileRepo(datasource: profileDs),
  );

  // --- Isar Database ---
  sl.registerLazySingleton<IsarDatabaseProvider>(
    IsarDatabaseProvider.new,
  );
  final isarProvider = sl<IsarDatabaseProvider>();
  await isarProvider.open();
  sl.registerLazySingleton<Isar>(() => isarProvider.instance);

  // --- Datasources ---
  sl.registerLazySingleton<LocationPermissionService>(
    LocationPermissionService.new,
  );
  sl.registerLazySingleton<GeolocatorLocationStream>(
    GeolocatorLocationStream.new,
  );
  sl.registerLazySingleton<AudioCoachService>(
    AudioCoachService.new,
  );
  sl.registerLazySingleton<SyncService>(
    SyncService.new,
  );
  sl.registerLazySingleton<AnalyticsSyncService>(
    AnalyticsSyncService.new,
  );
  sl.registerLazySingleton<ProductEventTracker>(
    ProductEventTracker.new,
  );
  sl.registerLazySingleton<PushNotificationService>(
    PushNotificationService.new,
  );
  sl.registerLazySingleton<NotificationRulesService>(
    NotificationRulesService.new,
  );
  sl.registerLazySingleton<BlePermissionService>(
    BlePermissionService.new,
  );
  sl.registerLazySingleton<IHeartRateSource>(
    BleHeartRateSource.new,
  );
  sl.registerLazySingleton<IHealthProvider>(
    HealthPlatformService.new,
  );

  // --- Repositories ---
  sl.registerLazySingleton<ILocationPermission>(
    () => LocationPermissionRepo(service: sl<LocationPermissionService>()),
  );
  sl.registerLazySingleton<ILocationStream>(
    () => LocationStreamRepo(datasource: sl<GeolocatorLocationStream>()),
  );
  sl.registerLazySingleton<IPointsRepo>(
    () => IsarPointsRepo(sl<Isar>()),
  );
  sl.registerLazySingleton<ISessionRepo>(
    () => IsarSessionRepo(sl<Isar>()),
  );
  sl.registerLazySingleton<IAudioCoach>(
    () => AudioCoachRepo(service: sl<AudioCoachService>()),
  );
  sl.registerLazySingleton<ICoachSettingsRepo>(
    CoachSettingsRepo.new,
  );
  sl.registerLazySingleton<ISyncRepo>(
    () => SyncRepo(
      service: sl<SyncService>(),
      isar: sl<Isar>(),
      pointsRepo: sl<IPointsRepo>(),
    ),
  );
  sl.registerLazySingleton<IBlePermission>(
    () => BlePermissionRepo(service: sl<BlePermissionService>()),
  );

  // --- Gamification Repositories ---
  sl.registerLazySingleton<IChallengeRepo>(
    () => IsarChallengeRepo(sl<Isar>()),
  );
  sl.registerLazySingleton<IWalletRepo>(
    () => IsarWalletRepo(sl<Isar>()),
  );
  sl.registerLazySingleton<ILedgerRepo>(
    () => IsarLedgerRepo(sl<Isar>()),
  );

  // --- Progression Repositories ---
  sl.registerLazySingleton<IProfileProgressRepo>(
    () => IsarProfileProgressRepo(sl<Isar>()),
  );
  sl.registerLazySingleton<IXpTransactionRepo>(
    () => IsarXpTransactionRepo(sl<Isar>()),
  );
  sl.registerLazySingleton<IBadgeAwardRepo>(
    () => IsarBadgeAwardRepo(sl<Isar>()),
  );
  sl.registerLazySingleton<IMissionProgressRepo>(
    () => IsarMissionProgressRepo(sl<Isar>()),
  );

  // --- Coaching Repositories ---
  sl.registerLazySingleton<ICoachingGroupRepo>(
    () => IsarCoachingGroupRepo(sl<Isar>()),
  );
  sl.registerLazySingleton<ICoachingMemberRepo>(
    () => IsarCoachingMemberRepo(sl<Isar>()),
  );
  sl.registerLazySingleton<ICoachingInviteRepo>(
    () => IsarCoachingInviteRepo(sl<Isar>()),
  );
  sl.registerLazySingleton<ICoachingRankingRepo>(
    () => IsarCoachingRankingRepo(sl<Isar>()),
  );

  // --- Switch Assessoria ---
  sl.registerLazySingleton<ISwitchAssessoriaRepo>(
    () => AppConfig.isSupabaseReady
        ? const RemoteSwitchAssessoriaRepo()
        : const StubSwitchAssessoriaRepo(),
  );

  // --- Token Intent ---
  sl.registerLazySingleton<ITokenIntentRepo>(
    () => AppConfig.isSupabaseReady
        ? const RemoteTokenIntentRepo()
        : const StubTokenIntentRepo(),
  );

  // --- Analytics Repositories ---
  sl.registerLazySingleton<IAthleteBaselineRepo>(
    () => IsarAthleteBaselineRepo(sl<Isar>()),
  );
  sl.registerLazySingleton<IAthleteTrendRepo>(
    () => IsarAthleteTrendRepo(sl<Isar>()),
  );
  sl.registerLazySingleton<ICoachInsightRepo>(
    () => IsarCoachInsightRepo(sl<Isar>()),
  );

  // --- Use Cases ---
  sl.registerFactory<EnsureLocationReady>(
    () => EnsureLocationReady(sl<ILocationPermission>()),
  );
  sl.registerFactory<EnsureBleReady>(
    () => EnsureBleReady(sl<IBlePermission>()),
  );
  sl.registerFactory<EnsureHealthReady>(
    () => EnsureHealthReady(
      sl<IHealthProvider>(),
      requestActivityRecognition: requestActivityRecognitionPermission,
    ),
  );
  sl.registerFactory<ExportWorkoutToHealth>(
    () => ExportWorkoutToHealth(
      healthProvider: sl<IHealthProvider>(),
      pointsRepo: sl<IPointsRepo>(),
    ),
  );
  sl.registerLazySingleton<FilterLocationPoints>(
    () => const FilterLocationPoints(),
  );
  sl.registerLazySingleton<AccumulateDistance>(
    () => const AccumulateDistance(),
  );
  sl.registerLazySingleton<CalculatePace>(
    () => const CalculatePace(),
  );
  sl.registerFactory<RecoverActiveSession>(
    () => RecoverActiveSession(
      sessionRepo: sl<ISessionRepo>(),
      pointsRepo: sl<IPointsRepo>(),
    ),
  );
  sl.registerFactory<DiscardSession>(
    () => DiscardSession(
      sessionRepo: sl<ISessionRepo>(),
      pointsRepo: sl<IPointsRepo>(),
    ),
  );
  sl.registerFactory<FinishSession>(
    () => FinishSession(
      sessionRepo: sl<ISessionRepo>(),
      pointsRepo: sl<IPointsRepo>(),
      syncRepo: sl<ISyncRepo>(),
    ),
  );
  sl.registerLazySingleton<AutoPauseDetector>(
    () => const AutoPauseDetector(),
  );
  sl.registerFactory<LoadGhostFromSession>(
    () => LoadGhostFromSession(
      sessionRepo: sl<ISessionRepo>(),
      pointsRepo: sl<IPointsRepo>(),
    ),
  );
  sl.registerLazySingleton<GhostPositionAt>(
    () => const GhostPositionAt(),
  );
  sl.registerLazySingleton<CalculateGhostDelta>(
    () => const CalculateGhostDelta(),
  );
  sl.registerLazySingleton<IntegrityDetectSpeed>(
    () => const IntegrityDetectSpeed(),
  );
  sl.registerLazySingleton<IntegrityDetectTeleport>(
    () => const IntegrityDetectTeleport(),
  );
  sl.registerFactory<SensorSourceResolver>(
    () => SensorSourceResolver(
      bleHr: sl<IHeartRateSource>(),
      healthProvider: sl<IHealthProvider>(),
    ),
  );
  sl.registerLazySingleton<IStepsSource>(
    () => HealthStepsSource(
      provider: sl<IHealthProvider>(),
      sessionRepo: sl<ISessionRepo>(),
    ),
  );

  // --- Health Export ---
  sl.registerLazySingleton<IHealthExportService>(
    () => HealthExportServiceImpl(
      healthProvider: sl<IHealthProvider>(),
      pointsRepo: sl<IPointsRepo>(),
    ),
  );
  sl.registerFactory<HealthExportController>(
    () => HealthExportController(
      service: sl<IHealthExportService>(),
    ),
  );

  // --- Strava ---
  // Client ID and Secret are injected via --dart-define at build time.
  // See docs/API_KEYS_AND_SCOPES.md for details.
  const stravaClientId = String.fromEnvironment('STRAVA_CLIENT_ID');
  const stravaClientSecret = String.fromEnvironment('STRAVA_CLIENT_SECRET');

  sl.registerLazySingleton<StravaSecureStore>(
    () => const StravaSecureStore(),
  );
  sl.registerLazySingleton<StravaHttpClient>(
    StravaHttpClient.new,
  );
  sl.registerLazySingleton<IStravaAuthRepository>(
    () => StravaAuthRepositoryImpl(
      store: sl<StravaSecureStore>(),
      httpClient: sl<StravaHttpClient>(),
      clientId: stravaClientId,
      clientSecret: stravaClientSecret,
    ),
  );
  sl.registerLazySingleton<IStravaUploadRepository>(
    () => StravaUploadRepositoryImpl(
      httpClient: sl<StravaHttpClient>(),
      authRepo: sl<IStravaAuthRepository>(),
    ),
  );
  sl.registerFactory<StravaConnectController>(
    () => StravaConnectController(
      authRepo: sl<IStravaAuthRepository>(),
      uploadRepo: sl<IStravaUploadRepository>(),
      store: sl<StravaSecureStore>(),
      httpClient: sl<StravaHttpClient>(),
    ),
  );

  // --- File Export ---
  sl.registerLazySingleton<IExportService>(
    () => const ExportServiceImpl(),
  );
  sl.registerFactory<ExportSheetController>(
    () => ExportSheetController(
      exportService: sl<IExportService>(),
      pointsRepo: sl<IPointsRepo>(),
    ),
  );

  // --- Watch Bridge ---
  sl.registerLazySingleton<WatchBridge>(WatchBridge.new);
  sl.registerLazySingleton<ProcessWatchSession>(
    () => ProcessWatchSession(
      sessionRepo: sl<ISessionRepo>(),
      pointsRepo: sl<IPointsRepo>(),
      watchBridge: sl<WatchBridge>(),
    ),
  );

  // --- Gamification Use Cases ---
  sl.registerFactory<CreateChallenge>(
    () => CreateChallenge(challengeRepo: sl<IChallengeRepo>()),
  );
  sl.registerFactory<JoinChallenge>(
    () => JoinChallenge(challengeRepo: sl<IChallengeRepo>()),
  );
  sl.registerFactory<CancelChallenge>(
    () => CancelChallenge(challengeRepo: sl<IChallengeRepo>()),
  );
  sl.registerFactory<StartChallenge>(
    () => StartChallenge(challengeRepo: sl<IChallengeRepo>()),
  );
  sl.registerFactory<EvaluateChallenge>(
    () => EvaluateChallenge(challengeRepo: sl<IChallengeRepo>()),
  );
  sl.registerFactory<SettleChallenge>(
    () => SettleChallenge(
      challengeRepo: sl<IChallengeRepo>(),
      ledgerRepo: sl<ILedgerRepo>(),
      walletRepo: sl<IWalletRepo>(),
    ),
  );
  sl.registerFactory<SubmitRunToChallenge>(
    () => SubmitRunToChallenge(challengeRepo: sl<IChallengeRepo>()),
  );
  sl.registerFactory<PostSessionChallengeDispatcher>(
    () => PostSessionChallengeDispatcher(
      challengeRepo: sl<IChallengeRepo>(),
      submitRun: sl<SubmitRunToChallenge>(),
    ),
  );
  sl.registerFactory<RewardSessionCoins>(
    () => RewardSessionCoins(
      ledgerRepo: sl<ILedgerRepo>(),
      walletRepo: sl<IWalletRepo>(),
    ),
  );

  // --- Progression Use Cases ---
  sl.registerFactory<AwardXpForWorkout>(
    () => AwardXpForWorkout(
      xpRepo: sl<IXpTransactionRepo>(),
      profileRepo: sl<IProfileProgressRepo>(),
    ),
  );
  sl.registerFactory<EvaluateBadges>(
    () => EvaluateBadges(awardRepo: sl<IBadgeAwardRepo>()),
  );
  sl.registerFactory<UpdateMissionProgress>(
    () => UpdateMissionProgress(progressRepo: sl<IMissionProgressRepo>()),
  );
  sl.registerFactory<ClaimRewards>(
    () => ClaimRewards(
      xpRepo: sl<IXpTransactionRepo>(),
      profileRepo: sl<IProfileProgressRepo>(),
      ledgerRepo: sl<ILedgerRepo>(),
      walletRepo: sl<IWalletRepo>(),
    ),
  );
  sl.registerFactory<CreateDailyMissions>(
    () => CreateDailyMissions(progressRepo: sl<IMissionProgressRepo>()),
  );
  sl.registerFactory<PostSessionProgression>(
    () => PostSessionProgression(
      awardXp: sl<AwardXpForWorkout>(),
      evaluateBadges: sl<EvaluateBadges>(),
      updateMissions: sl<UpdateMissionProgress>(),
      claimRewards: sl<ClaimRewards>(),
      profileRepo: sl<IProfileProgressRepo>(),
      activeMissionDefs: () => const [],
    ),
  );

  // --- BLoCs ---
  sl.registerFactory<ChallengesBloc>(
    () => ChallengesBloc(
      challengeRepo: sl<IChallengeRepo>(),
      createChallenge: sl<CreateChallenge>(),
      joinChallenge: sl<JoinChallenge>(),
      cancelChallenge: sl<CancelChallenge>(),
      startChallenge: sl<StartChallenge>(),
      evaluateChallenge: sl<EvaluateChallenge>(),
      settleChallenge: sl<SettleChallenge>(),
    ),
  );
  sl.registerFactory<WalletBloc>(
    () => WalletBloc(
      walletRepo: sl<IWalletRepo>(),
      ledgerRepo: sl<ILedgerRepo>(),
    ),
  );
  sl.registerFactory<ProgressionBloc>(
    () => ProgressionBloc(
      profileRepo: sl<IProfileProgressRepo>(),
      xpRepo: sl<IXpTransactionRepo>(),
    ),
  );
  sl.registerFactory<BadgesBloc>(
    () => BadgesBloc(
      awardRepo: sl<IBadgeAwardRepo>(),
      catalog: const [],
    ),
  );
  sl.registerFactory<MissionsBloc>(
    () => MissionsBloc(
      progressRepo: sl<IMissionProgressRepo>(),
      activeMissionDefs: () => const [],
    ),
  );

  // --- Coaching Use Cases ---
  sl.registerFactory<CreateCoachingGroup>(
    () => CreateCoachingGroup(
      groupRepo: sl<ICoachingGroupRepo>(),
      memberRepo: sl<ICoachingMemberRepo>(),
    ),
  );
  sl.registerFactory<InviteUserToGroup>(
    () => InviteUserToGroup(
      groupRepo: sl<ICoachingGroupRepo>(),
      memberRepo: sl<ICoachingMemberRepo>(),
      inviteRepo: sl<ICoachingInviteRepo>(),
    ),
  );
  sl.registerFactory<AcceptCoachingInvite>(
    () => AcceptCoachingInvite(
      inviteRepo: sl<ICoachingInviteRepo>(),
      memberRepo: sl<ICoachingMemberRepo>(),
    ),
  );
  sl.registerFactory<RemoveCoachingMember>(
    () => RemoveCoachingMember(
      memberRepo: sl<ICoachingMemberRepo>(),
    ),
  );
  sl.registerFactory<GetCoachingMembers>(
    () => GetCoachingMembers(
      groupRepo: sl<ICoachingGroupRepo>(),
      memberRepo: sl<ICoachingMemberRepo>(),
    ),
  );
  sl.registerFactory<GetCoachingGroupDetails>(
    () => GetCoachingGroupDetails(
      groupRepo: sl<ICoachingGroupRepo>(),
      memberRepo: sl<ICoachingMemberRepo>(),
    ),
  );
  sl.registerFactory<SwitchAssessoria>(
    () => SwitchAssessoria(repo: sl<ISwitchAssessoriaRepo>()),
  );

  // ── Coaching BLoCs ──
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
  sl.registerFactory<MyAssessoriaBloc>(
    () => MyAssessoriaBloc(
      groupRepo: sl<ICoachingGroupRepo>(),
      memberRepo: sl<ICoachingMemberRepo>(),
      switchAssessoria: sl<SwitchAssessoria>(),
    ),
  );
  sl.registerFactory<StaffQrBloc>(
    () => StaffQrBloc(repo: sl<ITokenIntentRepo>()),
  );

  // ── Coach Insights BLoC ──
  sl.registerFactory<CoachInsightsBloc>(
    () => CoachInsightsBloc(repo: sl<ICoachInsightRepo>()),
  );

  // ── Race Event BLoCs ──
  // TODO(sprint-16.5+): uncomment when Isar impls for IRaceEventRepo,
  // IRaceParticipationRepo and IRaceResultRepo are registered.
  // sl.registerFactory<RaceEventsBloc>(
  //   () => RaceEventsBloc(
  //     eventRepo: sl<IRaceEventRepo>(),
  //     participationRepo: sl<IRaceParticipationRepo>(),
  //   ),
  // );
  // sl.registerFactory<RaceEventDetailsBloc>(
  //   () => RaceEventDetailsBloc(
  //     eventRepo: sl<IRaceEventRepo>(),
  //     participationRepo: sl<IRaceParticipationRepo>(),
  //     resultRepo: sl<IRaceResultRepo>(),
  //   ),
  // );

  // ── Evolution BLoCs ──
  sl.registerFactory<AthleteEvolutionBloc>(
    () => AthleteEvolutionBloc(
      trendRepo: sl<IAthleteTrendRepo>(),
      baselineRepo: sl<IAthleteBaselineRepo>(),
    ),
  );
  sl.registerFactory<GroupEvolutionBloc>(
    () => GroupEvolutionBloc(
      trendRepo: sl<IAthleteTrendRepo>(),
    ),
  );

  // ── Social BLoCs ──
  // TODO(phase-15): uncomment when Isar impls for IFriendshipRepo,
  // IGroupRepo and IEventRepo are registered.
  // sl.registerFactory<FriendsBloc>(
  //   () => FriendsBloc(friendshipRepo: sl<IFriendshipRepo>()),
  // );
  // sl.registerFactory<GroupsBloc>(
  //   () => GroupsBloc(groupRepo: sl<IGroupRepo>()),
  // );
  // sl.registerFactory<EventsBloc>(
  //   () => EventsBloc(eventRepo: sl<IEventRepo>()),
  // );
  sl.registerFactory<LeaderboardsBloc>(
    () => LeaderboardsBloc(),
  );

  sl.registerFactory<TrackingBloc>(
    () => TrackingBloc(
      ensureLocationReady: sl<EnsureLocationReady>(),
      locationStream: sl<ILocationStream>(),
      filterPoints: sl<FilterLocationPoints>(),
      accumulateDistance: sl<AccumulateDistance>(),
      calculatePace: sl<CalculatePace>(),
      autoPause: sl<AutoPauseDetector>(),
      finishSession: sl<FinishSession>(),
      ghostPositionAt: sl<GhostPositionAt>(),
      calculateGhostDelta: sl<CalculateGhostDelta>(),
      detectSpeed: sl<IntegrityDetectSpeed>(),
      detectTeleport: sl<IntegrityDetectTeleport>(),
      audioCoach: sl<IAudioCoach>(),
      pointsRepo: sl<IPointsRepo>(),
      sessionRepo: sl<ISessionRepo>(),
      syncRepo: sl<ISyncRepo>(),
      coachSettings: sl<ICoachSettingsRepo>(),
      hrSource: sl<IHeartRateSource>(),
      exportWorkout: sl<ExportWorkoutToHealth>(),
      stepsSource: sl<IStepsSource>(),
      progression: sl<PostSessionProgression>(),
      challengeDispatcher: sl<PostSessionChallengeDispatcher>(),
      rewardCoins: sl<RewardSessionCoins>(),
    ),
  );
}
