import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:omni_runner/core/router/app_router.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';
import 'package:omni_runner/l10n/l10n.dart';

/// Hub listing all gamification / progress features.
///
/// Each navigation target is wrapped with a [BlocProvider] that creates the
/// BLoC from the service locator and auto-dispatches its Load event with
/// the local user ID from [UserIdentityProvider].
class ProgressHubScreen extends StatelessWidget {
  const ProgressHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.progression),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingSm),
        children: const [
          _SectionHeader(title: 'Progresso'),
          _Tile(
            icon: Icons.trending_up,
            title: 'Nível e XP',
            subtitle: 'Seu nível, sequência e meta semanal',
            target: _Target.progression,
          ),
          _Tile(
            icon: Icons.local_fire_department_rounded,
            title: 'Sequências',
            subtitle: 'Ranking de dias consecutivos correndo',
            target: _Target.streaks,
          ),
          _Tile(
            icon: Icons.show_chart_rounded,
            title: 'Minha Evolução',
            subtitle: 'Gráficos de pace, volume e frequência',
            target: _Target.evolution,
          ),
          _Tile(
            icon: Icons.hexagon_outlined,
            title: 'Meu DNA de Corredor',
            subtitle: 'Perfil radar, insights e previsão de PR',
            target: _Target.dna,
          ),
          _Tile(
            icon: Icons.auto_awesome_rounded,
            title: 'Minha Retrospectiva',
            subtitle: 'OmniWrapped — seu resumo do período',
            target: _Target.wrapped,
          ),

          _SectionHeader(title: 'Conquistas'),
          _Tile(
            icon: Icons.military_tech,
            title: 'Badges',
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
            icon: Icons.leaderboard,
            title: 'Rankings',
            subtitle: 'Rankings semanais e mensais',
            target: _Target.leaderboards,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spacingMd,
        DesignTokens.spacingMd,
        DesignTokens.spacingMd,
        DesignTokens.spacingXs,
      ),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

enum _Target { progression, wrapped, dna, evolution, streaks, badges, missions, challenges, championships, league, wallet, leaderboards }

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
    if (target == _Target.wrapped) {
      _navigateToWrapped(context);
      return;
    }

    final route = switch (target) {
      _Target.dna => AppRoutes.runningDna,
      _Target.evolution => AppRoutes.personalEvolution,
      _Target.progression => AppRoutes.progression,
      _Target.streaks => AppRoutes.streaksLeaderboard,
      _Target.badges => AppRoutes.badges,
      _Target.missions => AppRoutes.missions,
      _Target.challenges => AppRoutes.challenges,
      _Target.championships => AppRoutes.championships,
      _Target.league => AppRoutes.league,
      _Target.wallet => AppRoutes.wallet,
      _Target.leaderboards => AppRoutes.leaderboards,
      _Target.wrapped => AppRoutes.wrapped,
    };
    context.push(route);
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
              onTap: () => ctx.pop('month'),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_month),
              title: const Text('Mês passado'),
              subtitle: Text(_monthName(now.month == 1 ? 12 : now.month - 1)),
              onTap: () => ctx.pop('last_month'),
            ),
            ListTile(
              leading: const Icon(Icons.date_range),
              title: const Text('Este trimestre'),
              subtitle: Text('Q${((now.month - 1) ~/ 3) + 1} ${now.year}'),
              onTap: () => ctx.pop('quarter'),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: const Text('Este ano'),
              subtitle: Text('${now.year}'),
              onTap: () => ctx.pop('year'),
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

    context.push(AppRoutes.wrapped, extra: WrappedExtra(
      periodType: pType,
      periodKey: pKey,
      periodLabel: pLabel,
    ));
  }

  static String _monthName(int m) => const [
        '', 'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
        'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
      ][m];

}
