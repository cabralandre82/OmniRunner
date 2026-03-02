import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/domain/entities/ledger_entry_entity.dart';
import 'package:omni_runner/presentation/blocs/wallet/wallet_bloc.dart';
import 'package:omni_runner/presentation/blocs/wallet/wallet_event.dart';
import 'package:omni_runner/presentation/blocs/wallet/wallet_state.dart';
import 'package:omni_runner/core/tips/first_use_tips.dart';
import 'package:omni_runner/l10n/l10n.dart';
import 'package:omni_runner/presentation/widgets/contextual_tip_banner.dart';
import 'package:omni_runner/presentation/widgets/shimmer_loading.dart';

enum _WalletFilter { all, earned, spent }

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  _WalletFilter _filter = _WalletFilter.all;

  List<LedgerEntryEntity> _applyFilter(List<LedgerEntryEntity> entries) {
    return switch (_filter) {
      _WalletFilter.all => entries,
      _WalletFilter.earned => entries.where((e) => e.isCredit).toList(),
      _WalletFilter.spent => entries.where((e) => !e.isCredit).toList(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.coins),
        actions: [
          IconButton(
            tooltip: context.l10n.retry,
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                context.read<WalletBloc>().add(const RefreshWallet()),
          ),
        ],
      ),
      body: BlocBuilder<WalletBloc, WalletState>(
        builder: (context, state) => switch (state) {
          WalletInitial() || WalletLoading() =>
            const ShimmerListLoader(itemCount: 5),
          WalletLoaded(:final wallet, :final history) => RefreshIndicator(
              onRefresh: () async {
                final uid = sl<UserIdentityProvider>().userId;
                context.read<WalletBloc>().add(LoadWallet(uid));
                await Future<void>.delayed(const Duration(milliseconds: 500));
              },
              child: ListView(
              children: [
                const ContextualTipBanner(
                  tipKey: TipKey.firstWalletVisit,
                  message: 'Seus OmniCoins vêm da sua assessoria. '
                      'Use-os como inscrição em desafios.',
                  icon: Icons.account_balance_wallet_rounded,
                  color: Color(0xFFFFA000),
                ),
                _BalanceCard(
                  total: wallet.totalCoins,
                  available: wallet.balanceCoins,
                  pending: wallet.pendingCoins,
                  earned: wallet.lifetimeEarnedCoins,
                  spent: wallet.lifetimeSpentCoins,
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    'Histórico',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (history.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        FilterChip(
                          label: const Text('Todos'),
                          selected: _filter == _WalletFilter.all,
                          onSelected: (_) =>
                              setState(() => _filter = _WalletFilter.all),
                        ),
                        FilterChip(
                          label: const Text('Ganhos'),
                          selected: _filter == _WalletFilter.earned,
                          onSelected: (_) =>
                              setState(() => _filter = _WalletFilter.earned),
                        ),
                        FilterChip(
                          label: const Text('Gastos'),
                          selected: _filter == _WalletFilter.spent,
                          onSelected: (_) =>
                              setState(() => _filter = _WalletFilter.spent),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                if (history.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 40),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.toll_outlined,
                              size: 56,
                              color: Theme.of(context).colorScheme.outline),
                          const SizedBox(height: 16),
                          Text(
                            'Nenhuma movimentação ainda',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Seus créditos aparecem aqui.\n'
                            'Peça ao professor da sua assessoria\n'
                            'para distribuir OmniCoins.',
                            textAlign: TextAlign.center,
                            style:
                                Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ..._applyFilter(history).map(_LedgerTile.new),
              ],
            ),
            ),
          WalletError(:final message) => Center(
              child: Text(message),
            ),
        },
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final int total;
  final int available;
  final int pending;
  final int earned;
  final int spent;

  const _BalanceCard({
    required this.total,
    required this.available,
    required this.pending,
    required this.earned,
    required this.spent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onContainer = theme.colorScheme.onPrimaryContainer;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      color: theme.colorScheme.primaryContainer,
      child: Column(
        children: [
          Text(
            'Total',
            style: theme.textTheme.titleSmall?.copyWith(color: onContainer),
          ),
          const SizedBox(height: 4),
          Text(
            '$total',
            style: theme.textTheme.displayMedium?.copyWith(
              color: onContainer,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            'OmniCoins',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: onContainer.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatChip(
                icon: Icons.check_circle_outline,
                label: 'Disponível',
                value: '$available',
                color: Colors.green,
              ),
              _StatChip(
                icon: Icons.hourglass_top,
                label: 'Pendente',
                value: '$pending',
                color: Colors.orange,
              ),
            ],
          ),
          if (pending > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16,
                      color: Colors.orange.shade800),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Coins pendentes são prêmios de desafios entre assessorias '
                      'diferentes. Serão liberados automaticamente após confirmação '
                      'do staff da assessoria adversária (até 48h).',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.orange.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _StatChip(
                icon: Icons.arrow_upward,
                label: 'Ganhos',
                value: '$earned',
                color: Colors.green,
              ),
              const SizedBox(width: 24),
              _StatChip(
                icon: Icons.arrow_downward,
                label: 'Gastos',
                value: '$spent',
                color: theme.colorScheme.error,
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
  final String value;
  final Color color;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
        ),
      ],
    );
  }
}

class _LedgerTile extends StatelessWidget {
  final LedgerEntryEntity entry;

  const _LedgerTile(this.entry);

  @override
  Widget build(BuildContext context) {
    final isCredit = entry.isCredit;
    final color = isCredit ? Colors.green : Theme.of(context).colorScheme.error;
    final sign = isCredit ? '+' : '';

    return ListTile(
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: color.withValues(alpha: 0.1),
        child: Icon(
          isCredit ? Icons.add_circle_outline : Icons.remove_circle_outline,
          color: color,
          size: 20,
        ),
      ),
      title: Text(_reasonLabel(entry.reason)),
      subtitle: Text(_formatDate(entry.createdAtMs)),
      trailing: Text(
        '$sign${entry.deltaCoins}',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );
  }

  static String _reasonLabel(LedgerReason r) => switch (r) {
        LedgerReason.sessionCompleted => 'Corrida completada',
        LedgerReason.challengeOneVsOneCompleted => 'Desafio 1v1',
        LedgerReason.challengeOneVsOneWon => 'Vitória 1v1',
        LedgerReason.challengeGroupCompleted => 'Desafio em grupo',
        LedgerReason.streakWeekly => 'Streak semanal',
        LedgerReason.streakMonthly => 'Streak mensal',
        LedgerReason.prDistance => 'Recorde de distância',
        LedgerReason.prPace => 'Recorde de pace',
        LedgerReason.challengeEntryFee => 'Inscrição no desafio',
        LedgerReason.challengePoolWon => 'Recompensa do desafio',
        LedgerReason.challengeEntryRefund => 'Devolução da inscrição',
        LedgerReason.cosmeticPurchase => 'Personalização desbloqueada',
        LedgerReason.adminAdjustment => 'Distribuição da assessoria',
        LedgerReason.badgeReward => 'Conquista desbloqueada',
        LedgerReason.missionReward => 'Missão completada',
        LedgerReason.crossAssessoriaPending => 'Pendente (entre assessorias)',
        LedgerReason.crossAssessoriaCleared => 'Liberado (confirmado entre assessorias)',
        LedgerReason.crossAssessoriaBurned => 'Expirado (troca de assessoria)',
        LedgerReason.institutionTokenIssue => 'Recebido da assessoria',
        LedgerReason.institutionTokenBurn => 'Recolhido pela assessoria',
        LedgerReason.challengeTeamCompleted => 'Desafio de equipe',
        LedgerReason.challengeTeamWon => 'Vitória em equipe',
        LedgerReason.adminCorrection => 'Ajuste de reconciliação',
      };

  static String _formatDate(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}
