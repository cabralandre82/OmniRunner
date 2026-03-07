import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/l10n/l10n.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_rules_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';
import 'package:omni_runner/domain/repositories/i_coaching_member_repo.dart';
import 'package:omni_runner/domain/repositories/i_session_repo.dart';
import 'package:go_router/go_router.dart';
import 'package:omni_runner/core/router/app_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_bloc.dart';
import 'package:omni_runner/presentation/screens/challenge_create_screen.dart';
import 'package:omni_runner/features/parks/data/park_detection_service.dart';
import 'package:omni_runner/features/parks/data/parks_seed.dart';
import 'package:omni_runner/features/strava/presentation/strava_connect_controller.dart';
import 'package:omni_runner/presentation/blocs/verification/verification_bloc.dart';
import 'package:omni_runner/presentation/blocs/verification/verification_event.dart';
import 'package:omni_runner/presentation/widgets/verification_gate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

/// Queue-based matchmaking screen.
///
/// Flow:
///   1. User configures intent (metric, target, duration, entry fee)
///   2. Taps "Buscar Oponente"
///   3. Shows searching animation + polls for match
///   4. Match found → navigates to challenge details
///   OR user cancels → returns to previous screen
class MatchmakingScreen extends StatefulWidget {
  const MatchmakingScreen({super.key});

  @override
  State<MatchmakingScreen> createState() => _MatchmakingScreenState();
}

enum _MatchState { setup, searching, pendingConfirm, matched, error }

