import 'package:get_it/get_it.dart';
import 'package:isar/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/analytics/product_event_tracker.dart';
import 'package:omni_runner/core/cache/cache_metadata_store.dart';
import 'package:omni_runner/core/cache/membership_cache.dart';
import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/core/offline/connectivity_monitor.dart';
import 'package:omni_runner/core/offline/offline_queue.dart';
import 'package:omni_runner/core/secure_storage/isar_secure_store.dart';
import 'package:omni_runner/data/datasources/audio_coach_service.dart';
import 'package:omni_runner/data/datasources/ble_permission_service.dart';
import 'package:omni_runner/data/datasources/geolocator_location_stream.dart';
import 'package:omni_runner/data/datasources/health_platform_service.dart';
import 'package:omni_runner/data/datasources/isar_database_provider.dart';
import 'package:omni_runner/data/datasources/location_permission_service.dart';
import 'package:omni_runner/data/datasources/sync_service.dart';
import 'package:omni_runner/data/datasources/analytics_sync_service.dart';
import 'package:omni_runner/data/services/profile_data_service.dart';
import 'package:omni_runner/features/wearables_ble/ble_heart_rate_source.dart';
import 'package:omni_runner/features/wearables_ble/i_heart_rate_source.dart';
import 'package:omni_runner/data/repositories_impl/audio_coach_repo.dart';
import 'package:omni_runner/data/repositories_impl/ble_permission_repo.dart';
import 'package:omni_runner/data/repositories_impl/coach_settings_repo.dart';
import 'package:omni_runner/data/repositories_impl/isar_badge_award_repo.dart';
import 'package:omni_runner/data/repositories_impl/isar_challenge_repo.dart';
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
import 'package:omni_runner/data/datasources/activity_recognition_service.dart';
import 'package:omni_runner/data/datasources/health_steps_source.dart';
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
import 'package:omni_runner/domain/repositories/i_training_attendance_repo.dart';
import 'package:omni_runner/domain/repositories/i_training_session_repo.dart';
import 'package:omni_runner/domain/repositories/i_coaching_ranking_repo.dart';
import 'package:omni_runner/domain/repositories/i_friendship_repo.dart';
import 'package:omni_runner/domain/repositories/i_leaderboard_repo.dart';
import 'package:omni_runner/domain/repositories/i_health_provider.dart';
import 'package:omni_runner/domain/usecases/integrity_detect_vehicle.dart';
import 'package:omni_runner/domain/repositories/i_verification_remote_source.dart';
import 'package:omni_runner/domain/repositories/i_workout_repo.dart';
import 'package:omni_runner/domain/repositories/i_financial_repo.dart';
import 'package:omni_runner/domain/repositories/i_wearable_repo.dart';
import 'package:omni_runner/data/repositories_impl/supabase_leaderboard_repo.dart';
import 'package:omni_runner/data/repositories_impl/supabase_feed_remote_source.dart';
import 'package:omni_runner/domain/repositories/i_feed_remote_source.dart';
import 'package:omni_runner/data/repositories_impl/supabase_friendship_repo.dart';
import 'package:omni_runner/domain/repositories/i_wallet_repo.dart';
import 'package:omni_runner/domain/repositories/i_ledger_repo.dart';
import 'package:omni_runner/domain/repositories/i_atomic_ledger_ops.dart';
import 'package:omni_runner/data/repositories_impl/isar_atomic_ledger_ops.dart';
import 'package:omni_runner/data/repositories_impl/isar_coaching_group_repo.dart';
import 'package:omni_runner/data/repositories_impl/isar_coaching_invite_repo.dart';
import 'package:omni_runner/data/repositories_impl/isar_coaching_member_repo.dart';
import 'package:omni_runner/data/repositories_impl/isar_athlete_baseline_repo.dart';
import 'package:omni_runner/data/repositories_impl/isar_coach_insight_repo.dart';
import 'package:omni_runner/data/repositories_impl/isar_athlete_trend_repo.dart';
import 'package:omni_runner/data/repositories_impl/isar_coaching_ranking_repo.dart';
import 'package:omni_runner/data/repositories_impl/supabase_training_attendance_repo.dart';
import 'package:omni_runner/data/repositories_impl/supabase_training_session_repo.dart';
import 'package:omni_runner/data/repositories_impl/supabase_crm_repo.dart';
import 'package:omni_runner/domain/repositories/i_crm_repo.dart';
import 'package:omni_runner/data/repositories_impl/supabase_announcement_repo.dart';
import 'package:omni_runner/data/repositories_impl/supabase_verification_remote_source.dart';
import 'package:omni_runner/data/repositories_impl/supabase_workout_repo.dart';
import 'package:omni_runner/data/repositories_impl/supabase_financial_repo.dart';
import 'package:omni_runner/data/repositories_impl/supabase_wearable_repo.dart';
import 'package:omni_runner/domain/repositories/i_announcement_repo.dart';
import 'package:omni_runner/domain/repositories/i_switch_assessoria_repo.dart';
import 'package:omni_runner/data/repositories_impl/stub_switch_assessoria_repo.dart';
import 'package:omni_runner/data/repositories_impl/remote_switch_assessoria_repo.dart';
import 'package:omni_runner/domain/repositories/i_token_intent_repo.dart';
import 'package:omni_runner/data/repositories_impl/stub_token_intent_repo.dart';
import 'package:omni_runner/data/repositories_impl/remote_token_intent_repo.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/push/notification_rules_service.dart';
import 'package:omni_runner/core/push/push_notification_service.dart';
import 'package:omni_runner/domain/usecases/accumulate_distance.dart';
import 'package:omni_runner/domain/usecases/auto_pause_detector.dart';
import 'package:omni_runner/domain/usecases/calculate_ghost_delta.dart';
import 'package:omni_runner/domain/usecases/calculate_pace.dart';
import 'package:omni_runner/domain/usecases/ensure_ble_ready.dart';
import 'package:omni_runner/domain/usecases/ensure_health_ready.dart';
import 'package:omni_runner/domain/usecases/ensure_location_ready.dart';
import 'package:omni_runner/domain/usecases/export_workout_to_health.dart';
import 'package:omni_runner/domain/usecases/filter_location_points.dart';
import 'package:omni_runner/domain/usecases/finish_session.dart';
import 'package:omni_runner/domain/usecases/ghost_position_at.dart';
import 'package:omni_runner/domain/usecases/integrity_detect_speed.dart';
import 'package:omni_runner/domain/usecases/integrity_detect_teleport.dart';
import 'package:omni_runner/domain/usecases/load_ghost_from_session.dart';
import 'package:omni_runner/domain/usecases/recover_active_session.dart';
import 'package:omni_runner/domain/usecases/discard_session.dart';
import 'package:omni_runner/domain/usecases/sensor_source_resolver.dart';
import 'package:omni_runner/features/watch_bridge/process_watch_session.dart';
import 'package:omni_runner/features/watch_bridge/watch_bridge.dart';
import 'package:omni_runner/features/health_export/data/health_export_service_impl.dart';
import 'package:omni_runner/features/health_export/domain/i_health_export_service.dart';
import 'package:omni_runner/features/health_export/presentation/health_export_controller.dart';
import 'package:omni_runner/features/integrations_export/domain/i_export_service.dart';
import 'package:omni_runner/features/integrations_export/data/export_service_impl.dart';
import 'package:omni_runner/features/integrations_export/presentation/export_sheet_controller.dart';
import 'package:omni_runner/features/strava/data/strava_auth_repository_impl.dart';
import 'package:omni_runner/features/strava/data/strava_http_client.dart';
import 'package:omni_runner/features/strava/data/strava_secure_store.dart';
import 'package:omni_runner/features/strava/data/strava_upload_repository_impl.dart';
import 'package:omni_runner/features/strava/domain/i_strava_auth_repository.dart';
import 'package:omni_runner/features/strava/domain/i_strava_upload_repository.dart';
import 'package:omni_runner/features/strava/presentation/strava_connect_controller.dart';
import 'package:omni_runner/domain/usecases/gamification/cancel_challenge.dart';
import 'package:omni_runner/domain/usecases/gamification/create_challenge.dart';
import 'package:omni_runner/domain/usecases/gamification/join_challenge.dart';
import 'package:omni_runner/domain/usecases/gamification/start_challenge.dart';
import 'package:omni_runner/domain/usecases/gamification/evaluate_challenge.dart';
import 'package:omni_runner/domain/usecases/gamification/ledger_service.dart';
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
import 'package:omni_runner/domain/usecases/training/cancel_training_session.dart';
import 'package:omni_runner/domain/usecases/training/create_training_session.dart';
import 'package:omni_runner/domain/usecases/training/issue_checkin_token.dart';
import 'package:omni_runner/domain/usecases/training/list_attendance.dart';
import 'package:omni_runner/domain/usecases/training/list_training_sessions.dart';
import 'package:omni_runner/domain/usecases/training/mark_attendance.dart';
import 'package:omni_runner/domain/usecases/social/send_friend_invite.dart';
import 'package:omni_runner/domain/usecases/social/accept_friend.dart';
import 'package:omni_runner/domain/usecases/crm/manage_tags.dart';
import 'package:omni_runner/domain/usecases/crm/manage_notes.dart';
import 'package:omni_runner/domain/usecases/crm/manage_member_status.dart';
import 'package:omni_runner/domain/usecases/crm/list_crm_athletes.dart';
import 'package:omni_runner/domain/usecases/announcements/list_announcements.dart';
import 'package:omni_runner/domain/usecases/announcements/create_announcement.dart';
import 'package:omni_runner/domain/usecases/announcements/mark_announcement_read.dart';
import 'package:omni_runner/domain/usecases/wearable/link_device.dart';
import 'package:omni_runner/domain/usecases/wearable/import_execution.dart';
import 'package:omni_runner/domain/usecases/wearable/list_executions.dart';

