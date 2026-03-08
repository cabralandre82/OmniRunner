// ignore_for_file: dangling_library_doc_comments

/// ## Product Roadmap: Park / Same-Space Features
///
/// Brazil has a strong park-running culture (Ibirapuera, Aterro, Barigui, etc.).
/// Multiple Omni Runner athletes often run at the same park. Ideas to explore:
///
/// ### 1. Park Leaderboard ("Rei do Parque")
/// Auto-detect which park the athlete ran in (GPS polygon matching on
/// Strava polyline). Weekly ranking: fastest lap, longest distance, most
/// visits. Weekly crown holder gets XP bonus + exclusive badge.
///
/// ### 2. Park Check-in & Community
/// When Strava syncs a run inside a known park, auto check-in.
/// Show: "12 atletas do Omni Runner correram no Ibirapuera hoje".
/// Auto-create micro-communities per park with their own feed.
///
/// ### 3. Shadow Racing (Corrida Fantasma)
/// Two athletes ran the same park at different times? Let them "race"
/// each other's ghost. "João correu Ibirapuera às 7h com pace 5:20.
/// Desafie a rota dele!" Reconstructs ghost from Strava polyline.
///
/// ### 4. Park Segments & Records
/// Define popular segments within parks (e.g. "Volta do lago Ibirapuera",
/// "Reta da Faria Lima"). Track KOM-style records. Leaderboard per segment.
/// Badges for breaking segment PRs.
///
/// ### 5. Social Run Detection
/// If two+ users ran at the same park at overlapping times (within 30min),
/// suggest: "Parece que você e @Maria correram juntos no Ibirapuera!
/// Quer adicionar como amiga?" Builds organic social connections.
///
/// ### 6. Park Events / Flash Challenges
/// Push notification: "Desafio no Ibirapuera: quem correr mais nos
/// próximos 60 minutos!" Geo-fenced challenges.
/// Requires minimum 3 users at the park recently to trigger.
///
/// ### 7. Territory / Heat Map
/// Athletes "paint" the city map by running through different areas.
/// Park = high-density territory. Show aggregate heat map of all
/// Omni Runner users at a park. Badges for exploring new parks.
///
/// ### 8. Park Relay
/// Virtual relay at a shared park: team of 4, each runs their leg
/// at any time during the day. Combined time counts. Creates
/// coordination and team spirit among assessoria members.
///
/// ### 9. "Quem Corre Aqui" Discovery
/// Profile card showing "Parques favoritos" based on run frequency.
/// Users can discover and follow other runners who train at the
/// same parks. Great for assessorias that train in specific parks.
///
/// ### 10. Park-Based Matchmaking
/// Prefer matching opponents who run at the same park. A 1v1 challenge
/// between two Ibirapuera runners feels more personal and competitive
/// than random pairing. "Seu oponente também corre no Ibirapuera!"
///
/// Technical: All features work with Strava data (summary_polyline +
/// start_latlng). Park polygon database can be seeded from OpenStreetMap
/// leisure=park data for Brazilian cities. No real-time tracking needed.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/push/notification_rules_service.dart';
import 'package:omni_runner/core/router/app_router.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';
import 'package:omni_runner/core/tips/first_use_tips.dart';
import 'package:omni_runner/data/services/today_data_service.dart';
import 'package:omni_runner/domain/entities/badge_award_entity.dart';
import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_rules_entity.dart';
import 'package:omni_runner/domain/entities/profile_progress_entity.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';
import 'package:omni_runner/domain/repositories/i_badge_award_repo.dart';
import 'package:omni_runner/domain/repositories/i_challenge_repo.dart';
import 'package:omni_runner/domain/repositories/i_profile_progress_repo.dart';
import 'package:omni_runner/domain/repositories/i_session_repo.dart';
import 'package:omni_runner/features/parks/data/park_detection_service.dart';
import 'package:omni_runner/features/parks/data/parks_seed.dart';
import 'package:omni_runner/features/parks/domain/park_entity.dart';
import 'package:omni_runner/features/strava/presentation/strava_connect_controller.dart';
import 'package:omni_runner/l10n/l10n.dart';
import 'package:omni_runner/presentation/widgets/run_share_card.dart';
import 'package:omni_runner/presentation/widgets/shimmer_loading.dart';
import 'package:omni_runner/presentation/widgets/tip_banner.dart';

