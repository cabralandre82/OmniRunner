import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/core/service_locator.dart';

// ── Presentation screens ────────────────────────────────────────────────────
import 'package:omni_runner/presentation/screens/announcement_create_screen.dart';
import 'package:omni_runner/presentation/screens/announcement_detail_screen.dart';
import 'package:omni_runner/presentation/screens/announcement_feed_screen.dart';
import 'package:omni_runner/presentation/screens/assessoria_feed_screen.dart';
import 'package:omni_runner/presentation/screens/athlete_attendance_screen.dart';
import 'package:omni_runner/presentation/screens/athlete_championship_ranking_screen.dart';
import 'package:omni_runner/presentation/screens/athlete_championships_screen.dart';
import 'package:omni_runner/presentation/screens/athlete_checkin_qr_screen.dart';
import 'package:omni_runner/presentation/screens/athlete_dashboard_screen.dart';
import 'package:omni_runner/presentation/screens/athlete_delivery_screen.dart';
import 'package:omni_runner/presentation/screens/athlete_device_link_screen.dart';
import 'package:omni_runner/presentation/screens/athlete_evolution_screen.dart';
import 'package:omni_runner/presentation/screens/athlete_log_execution_screen.dart';
import 'package:omni_runner/presentation/screens/athlete_my_evolution_screen.dart';
import 'package:omni_runner/presentation/screens/athlete_training_list_screen.dart';
import 'package:omni_runner/presentation/screens/athlete_verification_screen.dart';
import 'package:omni_runner/presentation/screens/athlete_workout_day_screen.dart';
import 'package:omni_runner/presentation/screens/auth_gate.dart';
import 'package:omni_runner/presentation/screens/badges_screen.dart';
import 'package:omni_runner/presentation/screens/challenge_create_screen.dart';
import 'package:omni_runner/presentation/screens/challenge_details_screen.dart';
import 'package:omni_runner/presentation/screens/challenge_invite_screen.dart';
import 'package:omni_runner/presentation/screens/challenge_join_screen.dart';
import 'package:omni_runner/presentation/screens/challenge_result_screen.dart';
import 'package:omni_runner/presentation/screens/challenges_list_screen.dart';
import 'package:omni_runner/presentation/screens/coaching_group_details_screen.dart';
import 'package:omni_runner/presentation/screens/coaching_groups_screen.dart';
import 'package:omni_runner/presentation/screens/diagnostics_screen.dart';
import 'package:omni_runner/presentation/screens/event_details_screen.dart';
import 'package:omni_runner/presentation/screens/faq_screen.dart';
import 'package:omni_runner/presentation/screens/friend_profile_screen.dart';
import 'package:omni_runner/presentation/screens/friends_activity_feed_screen.dart';
import 'package:omni_runner/presentation/screens/friends_screen.dart';
import 'package:omni_runner/presentation/screens/group_details_screen.dart';
import 'package:omni_runner/presentation/screens/group_evolution_screen.dart';
import 'package:omni_runner/presentation/screens/group_members_screen.dart';
import 'package:omni_runner/presentation/screens/group_rankings_screen.dart';
import 'package:omni_runner/presentation/screens/history_screen.dart';
import 'package:omni_runner/presentation/screens/home_screen.dart';
import 'package:omni_runner/presentation/screens/how_it_works_screen.dart';
import 'package:omni_runner/presentation/screens/invite_friends_screen.dart';
import 'package:omni_runner/presentation/screens/invite_qr_screen.dart';
import 'package:omni_runner/presentation/screens/join_assessoria_screen.dart';
import 'package:omni_runner/presentation/screens/league_screen.dart';
import 'package:omni_runner/presentation/screens/leaderboards_screen.dart';
import 'package:omni_runner/presentation/screens/login_screen.dart';
import 'package:omni_runner/presentation/screens/map_screen.dart';
import 'package:omni_runner/presentation/screens/matchmaking_screen.dart';
import 'package:omni_runner/presentation/screens/missions_screen.dart';
import 'package:omni_runner/presentation/screens/more_screen.dart';
import 'package:omni_runner/presentation/screens/my_assessoria_screen.dart';
import 'package:omni_runner/presentation/screens/onboarding_role_screen.dart';
import 'package:omni_runner/presentation/screens/onboarding_tour_screen.dart';
import 'package:omni_runner/presentation/screens/partner_assessorias_screen.dart';
import 'package:omni_runner/presentation/screens/personal_evolution_screen.dart';
import 'package:omni_runner/presentation/screens/profile_screen.dart';
import 'package:omni_runner/presentation/screens/progress_hub_screen.dart';
import 'package:omni_runner/presentation/screens/progression_screen.dart';
import 'package:omni_runner/presentation/screens/recovery_screen.dart';
import 'package:omni_runner/presentation/screens/run_details_screen.dart';
import 'package:omni_runner/presentation/screens/run_replay_screen.dart';
import 'package:omni_runner/presentation/screens/run_summary_screen.dart';
import 'package:omni_runner/presentation/screens/running_dna_screen.dart';
import 'package:omni_runner/presentation/screens/settings_screen.dart';
import 'package:omni_runner/presentation/screens/staff_athlete_profile_screen.dart';
import 'package:omni_runner/presentation/screens/staff_challenge_invites_screen.dart';
import 'package:omni_runner/presentation/screens/staff_championship_invites_screen.dart';
import 'package:omni_runner/presentation/screens/staff_championship_manage_screen.dart';
import 'package:omni_runner/presentation/screens/staff_championship_templates_screen.dart';
import 'package:omni_runner/presentation/screens/staff_credits_screen.dart';
import 'package:omni_runner/presentation/screens/staff_crm_list_screen.dart';
import 'package:omni_runner/presentation/screens/staff_dashboard_screen.dart';
import 'package:omni_runner/presentation/screens/staff_generate_qr_screen.dart';
import 'package:omni_runner/presentation/screens/staff_join_requests_screen.dart';
import 'package:omni_runner/presentation/screens/staff_performance_screen.dart';
import 'package:omni_runner/presentation/screens/staff_qr_hub_screen.dart';
import 'package:omni_runner/presentation/screens/staff_retention_dashboard_screen.dart';
import 'package:omni_runner/presentation/screens/staff_scan_qr_screen.dart';
import 'package:omni_runner/presentation/screens/staff_setup_screen.dart';
import 'package:omni_runner/presentation/screens/staff_training_create_screen.dart';
import 'package:omni_runner/presentation/screens/staff_training_detail_screen.dart';
import 'package:omni_runner/presentation/screens/staff_training_list_screen.dart';
import 'package:omni_runner/presentation/screens/staff_training_scan_screen.dart';
import 'package:omni_runner/presentation/screens/staff_weekly_report_screen.dart';
import 'package:omni_runner/presentation/screens/staff_workout_assign_screen.dart';
import 'package:omni_runner/presentation/screens/staff_workout_builder_screen.dart';
import 'package:omni_runner/presentation/screens/staff_workout_templates_screen.dart';
import 'package:omni_runner/presentation/screens/streaks_leaderboard_screen.dart';
import 'package:omni_runner/presentation/screens/support_screen.dart';
import 'package:omni_runner/presentation/screens/support_ticket_screen.dart';
import 'package:omni_runner/presentation/screens/today_screen.dart';
import 'package:omni_runner/presentation/screens/wallet_screen.dart';
import 'package:omni_runner/presentation/screens/welcome_screen.dart';
import 'package:omni_runner/presentation/screens/athlete_my_exports_screen.dart';
import 'package:omni_runner/presentation/screens/athlete_my_invoices_screen.dart';
import 'package:omni_runner/presentation/screens/workout_delivery_screen.dart';
import 'package:omni_runner/presentation/screens/wrapped_screen.dart';
import 'package:omni_runner/presentation/screens/athlete_training_feed_screen.dart';
import 'package:omni_runner/presentation/screens/athlete_workout_detail_screen.dart';
import 'package:omni_runner/presentation/screens/athlete_workout_feedback_screen.dart';