/// Registers data sources, repositories, and use cases.
Future<void> registerDataModule(GetIt sl) async {
  final prefs = sl<SharedPreferences>();

  sl.registerSingleton<CacheMetadataStore>(CacheMetadataStore(prefs));
  sl.registerLazySingleton<MembershipCache>(MembershipCache.new);

  if (AppConfig.isSupabaseReady) {
    sl.registerLazySingleton<OfflineQueue>(
      () => OfflineQueue(
        prefs: prefs,
        client: Supabase.instance.client,
      ),
    );
    sl.registerLazySingleton<ConnectivityMonitor>(
      () => ConnectivityMonitor(queue: sl<OfflineQueue>()),
    );
  }

  sl.registerLazySingleton<IsarSecureStore>(IsarSecureStore.new);
  sl.registerLazySingleton<IsarDatabaseProvider>(
    () => IsarDatabaseProvider(sl<IsarSecureStore>()),
  );
  final isarProvider = sl<IsarDatabaseProvider>();
  await isarProvider.open();
  sl.registerLazySingleton<Isar>(() => isarProvider.instance);

  sl.registerLazySingleton<LocationPermissionService>(
    LocationPermissionService.new,
  );
  sl.registerLazySingleton<GeolocatorLocationStream>(
    GeolocatorLocationStream.new,
  );
  sl.registerLazySingleton<AudioCoachService>(AudioCoachService.new);
  sl.registerLazySingleton<SyncService>(SyncService.new);
  sl.registerLazySingleton<AnalyticsSyncService>(AnalyticsSyncService.new);
  sl.registerLazySingleton<ProductEventTracker>(ProductEventTracker.new);
  sl.registerLazySingleton<PushNotificationService>(
    PushNotificationService.new,
  );
  sl.registerLazySingleton<NotificationRulesService>(
    NotificationRulesService.new,
  );
  sl.registerLazySingleton<BlePermissionService>(BlePermissionService.new);
  sl.registerLazySingleton<IHeartRateSource>(BleHeartRateSource.new);
  sl.registerLazySingleton<IHealthProvider>(HealthPlatformService.new);

  sl.registerLazySingleton<ILocationPermission>(
    () => LocationPermissionRepo(service: sl<LocationPermissionService>()),
  );
  sl.registerLazySingleton<ILocationStream>(
    () => LocationStreamRepo(datasource: sl<GeolocatorLocationStream>()),
  );
  sl.registerLazySingleton<IPointsRepo>(() => IsarPointsRepo(sl<Isar>()));
  sl.registerLazySingleton<ISessionRepo>(() => IsarSessionRepo(sl<Isar>()));
  sl.registerLazySingleton<IAudioCoach>(
    () => AudioCoachRepo(service: sl<AudioCoachService>()),
  );
  sl.registerLazySingleton<ICoachSettingsRepo>(CoachSettingsRepo.new);
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

  sl.registerLazySingleton<IChallengeRepo>(
    () => IsarChallengeRepo(sl<Isar>()),
  );
  sl.registerLazySingleton<IWalletRepo>(
    () => IsarWalletRepo(sl<Isar>(), sl<CacheMetadataStore>()),
  );
  sl.registerLazySingleton<ILedgerRepo>(() => IsarLedgerRepo(sl<Isar>()));
  sl.registerLazySingleton<IAtomicLedgerOps>(
    () => IsarAtomicLedgerOps(sl<Isar>()),
  );

  sl.registerLazySingleton<IProfileProgressRepo>(
    () => IsarProfileProgressRepo(sl<Isar>(), sl<CacheMetadataStore>()),
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

  sl.registerLazySingleton<ISwitchAssessoriaRepo>(
    () => AppConfig.isSupabaseReady
        ? const RemoteSwitchAssessoriaRepo()
        : () {
            AppLogger.critical(
              'SWITCH_ASSESSORIA: Supabase not ready — using StubSwitchAssessoriaRepo. '
              'This should NEVER happen in production.',
            );
            return const StubSwitchAssessoriaRepo();
          }(),
  );

  sl.registerLazySingleton<ITokenIntentRepo>(
    () => AppConfig.isSupabaseReady
        ? const RemoteTokenIntentRepo()
        : () {
            AppLogger.critical(
              'TOKEN_INTENT: Supabase not ready — using StubTokenIntentRepo. '
              'This should NEVER happen in production.',
            );
            return const StubTokenIntentRepo();
          }(),
  );

  sl.registerLazySingleton<IAthleteBaselineRepo>(
    () => IsarAthleteBaselineRepo(sl<Isar>()),
  );
  sl.registerLazySingleton<IAthleteTrendRepo>(
    () => IsarAthleteTrendRepo(sl<Isar>()),
  );
  sl.registerLazySingleton<ICoachInsightRepo>(
    () => IsarCoachInsightRepo(sl<Isar>()),
  );

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
  sl.registerLazySingleton<AccumulateDistance>(() => const AccumulateDistance());
  sl.registerLazySingleton<CalculatePace>(() => const CalculatePace());
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
  sl.registerLazySingleton<AutoPauseDetector>(() => const AutoPauseDetector());
  sl.registerFactory<LoadGhostFromSession>(
    () => LoadGhostFromSession(
      sessionRepo: sl<ISessionRepo>(),
      pointsRepo: sl<IPointsRepo>(),
    ),
  );
  sl.registerLazySingleton<GhostPositionAt>(() => const GhostPositionAt());
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

  sl.registerLazySingleton<IHealthExportService>(
    () => HealthExportServiceImpl(
      healthProvider: sl<IHealthProvider>(),
      pointsRepo: sl<IPointsRepo>(),
    ),
  );
  sl.registerFactory<HealthExportController>(
    () => HealthExportController(service: sl<IHealthExportService>()),
  );

  const stravaClientId = String.fromEnvironment('STRAVA_CLIENT_ID');
  const stravaClientSecret = String.fromEnvironment('STRAVA_CLIENT_SECRET');

  sl.registerLazySingleton<StravaSecureStore>(() => const StravaSecureStore());
  sl.registerLazySingleton<StravaHttpClient>(StravaHttpClient.new);
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

  sl.registerLazySingleton<IExportService>(() => const ExportServiceImpl());
  sl.registerFactory<ExportSheetController>(
    () => ExportSheetController(
      exportService: sl<IExportService>(),
      pointsRepo: sl<IPointsRepo>(),
    ),
  );

  sl.registerLazySingleton<WatchBridge>(WatchBridge.new);
  sl.registerLazySingleton<ProcessWatchSession>(
    () => ProcessWatchSession(
      sessionRepo: sl<ISessionRepo>(),
      pointsRepo: sl<IPointsRepo>(),
      watchBridge: sl<WatchBridge>(),
    ),
  );

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
  sl.registerFactory<LedgerService>(
    () => LedgerService(
      ledgerRepo: sl<ILedgerRepo>(),
      walletRepo: sl<IWalletRepo>(),
      atomicOps: sl<IAtomicLedgerOps>(),
    ),
  );
  sl.registerFactory<SettleChallenge>(
    () => SettleChallenge(
      challengeRepo: sl<IChallengeRepo>(),
      ledgerService: sl<LedgerService>(),
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
    () => RemoveCoachingMember(memberRepo: sl<ICoachingMemberRepo>()),
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

  sl.registerLazySingleton<ITrainingSessionRepo>(
    () => SupabaseTrainingSessionRepo(Supabase.instance.client),
  );
  sl.registerLazySingleton<ITrainingAttendanceRepo>(
    () => SupabaseTrainingAttendanceRepo(Supabase.instance.client),
  );
  sl.registerFactory<ListTrainingSessions>(
    () => ListTrainingSessions(repo: sl<ITrainingSessionRepo>()),
  );
  sl.registerFactory<CreateTrainingSession>(
    () => CreateTrainingSession(repo: sl<ITrainingSessionRepo>()),
  );
  sl.registerFactory<ListAttendance>(
    () => ListAttendance(repo: sl<ITrainingAttendanceRepo>()),
  );
  sl.registerFactory<CancelTrainingSession>(
    () => CancelTrainingSession(repo: sl<ITrainingSessionRepo>()),
  );
  sl.registerFactory<IssueCheckinToken>(
    () => IssueCheckinToken(repo: sl<ITrainingAttendanceRepo>()),
  );
  sl.registerFactory<MarkAttendance>(
    () => MarkAttendance(repo: sl<ITrainingAttendanceRepo>()),
  );

  sl.registerLazySingleton<ICrmRepo>(
    () => SupabaseCrmRepo(Supabase.instance.client),
  );
  sl.registerFactory<ManageTags>(() => ManageTags(repo: sl<ICrmRepo>()));
  sl.registerFactory<ManageNotes>(() => ManageNotes(repo: sl<ICrmRepo>()));
  sl.registerFactory<ManageMemberStatus>(
    () => ManageMemberStatus(repo: sl<ICrmRepo>()),
  );
  sl.registerFactory<ListCrmAthletes>(
    () => ListCrmAthletes(repo: sl<ICrmRepo>()),
  );

  sl.registerLazySingleton<IAnnouncementRepo>(
    () => SupabaseAnnouncementRepo(Supabase.instance.client),
  );
  sl.registerFactory<ListAnnouncements>(
    () => ListAnnouncements(repo: sl<IAnnouncementRepo>()),
  );
  sl.registerFactory<CreateAnnouncement>(
    () => CreateAnnouncement(repo: sl<IAnnouncementRepo>()),
  );
  sl.registerFactory<MarkAnnouncementRead>(
    () => MarkAnnouncementRead(repo: sl<IAnnouncementRepo>()),
  );

  sl.registerLazySingleton<IFriendshipRepo>(() => SupabaseFriendshipRepo());
  sl.registerFactory<SendFriendInvite>(
    () => SendFriendInvite(friendshipRepo: sl<IFriendshipRepo>()),
  );
  sl.registerFactory<AcceptFriend>(
    () => AcceptFriend(friendshipRepo: sl<IFriendshipRepo>()),
  );

  sl.registerLazySingleton<ILeaderboardRepo>(
    SupabaseLeaderboardRepo.new,
  );

  sl.registerLazySingleton<IFeedRemoteSource>(
    SupabaseFeedRemoteSource.new,
  );

  sl.registerLazySingleton<IVerificationRemoteSource>(
    () => SupabaseVerificationRemoteSource(
      stravaFactory: () => sl<StravaConnectController>(),
    ),
  );

  sl.registerLazySingleton<ProfileDataService>(
    () => ProfileDataService(Supabase.instance.client),
  );

  sl.registerLazySingleton<IWorkoutRepo>(
    () => SupabaseWorkoutRepo(Supabase.instance.client),
  );

  sl.registerLazySingleton<IFinancialRepo>(
    () => SupabaseFinancialRepo(Supabase.instance.client),
  );

  sl.registerLazySingleton<IWearableRepo>(
    () => SupabaseWearableRepo(
      Supabase.instance.client,
      offlineQueue: AppConfig.isSupabaseReady ? sl<OfflineQueue>() : null,
    ),
  );
  sl.registerFactory<LinkDevice>(
    () => LinkDevice(repo: sl<IWearableRepo>()),
  );
  sl.registerFactory<ImportExecution>(
    () => ImportExecution(repo: sl<IWearableRepo>()),
  );
  sl.registerFactory<ListExecutions>(
    () => ListExecutions(repo: sl<IWearableRepo>()),
  );
}
