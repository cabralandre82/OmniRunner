import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_rules_entity.dart';
import 'package:omni_runner/features/strava/domain/strava_auth_state.dart';
import 'package:omni_runner/features/strava/presentation/strava_connect_controller.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_bloc.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_event.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_state.dart';
import 'package:omni_runner/core/tips/first_use_tips.dart';
import 'package:omni_runner/presentation/screens/challenge_create_screen.dart';
import 'package:omni_runner/presentation/screens/challenge_details_screen.dart';
import 'package:omni_runner/presentation/screens/matchmaking_screen.dart';
import 'package:omni_runner/presentation/screens/settings_screen.dart';
import 'package:omni_runner/presentation/widgets/error_state.dart';
import 'package:omni_runner/presentation/widgets/shimmer_loading.dart';
import 'package:omni_runner/presentation/widgets/tip_banner.dart';

void _openMatchmaking(BuildContext context) async {
  final challengeId = await Navigator.of(context).push<String>(
    MaterialPageRoute<String>(
      builder: (_) => const MatchmakingScreen(),
    ),
  );
  if (challengeId != null && context.mounted) {
    final uid = sl<UserIdentityProvider>().userId;
    context.read<ChallengesBloc>().add(LoadChallenges(uid));
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BlocProvider.value(
        value: context.read<ChallengesBloc>()
          ..add(ViewChallengeDetails(challengeId)),
        child: ChallengeDetailsScreen(challengeId: challengeId),
      ),
    ));
  }
}

class ChallengesListScreen extends StatefulWidget {
  const ChallengesListScreen({super.key});

  @override
  State<ChallengesListScreen> createState() => _ChallengesListScreenState();
}

class _ChallengesListScreenState extends State<ChallengesListScreen> {
  bool _stravaConnected = true; // assume connected until proven otherwise

  @override
  void initState() {
    super.initState();
    _checkStrava();
  }

  Future<void> _checkStrava() async {
    try {
      final state = await sl<StravaConnectController>().getState();
      if (mounted) {
        setState(() => _stravaConnected = state is StravaConnected);
      }
    } on Exception catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Desafios'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sports_mma_rounded),
            tooltip: 'Encontrar oponente',
            onPressed: () => _openMatchmaking(context),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Criar desafio',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => BlocProvider.value(
                  value: context.read<ChallengesBloc>(),
                  child: const ChallengeCreateScreen(),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_stravaConnected) _StravaConnectBanner(onConnected: () {
            _checkStrava();
          }),
          Expanded(
            child: BlocBuilder<ChallengesBloc, ChallengesState>(
              builder: (context, state) => switch (state) {
                ChallengesInitial() || ChallengesLoading() =>
                  const ShimmerListLoader(),
                ChallengesLoaded(:final challenges) => challenges.isEmpty
                    ? _empty(context)
                    : _listWithTip(context, challenges),
                ChallengeCreated(:final challenge) =>
                  _list(context, [challenge]),
                ChallengeDetailLoaded() => const SizedBox.shrink(),
                ChallengesError(:final message) => ErrorState(
                    message: message,
                    onRetry: () {
                      final uid = sl<UserIdentityProvider>().userId;
                      context.read<ChallengesBloc>().add(LoadChallenges(uid));
                    },
                  ),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.emoji_events_outlined,
              size: 72,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 20),
            Text(
              'Nenhum desafio ainda',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Crie um desafio e convide corredores\npara competir com você!',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _openMatchmaking(context),
              icon: const Icon(Icons.sports_mma_rounded),
              label: const Text('Encontrar Oponente'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => BlocProvider.value(
                    value: context.read<ChallengesBloc>(),
                    child: const ChallengeCreateScreen(),
                  ),
                ),
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Criar e convidar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _listWithTip(
    BuildContext context,
    List<ChallengeEntity> challenges,
  ) {
    return RefreshIndicator(
      onRefresh: () async {
        final uid = sl<UserIdentityProvider>().userId;
        context.read<ChallengesBloc>().add(LoadChallenges(uid));
        await Future<void>.delayed(const Duration(milliseconds: 500));
      },
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TipBanner(
              tipKey: TipKey.challengeHowTo,
              icon: Icons.emoji_events_outlined,
              text: 'Toque no "+" para criar um novo desafio. '
                  'Escolha distância, pace ou tempo, defina o prazo '
                  'e convide seus amigos!',
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: TipBanner(
              tipKey: TipKey.matchmakingHowTo,
              icon: Icons.sports_mma_rounded,
              text: 'Matchmaking automático: toque no ícone de luta '
                  'para encontrar um oponente do seu nível. '
                  'O sistema analisa seu pace médio das últimas corridas '
                  'e te pareia com alguém compatível — mesma métrica, '
                  'mesma faixa de habilidade. Desafios justos e '
                  'competitivos!',
            ),
          ),
          Expanded(child: _list(context, challenges)),
        ],
      ),
    );
  }

  Widget _list(BuildContext context, List<ChallengeEntity> challenges) {
    final active = challenges
        .where((c) =>
            c.status == ChallengeStatus.pending ||
            c.status == ChallengeStatus.active ||
            c.status == ChallengeStatus.completing)
        .toList();
    final completed = challenges
        .where((c) =>
            c.status == ChallengeStatus.completed ||
            c.status == ChallengeStatus.cancelled ||
            c.status == ChallengeStatus.expired)
        .toList();

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (active.isNotEmpty) ...[
          _SectionHeader(title: 'Ativos', count: active.length),
          ...active.map((c) => _ChallengeListTile(challenge: c)),
        ],
        if (completed.isNotEmpty) ...[
          _SectionHeader(title: 'Concluídos', count: completed.length),
          ...completed.map((c) => _ChallengeListTile(challenge: c)),
        ],
      ],
    );
  }
}