// ── Feature screens ─────────────────────────────────────────────────────────
import 'package:omni_runner/features/integrations_export/presentation/export_screen.dart';
import 'package:omni_runner/features/integrations_export/presentation/how_to_import_screen.dart';
import 'package:omni_runner/features/parks/presentation/my_parks_screen.dart';
import 'package:omni_runner/features/parks/presentation/park_screen.dart';
import 'package:omni_runner/features/wearables_ble/debug_hrm_screen.dart';

// ── Bloc / Entity imports needed for BlocProvider wrappers & extra data ──────
import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_result_entity.dart';
import 'package:omni_runner/domain/entities/coaching_member_entity.dart';
import 'package:omni_runner/domain/entities/event_entity.dart';
import 'package:omni_runner/domain/entities/event_participation_entity.dart';
import 'package:omni_runner/domain/entities/group_entity.dart';
import 'package:omni_runner/domain/entities/group_member_entity.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/entities/profile_entity.dart';
import 'package:omni_runner/domain/entities/training_session_entity.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/entities/announcement_entity.dart';
import 'package:omni_runner/domain/entities/token_intent_entity.dart';
import 'package:omni_runner/features/parks/domain/park_entity.dart';
import 'package:omni_runner/domain/usecases/recover_active_session.dart';

import 'package:omni_runner/presentation/blocs/badges/badges_bloc.dart';
import 'package:omni_runner/presentation/blocs/training_feed/training_feed_bloc.dart';
import 'package:omni_runner/presentation/blocs/training_feed/training_feed_event.dart';
import 'package:omni_runner/domain/entities/plan_workout_entity.dart';
import 'package:omni_runner/presentation/blocs/badges/badges_event.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_bloc.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_event.dart';
import 'package:omni_runner/presentation/blocs/coaching_groups/coaching_groups_bloc.dart';
import 'package:omni_runner/presentation/blocs/coaching_groups/coaching_groups_event.dart';
import 'package:omni_runner/presentation/blocs/leaderboards/leaderboards_bloc.dart';
import 'package:omni_runner/presentation/blocs/missions/missions_bloc.dart';
import 'package:omni_runner/presentation/blocs/missions/missions_event.dart';
import 'package:omni_runner/presentation/blocs/my_assessoria/my_assessoria_bloc.dart';
import 'package:omni_runner/presentation/blocs/my_assessoria/my_assessoria_event.dart';
import 'package:omni_runner/presentation/blocs/progression/progression_bloc.dart';
import 'package:omni_runner/presentation/blocs/progression/progression_event.dart';
import 'package:omni_runner/presentation/blocs/wallet/wallet_bloc.dart';
import 'package:omni_runner/presentation/blocs/wallet/wallet_event.dart';
import 'package:omni_runner/presentation/blocs/assessoria_feed/assessoria_feed_bloc.dart';
import 'package:omni_runner/presentation/blocs/assessoria_feed/assessoria_feed_event.dart';
import 'package:omni_runner/presentation/blocs/friends/friends_bloc.dart';
import 'package:omni_runner/presentation/blocs/friends/friends_event.dart';
import 'package:omni_runner/presentation/blocs/staff_qr/staff_qr_bloc.dart';
import 'package:omni_runner/domain/repositories/i_token_intent_repo.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Route name constants
// ═══════════════════════════════════════════════════════════════════════════════

abstract final class AppRoutes {
  // ── Auth / Onboarding ───────────────────────────────────────────────────
  static const root = '/';
  static const welcome = '/welcome';
  static const login = '/login';
  static const onboarding = '/onboarding';
  static const onboardingTour = '/onboarding-tour';
  static const staffSetup = '/staff-setup';
  static const recovery = '/recovery';

  // ── Home shell tabs ─────────────────────────────────────────────────────
  static const home = '/home';
  static const dashboard = '/dashboard';
  static const staffDashboard = '/staff/dashboard';
  static const today = '/today';
  static const history = '/history';
  static const more = '/more';

  // ── Challenges ──────────────────────────────────────────────────────────
  static const challenges = '/challenges';
  static const challengeDetails = '/challenges/:id';
  static const challengeCreate = '/challenges/create';
  static const challengeJoin = '/challenges/join/:id';
  static const challengeInvite = '/challenges/invite';
  static const challengeResult = '/challenges/result';

  // ── Championships ───────────────────────────────────────────────────────
  static const championships = '/championships';
  static const championshipRanking = '/championships/:id/ranking';

  // ── Assessoria / Coaching ───────────────────────────────────────────────
  static const myAssessoria = '/assessoria';
  static const joinAssessoria = '/assessoria/join';
  static const assessoriaFeed = '/assessoria/feed';
  static const partnerAssessorias = '/assessoria/partners/:groupId';
  static const coachingGroups = '/coaching';
  static const coachingGroupDetails = '/coaching/:groupId';