class _MatchmakingScreenState extends State<MatchmakingScreen>
    with SingleTickerProviderStateMixin {
  static const _tag = 'Matchmaking';

  final _feeCtrl = TextEditingController(text: '0');
  final _targetCtrl = TextEditingController();
  final _verificationBloc = sl<VerificationBloc>()
    ..add(const LoadVerificationState());

  ChallengeGoal _goal = ChallengeGoal.fastestAtDistance;
  int _windowMin = 180;
  _MatchState _state = _MatchState.setup;
  String? _errorMsg;
  String? _matchedChallengeId;
  String? _opponentName;
  String? _skillBracket;
  int? _queuePosition;
  Timer? _pollTimer;
  late AnimationController _pulseCtrl;
  bool _stravaConnected = true;
  String? _preferredParkId;
  String? _preferredParkName;
  List<Map<String, dynamic>> _assessoriaMembers = const [];

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _checkStrava();
    _detectPreferredPark();
    _loadAssessoriaMembers();
  }

  Future<void> _checkStrava() async {
    try {
      final connected = await sl<StravaConnectController>().isConnected;
      if (mounted) setState(() => _stravaConnected = connected);
    } catch (e) {
      AppLogger.warn('Unexpected error', tag: 'MatchmakingScreen', error: e);
    }
  }

  Future<void> _loadAssessoriaMembers() async {
    try {
      final uid = sl<UserIdentityProvider>().userId;

      // Get membership from Supabase first, fallback to Isar
      String? groupId;
      try {
        final row = await sl<SupabaseClient>()
            .from('coaching_members')
            .select('group_id')
            .eq('user_id', uid)
            .inFilter('role', ['athlete', 'atleta'])
            .maybeSingle();
        groupId = row?['group_id'] as String?;
      } catch (e) {
      AppLogger.warn('Caught error', tag: 'MatchmakingScreen', error: e);
        final memberships =
            await sl<ICoachingMemberRepo>().getByUserId(uid);
        groupId = memberships
            .where((m) => m.isAthlete)
            .firstOrNull
            ?.groupId;
      }
      if (groupId == null) return;

      final rows = await sl<SupabaseClient>()
          .from('coaching_members')
          .select('user_id, profiles(display_name)')
          .eq('group_id', groupId)
          .inFilter('role', ['athlete', 'atleta'])
          .neq('user_id', uid)
          .limit(10);

      if (mounted && (rows as List).isNotEmpty) {
        setState(() {
          _assessoriaMembers = rows
              .map((r) => <String, dynamic>{
                    'user_id': r['user_id'] as String,
                    'display_name':
                        ((r['profiles'] as Map?)?['display_name']
                                as String?) ??
                            'Atleta',
                  })
              .toList();
        });
      }
    } catch (e) {
      AppLogger.warn('Unexpected error', tag: 'MatchmakingScreen', error: e);
    }
  }

  Future<void> _detectPreferredPark() async {
    try {
      final runs =
          await sl<ISessionRepo>().getByStatus(WorkoutStatus.completed);
      if (runs.isEmpty) return;

      const detector = ParkDetectionService(kBrazilianParksSeed);
      final parkCounts = <String, int>{};

      for (final run in runs.take(20)) {
        if (run.route.isEmpty) continue;
        final pt = run.route.first;
        final park = detector.detectPark(pt.lat, pt.lng);
        if (park != null) {
          parkCounts[park.id] = (parkCounts[park.id] ?? 0) + 1;
        }
      }

      if (parkCounts.isNotEmpty) {
        final topParkId =
            (parkCounts.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value)))
                .first
                .key;
        final park =
            kBrazilianParksSeed.where((p) => p.id == topParkId).firstOrNull;
        if (park != null && mounted) {
          setState(() {
            _preferredParkId = park.id;
            _preferredParkName = park.name;
          });
        }
      }
    } on Exception catch (e) {
      AppLogger.warn('Unexpected error', tag: 'MatchmakingScreen', error: e);
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pulseCtrl.dispose();
    _verificationBloc.close();
    _feeCtrl.dispose();
    _targetCtrl.dispose();
    super.dispose();
  }

  // ── API calls ────────────────────────────────────────────────────────────

  Future<void> _startMatchmaking() async {
    if (!AppConfig.isSupabaseReady) {
      _showError('Sem conexão com o servidor.');
      return;
    }

    final fee = int.tryParse(_feeCtrl.text) ?? 0;

    if (fee > 0) {
      final ok = await checkVerificationGate(
        context,
        verification: _verificationBloc.cached,
        entryFeeCoins: fee,
      );
      if (!ok) return;
    }

    double? target;
    if (_targetCtrl.text.isNotEmpty) {
      final raw = double.tryParse(_targetCtrl.text);
      if (raw != null && raw > 0) {
        target = switch (_goal) {
          ChallengeGoal.fastestAtDistance => raw * 1000,
          ChallengeGoal.mostDistance => raw * 1000,
          ChallengeGoal.bestPaceAtDistance => raw * 1000,
          ChallengeGoal.collectiveDistance => raw * 1000,
        };
      }
    }

    setState(() {
      _state = _MatchState.searching;
      _errorMsg = null;
    });

    try {
      final res = await sl<SupabaseClient>().functions.invoke(
        'matchmake',
        body: {
          'action': 'queue',
          'goal': _goal.name,
          'target': target,
          'entry_fee_coins': fee,
          'window_ms': _windowMin * 60 * 1000,
          if (_preferredParkId != null) 'preferred_park_id': _preferredParkId,
        },
      );

      final data = res.data as Map<String, dynamic>?;
      if (data == null) {
        _showError('Resposta inválida do servidor.');
        return;
      }

      final innerData = data['data'] as Map<String, dynamic>? ?? data;
      final st = innerData['status'] as String?;

      if (st == 'matched') {
        _onMatchFound(innerData);
      } else if (st == 'queued') {
        setState(() {
          _skillBracket = innerData['skill_bracket'] as String?;
        });
        _startPolling();
      } else {
        final errMsg = (data['error'] as Map?)?['message'] as String?;
        _showError(errMsg ?? 'Erro ao buscar oponente.');
      }
    } on Exception catch (e) {
      AppLogger.warn('Matchmake failed: $e', tag: _tag);
      _showError('Falha na conexão. Tente novamente.');
    }
  }

  void _onMatchFound(Map<String, dynamic> data) {
    _pollTimer?.cancel();
    final opp = data['opponent'] as Map<String, dynamic>?;
    setState(() {
      _state = _MatchState.pendingConfirm;
      _matchedChallengeId = data['challenge_id'] as String?;
      _opponentName = opp?['display_name'] as String? ?? 'Oponente';
      _skillBracket = data['skill_bracket'] as String?;
    });
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      if (!mounted || _state != _MatchState.searching) {
        _pollTimer?.cancel();
        return;
      }
      try {
        final res = await sl<SupabaseClient>().functions.invoke(
          'matchmake',
          method: HttpMethod.get,
        );
        final data = res.data as Map<String, dynamic>?;
        final inner = data?['data'] as Map<String, dynamic>? ?? data;
        final entry = inner?['queue_entry'] as Map<String, dynamic>?;

        final pos = inner?['queue_position'] as int?;
        if (pos != null && mounted) {
          setState(() => _queuePosition = pos);
        }

        if (entry == null) return;

        if (entry['status'] == 'matched') {
          final challengeId = entry['matched_challenge_id'] as String?;
          if (challengeId != null) {
            _pollTimer?.cancel();
            // Get opponent name
            final oppId = entry['matched_with_user_id'] as String?;
            String oppName = 'Oponente';
            if (oppId != null) {
              try {
                final prof = await sl<SupabaseClient>()
                    .from('profiles')
                    .select('display_name')
                    .eq('id', oppId)
                    .maybeSingle();
                oppName = prof?['display_name'] as String? ?? oppName;
              } on Exception catch (e) {
      AppLogger.warn('Unexpected error', tag: 'MatchmakingScreen', error: e);
    }
            }
            if (!mounted) return;
            setState(() {
              _state = _MatchState.pendingConfirm;
              _matchedChallengeId = challengeId;
              _opponentName = oppName;
            });
          }
        } else if (entry['status'] == 'expired') {
          _pollTimer?.cancel();
          if (!mounted) return;
          _showError('Tempo esgotado. Nenhum oponente encontrado.');
        }
      } on Exception catch (e) {
      AppLogger.warn('Caught error', tag: 'MatchmakingScreen', error: e);
        // Polling failure — retry on next tick
      }
    });
  }

  Future<void> _cancelSearch() async {
    _pollTimer?.cancel();
    try {
      await sl<SupabaseClient>().functions.invoke(
        'matchmake',
        body: {'action': 'cancel'},
      );
    } on Exception catch (e) {
      AppLogger.warn('Unexpected error', tag: 'MatchmakingScreen', error: e);
    }
    if (!mounted) return;
    setState(() => _state = _MatchState.setup);
  }

  void _showError(String msg) {
    if (!mounted) return;
    setState(() {
      _state = _MatchState.error;
      _errorMsg = msg;
    });
  }

  void _goToChallenge() {
    if (_matchedChallengeId == null) return;
    context.pop(_matchedChallengeId);
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _state != _MatchState.searching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _state == _MatchState.searching) {
          _cancelSearch();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Encontrar Oponente'),
          leading: _state == _MatchState.searching
              ? IconButton(
                  tooltip: context.l10n.cancel,
                  icon: const Icon(Icons.close),
                  onPressed: _cancelSearch,
                )
              : null,
        ),
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: switch (_state) {
            _MatchState.setup => _buildSetup(),
            _MatchState.searching => _buildSearching(),
            _MatchState.pendingConfirm => _buildPendingConfirm(),
            _MatchState.matched => _buildMatched(),
            _MatchState.error => _buildError(),
          },
        ),
      ),
    );
  }

  // ── Setup form ─────────────────────────────────────────────────────────

  Widget _buildSetup() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return SingleChildScrollView(
      key: const ValueKey('setup'),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(DesignTokens.spacingMd),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [cs.primaryContainer, cs.tertiaryContainer],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
            ),
            child: Column(
              children: [
                Icon(Icons.sports_mma_rounded, size: 40, color: cs.primary),
                const SizedBox(height: 8),
                Text(
                  'Matchmaking Automático',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Configure seu desafio e encontraremos um oponente '
                  'do seu nível automaticamente.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (!_stravaConnected)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: DesignTokens.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                border: Border.all(color: DesignTokens.warning.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 20, color: DesignTokens.warning),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Strava não conectado',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: DesignTokens.warning,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Suas corridas precisam ser registradas via Strava '
                          'para contar no desafio. Conecte nas Configurações.',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: () {
                            context
                                .push(AppRoutes.settings)
                                .then((_) => _checkStrava());
                          },
                          child: const Text(
                            'Ir para Configurações →',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFFC4C02),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),

          // How matchmaking works
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.help_outline, size: 16, color: cs.primary),
                  const SizedBox(width: 6),
                  Text('Como funciona?',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: cs.primary,
                      )),
                ]),
                const SizedBox(height: 6),
                Text(
                  'O matchmaking analisa seu pace médio das últimas '
                  'corridas e encontra um oponente do mesmo nível. '
                  'Vocês competem na mesma métrica, com o mesmo prazo '
                  'e mesma inscrição — garantindo uma disputa justa.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          if (_preferredParkName != null)
            Padding(
              padding: const EdgeInsets.only(top: DesignTokens.spacingSm),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: DesignTokens.spacingSm),
                decoration: BoxDecoration(
                  color: DesignTokens.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: DesignTokens.success.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.park,
                        size: 16, color: DesignTokens.success),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Prioridade: oponentes do $_preferredParkName',
                        style: const TextStyle(
                          fontSize: 12,
                          color: DesignTokens.success,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 16),

          // Metric
          Text('O que vai contar?',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SegmentedButton<ChallengeGoal>(
            segments: const [
              ButtonSegment(
                  value: ChallengeGoal.fastestAtDistance, label: Text('Mais rápido')),
              ButtonSegment(
                  value: ChallengeGoal.mostDistance, label: Text('Mais km')),
              ButtonSegment(
                  value: ChallengeGoal.bestPaceAtDistance, label: Text('Melhor pace')),
            ],
            selected: {_goal},
            onSelectionChanged: (v) => setState(() => _goal = v.first),
          ),
          const SizedBox(height: 16),

          // Target (optional)
          TextFormField(
            controller: _targetCtrl,
            decoration: InputDecoration(
              labelText: 'Meta ${_targetUnit()} (opcional)',
              border: const OutlineInputBorder(),
              helperText: 'Deixe vazio = quem fizer mais ganha',
            ),
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
            ],
          ),
          const SizedBox(height: 16),

          // Duration
          Text('Tempo para correr',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _chip('1 hora', 60),
              _chip('3 horas', 180),
              _chip('6 horas', 360),
              _chip('12 horas', 720),
              _chip('24 horas', 1440),
            ],
          ),
          const SizedBox(height: 16),

          // Entry fee
          TextFormField(
            controller: _feeCtrl,
            decoration: const InputDecoration(
              labelText: 'Inscrição (OmniCoins)',
              border: OutlineInputBorder(),
              helperText: '0 = desafio gratuito',
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Você será pareado com alguém do seu nível, '
                    'mesma métrica e mesma inscrição. Se não houver '
                    'oponente imediato, ficará na fila (expira em 24h).',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          FilledButton.icon(
            icon: const Icon(Icons.search_rounded),
            label: const Text('Buscar Oponente'),
            onPressed: _startMatchmaking,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingMd),
              textStyle: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),

          if (_assessoriaMembers.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),
            Text(
              'Desafiar colegas da assessoria',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Crie um desafio direto com alguém da sua assessoria',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            ..._assessoriaMembers.take(5).map((m) => ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingXs),
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: cs.primaryContainer,
                    child: Text(
                      (m['display_name'] as String).isNotEmpty
                          ? (m['display_name'] as String)[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: cs.primary,
                      ),
                    ),
                  ),
                  title: Text(
                    m['display_name'] as String,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  trailing: TextButton(
                    onPressed: () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute<void>(
                          builder: (_) => BlocProvider(
                            create: (_) => sl<ChallengesBloc>(),
                            child: ChallengeCreateScreen(
                              initialType: ChallengeType.oneVsOne,
                              initialGoal: _goal,
                              initialWindowMin: _windowMin,
                              initialFee: int.tryParse(_feeCtrl.text),
                            ),
                          ),
                        ),
                      );
                    },
                    child: const Text('Desafiar'),
                  ),
                )),
          ],
        ],
      ),
    );
  }

  Widget _chip(String label, int minutes) {
    final selected = _windowMin == minutes;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _windowMin = minutes),
      showCheckmark: false,
      selectedColor: Theme.of(context).colorScheme.primaryContainer,
      side: selected ? BorderSide.none : null,
      visualDensity: VisualDensity.compact,
    );
  }

  String _targetUnit() => switch (_goal) {
        ChallengeGoal.fastestAtDistance => '(km)',
        ChallengeGoal.mostDistance => '(km)',
        ChallengeGoal.bestPaceAtDistance => '(km)',
        ChallengeGoal.collectiveDistance => '(km)',
      };

  // ── Searching animation ────────────────────────────────────────────────

  Widget _buildSearching() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Center(
      key: const ValueKey('searching'),
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (_, __) {
                final scale = 1.0 + _pulseCtrl.value * 0.15;
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: cs.primaryContainer,
                      boxShadow: [
                        BoxShadow(
                          color: cs.primary.withValues(alpha: 0.3 * _pulseCtrl.value),
                          blurRadius: 30 * _pulseCtrl.value,
                          spreadRadius: 10 * _pulseCtrl.value,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.sports_mma_rounded,
                      size: 50,
                      color: cs.primary,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 32),
            Text(
              'Buscando oponente...',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (_skillBracket != null)
              Tooltip(
                message: 'Seu nível é calculado pelo pace médio '
                    'das suas últimas 10 corridas.',
                triggerMode: TooltipTriggerMode.tap,
                child: Chip(
                  avatar: Icon(Icons.trending_up, size: 16, color: cs.primary),
                  label: Text('Nível: ${_bracketLabel(_skillBracket!)}'),
                  backgroundColor: cs.surfaceContainerHighest,
                  deleteIcon: Icon(Icons.help_outline, size: 14,
                      color: cs.onSurfaceVariant),
                  onDeleted: () {},
                ),
              ),
            if (_queuePosition != null && _queuePosition! > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: DesignTokens.spacingMd, vertical: DesignTokens.spacingSm),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _queuePosition == 1
                      ? 'Você é o próximo da fila'
                      : 'Posição na fila: $_queuePosition',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.primary,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Procurando alguém com configurações compatíveis.\n'
              'Isso pode levar alguns segundos...',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              icon: const Icon(Icons.close),
              label: const Text('Cancelar busca'),
              onPressed: _cancelSearch,
            ),
          ],
        ),
      ),
    );
  }

  // ── Pending confirmation ───────────────────────────────────────────────

  Widget _buildPendingConfirm() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final fee = int.tryParse(_feeCtrl.text) ?? 0;

    return SingleChildScrollView(
      key: const ValueKey('pending_confirm'),
      padding: const EdgeInsets.all(DesignTokens.spacingLg),
      child: Column(
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: DesignTokens.warning,
              border: Border.all(color: DesignTokens.warning, width: 3),
            ),
            child: Icon(
              Icons.handshake_rounded,
              size: 48,
              color: DesignTokens.warning,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Oponente encontrado!',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Revise os detalhes antes de aceitar',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(DesignTokens.spacingMd),
              child: Column(
                children: [
                  _ConfirmRow(
                    icon: Icons.person,
                    label: 'Oponente',
                    value: _opponentName ?? 'Atleta',
                  ),
                  const Divider(height: 20),
                  _ConfirmRow(
                    icon: Icons.straighten,
                    label: 'Métrica',
                    value: _goalLabel(_goal),
                  ),
                  if (_targetCtrl.text.isNotEmpty) ...[
                    const Divider(height: 20),
                    _ConfirmRow(
                      icon: Icons.flag,
                      label: 'Meta',
                      value: '${_targetCtrl.text} ${_targetUnit()}',
                    ),
                  ],
                  const Divider(height: 20),
                  _ConfirmRow(
                    icon: Icons.timer,
                    label: 'Tempo para correr',
                    value: _windowLabel(_windowMin),
                  ),
                  if (fee > 0) ...[
                    const Divider(height: 20),
                    _ConfirmRow(
                      icon: Icons.toll,
                      label: 'Inscrição',
                      value: '$fee OmniCoins',
                      valueColor: DesignTokens.warning,
                    ),
                  ],
                  if (_skillBracket != null) ...[
                    const Divider(height: 20),
                    _ConfirmRow(
                      icon: Icons.trending_up,
                      label: 'Nível',
                      value: _bracketLabel(_skillBracket!),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (fee > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: DesignTokens.warning,
                borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                border: Border.all(color: DesignTokens.warning),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 18, color: DesignTokens.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Ao aceitar, $fee OmniCoins serão debitados '
                      'como entrada do desafio.',
                      style: TextStyle(
                        fontSize: 12,
                        color: DesignTokens.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.check_circle),
              label: const Text('Aceitar Desafio'),
              onPressed: _acceptMatch,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingMd),
                backgroundColor: DesignTokens.success,
                textStyle: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.close),
              label: const Text('Recusar'),
              onPressed: _declineMatch,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                foregroundColor: cs.error,
                side: BorderSide(color: cs.error.withValues(alpha: 0.5)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _acceptMatch() {
    setState(() => _state = _MatchState.matched);
  }

  Future<void> _declineMatch() async {
    if (_matchedChallengeId == null) {
      setState(() => _state = _MatchState.setup);
      return;
    }

    try {
      await sl<SupabaseClient>()
          .from('challenge_participants')
          .update({'status': 'declined'})
          .eq('challenge_id', _matchedChallengeId!)
          .eq('user_id',
              sl<SupabaseClient>().auth.currentUser?.id ?? '');
    } on Exception catch (e) {
      AppLogger.warn('Decline match failed: $e', tag: _tag);
    }

    if (!mounted) return;
    setState(() {
      _state = _MatchState.setup;
      _matchedChallengeId = null;
      _opponentName = null;
    });
  }

  String _goalLabel(ChallengeGoal m) => switch (m) {
        ChallengeGoal.fastestAtDistance => 'Mais rápido',
        ChallengeGoal.mostDistance => 'Mais km',
        ChallengeGoal.bestPaceAtDistance => 'Melhor pace',
        ChallengeGoal.collectiveDistance => 'Coletivo',
      };

  String _windowLabel(int minutes) {
    if (minutes < 60) return '$minutes min';
    if (minutes < 1440) return '${minutes ~/ 60} hora${minutes >= 120 ? 's' : ''}';
    return '${minutes ~/ 1440} dia${minutes >= 2880 ? 's' : ''}';
  }

  // ── Match found ────────────────────────────────────────────────────────

  Widget _buildMatched() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Center(
      key: const ValueKey('matched'),
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: DesignTokens.success,
                border: Border.all(color: DesignTokens.success, width: 3),
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                size: 60,
                color: DesignTokens.success,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Oponente encontrado!',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: DesignTokens.success,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    backgroundColor: cs.primaryContainer,
                    child: Icon(Icons.person, color: cs.primary),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _opponentName ?? 'Oponente',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              icon: const Icon(Icons.emoji_events_rounded),
              label: const Text('Ver Desafio'),
              onPressed: _goToChallenge,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                    horizontal: DesignTokens.spacingXl, vertical: DesignTokens.spacingMd),
                textStyle: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Error ──────────────────────────────────────────────────────────────

  Widget _buildError() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Center(
      key: const ValueKey('error'),
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 64, color: cs.error),
            const SizedBox(height: 16),
            Text(
              _errorMsg ?? 'Ocorreu um erro.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(color: cs.error),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => setState(() => _state = _MatchState.setup),
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }

  String _bracketLabel(String bracket) => switch (bracket) {
        'beginner' => 'Iniciante',
        'intermediate' => 'Intermediário',
        'advanced' => 'Avançado',
        'elite' => 'Elite',
        _ => bracket,
      };
}

class _ConfirmRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _ConfirmRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: cs.onSurfaceVariant),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: cs.onSurfaceVariant)),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}