class TodayScreen extends StatefulWidget {
  final bool isVisible;
  const TodayScreen({super.key, this.isVisible = true});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  ProfileProgressEntity? _profile;
  WorkoutSessionEntity? _lastRun;
  WorkoutSessionEntity? _previousRun;
  bool _stravaConnected = false;
  bool _loading = true;
  String? _errorMessage;
  ParkEntity? _detectedPark;
  List<ChallengeEntity> _activeChallenges = const [];
  List<Map<String, dynamic>> _activeChampionships = const [];
  List<BadgeAwardEntity> _recentBadges = const [];
  DateTime? _lastLoadTime;
  bool _connectingStrava = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TodayScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _load();
    }
  }

  Future<void> _load() async {
    if (AppConfig.demoMode) {
      _loadDemoData();
      return;
    }
    if (_lastLoadTime != null &&
        DateTime.now().difference(_lastLoadTime!) < const Duration(seconds: 60)) {
      return;
    }
    try {
      final uid = sl<UserIdentityProvider>().userId;

      // Ensure profile_progress is up-to-date (awards XP for
      // Strava sessions that never went through calculate-progression)
      try {
        await sl<TodayDataService>().recalculateProfileProgress(uid);
      } catch (e) {
        AppLogger.debug('recalculate_profile_progress failed', tag: 'Today', error: e);
      }

      // Profile progress: Supabase first (authoritative), fallback to Isar
      ProfileProgressEntity profile;
      try {
        final row = await sl<TodayDataService>().getProfileProgress(uid);
        if (row != null) {
          profile = ProfileProgressEntity(
            userId: uid,
            totalXp: (row['total_xp'] as num?)?.toInt() ?? 0,
            seasonXp: (row['season_xp'] as num?)?.toInt() ?? 0,
            currentSeasonId: row['current_season_id'] as String?,
            dailyStreakCount:
                (row['daily_streak_count'] as num?)?.toInt() ?? 0,
            streakBest: (row['streak_best'] as num?)?.toInt() ?? 0,
            lastStreakDayMs:
                (row['last_streak_day_ms'] as num?)?.toInt(),
            hasFreezeAvailable:
                row['has_freeze_available'] as bool? ?? false,
            weeklySessionCount:
                (row['weekly_session_count'] as num?)?.toInt() ?? 0,
            monthlySessionCount:
                (row['monthly_session_count'] as num?)?.toInt() ?? 0,
            lifetimeSessionCount:
                (row['lifetime_session_count'] as num?)?.toInt() ?? 0,
            lifetimeDistanceM:
                (row['lifetime_distance_m'] as num?)?.toDouble() ?? 0,
            lifetimeMovingMs:
                (row['lifetime_moving_ms'] as num?)?.toInt() ?? 0,
          );
          await sl<IProfileProgressRepo>().save(profile);
        } else {
          profile = await sl<IProfileProgressRepo>().getByUserId(uid);
        }
      } catch (e) {
        AppLogger.debug('Profile fetch offline, using Isar', tag: 'Today', error: e);
        profile = await sl<IProfileProgressRepo>().getByUserId(uid);
      }

      // Fetch completed sessions from local Isar, filter >= 1km
      final localAll =
          await sl<ISessionRepo>().getByStatus(WorkoutStatus.completed);
      final localCompleted = localAll
          .where((s) => (s.totalDistanceM ?? 0) >= 1000)
          .toList();

      // Also fetch latest sessions from Supabase (includes Strava imports)
      // Only sessions >= 1km count as real runs
      List<WorkoutSessionEntity> remoteCompleted = const [];
      try {
        final rows = await sl<TodayDataService>().getRemoteSessions(uid);
        remoteCompleted = rows.map((r) => _remoteSessionToEntity(r)).toList();
      } catch (e) {
        AppLogger.debug('Remote sessions fetch failed', tag: 'Today', error: e);
      }

      // Merge: use most recent from either source, deduplicate by id
      final merged = _mergeRuns(localCompleted, remoteCompleted);

      final stravaConnected = await sl<StravaConnectController>().isConnected;

      // Active challenges: Supabase first, fallback to Isar
      List<ChallengeEntity> active = const [];
      try {
        final partIds = await sl<TodayDataService>().getActiveChallengeIds(uid);
        if (partIds.isNotEmpty) {
          final challRows =
              await sl<TodayDataService>().getChallengesByIds(partIds);
          active = challRows.map((r) {
            final typeStr = r['type'] as String? ?? 'one_vs_one';
            return ChallengeEntity(
              id: r['id'] as String,
              creatorUserId: '',
              status: ChallengeStatus.active,
              type: switch (typeStr) {
                'group' => ChallengeType.group,
                'team' => ChallengeType.team,
                _ => ChallengeType.oneVsOne,
              },
              rules: ChallengeRulesEntity(
                goal: ChallengeGoal.mostDistance,
                windowMs: 0,
                entryFeeCoins:
                    (r['entry_fee_coins'] as num?)?.toInt() ?? 0,
              ),
              participants: const [],
              createdAtMs: 0,
              endsAtMs: (r['ends_at_ms'] as num?)?.toInt(),
              title: r['title'] as String?,
            );
          }).toList();
        }
      } catch (e) {
        AppLogger.debug('Challenges fetch offline, using Isar', tag: 'Today', error: e);
        try {
          final all = await sl<IChallengeRepo>().getByUserId(uid);
          active = all
              .where((c) => c.status == ChallengeStatus.active)
              .toList();
        } catch (e2) {
          AppLogger.warn('Isar challenges fallback failed', tag: 'Today', error: e2);
        }
      }

      List<Map<String, dynamic>> champs = const [];
      try {
        final ids = await sl<TodayDataService>().getActiveChampionshipIds(uid);
        if (ids.isNotEmpty) {
          champs =
              await sl<TodayDataService>().getChampionshipsByIds(ids);
        }
      } catch (e) {
        AppLogger.debug('Championships fetch failed', tag: 'Today', error: e);
      }

      List<BadgeAwardEntity> recentBadges = const [];
      try {
        final allAwards = await sl<IBadgeAwardRepo>().getByUserId(uid);
        final cutoff = DateTime.now().subtract(const Duration(hours: 24)).millisecondsSinceEpoch;
        recentBadges = allAwards.where((a) => a.unlockedAtMs > cutoff).toList();
      } catch (e) {
        AppLogger.debug('Recent badges fetch failed', tag: 'Today', error: e);
      }

      ParkEntity? park;
      final lastRun = merged.isNotEmpty ? merged.first : null;
      if (lastRun != null && lastRun.route.isNotEmpty) {
        const detector = ParkDetectionService(kBrazilianParksSeed);
        final firstPoint = lastRun.route.first;
        park = detector.detectPark(firstPoint.lat, firstPoint.lng);
      }

      if (!mounted) return;
      _lastLoadTime = DateTime.now();
      setState(() {
        _profile = profile;
        _lastRun = lastRun;
        _previousRun = merged.length > 1 ? merged[1] : null;
        _stravaConnected = stravaConnected;
        _detectedPark = park;
        _activeChallenges = active;
        _activeChampionships = champs;
        _recentBadges = recentBadges;
        _loading = false;
        _errorMessage = null;
      });

      _checkStreakAtRisk(uid, profile, lastRun);
    } catch (e) {
      AppLogger.error('Today data load failed', tag: 'Today', error: e);
      if (mounted) {
        setState(() {
          _loading = false;
          _errorMessage = 'Não foi possível carregar seus dados.';
        });
      }
    }
  }

  void _loadDemoData() {
    final now = DateTime.now();
    final demoRun = WorkoutSessionEntity(
      id: 'demo-run-1',
      userId: 'demo',
      status: WorkoutStatus.completed,
      startTimeMs: now.subtract(const Duration(hours: 2)).millisecondsSinceEpoch,
      endTimeMs: now.subtract(const Duration(hours: 1, minutes: 28)).millisecondsSinceEpoch,
      totalDistanceM: 5200,
      route: const [],
      isVerified: true,
      integrityFlags: const [],
      isSynced: false,
      avgBpm: 152,
      maxBpm: 171,
      source: 'strava',
    );
    const demoProfile = ProfileProgressEntity(
      userId: 'demo',
      totalXp: 1250,
      seasonXp: 480,
      dailyStreakCount: 7,
      streakBest: 12,
      hasFreezeAvailable: true,
      weeklySessionCount: 4,
      monthlySessionCount: 14,
      lifetimeSessionCount: 42,
      lifetimeDistanceM: 287000,
      lifetimeMovingMs: 86400000,
    );
    if (!mounted) return;
    setState(() {
      _profile = demoProfile;
      _lastRun = demoRun;
      _previousRun = null;
      _stravaConnected = true;
      _detectedPark = null;
      _activeChallenges = const [];
      _activeChampionships = const [];
      _recentBadges = const [];
      _loading = false;
      _errorMessage = null;
    });
  }

  /// Merge local and remote sessions, dedup by id, sort by most recent.
  List<WorkoutSessionEntity> _mergeRuns(
    List<WorkoutSessionEntity> local,
    List<WorkoutSessionEntity> remote,
  ) {
    final byId = <String, WorkoutSessionEntity>{};
    for (final s in local) {
      byId[s.id] = s;
    }
    for (final s in remote) {
      byId.putIfAbsent(s.id, () => s);
    }
    final list = byId.values.toList()
      ..sort((a, b) => b.startTimeMs.compareTo(a.startTimeMs));
    return list;
  }

  static WorkoutSessionEntity _remoteSessionToEntity(Map<String, dynamic> r) {
    return WorkoutSessionEntity(
      id: r['id'] as String,
      userId: r['user_id'] as String?,
      status: WorkoutStatus.completed,
      startTimeMs: (r['start_time_ms'] as num).toInt(),
      endTimeMs: (r['end_time_ms'] as num?)?.toInt(),
      totalDistanceM: (r['total_distance_m'] as num?)?.toDouble(),
      route: const [],
      isVerified: r['is_verified'] as bool? ?? false,
      integrityFlags:
          (r['integrity_flags'] as List<dynamic>?)?.cast<String>() ?? const [],
      isSynced: true,
      avgBpm: (r['avg_bpm'] as num?)?.toInt(),
      maxBpm: (r['max_bpm'] as num?)?.toInt(),
      source: r['source'] as String? ?? 'app',
    );
  }

  void _checkStreakAtRisk(
    String uid,
    ProfileProgressEntity? profile,
    WorkoutSessionEntity? lastRun,
  ) {
    if (profile == null || profile.dailyStreakCount < 3) return;
    final now = DateTime.now();
    if (lastRun != null) {
      final runDate =
          DateTime.fromMillisecondsSinceEpoch(lastRun.startTimeMs);
      if (runDate.year == now.year &&
          runDate.month == now.month &&
          runDate.day == now.day) {
        return;
      }
    }
    if (now.hour >= 18) {
      sl<NotificationRulesService>().notifyStreakAtRisk(
        userId: uid,
        currentStreak: profile.dailyStreakCount,
      );
    }
  }

  Future<void> _connectStrava() async {
    if (AppConfig.demoMode) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Crie uma conta para usar esta funcionalidade')),
        );
      }
      return;
    }
    setState(() => _connectingStrava = true);
    try {
      final controller = sl<StravaConnectController>();
      final result = await controller.startConnect();
      if (mounted) {
        setState(() {
          _stravaConnected = true;
          _connectingStrava = false;
        });
        final msg = result.importedCount > 0
            ? '${result.importedCount} corridas importadas do Strava!'
            : 'Strava conectado como ${result.state.athleteName}!';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        _lastLoadTime = null;
        _load();
      }
    } catch (e) {
      final controller = sl<StravaConnectController>();
      final stillConnected = await controller.isConnected;
      if (mounted) {
        if (stillConnected) {
          controller.retryBackfillIfNeeded().ignore();
          setState(() {
            _stravaConnected = true;
            _connectingStrava = false;
          });
          _lastLoadTime = null;
          _load();
        } else {
          setState(() => _connectingStrava = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Erro ao conectar Strava. Tente novamente.')),
          );
        }
      }
    }
  }

  bool get _ranToday {
    final lastRun = _lastRun;
    if (lastRun == null) return false;
    final now = DateTime.now();
    final runDate = DateTime.fromMillisecondsSinceEpoch(lastRun.startTimeMs);
    return runDate.year == now.year &&
        runDate.month == now.month &&
        runDate.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Semantics(
      label: 'Tela de Hoje',
      child: Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.today),
      ),
      body: _errorMessage != null && _profile == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(DesignTokens.spacingXl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_off_rounded,
                        size: 64, color: cs.outline),
                    const SizedBox(height: DesignTokens.spacingMd),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: DesignTokens.spacingLg),
                    FilledButton.icon(
                      onPressed: () {
                        _lastLoadTime = null;
                        setState(() {
                          _loading = true;
                          _errorMessage = null;
                        });
                        _load();
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            )
          : _loading
          ? Padding(
              padding: const EdgeInsets.fromLTRB(DesignTokens.spacingMd, 12, DesignTokens.spacingMd, DesignTokens.spacingLg),
              child: ShimmerLoading(
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      height: 80,
                      decoration: BoxDecoration(
                        color: DesignTokens.textMuted,
                        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      height: 120,
                      decoration: BoxDecoration(
                        color: DesignTokens.textMuted,
                        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      height: 160,
                      decoration: BoxDecoration(
                        color: DesignTokens.textMuted,
                        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      height: 80,
                      decoration: BoxDecoration(
                        color: DesignTokens.textMuted,
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(DesignTokens.spacingMd, 12, DesignTokens.spacingMd, DesignTokens.spacingLg),
                children: [
                  const TipBanner(
                    tipKey: TipKey.stravaConnect,
                    icon: Icons.watch,
                    text: 'O Omni Runner funciona com o Strava: corra com '
                        'qualquer relógio (Garmin, Coros, Apple Watch) e '
                        'suas corridas serão importadas automaticamente. '
                        'Conecte em Configurações → Integrações.',
                  ),

                  // Streak banner
                  if (_profile != null) _StreakBanner(profile: _profile!),
                  const SizedBox(height: 14),

                  // Recent badge unlock
                  if (_recentBadges.isNotEmpty) ...[
                    _RecentBadgeUnlockCard(
                      badgeCount: _recentBadges.length,
                      onTap: () {
                        context.push(AppRoutes.badges);
                      },
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Active challenges
                  if (_activeChallenges.isNotEmpty) ...[
                    _ActiveChallengesCard(
                      challenges: _activeChallenges,
                      onTap: (c) {
                        context.push(AppRoutes.challengeDetailsPath(c.id));
                      },
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Active championships
                  if (_activeChampionships.isNotEmpty) ...[
                    _ActiveChampionshipsCard(
                      championships: _activeChampionships,
                      onTap: () {
                        context.push(AppRoutes.championships);
                      },
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Strava CTA or "bora correr"
                  _BoraCorrerCard(
                    stravaConnected: _stravaConnected,
                    ranToday: _ranToday,
                    connectingStrava: _connectingStrava,
                    onConnectStrava: _connectStrava,
                  ),
                  const SizedBox(height: 14),

                  // Run recap (if there's a last run)
                  if (_lastRun != null) ...[
                    _RunRecapCard(
                      run: _lastRun!,
                      previousRun: _previousRun,
                      onShare: () => _shareRun(_lastRun!),
                      onJournal: () => _openJournal(_lastRun!),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Park check-in
                  if (_detectedPark != null) ...[
                    _ParkCheckinCard(
                      park: _detectedPark!,
                      onTap: () {
                        context.push(AppRoutes.parkDetail, extra: _detectedPark!);
                      },
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Quick stats
                  if (_profile != null) _QuickStatsRow(profile: _profile!),

                  const SizedBox(height: 14),

                  // Active runners nearby
                  const _ActiveRunnersChip(),

                  const SizedBox(height: 14),

                  // Daily running tip
                  const _RunningTipCard(),
                ],
              ),
            ),
    ),
    );
  }

  void _shareRun(WorkoutSessionEntity run) {
    final distKm = (run.totalDistanceM ?? 0) / 1000;
    final elapsed = (run.endTimeMs ?? run.startTimeMs) - run.startTimeMs;
    final paceSecPerKm = distKm > 0 ? elapsed / 1000 / distKm : 0.0;
    final paceMin = paceSecPerKm ~/ 60;
    final paceSec = (paceSecPerKm % 60).round();
    final durMin = elapsed ~/ 60000;
    final durSec = (elapsed % 60000) ~/ 1000;
    final date = DateTime.fromMillisecondsSinceEpoch(run.startTimeMs);

    shareRunCard(
      context,
      distanceKm: distKm,
      pace: '$paceMin:${paceSec.toString().padLeft(2, '0')}',
      duration: '$durMin:${durSec.toString().padLeft(2, '0')}',
      date: '${date.day}/${date.month}/${date.year}',
      avgBpm: run.avgBpm,
    );
  }

  Future<void> _openJournal(WorkoutSessionEntity run) async {
    final uid = sl<UserIdentityProvider>().userId;
    String? initialNotes;
    String? initialMood;
    try {
      final row = await sl<TodayDataService>().getJournalEntry(run.id, uid);
      if (row != null) {
        initialNotes = row['notes'] as String?;
        initialMood = row['mood_emoji'] as String?;
      }
    } catch (e) {
      AppLogger.debug('Journal load failed', tag: 'Today', error: e);
    }

    final controller = TextEditingController(text: initialNotes ?? '');
    String? selectedMood = initialMood;
    Timer? debounceTimer;

    Future<void> saveJournal(String notes, String? mood) async {
      try {
        await sl<TodayDataService>().upsertJournalEntry(
          sessionId: run.id,
          userId: uid,
          notes: notes.isEmpty ? null : notes,
          moodEmoji: mood,
        );
      } catch (e) {
        AppLogger.debug('Journal save failed', tag: 'Today', error: e);
      }
    }

    if (!context.mounted) return;
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              DesignTokens.spacingLg,
              DesignTokens.spacingLg,
              DesignTokens.spacingLg,
              MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Diário de corrida',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Como foi essa corrida? Anote o que sentiu, '
                  'o clima, seu humor...',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  maxLines: 4,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Hoje acordei cedo e corri no parque...',
                  ),
                  onChanged: (value) {
                    debounceTimer?.cancel();
                    debounceTimer = Timer(const Duration(seconds: 1), () {
                      saveJournal(value, selectedMood);
                    });
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Humor:'),
                    const SizedBox(width: 8),
                    ..._moodOptions(ctx, selectedMood, (mood) {
                      setModalState(() => selectedMood = mood);
                      debounceTimer?.cancel();
                      debounceTimer = Timer(const Duration(milliseconds: 500), () {
                        saveJournal(controller.text, mood);
                      });
                    }),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      debounceTimer?.cancel();
                      await saveJournal(controller.text, selectedMood);
                      if (!ctx.mounted) return;
                      ctx.pop(controller.text);
                    },
                    child: Text(ctx.l10n.save),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    debounceTimer?.cancel();
    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Anotação salva!')),
      );
    }
  }

  List<Widget> _moodOptions(
    BuildContext ctx,
    String? selectedMood,
    void Function(String) onMoodSelected,
  ) {
    const moods = ['😴', '😐', '😊', '💪', '🔥'];
    return moods
        .map((m) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingXs),
              child: GestureDetector(
                onTap: () => onMoodSelected(m),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: selectedMood == m
                        ? Theme.of(ctx).colorScheme.primaryContainer
                        : null,
                  ),
                  child: Text(m, style: const TextStyle(fontSize: 24)),
                ),
              ),
            ))
        .toList();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Streak Banner
// ═══════════════════════════════════════════════════════════════════════════════

class _StreakBanner extends StatelessWidget {
  final ProfileProgressEntity profile;
  const _StreakBanner({required this.profile});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final streak = profile.dailyStreakCount;
    final best = profile.streakBest;
    final hasFreeze = profile.hasFreezeAvailable;

    final isActive = streak > 0;
    final streakColor =
        isActive ? DesignTokens.warning : DesignTokens.textMuted;

    return Container(
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      decoration: BoxDecoration(
        gradient: isActive
            ? const LinearGradient(
                colors: [
                  DesignTokens.warning,
                  DesignTokens.error,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: isActive ? null : DesignTokens.surfaceElevated,
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        border: Border.all(
          color: isActive
              ? DesignTokens.warning
              : DesignTokens.textMuted,
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: streakColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                isActive ? '🔥' : '❄️',
                style: const TextStyle(fontSize: 28),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      isActive
                          ? '$streak dia${streak > 1 ? 's' : ''} seguido${streak > 1 ? 's' : ''}!'
                          : 'Sem sequência ativa',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: streakColor,
                      ),
                    ),
                    if (hasFreeze) ...[
                      const SizedBox(width: 6),
                      const Tooltip(
                        message: 'Freeze disponível: protege 1 dia sem correr',
                        child: Icon(Icons.ac_unit,
                            size: 16, color: DesignTokens.primary),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  isActive
                      ? 'Corra hoje para manter! Recorde: $best dias'
                      : 'Corra hoje para iniciar uma nova sequência!',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (isActive && streak >= 3) ...[
                  const SizedBox(height: 6),
                  _StreakMilestones(current: streak),
                ],
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () {
                    context.push(AppRoutes.streaksLeaderboard);
                  },
                  child: Text(
                    'Ver ranking →',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isActive
                          ? Colors.white.withValues(alpha: 0.85)
                          : theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StreakMilestones extends StatelessWidget {
  final int current;
  const _StreakMilestones({required this.current});

  @override
  Widget build(BuildContext context) {
    const milestones = [7, 14, 30, 60, 100];
    final next = milestones.firstWhere((m) => m > current, orElse: () => 0);
    if (next == 0) return const SizedBox.shrink();

    final progress = current / next;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: DesignTokens.warning,
                  valueColor:
                      const AlwaysStoppedAnimation(DesignTokens.warning),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$current/$next',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: DesignTokens.warning,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'Próximo marco: $next dias → +${_xpForMilestone(next)} XP',
          style: const TextStyle(fontSize: 10, color: DesignTokens.warning),
        ),
      ],
    );
  }

  static int _xpForMilestone(int days) => switch (days) {
        7 => 100,
        14 => 200,
        30 => 500,
        60 => 1000,
        100 => 2000,
        _ => 50,
      };
}

// ═══════════════════════════════════════════════════════════════════════════════
// Bora Correr CTA
// ═══════════════════════════════════════════════════════════════════════════════

class _BoraCorrerCard extends StatelessWidget {
  final bool stravaConnected;
  final bool ranToday;
  final bool connectingStrava;
  final VoidCallback onConnectStrava;

  const _BoraCorrerCard({
    required this.stravaConnected,
    required this.ranToday,
    required this.connectingStrava,
    required this.onConnectStrava,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (!stravaConnected) {
      return _buildStravaPrompt(context, theme);
    }

    return Container(
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: ranToday
              ? [DesignTokens.success, DesignTokens.success.withValues(alpha: 0.85)]
              : [cs.primaryContainer, cs.tertiaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
      ),
      child: Column(
        children: [
          Icon(
            ranToday ? Icons.check_circle_rounded : Icons.directions_run,
            size: 40,
            color: ranToday ? Colors.white : cs.primary,
          ),
          const SizedBox(height: 8),
          Text(
            ranToday ? 'Boa! Você já correu hoje!' : 'Bora correr?',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: ranToday ? Colors.white : null,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            ranToday
                ? 'Sua corrida foi registrada. Veja o recap abaixo!'
                : 'Corra com seu relógio e sua atividade '
                    'será importada automaticamente.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: ranToday ? Colors.white70 : cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStravaPrompt(BuildContext context, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      decoration: BoxDecoration(
        color: const Color(0xFFFC4C02).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        border: Border.all(color: const Color(0xFFFC4C02).withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFC4C02),
              borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
            ),
            child: const Icon(Icons.watch, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 12),
          Text(
            'Conecte o Strava para começar',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: const Color(0xFFFC4C02),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'O Omni Runner importa suas corridas direto do Strava. '
            'Funciona com qualquer relógio: Garmin, Coros, Apple Watch, '
            'Polar, Suunto, ou até correndo só com o celular.\n\n'
            'Ao conectar, suas últimas corridas são importadas '
            'automaticamente para calibrar seu nível.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          connectingStrava
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : FilledButton.icon(
                  onPressed: onConnectStrava,
                  icon: const Icon(Icons.link, size: 18),
                  label: const Text('Conectar Strava'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFC4C02),
                    padding: const EdgeInsets.symmetric(
                        horizontal: DesignTokens.spacingLg, vertical: 12),
                  ),
                ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Run Recap Card
// ═══════════════════════════════════════════════════════════════════════════════

class _RunRecapCard extends StatelessWidget {
  final WorkoutSessionEntity run;
  final WorkoutSessionEntity? previousRun;
  final VoidCallback onShare;
  final VoidCallback onJournal;

  const _RunRecapCard({
    required this.run,
    this.previousRun,
    required this.onShare,
    required this.onJournal,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final distKm = (run.totalDistanceM ?? 0) / 1000;
    final elapsed = (run.endTimeMs ?? run.startTimeMs) - run.startTimeMs;
    final paceSecPerKm = distKm > 0 ? elapsed / 1000 / distKm : 0.0;
    final paceMin = paceSecPerKm ~/ 60;
    final paceSec = (paceSecPerKm % 60).round();
    final durMin = elapsed ~/ 60000;
    final durSec = (elapsed % 60000) ~/ 1000;
    final date = DateTime.fromMillisecondsSinceEpoch(run.startTimeMs);
    final isToday = _isToday(date);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignTokens.radiusLg)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(DesignTokens.spacingMd, 14, DesignTokens.spacingMd, 10),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.4),
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Icon(Icons.directions_run, color: cs.primary, size: 22),
                const SizedBox(width: 8),
                Text(
                  isToday
                      ? 'Corrida de hoje'
                      : 'Última corrida — ${date.day}/${date.month}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (run.source != 'app')
                  Chip(
                    label: Text(
                      run.source == 'strava' ? 'Strava' : run.source,
                      style: const TextStyle(fontSize: 10),
                    ),
                    avatar: const Icon(Icons.watch, size: 14),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
          ),

          // Metrics
          Padding(
            padding: const EdgeInsets.fromLTRB(DesignTokens.spacingMd, 12, DesignTokens.spacingMd, DesignTokens.spacingXs),
            child: Row(
              children: [
                _MetricTile(
                  label: context.l10n.distance,
                  value: '${distKm.toStringAsFixed(2)} km',
                  icon: Icons.straighten,
                ),
                _MetricTile(
                  label: context.l10n.pace,
                  value: '$paceMin:${paceSec.toString().padLeft(2, '0')} /km',
                  icon: Icons.speed,
                ),
                _MetricTile(
                  label: context.l10n.duration,
                  value: '$durMin:${durSec.toString().padLeft(2, '0')}',
                  icon: Icons.timer,
                ),
              ],
            ),
          ),

          if (run.avgBpm != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(DesignTokens.spacingMd, 0, DesignTokens.spacingMd, DesignTokens.spacingXs),
              child: Row(
                children: [
                  const Icon(Icons.favorite, size: 14, color: DesignTokens.error),
                  const SizedBox(width: 4),
                  Text(
                    'FC média: ${run.avgBpm} bpm',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  if (run.maxBpm != null) ...[
                    Text(
                      ' · máx: ${run.maxBpm} bpm',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),

          // Comparison with previous run
          if (previousRun case final prev?)
            _ComparisonRow(current: run, previous: prev),

          // Action buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(DesignTokens.spacingSm, DesignTokens.spacingXs, DesignTokens.spacingSm, DesignTokens.spacingSm),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: onShare,
                  icon: const Icon(Icons.share, size: 18),
                  label: Text(context.l10n.share),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: onJournal,
                  icon: const Icon(Icons.edit_note, size: 18),
                  label: Text(context.l10n.history),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Comparison with previous run
// ═══════════════════════════════════════════════════════════════════════════════

class _ComparisonRow extends StatelessWidget {
  final WorkoutSessionEntity current;
  final WorkoutSessionEntity previous;

  const _ComparisonRow({required this.current, required this.previous});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final curDist = current.totalDistanceM ?? 0;
    final prevDist = previous.totalDistanceM ?? 0;
    final curElapsed =
        (current.endTimeMs ?? current.startTimeMs) - current.startTimeMs;
    final prevElapsed =
        (previous.endTimeMs ?? previous.startTimeMs) - previous.startTimeMs;

    final curPace = curDist > 0 ? curElapsed / curDist : 0.0;
    final prevPace = prevDist > 0 ? prevElapsed / prevDist : 0.0;

    // Pace difference (negative = faster = better)
    final paceDiff = prevPace > 0 ? ((curPace - prevPace) / prevPace * 100) : 0.0;
    final distDiff = prevDist > 0 ? ((curDist - prevDist) / prevDist * 100) : 0.0;

    final paceImproved = paceDiff < -0.5;
    final paceWorsened = paceDiff > 0.5;
    final distImproved = distDiff > 0.5;

    if (!paceImproved && !paceWorsened && !distImproved) {
      return const SizedBox.shrink();
    }

    final buffer = StringBuffer();
    if (paceImproved) {
      buffer.write('${paceDiff.abs().toStringAsFixed(1)}% mais rápido');
    } else if (paceWorsened) {
      buffer.write('${paceDiff.toStringAsFixed(1)}% mais lento');
    }
    if (distImproved) {
      if (buffer.isNotEmpty) buffer.write(' · ');
      buffer.write('+${distDiff.toStringAsFixed(1)}% mais longe');
    }

    final color = paceImproved
        ? DesignTokens.success
        : paceWorsened
            ? DesignTokens.warning
            : DesignTokens.primary;
    final icon = paceImproved
        ? Icons.trending_up
        : paceWorsened
            ? Icons.trending_down
            : Icons.trending_flat;

    return Padding(
      padding: const EdgeInsets.fromLTRB(DesignTokens.spacingMd, DesignTokens.spacingXs, DesignTokens.spacingMd, DesignTokens.spacingXs),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: DesignTokens.spacingSm),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'vs. corrida anterior: $buffer',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Quick Stats Row
// ═══════════════════════════════════════════════════════════════════════════════

class _QuickStatsRow extends StatelessWidget {
  final ProfileProgressEntity profile;
  const _QuickStatsRow({required this.profile});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Resumo',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _StatChip(
                icon: Icons.star,
                label: 'Nível ${profile.level}',
                color: Colors.amber,
              ),
              const SizedBox(width: 8),
              _StatChip(
                icon: Icons.bolt,
                label: '${profile.totalXp} XP',
                color: Colors.blue,
              ),
              const SizedBox(width: 8),
              _StatChip(
                icon: Icons.calendar_today,
                label: '${profile.weeklySessionCount} esta semana',
                color: Colors.green,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _StatChip(
                icon: Icons.straighten,
                label: '${profile.lifetimeDistanceKm.toStringAsFixed(0)} km total',
                color: Colors.purple,
              ),
              const SizedBox(width: 8),
              _StatChip(
                icon: Icons.directions_run,
                label: '${profile.lifetimeSessionCount} corridas',
                color: Colors.teal,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final MaterialColor color;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingSm, vertical: 6),
        decoration: BoxDecoration(
          color: color.shade50,
          borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color.shade700),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color.shade800,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Park Check-in Card
// ═══════════════════════════════════════════════════════════════════════════════

class _ParkCheckinCard extends StatelessWidget {
  final ParkEntity park;
  final VoidCallback onTap;

  const _ParkCheckinCard({required this.park, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: DesignTokens.success,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: DesignTokens.success,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                ),
                child: const Icon(Icons.park, color: DesignTokens.success, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Check-in: ${park.name}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: DesignTokens.success,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Toque para ver o ranking e quem mais corre aqui',
                      style: TextStyle(
                          fontSize: 12, color: DesignTokens.success),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: DesignTokens.success),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Active Challenges Card
// ═══════════════════════════════════════════════════════════════════════════════

class _ActiveChallengesCard extends StatelessWidget {
  final List<ChallengeEntity> challenges;
  final ValueChanged<ChallengeEntity> onTap;

  const _ActiveChallengesCard({
    required this.challenges,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignTokens.radiusLg)),
      color: cs.primaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sports_kabaddi_rounded,
                    size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  challenges.length == 1
                      ? 'Desafio ativo'
                      : '${challenges.length} desafios ativos',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...challenges.take(3).map((c) => _ActiveChallengeRow(
                  challenge: c,
                  onTap: () => onTap(c),
                  theme: theme,
                )),
            if (challenges.length > 3)
              Padding(
                padding: const EdgeInsets.only(top: DesignTokens.spacingXs),
                child: Text(
                  '+${challenges.length - 3} mais',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActiveChallengeRow extends StatelessWidget {
  final ChallengeEntity challenge;
  final VoidCallback onTap;
  final ThemeData theme;

  const _ActiveChallengeRow({
    required this.challenge,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final cs = theme.colorScheme;
    final title = challenge.title ?? _challengeDefaultTitle(challenge);
    final remaining = _timeRemaining(challenge);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: DesignTokens.spacingSm),
        margin: const EdgeInsets.only(bottom: DesignTokens.spacingXs),
        decoration: BoxDecoration(
          color: cs.surface.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              _iconForType(challenge.type),
              size: 18,
              color: cs.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (remaining != null)
                    Text(
                      remaining,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            if (challenge.rules.entryFeeCoins > 0)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: DesignTokens.warning,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${challenge.rules.entryFeeCoins} OC',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: DesignTokens.warning,
                  ),
                ),
              ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 18, color: cs.outline),
          ],
        ),
      ),
    );
  }

  static String? _timeRemaining(ChallengeEntity c) {
    final endsAtMs = c.endsAtMs;
    if (endsAtMs == null) return null;
    final diff = endsAtMs - DateTime.now().millisecondsSinceEpoch;
    if (diff <= 0) return 'Encerrado';
    final hours = diff ~/ 3600000;
    final minutes = (diff % 3600000) ~/ 60000;
    if (hours > 0) return 'Faltam ${hours}h${minutes > 0 ? ' ${minutes}min' : ''}';
    return 'Faltam ${minutes}min';
  }

  static IconData _iconForType(ChallengeType t) => switch (t) {
        ChallengeType.oneVsOne => Icons.person,
        ChallengeType.group => Icons.groups,
        ChallengeType.team => Icons.shield_rounded,
      };
}

String _challengeDefaultTitle(ChallengeEntity c) => switch (c.type) {
      ChallengeType.oneVsOne => 'Desafio 1 vs 1',
      ChallengeType.group => 'Desafio em Grupo',
      ChallengeType.team => 'Desafio Time A vs B',
    };

// ═══════════════════════════════════════════════════════════════════════════════
// Recent Badge Unlock Card
// ═══════════════════════════════════════════════════════════════════════════════

class _RecentBadgeUnlockCard extends StatelessWidget {
  final int badgeCount;
  final VoidCallback onTap;

  const _RecentBadgeUnlockCard({
    required this.badgeCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
      ),
      color: DesignTokens.warning.withValues(alpha: 0.1),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        child: Container(
          padding: const EdgeInsets.all(DesignTokens.spacingMd),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
            border: Border.all(
              color: DesignTokens.warning.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [DesignTokens.warning, Color(0xFFFFD700)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                ),
                child: const Icon(Icons.military_tech, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      badgeCount == 1
                          ? 'Novo badge desbloqueado!'
                          : '$badgeCount novos badges desbloqueados!',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: DesignTokens.warning,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Ver badges →',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: DesignTokens.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: DesignTokens.warning),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Active Championships Card
// ═══════════════════════════════════════════════════════════════════════════════

class _ActiveChampionshipsCard extends StatelessWidget {
  final List<Map<String, dynamic>> championships;
  final VoidCallback onTap;

  const _ActiveChampionshipsCard({
    required this.championships,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignTokens.radiusLg)),
      color: DesignTokens.warning,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: DesignTokens.warning,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                ),
                child: const Icon(Icons.emoji_events_rounded,
                    color: DesignTokens.warning, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      championships.length == 1
                          ? 'Campeonato ativo'
                          : '${championships.length} campeonatos ativos',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: DesignTokens.warning,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      championships
                          .take(2)
                          .map((c) => c['name'] as String? ?? 'Campeonato')
                          .join(', '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: DesignTokens.warning,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: DesignTokens.warning),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Running Tip Card (#37)
// ═══════════════════════════════════════════════════════════════════════════════

class _RunningTipCard extends StatelessWidget {
  const _RunningTipCard();

  static const _tips = [
    'Hidrate-se antes, durante e depois da corrida. 500ml 2h antes é um bom começo.',
    'Aumente seu volume semanal no máximo 10% por semana para evitar lesões.',
    'Treinos intervalados (tiros) melhoram seu VO2max e pace em poucas semanas.',
    'Corrida lenta (zona 2) deve ser 80% do seu volume. Isso constrói base aeróbica.',
    'Alongamento dinâmico antes e estático depois. Nunca alongue a frio.',
    'Seu pace ideal de corrida longa é 30-60s mais lento que seu pace de 10K.',
    'Cadência ideal fica entre 170-180 passos por minuto para a maioria dos corredores.',
    'Descanso é treino. Sem recuperação, não há evolução.',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final now = DateTime.now();
    final dayOfYear = now.difference(DateTime(now.year)).inDays;
    final tip = _tips[dayOfYear % _tips.length];

    return Container(
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        border: Border.all(
          color: cs.tertiaryContainer.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline, size: 22, color: cs.tertiary),
          const SizedBox(width: DesignTokens.spacingSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dica do dia',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.tertiary,
                  ),
                ),
                const SizedBox(height: DesignTokens.spacingXs),
                Text(
                  tip,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Active Runners Nearby (#43)
// ═══════════════════════════════════════════════════════════════════════════════

class _ActiveRunnersChip extends StatefulWidget {
  const _ActiveRunnersChip();

  @override
  State<_ActiveRunnersChip> createState() => _ActiveRunnersChipState();
}

class _ActiveRunnersChipState extends State<_ActiveRunnersChip> {
  int? _count;

  @override
  void initState() {
    super.initState();
    _loadCount();
  }

  Future<void> _loadCount() async {
    try {
      final sevenDaysAgo = DateTime.now()
          .subtract(const Duration(days: 7))
          .millisecondsSinceEpoch;

      final rows = await sl<SupabaseClient>()
          .from('sessions')
          .select('user_id')
          .gte('start_time_ms', sevenDaysAgo);

      final uniqueUsers =
          (rows as List).map((r) => r['user_id']).toSet().length;
      if (mounted && uniqueUsers > 0) {
        setState(() => _count = uniqueUsers);
      }
    } catch (e) {
      AppLogger.debug('Active runners count failed', tag: 'Today', error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_count == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacingMd,
        vertical: DesignTokens.spacingSm,
      ),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
      ),
      child: Row(
        children: [
          Icon(Icons.groups_rounded, size: 20, color: cs.primary),
          const SizedBox(width: DesignTokens.spacingSm),
          Expanded(
            child: Text(
              '$_count corredor${_count == 1 ? '' : 'es'} ativo${_count == 1 ? '' : 's'} esta semana',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Icon(Icons.trending_up, size: 16, color: DesignTokens.success),
        ],
      ),
    );
  }
}