  // ── Groups ──────────────────────────────────────────────────────────────
  static const groups = '/groups';
  static const groupDetails = '/groups/details';
  static const groupRankings = '/groups/rankings';
  static const groupMembers = '/groups/members';
  static const groupEvolution = '/groups/evolution';
  static const groupEvents = '/groups/events';

  // ── Friends / Social ────────────────────────────────────────────────────
  static const friends = '/friends';
  static const friendProfile = '/friends/:userId';
  static const friendsActivity = '/friends/activity';
  static const inviteFriends = '/invite-friends';
  static const inviteQr = '/invite-qr';

  // ── Profile & Settings ──────────────────────────────────────────────────
  static const profile = '/profile';
  static const settings = '/settings';
  static const faq = '/faq';
  static const howItWorks = '/how-it-works';
  static const diagnostics = '/diagnostics';

  // ── Wallet ──────────────────────────────────────────────────────────────
  static const wallet = '/wallet';

  // ── Progress / Gamification ─────────────────────────────────────────────
  static const progress = '/progress';
  static const badges = '/badges';
  static const missions = '/missions';
  static const progression = '/progression';
  static const personalEvolution = '/personal-evolution';
  static const runningDna = '/running-dna';
  static const leaderboards = '/leaderboards';
  static const league = '/league';
  static const streaksLeaderboard = '/streaks-leaderboard';
  static const matchmaking = '/matchmaking';
  static const wrapped = '/wrapped';

  // ── Runs / Workouts ─────────────────────────────────────────────────────
  static const runDetails = '/runs/details';
  static const runSummary = '/runs/summary';
  static const runReplay = '/runs/replay';
  static const map = '/map';
  static const workoutDelivery = '/workouts/delivery';
  static const athleteDelivery = '/workouts/athlete-delivery';
  static const myExports = '/workouts/my-exports';

  // ── Financial (atleta) ─────────────────────────────────────────────────
  static const myInvoices = '/financial/my-invoices';

  // ── Events ──────────────────────────────────────────────────────────────
  static const events = '/events';
  static const eventDetails = '/events/details';
  static const raceEventDetails = '/events/race';

  // ── Announcements ─────────────────────────────────────────────────────
  static const announcementFeed = '/announcements/:groupId';
  static const announcementDetail = '/announcements/detail/:id';
  static const announcementCreate = '/announcements/create/:groupId';

  // ── Training Feed (plan-based) ────────────────────────────────────────
  static const athleteTrainingFeed = '/athlete/training-feed';
  static const athletePlanWorkout = '/athlete/plan-workout/:workoutId';
  static const athletePlanWorkoutFeedback =
      '/athlete/plan-workout/:workoutId/feedback';

  static String athletePlanWorkoutPath(String workoutId) =>
      '/athlete/plan-workout/$workoutId';
  static String athletePlanWorkoutFeedbackPath(String workoutId) =>
      '/athlete/plan-workout/$workoutId/feedback';

  // ── Athlete features ──────────────────────────────────────────────────
  static const athleteVerification = '/athlete/verification';
  static const athleteWorkoutDay = '/athlete/workout-day/:groupId';
  static const athleteTrainingList = '/athlete/training/:groupId';
  static const athleteAttendance = '/athlete/attendance';
  static const athleteEvolution = '/athlete/evolution';
  static const athleteMyEvolution = '/athlete/my-evolution';
  static const athleteLogExecution = '/athlete/log-execution';
  static const athleteCheckinQr = '/athlete/checkin-qr';
  static const athleteDeviceLink = '/athlete/device-link';

  // ── Staff features ────────────────────────────────────────────────────
  static const staffQrHub = '/staff/qr-hub';
  static const staffScanQr = '/staff/scan-qr';
  static const staffGenerateQr = '/staff/generate-qr';
  static const staffJoinRequests = '/staff/join-requests/:groupId';
  static const staffChallengeInvites = '/staff/challenge-invites/:groupId';
  static const staffChampionshipInvites = '/staff/championship-invites/:groupId';
  static const staffChampionshipManage = '/staff/championships/:id/manage';
  static const staffChampionshipTemplates = '/staff/championship-templates';
  static const staffCrmList = '/staff/crm/:groupId';
  static const staffAthleteProfile = '/staff/athlete-profile';
  static const staffCredits = '/staff/credits';
  static const staffWeeklyReport = '/staff/weekly-report';
  static const staffRetentionDashboard = '/staff/retention';
  static const staffPerformance = '/staff/performance';
  static const staffTrainingList = '/staff/training/:groupId';
  static const staffTrainingDetail = '/staff/training/detail/:sessionId';
  static const staffTrainingCreate = '/staff/training/create';
  static const staffTrainingScan = '/staff/training/scan/:sessionId';
  static const staffWorkoutTemplates = '/staff/workout-templates/:groupId';
  static const staffWorkoutBuilder = '/staff/workout-builder/:groupId';
  static const staffWorkoutAssign = '/staff/workout-assign/:groupId';

  // ── Support ─────────────────────────────────────────────────────────────
  static const support = '/support/:groupId';
  static const supportTicket = '/support/ticket';

  // ── Parks (feature) ─────────────────────────────────────────────────────
  static const parks = '/parks';
  static const parkDetail = '/parks/detail';

  // ── Export / Import (feature) ─────────────────────────────────────────
  static const exportRun = '/export';
  static const howToImport = '/how-to-import';

  // ── Debug ───────────────────────────────────────────────────────────────
  static const debugHrm = '/debug/hrm';

  // ── Helpers ─────────────────────────────────────────────────────────────

