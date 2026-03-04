import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/presentation/blocs/badges/badges_bloc.dart';
import 'package:omni_runner/presentation/blocs/badges/badges_event.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_bloc.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_event.dart';
import 'package:omni_runner/presentation/blocs/leaderboards/leaderboards_bloc.dart';
import 'package:omni_runner/presentation/blocs/missions/missions_bloc.dart';
import 'package:omni_runner/presentation/blocs/missions/missions_event.dart';
import 'package:omni_runner/presentation/blocs/progression/progression_bloc.dart';
import 'package:omni_runner/presentation/blocs/progression/progression_event.dart';
import 'package:omni_runner/presentation/blocs/wallet/wallet_bloc.dart';
import 'package:omni_runner/presentation/blocs/wallet/wallet_event.dart';
import 'package:omni_runner/presentation/blocs/assessoria_feed/assessoria_feed_bloc.dart';
import 'package:omni_runner/presentation/blocs/assessoria_feed/assessoria_feed_event.dart';
import 'package:omni_runner/presentation/screens/assessoria_feed_screen.dart';
import 'package:omni_runner/presentation/screens/athlete_championships_screen.dart';
import 'package:omni_runner/presentation/screens/badges_screen.dart';
import 'package:omni_runner/presentation/screens/challenges_list_screen.dart';
import 'package:omni_runner/presentation/screens/leaderboards_screen.dart';
import 'package:omni_runner/presentation/screens/missions_screen.dart';
import 'package:omni_runner/presentation/screens/personal_evolution_screen.dart';
import 'package:omni_runner/presentation/screens/progression_screen.dart';
import 'package:omni_runner/presentation/screens/streaks_leaderboard_screen.dart';
import 'package:omni_runner/presentation/screens/league_screen.dart';
import 'package:omni_runner/presentation/screens/running_dna_screen.dart';
import 'package:omni_runner/presentation/screens/wallet_screen.dart';
import 'package:omni_runner/presentation/screens/wrapped_screen.dart';
import 'package:omni_runner/l10n/l10n.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

/// Hub listing all gamification / progress features.
///
/// Each navigation target is wrapped with a [BlocProvider] that creates the
/// BLoC from the service locator and auto-dispatches its Load event with
/// the local user ID from [UserIdentityProvider].
class ProgressHubScreen extends StatelessWidget {
  const ProgressHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.progression),
        backgroundColor: cs.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingSm),
        children: const [
          _Tile(
            icon: Icons.trending_up,
            title: 'Nível e XP',
            subtitle: 'Seu nível, sequência e meta semanal',
            target: _Target.progression,
          ),
          _Tile(
            icon: Icons.auto_awesome_rounded,
            title: 'Minha Retrospectiva',
            subtitle: 'OmniWrapped — seu resumo do período',
            target: _Target.wrapped,
          ),
          _Tile(
            icon: Icons.hexagon_outlined,
            title: 'Meu DNA de Corredor',
            subtitle: 'Perfil radar, insights e previsão de PR',
            target: _Target.dna,
          ),
          _Tile(
            icon: Icons.show_chart_rounded,
            title: 'Minha Evolução',
            subtitle: 'Gráficos de pace, volume e frequência',
            target: _Target.evolution,
          ),
          _Tile(
            icon: Icons.local_fire_department_rounded,
            title: 'Consistência',
            subtitle: 'Ranking de dias consecutivos correndo',
            target: _Target.streaks,
          ),
          _Tile(
            icon: Icons.military_tech,
            title: 'Conquistas',
            subtitle: 'Conquistas e badges desbloqueados',
            target: _Target.badges,
          ),
          _Tile(
            icon: Icons.flag,
            title: 'Missões',
            subtitle: 'Missões diárias e semanais',
            target: _Target.missions,
          ),
          _Tile(
            icon: Icons.sports_kabaddi,
            title: 'Desafios',
            subtitle: 'Desafios 1v1 e em grupo',
            target: _Target.challenges,
          ),
          _Tile(
            icon: Icons.emoji_events_rounded,
            title: 'Campeonatos',
            subtitle: 'Competições entre assessorias',
            target: _Target.championships,
          ),
          _Tile(
            icon: Icons.shield_rounded,
            title: 'Liga de Assessorias',
            subtitle: 'Ranking entre assessorias da plataforma',
            target: _Target.league,
          ),
          _Tile(
            icon: Icons.toll_rounded,
            title: 'OmniCoins',
            subtitle: 'Créditos e movimentações',
            target: _Target.wallet,
          ),
          _Tile(
            icon: Icons.leaderboard,
            title: 'Rankings',
            subtitle: 'Rankings semanais e mensais',
            target: _Target.leaderboards,
          ),
          _Tile(
            icon: Icons.forum_rounded,
            title: 'Feed da Assessoria',
            subtitle: 'Atividades recentes do seu grupo',
            target: _Target.feed,
          ),
        ],
      ),
    );
  }
}