class _ChallengeListTile extends StatelessWidget {
  final ChallengeEntity challenge;

  const _ChallengeListTile({required this.challenge});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _statusColor(challenge.status, theme);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: statusColor.withValues(alpha: 0.15),
        child: Icon(_statusIcon(challenge.status), color: statusColor),
      ),
      title: Text(
        challenge.title ?? _defaultTitle(challenge),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${_goalLabel(challenge.rules.goal)}'
        ' · ${challenge.acceptedCount} participantes'
        ' · ${_modeTag(challenge.rules)}'
        ' · ${_statusLabel(challenge.status)}',
      ),
      trailing: challenge.rules.entryFeeCoins > 0
          ? Chip(
              label: Text('${challenge.rules.entryFeeCoins} OmniCoins',
                  style: const TextStyle(fontSize: 11)),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            )
          : null,
      onTap: () {
        HapticFeedback.selectionClick();
        context
            .read<ChallengesBloc>()
            .add(ViewChallengeDetails(challenge.id));
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => BlocProvider.value(
              value: context.read<ChallengesBloc>(),
              child: ChallengeDetailsScreen(challengeId: challenge.id),
            ),
          ),
        );
      },
    );
  }

  static String _defaultTitle(ChallengeEntity c) => switch (c.type) {
        ChallengeType.oneVsOne => 'Desafio 1 vs 1',
        ChallengeType.group => 'Desafio em Grupo',
        ChallengeType.team => 'Desafio Time A vs B',
      };

  static String _goalLabel(ChallengeGoal m) => switch (m) {
        ChallengeGoal.fastestAtDistance => 'Menor tempo',
        ChallengeGoal.mostDistance => 'Mais km',
        ChallengeGoal.bestPaceAtDistance => 'Melhor pace',
        ChallengeGoal.collectiveDistance => 'Meta coletiva',
      };

  static String _statusLabel(ChallengeStatus s) => switch (s) {
        ChallengeStatus.pending => 'Pendente',
        ChallengeStatus.active => 'Ativo',
        ChallengeStatus.completing => 'Finalizando',
        ChallengeStatus.completed => 'Concluído',
        ChallengeStatus.cancelled => 'Cancelado',
        ChallengeStatus.expired => 'Expirado',
      };

  static IconData _statusIcon(ChallengeStatus s) => switch (s) {
        ChallengeStatus.pending => Icons.hourglass_empty,
        ChallengeStatus.active => Icons.directions_run,
        ChallengeStatus.completing => Icons.timer,
        ChallengeStatus.completed => Icons.emoji_events,
        ChallengeStatus.cancelled => Icons.cancel_outlined,
        ChallengeStatus.expired => Icons.schedule,
      };

  static Color _statusColor(ChallengeStatus s, ThemeData theme) => switch (s) {
        ChallengeStatus.pending => Colors.orange,
        ChallengeStatus.active => Colors.green,
        ChallengeStatus.completing => Colors.blue,
        ChallengeStatus.completed => Colors.teal,
        ChallengeStatus.cancelled => theme.colorScheme.error,
        ChallengeStatus.expired => Colors.grey,
      };

  static String _modeTag(ChallengeRulesEntity rules) =>
      rules.startMode == ChallengeStartMode.scheduled
          ? 'Agendado'
          : 'Imediato';
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;

  const _SectionHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Strava connection banner — shown when the athlete hasn't connected Strava
// ═══════════════════════════════════════════════════════════════════════════════

class _StravaConnectBanner extends StatelessWidget {
  final VoidCallback onConnected;

  const _StravaConnectBanner({required this.onConnected});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFC4C02).withValues(alpha: 0.12),
            const Color(0xFFFC4C02).withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFFC4C02).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFC4C02),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.watch, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Conecte o Strava para participar',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFFBF360C),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Para que suas corridas contem nos desafios, você precisa '
            'conectar o Strava. Funciona com qualquer relógio (Garmin, '
            'Coros, Apple Watch, etc.). Seus dados de GPS e frequência '
            'cardíaca são verificados pelo anti-cheat para garantir '
            'competições justas.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF5D4037),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Ao conectar, importamos suas últimas corridas '
                  'para calibrar seu nível automaticamente.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF8D6E63),
                    fontStyle: FontStyle.italic,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context)
                      .push(MaterialPageRoute<void>(
                        builder: (_) => const SettingsScreen(),
                      ))
                      .then((_) => onConnected());
                },
                icon: const Icon(Icons.link, size: 16),
                label: const Text('Conectar'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFC4C02),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  textStyle: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