  static String challengeDetailsPath(String id) => '/challenges/$id';
  static String challengeJoinPath(String id) => '/challenges/join/$id';
  static String championshipRankingPath(String id) => '/championships/$id/ranking';
  static String friendProfilePath(String userId) => '/friends/$userId';
  static String partnerAssessoriasPath(String groupId) => '/assessoria/partners/$groupId';
  static String coachingGroupDetailsPath(String groupId) => '/coaching/$groupId';
  static String announcementFeedPath(String groupId) => '/announcements/$groupId';
  static String announcementDetailPath(String id) => '/announcements/detail/$id';
  static String announcementCreatePath(String groupId) => '/announcements/create/$groupId';
  static String athleteWorkoutDayPath(String groupId) => '/athlete/workout-day/$groupId';
  static String athleteTrainingListPath(String groupId) => '/athlete/training/$groupId';
  static String staffJoinRequestsPath(String groupId) => '/staff/join-requests/$groupId';
  static String staffChallengeInvitesPath(String groupId) => '/staff/challenge-invites/$groupId';
  static String staffChampionshipInvitesPath(String groupId) => '/staff/championship-invites/$groupId';
  static String staffChampionshipManagePath(String id) => '/staff/championships/$id/manage';
  static String staffCrmListPath(String groupId) => '/staff/crm/$groupId';
  static String staffTrainingListPath(String groupId) => '/staff/training/$groupId';
  static String staffTrainingDetailPath(String sessionId) => '/staff/training/detail/$sessionId';
  static String staffTrainingScanPath(String sessionId) => '/staff/training/scan/$sessionId';
  static String staffWorkoutTemplatesPath(String groupId) => '/staff/workout-templates/$groupId';
  static String staffWorkoutBuilderPath(String groupId) => '/staff/workout-builder/$groupId';
  static String staffWorkoutAssignPath(String groupId) => '/staff/workout-assign/$groupId';
  static String supportPath(String groupId) => '/support/$groupId';
}

// ═══════════════════════════════════════════════════════════════════════════════
// Extra data wrappers for routes that require complex objects
// ═══════════════════════════════════════════════════════════════════════════════

class ChallengeResultExtra {
  final ChallengeEntity challenge;
  final ChallengeResultEntity result;
  const ChallengeResultExtra({required this.challenge, required this.result});
}

class GroupDetailsExtra {
  final GroupEntity group;
  final List<GroupMemberEntity> members;
  final List<GroupGoalEntity> goals;
  const GroupDetailsExtra({
    required this.group,
    this.members = const [],
    this.goals = const [],
  });
}

class GroupMembersExtra {
  final String groupName;
  final List<CoachingMemberEntity> members;
  final String currentUserId;
  const GroupMembersExtra({
    required this.groupName,
    required this.members,
    required this.currentUserId,
  });
}

class EventDetailsExtra {
  final EventEntity event;
  final EventParticipationEntity? myParticipation;
  final List<EventParticipationEntity> allParticipations;
  const EventDetailsExtra({
    required this.event,
    this.myParticipation,
    this.allParticipations = const [],
  });
}

class RunDetailsExtra {
  final WorkoutSessionEntity session;
  const RunDetailsExtra({required this.session});
}

class RunSummaryExtra {
  final List<LocationPointEntity> points;
  final double totalDistanceM;
  final int elapsedMs;
  final double? avgPaceSecPerKm;
  final double? ghostFinalDeltaM;
  final int? ghostDurationMs;
  final double? ghostDistanceM;
  final bool isVerified;
  final List<String> integrityFlags;
  final int? avgBpm;

  const RunSummaryExtra({
    required this.points,
    required this.totalDistanceM,
    required this.elapsedMs,
    this.avgPaceSecPerKm,
    this.ghostFinalDeltaM,
    this.ghostDurationMs,
    this.ghostDistanceM,
    this.isVerified = false,
    this.integrityFlags = const [],
    this.avgBpm,
  });
}

class RunReplayExtra {
  final List<LocationPointEntity> points;
  final double totalDistanceM;
  final int elapsedMs;
  const RunReplayExtra({
    required this.points,
    required this.totalDistanceM,
    required this.elapsedMs,
  });
}

class StaffTrainingCreateExtra {
  final String groupId;
  final String userId;
  final TrainingSessionEntity? existing;
  const StaffTrainingCreateExtra({
    required this.groupId,
    required this.userId,
    this.existing,
  });
}

class StaffAthleteProfileExtra {
  final String groupId;
  final String athleteUserId;
  final String athleteDisplayName;
  const StaffAthleteProfileExtra({
    required this.groupId,
    required this.athleteUserId,
    required this.athleteDisplayName,
  });
}

class StaffGenerateQrExtra {
  final TokenIntentType type;
  final String groupId;
  final String? championshipId;
  const StaffGenerateQrExtra({
    required this.type,
    required this.groupId,
    this.championshipId,
  });
}

class AthleteAttendanceExtra {
  final String groupId;
  final String athleteUserId;
  const AthleteAttendanceExtra({
    required this.groupId,
    required this.athleteUserId,
  });
}

class AthleteDeviceLinkExtra {
  final String athleteUserId;
  final String groupId;
  const AthleteDeviceLinkExtra({
    required this.athleteUserId,
    required this.groupId,
  });
}

class AthleteMyEvolutionExtra {
  final String groupId;
  final String userId;
  const AthleteMyEvolutionExtra({
    required this.groupId,
    required this.userId,
  });
}

class StaffCreditsExtra {
  final String groupId;
  final String groupName;
  const StaffCreditsExtra({required this.groupId, required this.groupName});
}

class StaffWeeklyReportExtra {
  final String groupId;
  final String groupName;
  const StaffWeeklyReportExtra({required this.groupId, required this.groupName});
}

class StaffRetentionExtra {
  final String groupId;
  final String groupName;
  const StaffRetentionExtra({required this.groupId, required this.groupName});
}

class StaffPerformanceExtra {
  final String groupId;
  final String groupName;
  const StaffPerformanceExtra({required this.groupId, required this.groupName});
}

class StaffChampionshipTemplatesExtra {
  final String groupId;
  final String groupName;
  const StaffChampionshipTemplatesExtra({
    required this.groupId,
    required this.groupName,
  });
}

class ChampionshipRankingExtra {
  final String championshipId;
  final String championshipName;
  final String metric;
  const ChampionshipRankingExtra({
    required this.championshipId,
    required this.championshipName,
    required this.metric,
  });
}

class InviteQrExtra {
  final String inviteCode;
  final String groupName;
  const InviteQrExtra({required this.inviteCode, required this.groupName});
}

class SupportTicketExtra {
  final String ticketId;
  final String subject;
  const SupportTicketExtra({required this.ticketId, required this.subject});
}

class WrappedExtra {
  final String periodType;
  final String periodKey;
  final String periodLabel;
  const WrappedExtra({
    required this.periodType,
    required this.periodKey,
    required this.periodLabel,
  });
}

class StaffChampionshipManageExtra {
  final String championshipId;
  final String hostGroupId;
  const StaffChampionshipManageExtra({
    required this.championshipId,
    required this.hostGroupId,
  });
}