enum _Target { progression, wrapped, dna, evolution, streaks, badges, missions, challenges, championships, league, wallet, leaderboards, feed }

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final _Target target;

  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.target,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _navigate(context),
    );
  }

  void _navigate(BuildContext context) {
    if (target == _Target.feed) {
      _navigateToFeed(context);
      return;
    }

    if (target == _Target.wrapped) {
      _navigateToWrapped(context);
      return;
    }

    final uid = sl<UserIdentityProvider>().userId;
    final Widget page = switch (target) {
      _Target.dna => const RunningDnaScreen(),
      _Target.evolution => const PersonalEvolutionScreen(),
      _Target.progression => BlocProvider<ProgressionBloc>(
          create: (_) => sl<ProgressionBloc>()..add(LoadProgression(uid)),
          child: const ProgressionScreen(),
        ),
      _Target.streaks => const StreaksLeaderboardScreen(),
      _Target.badges => BlocProvider<BadgesBloc>(
          create: (_) => sl<BadgesBloc>()..add(LoadBadges(uid)),
          child: const BadgesScreen(),
        ),
      _Target.missions => BlocProvider<MissionsBloc>(
          create: (_) => sl<MissionsBloc>()..add(LoadMissions(uid)),
          child: const MissionsScreen(),
        ),
      _Target.challenges => BlocProvider<ChallengesBloc>(
          create: (_) => sl<ChallengesBloc>()..add(LoadChallenges(uid)),
          child: const ChallengesListScreen(),
        ),
      _Target.championships => const AthleteChampionshipsScreen(),
      _Target.league => const LeagueScreen(),
      _Target.wallet => BlocProvider<WalletBloc>(
          create: (_) => sl<WalletBloc>()..add(LoadWallet(uid)),
          child: const WalletScreen(),
        ),
      _Target.leaderboards => BlocProvider<LeaderboardsBloc>(
          create: (_) => sl<LeaderboardsBloc>(),
          child: const LeaderboardsScreen(),
        ),
      _Target.wrapped => const SizedBox.shrink(),
      _Target.feed => const SizedBox.shrink(),
    };
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  Future<void> _navigateToWrapped(BuildContext context) async {
    final now = DateTime.now();
    final periodType = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(DesignTokens.spacingMd),
              child: Text(
                'Escolha o período',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_month),
              title: const Text('Este mês'),
              subtitle: Text(_monthName(now.month)),
              onTap: () => Navigator.pop(ctx, 'month'),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_month),
              title: const Text('Mês passado'),
              subtitle: Text(_monthName(now.month == 1 ? 12 : now.month - 1)),
              onTap: () => Navigator.pop(ctx, 'last_month'),
            ),
            ListTile(
              leading: const Icon(Icons.date_range),
              title: const Text('Este trimestre'),
              subtitle: Text('Q${((now.month - 1) ~/ 3) + 1} ${now.year}'),
              onTap: () => Navigator.pop(ctx, 'quarter'),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: const Text('Este ano'),
              subtitle: Text('${now.year}'),
              onTap: () => Navigator.pop(ctx, 'year'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (periodType == null || !context.mounted) return;

    String pType;
    String pKey;
    String pLabel;

    switch (periodType) {
      case 'month':
        pType = 'month';
        pKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';
        pLabel = '${_monthName(now.month)} ${now.year}';
      case 'last_month':
        final lm = now.month == 1 ? 12 : now.month - 1;
        final ly = now.month == 1 ? now.year - 1 : now.year;
        pType = 'month';
        pKey = '$ly-${lm.toString().padLeft(2, '0')}';
        pLabel = '${_monthName(lm)} $ly';
      case 'quarter':
        final q = ((now.month - 1) ~/ 3) + 1;
        pType = 'quarter';
        pKey = '${now.year}-Q$q';
        pLabel = 'Q$q ${now.year}';
      case 'year':
        pType = 'year';
        pKey = '${now.year}';
        pLabel = 'Ano ${now.year}';
      default:
        return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WrappedScreen(
          periodType: pType,
          periodKey: pKey,
          periodLabel: pLabel,
        ),
      ),
    );
  }

  static String _monthName(int m) => const [
        '', 'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
        'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
      ][m];

  Future<void> _navigateToFeed(BuildContext context) async {
    final nav = Navigator.of(context);
    final scaffold = ScaffoldMessenger.of(context);
    final uid = sl<UserIdentityProvider>().userId;

    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('active_coaching_group_id')
          .eq('id', uid)
          .maybeSingle();

      final groupId =
          row?['active_coaching_group_id'] as String?;

      if (groupId == null || groupId.isEmpty) {
        scaffold.showSnackBar(const SnackBar(
          content: Text('Você não está em nenhuma assessoria'),
        ));
        return;
      }

      final page = BlocProvider<AssessoriaFeedBloc>(
        create: (_) => sl<AssessoriaFeedBloc>()..add(LoadFeed(groupId)),
        child: const AssessoriaFeedScreen(),
      );
      nav.push(MaterialPageRoute<void>(builder: (_) => page));
    } on Exception {
      scaffold.showSnackBar(const SnackBar(
        content: Text('Erro ao carregar assessoria'),
      ));
    }
  }
}
