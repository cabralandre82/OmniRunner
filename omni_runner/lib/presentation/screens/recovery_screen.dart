import 'package:flutter/material.dart';

import 'package:omni_runner/core/utils/format_pace.dart';
import 'package:omni_runner/domain/entities/workout_metrics_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';
import 'package:omni_runner/domain/usecases/recover_active_session.dart';
import 'package:omni_runner/l10n/l10n.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

/// Screen shown when a previous active session is found on app start.
///
/// Displays session summary (status, distance, pace, points) and offers
/// two actions: Resume or Discard.
class RecoveryScreen extends StatelessWidget {
  final RecoveredSession recovery;
  final VoidCallback onResume;
  final VoidCallback onDiscard;

  const RecoveryScreen({
    super.key,
    required this.recovery,
    required this.onResume,
    required this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = recovery.session;
    final metrics = recovery.metrics;
    final isRunning = session.status == WorkoutStatus.running;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.recoverSession),
        backgroundColor: theme.colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.history,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Sessão anterior detectada',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              isRunning
                  ? 'Uma corrida estava em andamento quando o app fechou.'
                  : 'Uma corrida pausada foi encontrada.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            _buildSummaryCard(context, metrics),
            const Spacer(),
            FilledButton.icon(
              onPressed: onResume,
              icon: const Icon(Icons.save),
              label: const Text('Salvar e continuar'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingMd),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _confirmDiscard(context),
              icon: const Icon(Icons.delete_outline),
              label: Text(context.l10n.discardSession),
              style: OutlinedButton.styleFrom(
                foregroundColor: DesignTokens.error,
                padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingMd),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context, WorkoutMetricsEntity metrics) {
    final distKm = (metrics.totalDistanceM / 1000).toStringAsFixed(2);
    final pace = formatPace(metrics.currentPaceSecPerKm);
    final pts = metrics.pointsCount;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        child: Column(
          children: [
            _row(context.l10n.distance, '$distKm km'),
            const Divider(),
            _row(context.l10n.pace, pace),
            const Divider(),
            _row('Pontos GPS', '$pts'),
            const Divider(),
            _row('Status', recovery.session.status.name.toUpperCase()),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingXs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 16)),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  void _confirmDiscard(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Descartar sessão?'),
        content: const Text(
          'Isso vai apagar permanentemente a sessão e todos os dados GPS.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              onDiscard();
            },
            style: TextButton.styleFrom(foregroundColor: DesignTokens.error),
            child: Text(context.l10n.discardRun),
          ),
        ],
      ),
    );
  }
}