class AthleteCheckinQrExtra {
  final String sessionId;
  final String sessionTitle;
  const AthleteCheckinQrExtra({
    required this.sessionId,
    required this.sessionTitle,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// Router configuration
// ═══════════════════════════════════════════════════════════════════════════════

final GlobalKey<NavigatorState> rootNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'root');

GoRouter createAppRouter({RecoveredSession? recovery}) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: recovery != null ? AppRoutes.recovery : AppRoutes.root,
    debugLogDiagnostics: !AppConfig.isProd,
    redirect: _rootRedirect,
    routes: [
      // ── Auth / Onboarding ───────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.root,
        builder: (context, state) => const AuthGate(),
      ),
      GoRoute(
        path: AppRoutes.welcome,
        builder: (context, state) {
          final callbacks = state.extra as Map<String, VoidCallback>?;
          return WelcomeScreen(
            onStart: callbacks?['onStart'] ?? () => context.go(AppRoutes.login),
            onExplore: callbacks?['onExplore'],
          );
        },
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return LoginScreen(
            onSuccess: (extra?['onSuccess'] as VoidCallback?) ??
                () => context.go(AppRoutes.root),
            hasPendingInvite: (extra?['hasPendingInvite'] as bool?) ?? false,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return OnboardingRoleScreen(
            initialState: (extra?['initialState'] as OnboardingState?) ??
                OnboardingState.newUser,
            onComplete: (extra?['onComplete'] as VoidCallback?) ??
                () => context.go(AppRoutes.root),
            onBack: extra?['onBack'] as VoidCallback?,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.onboardingTour,
        builder: (context, state) {
          final onComplete = state.extra as VoidCallback?;
          return OnboardingTourScreen(
            onComplete: onComplete ?? () => context.go(AppRoutes.home),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.staffSetup,
        builder: (context, state) {
          final extra = state.extra as Map<String, VoidCallback>?;
          return StaffSetupScreen(
            onComplete:
                extra?['onComplete'] ?? () => context.go(AppRoutes.root),
            onBack: extra?['onBack'],
          );
        },
      ),
      GoRoute(
        path: AppRoutes.recovery,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final rec = extra?['recovery'] as RecoveredSession?;
          return RecoveryScreen(
            recovery: rec ?? recovery!,
            onResume: (extra?['onResume'] as VoidCallback?) ??
                () => context.go(AppRoutes.root),
            onDiscard: (extra?['onDiscard'] as VoidCallback?) ??
                () => context.go(AppRoutes.root),
          );
        },
      ),

      // ── Home / Main tabs ────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) {
          final userRole = state.extra as String?;
          return HomeScreen(userRole: userRole);
        },
      ),
      GoRoute(
        path: AppRoutes.dashboard,
        builder: (context, state) => const AthleteDashboardScreen(),
      ),
      GoRoute(
        path: AppRoutes.staffDashboard,
        builder: (context, state) => const StaffDashboardScreen(),
      ),
      GoRoute(
        path: AppRoutes.today,
        builder: (context, state) => const TodayScreen(),
      ),
      GoRoute(
        path: AppRoutes.history,
        builder: (context, state) {
          final pickGhost = state.uri.queryParameters['pickGhost'] == 'true';
          return HistoryScreen(pickGhostMode: pickGhost);
        },
      ),
      GoRoute(
        path: AppRoutes.more,
        builder: (context, state) {
          final userRole = state.extra as String?;
          return MoreScreen(userRole: userRole);
        },
      ),

      // ── Challenges ──────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.challenges,
        builder: (context, state) => BlocProvider<ChallengesBloc>(
          create: (_) => sl<ChallengesBloc>()
            ..add(LoadChallenges(sl<UserIdentityProvider>().userId)),
          child: const ChallengesListScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.challengeCreate,
        builder: (context, state) => BlocProvider<ChallengesBloc>(
          create: (_) => sl<ChallengesBloc>(),
          child: const ChallengeCreateScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.challengeDetails,
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return BlocProvider<ChallengesBloc>(
            create: (_) => sl<ChallengesBloc>()
              ..add(ViewChallengeDetails(id)),
            child: ChallengeDetailsScreen(challengeId: id),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.challengeJoin,
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return ChallengeJoinScreen(challengeId: id);
        },
      ),
      GoRoute(
        path: AppRoutes.challengeInvite,
        builder: (context, state) {
          final challenge = state.extra as ChallengeEntity;
          return BlocProvider<ChallengesBloc>(
            create: (_) => sl<ChallengesBloc>(),
            child: ChallengeInviteScreen(challenge: challenge),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.challengeResult,
        builder: (context, state) {
          final extra = state.extra as ChallengeResultExtra;
          return ChallengeResultScreen(
            challenge: extra.challenge,
            result: extra.result,
          );
        },
      ),

      // ── Championships ───────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.championships,
        builder: (context, state) => const AthleteChampionshipsScreen(),
      ),
      GoRoute(
        path: AppRoutes.championshipRanking,
        builder: (context, state) {
          final extra = state.extra as ChampionshipRankingExtra;
          return AthleteChampionshipRankingScreen(
            championshipId: extra.championshipId,
            championshipName: extra.championshipName,
            metric: extra.metric,
          );
        },
      ),

      // ── Assessoria / Coaching ───────────────────────────────────────────
      GoRoute(
        path: AppRoutes.myAssessoria,
        builder: (context, state) => BlocProvider<MyAssessoriaBloc>(
          create: (_) => sl<MyAssessoriaBloc>()
            ..add(LoadMyAssessoria(sl<UserIdentityProvider>().userId)),
          child: const MyAssessoriaScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.joinAssessoria,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return JoinAssessoriaScreen(
            onComplete: (extra?['onComplete'] as VoidCallback?) ??
                () => context.pop(),
            onBack: extra?['onBack'] as VoidCallback?,
            initialCode: extra?['initialCode'] as String?,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.assessoriaFeed,
        builder: (context, state) {
          final groupId = state.extra as String? ?? '';
          return BlocProvider<AssessoriaFeedBloc>(
            create: (_) =>
                sl<AssessoriaFeedBloc>()..add(LoadFeed(groupId)),
            child: const AssessoriaFeedScreen(),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.partnerAssessorias,
        builder: (context, state) {
          final groupId = state.pathParameters['groupId']!;
          return PartnerAssessoriasScreen(groupId: groupId);
        },
      ),
      GoRoute(
        path: AppRoutes.coachingGroups,
        builder: (context, state) => BlocProvider<CoachingGroupsBloc>(
          create: (_) => sl<CoachingGroupsBloc>()
            ..add(LoadCoachingGroups(sl<UserIdentityProvider>().userId)),
          child: const CoachingGroupsScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.coachingGroupDetails,
        builder: (context, state) {
          final groupId = state.pathParameters['groupId']!;
          final callerUserId = state.uri.queryParameters['callerId'] ??
              sl<UserIdentityProvider>().userId;
          return CoachingGroupDetailsScreen(
            groupId: groupId,
            callerUserId: callerUserId,
          );
        },
      ),

      // ── Groups ──────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.groupDetails,
        builder: (context, state) {
          final extra = state.extra as GroupDetailsExtra;
          return GroupDetailsScreen(
            group: extra.group,
            members: extra.members,
            goals: extra.goals,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.groupRankings,
        builder: (context, state) {
          final groupName =
              state.uri.queryParameters['name'] ?? state.extra as String? ?? '';
          return GroupRankingsScreen(groupName: groupName);
        },
      ),
      GoRoute(
        path: AppRoutes.groupMembers,
        builder: (context, state) {
          final extra = state.extra as GroupMembersExtra;
          return GroupMembersScreen(
            groupName: extra.groupName,
            members: extra.members,
            currentUserId: extra.currentUserId,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.groupEvolution,
        builder: (context, state) {
          final groupName =
              state.uri.queryParameters['name'] ?? state.extra as String? ?? '';
          return GroupEvolutionScreen(groupName: groupName);
        },
      ),
      // ── Friends / Social ────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.friends,
        builder: (context, state) => BlocProvider(
          create: (_) => sl<FriendsBloc>()
            ..add(LoadFriends(sl<UserIdentityProvider>().userId)),
          child: const FriendsScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.friendProfile,
        builder: (context, state) {
          final userId = state.pathParameters['userId']!;
          return FriendProfileScreen(userId: userId);
        },
      ),
      GoRoute(
        path: AppRoutes.friendsActivity,
        builder: (context, state) => const FriendsActivityFeedScreen(),
      ),
      GoRoute(
        path: AppRoutes.inviteFriends,
        builder: (context, state) => const InviteFriendsScreen(),
      ),
      GoRoute(
        path: AppRoutes.inviteQr,
        builder: (context, state) {
          final extra = state.extra as InviteQrExtra;
          return InviteQrScreen(
            inviteCode: extra.inviteCode,
            groupName: extra.groupName,
          );
        },
      ),

      // ── Profile & Settings ──────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.profile,
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) {
          final isStaff = state.uri.queryParameters['staff'] == 'true';
          return SettingsScreen(isStaff: isStaff);
        },
      ),
      GoRoute(
        path: AppRoutes.faq,
        builder: (context, state) {
          final isStaff = state.uri.queryParameters['staff'] == 'true';
          return FaqScreen(isStaff: isStaff);
        },
      ),
      GoRoute(
        path: AppRoutes.howItWorks,
        builder: (context, state) => const HowItWorksScreen(),
      ),
      GoRoute(
        path: AppRoutes.diagnostics,
        builder: (context, state) => const DiagnosticsScreen(),
      ),

      // ── Wallet ──────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.wallet,
        builder: (context, state) => BlocProvider<WalletBloc>(
          create: (_) => sl<WalletBloc>()
            ..add(LoadWallet(sl<UserIdentityProvider>().userId)),
          child: const WalletScreen(),
        ),
      ),

      // ── Progress / Gamification ─────────────────────────────────────────
      GoRoute(
        path: AppRoutes.progress,
        builder: (context, state) => const ProgressHubScreen(),
      ),
      GoRoute(
        path: AppRoutes.badges,
        builder: (context, state) => BlocProvider<BadgesBloc>(
          create: (_) => sl<BadgesBloc>()
            ..add(LoadBadges(sl<UserIdentityProvider>().userId)),
          child: const BadgesScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.missions,
        builder: (context, state) => BlocProvider<MissionsBloc>(
          create: (_) => sl<MissionsBloc>()
            ..add(LoadMissions(sl<UserIdentityProvider>().userId)),
          child: const MissionsScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.progression,
        builder: (context, state) => BlocProvider<ProgressionBloc>(
          create: (_) => sl<ProgressionBloc>()
            ..add(LoadProgression(sl<UserIdentityProvider>().userId)),
          child: const ProgressionScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.personalEvolution,
        builder: (context, state) => const PersonalEvolutionScreen(),
      ),
      GoRoute(
        path: AppRoutes.runningDna,
        builder: (context, state) => const RunningDnaScreen(),
      ),
      GoRoute(
        path: AppRoutes.leaderboards,
        builder: (context, state) => BlocProvider<LeaderboardsBloc>(
          create: (_) => sl<LeaderboardsBloc>(),
          child: const LeaderboardsScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.league,
        builder: (context, state) => const LeagueScreen(),
      ),
      GoRoute(
        path: AppRoutes.streaksLeaderboard,
        builder: (context, state) => const StreaksLeaderboardScreen(),
      ),
      GoRoute(
        path: AppRoutes.matchmaking,
        builder: (context, state) => const MatchmakingScreen(),
      ),
      GoRoute(
        path: AppRoutes.wrapped,
        builder: (context, state) {
          final extra = state.extra as WrappedExtra;
          return WrappedScreen(
            periodType: extra.periodType,
            periodKey: extra.periodKey,
            periodLabel: extra.periodLabel,
          );
        },
      ),

      // ── Runs / Workouts ─────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.runDetails,
        builder: (context, state) {
          final extra = state.extra as RunDetailsExtra;
          return RunDetailsScreen(session: extra.session);
        },
      ),
      GoRoute(
        path: AppRoutes.runSummary,
        builder: (context, state) {
          final extra = state.extra as RunSummaryExtra;
          return RunSummaryScreen(
            points: extra.points,
            totalDistanceM: extra.totalDistanceM,
            elapsedMs: extra.elapsedMs,
            avgPaceSecPerKm: extra.avgPaceSecPerKm,
            ghostFinalDeltaM: extra.ghostFinalDeltaM,
            ghostDurationMs: extra.ghostDurationMs,
            ghostDistanceM: extra.ghostDistanceM,
            isVerified: extra.isVerified,
            integrityFlags: extra.integrityFlags,
            avgBpm: extra.avgBpm,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.runReplay,
        builder: (context, state) {
          final extra = state.extra as RunReplayExtra;
          return RunReplayScreen(
            points: extra.points,
            totalDistanceM: extra.totalDistanceM,
            elapsedMs: extra.elapsedMs,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.map,
        builder: (context, state) => const MapScreen(),
      ),
      GoRoute(
        path: AppRoutes.workoutDelivery,
        builder: (context, state) => const WorkoutDeliveryScreen(),
      ),
      GoRoute(
        path: AppRoutes.athleteDelivery,
        builder: (context, state) => const AthleteDeliveryScreen(),
      ),
      GoRoute(
        path: AppRoutes.myExports,
        builder: (context, state) => const AthleteMyExportsScreen(),
      ),
      GoRoute(
        path: AppRoutes.myInvoices,
        builder: (context, state) => const AthleteMyInvoicesScreen(),
      ),

      // ── Events ──────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.eventDetails,
        builder: (context, state) {
          final extra = state.extra as EventDetailsExtra;
          return EventDetailsScreen(
            event: extra.event,
            myParticipation: extra.myParticipation,
            allParticipations: extra.allParticipations,
          );
        },
      ),

      // ── Announcements ─────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.announcementFeed,
        builder: (context, state) {
          final groupId = state.pathParameters['groupId']!;
          final isStaff = state.uri.queryParameters['staff'] == 'true';
          return AnnouncementFeedScreen(groupId: groupId, isStaff: isStaff);
        },
      ),
      GoRoute(
        path: AppRoutes.announcementDetail,
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          final isStaff = state.uri.queryParameters['staff'] == 'true';
          return AnnouncementDetailScreen(
            announcementId: id,
            isStaff: isStaff,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.announcementCreate,
        builder: (context, state) {
          final groupId = state.pathParameters['groupId']!;
          final existing = state.extra as AnnouncementEntity?;
          return AnnouncementCreateScreen(
            groupId: groupId,
            existing: existing,
          );
        },
      ),

      // ── Training Feed (plan-based) ────────────────────────────────────────
      GoRoute(
        path: AppRoutes.athleteTrainingFeed,
        builder: (context, state) => BlocProvider<TrainingFeedBloc>(
          create: (_) => sl<TrainingFeedBloc>()
            ..add(LoadTrainingFeed(focusDate: DateTime.now())),
          child: const AthleteTrainingFeedScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.athletePlanWorkout,
        builder: (context, state) {
          final workoutId = state.pathParameters['workoutId']!;
          final extra = state.extra as PlanWorkoutEntity?;
          return AthleteWorkoutDetailScreen(
            workoutId: workoutId,
            initialWorkout: extra,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.athletePlanWorkoutFeedback,
        builder: (context, state) {
          final workoutId = state.pathParameters['workoutId']!;
          final extra = state.extra as PlanWorkoutEntity?;
          return AthleteWorkoutFeedbackScreen(
            releaseId: workoutId,
            workout: extra,
          );
        },
      ),

      // ── Athlete features ────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.athleteVerification,
        builder: (context, state) => const AthleteVerificationScreen(),
      ),
      GoRoute(
        path: AppRoutes.athleteWorkoutDay,
        builder: (context, state) {
          final groupId = state.pathParameters['groupId']!;
          return AthleteWorkoutDayScreen(groupId: groupId);
        },
      ),
      GoRoute(
        path: AppRoutes.athleteTrainingList,
        builder: (context, state) {
          final groupId = state.pathParameters['groupId']!;
          return AthleteTrainingListScreen(groupId: groupId);
        },
      ),
      GoRoute(
        path: AppRoutes.athleteAttendance,
        builder: (context, state) {
          final extra = state.extra as AthleteAttendanceExtra;
          return AthleteAttendanceScreen(
            groupId: extra.groupId,
            athleteUserId: extra.athleteUserId,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.athleteEvolution,
        builder: (context, state) {
          final athleteName = state.uri.queryParameters['name'] ??
              state.extra as String? ??
              '';
          return AthleteEvolutionScreen(athleteName: athleteName);
        },
      ),
      GoRoute(
        path: AppRoutes.athleteMyEvolution,
        builder: (context, state) {
          final extra = state.extra as AthleteMyEvolutionExtra;
          return AthleteMyEvolutionScreen(
            groupId: extra.groupId,
            userId: extra.userId,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.athleteLogExecution,
        builder: (context, state) {
          final assignmentId = state.uri.queryParameters['assignmentId'];
          final assignmentLabel = state.uri.queryParameters['label'];
          return AthleteLogExecutionScreen(
            assignmentId: assignmentId,
            assignmentLabel: assignmentLabel,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.athleteCheckinQr,
        builder: (context, state) {
          final extra = state.extra as AthleteCheckinQrExtra;
          return AthleteCheckinQrScreen(
            sessionId: extra.sessionId,
            sessionTitle: extra.sessionTitle,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.athleteDeviceLink,
        builder: (context, state) {
          final extra = state.extra as AthleteDeviceLinkExtra;
          return AthleteDeviceLinkScreen(
            athleteUserId: extra.athleteUserId,
            groupId: extra.groupId,
          );
        },
      ),

      // ── Staff features ──────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.staffQrHub,
        builder: (context, state) {
          final membership = state.extra as CoachingMemberEntity;
          return StaffQrHubScreen(membership: membership);
        },
      ),
      GoRoute(
        path: AppRoutes.staffScanQr,
        builder: (context, state) => BlocProvider<StaffQrBloc>(
          create: (_) => StaffQrBloc(repo: sl<ITokenIntentRepo>()),
          child: const StaffScanQrScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.staffGenerateQr,
        builder: (context, state) {
          final extra = state.extra as StaffGenerateQrExtra;
          return BlocProvider<StaffQrBloc>(
            create: (_) => sl<StaffQrBloc>(),
            child: StaffGenerateQrScreen(
              type: extra.type,
              groupId: extra.groupId,
              championshipId: extra.championshipId,
            ),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.staffJoinRequests,
        builder: (context, state) {
          final groupId = state.pathParameters['groupId']!;
          return StaffJoinRequestsScreen(groupId: groupId);
        },
      ),
      GoRoute(
        path: AppRoutes.staffChallengeInvites,
        builder: (context, state) {
          final groupId = state.pathParameters['groupId']!;
          return StaffChallengeInvitesScreen(groupId: groupId);
        },
      ),
      GoRoute(
        path: AppRoutes.staffChampionshipInvites,
        builder: (context, state) {
          final groupId = state.pathParameters['groupId']!;
          return StaffChampionshipInvitesScreen(groupId: groupId);
        },
      ),
      GoRoute(
        path: AppRoutes.staffChampionshipManage,
        builder: (context, state) {
          final extra = state.extra as StaffChampionshipManageExtra;
          return StaffChampionshipManageScreen(
            championshipId: extra.championshipId,
            hostGroupId: extra.hostGroupId,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.staffChampionshipTemplates,
        builder: (context, state) {
          final extra = state.extra as StaffChampionshipTemplatesExtra;
          return StaffChampionshipTemplatesScreen(
            groupId: extra.groupId,
            groupName: extra.groupName,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.staffCrmList,
        builder: (context, state) {
          final groupId = state.pathParameters['groupId']!;
          return StaffCrmListScreen(groupId: groupId);
        },
      ),
      GoRoute(
        path: AppRoutes.staffAthleteProfile,
        builder: (context, state) {
          final extra = state.extra as StaffAthleteProfileExtra;
          return StaffAthleteProfileScreen(
            groupId: extra.groupId,
            athleteUserId: extra.athleteUserId,
            athleteDisplayName: extra.athleteDisplayName,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.staffCredits,
        builder: (context, state) {
          final extra = state.extra as StaffCreditsExtra;
          return StaffCreditsScreen(
            groupId: extra.groupId,
            groupName: extra.groupName,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.staffWeeklyReport,
        builder: (context, state) {
          final extra = state.extra as StaffWeeklyReportExtra;
          return StaffWeeklyReportScreen(
            groupId: extra.groupId,
            groupName: extra.groupName,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.staffRetentionDashboard,
        builder: (context, state) {
          final extra = state.extra as StaffRetentionExtra;
          return StaffRetentionDashboardScreen(
            groupId: extra.groupId,
            groupName: extra.groupName,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.staffPerformance,
        builder: (context, state) {
          final extra = state.extra as StaffPerformanceExtra;
          return StaffPerformanceScreen(
            groupId: extra.groupId,
            groupName: extra.groupName,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.staffTrainingList,
        builder: (context, state) {
          final groupId = state.pathParameters['groupId']!;
          return StaffTrainingListScreen(groupId: groupId);
        },
      ),
      GoRoute(
        path: AppRoutes.staffTrainingDetail,
        builder: (context, state) {
          final sessionId = state.pathParameters['sessionId']!;
          return StaffTrainingDetailScreen(sessionId: sessionId);
        },
      ),
      GoRoute(
        path: AppRoutes.staffTrainingCreate,
        builder: (context, state) {
          final extra = state.extra as StaffTrainingCreateExtra;
          return StaffTrainingCreateScreen(
            groupId: extra.groupId,
            userId: extra.userId,
            existing: extra.existing,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.staffTrainingScan,
        builder: (context, state) {
          final sessionId = state.pathParameters['sessionId']!;
          return StaffTrainingScanScreen(sessionId: sessionId);
        },
      ),
      GoRoute(
        path: AppRoutes.staffWorkoutTemplates,
        builder: (context, state) {
          final groupId = state.pathParameters['groupId']!;
          return StaffWorkoutTemplatesScreen(groupId: groupId);
        },
      ),
      GoRoute(
        path: AppRoutes.staffWorkoutBuilder,
        builder: (context, state) {
          final groupId = state.pathParameters['groupId']!;
          final templateId = state.uri.queryParameters['templateId'];
          return StaffWorkoutBuilderScreen(
            groupId: groupId,
            templateId: templateId,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.staffWorkoutAssign,
        builder: (context, state) {
          final groupId = state.pathParameters['groupId']!;
          return StaffWorkoutAssignScreen(groupId: groupId);
        },
      ),

      // ── Support ─────────────────────────────────────────────────────────
      // IMPORTANT: static route (/support/ticket) must come before the
      // parameterised route (/support/:groupId) so go_router doesn't
      // capture "ticket" as a groupId value.
      GoRoute(
        path: AppRoutes.supportTicket,
        builder: (context, state) {
          final extra = state.extra as SupportTicketExtra;
          return SupportTicketScreen(
            ticketId: extra.ticketId,
            subject: extra.subject,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.support,
        builder: (context, state) {
          final groupId = state.pathParameters['groupId']!;
          return SupportScreen(groupId: groupId);
        },
      ),

      // ── Parks (feature) ─────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.parks,
        builder: (context, state) => const MyParksScreen(),
      ),
      GoRoute(
        path: AppRoutes.parkDetail,
        builder: (context, state) {
          final park = state.extra as ParkEntity;
          return ParkScreen(park: park);
        },
      ),

      // ── Export / Import (feature) ─────────────────────────────────────
      GoRoute(
        path: AppRoutes.exportRun,
        builder: (context, state) {
          final session = state.extra as WorkoutSessionEntity;
          return ExportScreen(session: session);
        },
      ),
      GoRoute(
        path: AppRoutes.howToImport,
        builder: (context, state) => const HowToImportScreen(),
      ),

      // ── Debug ───────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.debugHrm,
        builder: (context, state) => const DebugHrmScreen(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Página não encontrada')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Rota não encontrada: ${state.uri}',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => context.go(AppRoutes.root),
              child: const Text('Voltar ao início'),
            ),
          ],
        ),
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// Auth redirect
// ═══════════════════════════════════════════════════════════════════════════════

const _publicRoutes = {
  AppRoutes.root,
  AppRoutes.welcome,
  AppRoutes.login,
  AppRoutes.onboarding,
  AppRoutes.onboardingTour,
  AppRoutes.staffSetup,
  AppRoutes.recovery,
  AppRoutes.howItWorks,
  AppRoutes.faq,
};

String? _rootRedirect(BuildContext context, GoRouterState state) {
  // Skip auth gating for mock / demo mode.
  if (AppConfig.demoMode || !AppConfig.isSupabaseReady) return null;

  final location = state.matchedLocation;

  // Allow public routes without auth.
  if (_publicRoutes.contains(location)) return null;

  // Deep-link challenge join is allowed unauthenticated — AuthGate handles it.
  if (location.startsWith('/challenges/join/')) return null;

  final identity = sl<UserIdentityProvider>();
  final isSignedIn = identity.authRepository.isSignedIn;
  final isAnonymous = identity.isAnonymous;

  if (!isSignedIn || isAnonymous) {
    return AppRoutes.root;
  }

  return null;
}
