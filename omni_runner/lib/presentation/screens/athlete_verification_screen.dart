import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/domain/entities/athlete_verification_entity.dart';
import 'package:omni_runner/core/tips/first_use_tips.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';
import 'package:omni_runner/domain/repositories/i_session_repo.dart';
import 'package:omni_runner/presentation/blocs/verification/verification_bloc.dart';
import 'package:omni_runner/presentation/widgets/contextual_tip_banner.dart';
import 'package:omni_runner/presentation/blocs/verification/verification_event.dart';
import 'package:omni_runner/presentation/blocs/verification/verification_state.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AthleteVerificationScreen extends StatelessWidget {
  const AthleteVerificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => VerificationBloc()..add(const LoadVerificationState()),
      child: Scaffold(
        appBar: AppBar(title: const Text('Verificação do Atleta')),
        body: BlocBuilder<VerificationBloc, VerificationState>(
          builder: (context, state) => switch (state) {
            VerificationLoading() =>
              const Center(child: CircularProgressIndicator()),
            VerificationLoaded(:final verification) =>
              _Body(v: verification),
            VerificationEvaluating(:final previous) =>
              previous != null
                  ? _Body(v: previous, evaluating: true)
                  : const Center(child: CircularProgressIndicator()),
            VerificationError(:final message) =>
              _ErrorView(message: message),
            VerificationInitial() =>
              const Center(child: CircularProgressIndicator()),
          },
        ),
      ),
    );
  }
}

class _Body extends StatefulWidget {
  final AthleteVerificationEntity v;
  final bool evaluating;

  const _Body({required this.v, this.evaluating = false});

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  DateTime? _lastEvalTap;
  List<WorkoutSessionEntity> _recentSessions = const [];

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    try {
      final uid = sl<UserIdentityProvider>().userId;

      // Local sessions >= 1km
      final localAll =
          await sl<ISessionRepo>().getByStatus(WorkoutStatus.completed);
      final localFiltered = localAll
          .where((s) => (s.totalDistanceM ?? 0) >= 1000)
          .toList();

      // Remote sessions >= 1km (includes Strava imports)
      List<WorkoutSessionEntity> remoteFiltered = const [];
      try {
        final db = Supabase.instance.client;
        final rows = await db
            .from('sessions')
            .select()
            .eq('user_id', uid)
            .eq('status', 3)
            .gte('total_distance_m', 1000)
            .order('start_time_ms', ascending: false)
            .limit(10);
        remoteFiltered = (rows as List).map((r) {
          return WorkoutSessionEntity(
            id: r['id'] as String,
            userId: r['user_id'] as String?,
            status: WorkoutStatus.completed,
            startTimeMs: (r['start_time_ms'] as num).toInt(),
            endTimeMs: (r['end_time_ms'] as num?)?.toInt(),
            totalDistanceM: (r['total_distance_m'] as num?)?.toDouble(),
            route: const [],
            isVerified: r['is_verified'] as bool? ?? false,
            integrityFlags: (r['integrity_flags'] as List<dynamic>?)
                    ?.cast<String>() ??
                const [],
            isSynced: true,
            avgBpm: (r['avg_bpm'] as num?)?.toInt(),
            maxBpm: (r['max_bpm'] as num?)?.toInt(),
            source: r['source'] as String? ?? 'app',
          );
        }).toList();
      } catch (_) {}

      // Merge and dedup by id, sort by most recent
      final byId = <String, WorkoutSessionEntity>{};
      for (final s in localFiltered) {
        byId[s.id] = s;
      }
      for (final s in remoteFiltered) {
        byId.putIfAbsent(s.id, () => s);
      }
      final merged = byId.values.toList()
        ..sort((a, b) => b.startTimeMs.compareTo(a.startTimeMs));

      if (mounted) {
        setState(() => _recentSessions = merged.take(10).toList());
      }
    } catch (_) {}
  }

  bool get _inCooldown {
    if (_lastEvalTap == null) return false;
    return DateTime.now().difference(_lastEvalTap!) < const Duration(seconds: 30);
  }

  AthleteVerificationEntity get v => widget.v;
  bool get evaluating => widget.evaluating;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return RefreshIndicator(
      onRefresh: () async {
        context
            .read<VerificationBloc>()
            .add(const LoadVerificationState());
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const ContextualTipBanner(
            tipKey: TipKey.firstVerificationVisit,
            message: 'Cada corrida válida te aproxima do status '
                'Verificado. Com 7 corridas, você desbloqueia '
                'desafios com OmniCoins!',
            icon: Icons.verified_user_rounded,
            color: Color(0xFF1565C0),
          ),

          // ── Status badge ─────────────────────────────────────────────
          _StatusCard(v: v),
          const SizedBox(height: 16),

          // ── Progress bar ─────────────────────────────────────────────
          _ProgressSection(v: v),
          const SizedBox(height: 16),

          // ── Checklist ────────────────────────────────────────────────
          _ChecklistCard(v: v),
          const SizedBox(height: 16),

          // ── Stats ────────────────────────────────────────────────────
          _StatsCard(v: v),
          const SizedBox(height: 16),

          // ── Recent sessions ───────────────────────────────────────────
          if (_recentSessions.isNotEmpty) ...[
            _RecentSessionsCard(sessions: _recentSessions),
            const SizedBox(height: 16),
          ],

          // ── Re-evaluate button ───────────────────────────────────────
          FilledButton.icon(
            onPressed: evaluating || _inCooldown
                ? null
                : () {
                    setState(() => _lastEvalTap = DateTime.now());
                    context
                        .read<VerificationBloc>()
                        .add(const RequestEvaluation());
                  },
            icon: evaluating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh),
            label: Text(evaluating
                ? 'Avaliando...'
                : _inCooldown
                    ? 'Aguarde 30s...'
                    : 'Reavaliar agora'),
          ),
          const SizedBox(height: 8),
          Text(
            'A avaliação é feita automaticamente após cada corrida. '
            'Use este botão se quiser atualizar manualmente.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: cs.outline),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // ── Info section ─────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.info_outline, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Text('Como funciona?',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 8),
                Text(
                  'Desafios gratuitos (0 OmniCoins) estao sempre disponíveis '
                  'para todos. Para desafios com inscrição (OmniCoins > 0), '
                  'você precisa ser um Atleta Verificado.\n\n'
                  'Complete as corridas e mantenha um bom histórico — '
                  'o sistema avalia automaticamente.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Status card
// ═════════════════════════════════════════════════════════════════════════════

class _StatusCard extends StatelessWidget {
  final AthleteVerificationEntity v;
  const _StatusCard({required this.v});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color, label, subtitle) = _statusVisual(v);

    return Card(
      elevation: 0,
      color: color.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: color,
                    )),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  static (IconData, Color, String, String) _statusVisual(
      AthleteVerificationEntity v) {
    final remaining = v.requiredValidRuns - v.validRunsCount;
    final runsMsg = remaining > 0
        ? 'Mais $remaining corrida${remaining == 1 ? '' : 's'} válida${remaining == 1 ? '' : 's'} e você estará verificado!'
        : 'Corridas suficientes! Aguarde a avaliação.';

    return switch (v.status) {
      VerificationStatus.unverified => (
          Icons.hourglass_empty,
          Colors.grey,
          'Não Verificado',
          remaining > 0
              ? 'Faça $remaining corrida${remaining == 1 ? '' : 's'} para começar a calibração.'
              : 'Complete corridas para iniciar sua verificação.',
        ),
      VerificationStatus.calibrating => (
          Icons.trending_up,
          Colors.blue,
          'Em Calibração',
          runsMsg,
        ),
      VerificationStatus.monitored => (
          Icons.visibility,
          Colors.orange,
          'Em Observação',
          'Seu score está em ${v.trustScore}/100 (mínimo: ${v.requiredTrustScore}). '
              'Continue treinando para aumentar!',
        ),
      VerificationStatus.verified => (
          Icons.verified,
          Colors.green,
          'Atleta Verificado',
          'Você pode criar e participar de desafios com inscrição!',
        ),
      VerificationStatus.downgraded => (
          Icons.warning_amber_rounded,
          Colors.red,
          'Rebaixado',
          'Problemas de integridade detectados. Continue treinando limpo para '
              'recuperar seu status.',
        ),
    };
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Progress section
// ═════════════════════════════════════════════════════════════════════════════

class _ProgressSection extends StatelessWidget {
  final AthleteVerificationEntity v;
  const _ProgressSection({required this.v});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final pct = (v.progress * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Progresso',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
            Text('$pct%',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cs.primary,
                )),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: v.progress,
            minHeight: 10,
            backgroundColor: cs.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(
              v.isVerified ? Colors.green : cs.primary,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${v.completedChecks} de ${v.totalChecks} requisitos completos',
          style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Checklist card
// ═════════════════════════════════════════════════════════════════════════════

class _ChecklistCard extends StatelessWidget {
  final AthleteVerificationEntity v;
  const _ChecklistCard({required this.v});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = v.requiredValidRuns - v.validRunsCount;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Checklist',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _CheckItem(
              label: 'Corridas válidas',
              done: v.validRunsOk,
              detail: v.validRunsOk
                  ? '${v.validRunsCount} corridas (meta atingida!)'
                  : remaining > 0
                      ? 'Faltam $remaining corrida${remaining > 1 ? "s" : ""} '
                          '(${v.validRunsCount}/${v.requiredValidRuns})'
                      : '${v.validRunsCount}/${v.requiredValidRuns}',
            ),
            _CheckItem(
              label: 'Integridade',
              done: v.integrityOk,
              detail: v.integrityOk
                  ? 'Nenhum problema recente'
                  : '${v.flaggedRunsRecent} corrida${v.flaggedRunsRecent > 1 ? "s" : ""} '
                      'com flags nos últimos 30 dias',
            ),
            _CheckItem(
              label: 'Consistência',
              done: v.baselineOk,
              detail: v.baselineOk
                  ? 'Distância média: ${(v.avgDistanceM / 1000).toStringAsFixed(1)} km'
                  : 'Corra pelo menos 3 sessões com média >= 1 km',
            ),
            _CheckItem(
              label: 'Score de confiança',
              done: v.trustOk,
              detail: '${v.trustScore}/${v.requiredTrustScore} pontos',
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckItem extends StatelessWidget {
  final String label;
  final bool done;
  final String detail;

  const _CheckItem({
    required this.label,
    required this.done,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            child: Icon(
              done ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 20,
              color: done ? Colors.green : cs.outline,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      decoration: done ? TextDecoration.lineThrough : null,
                      color: done ? cs.outline : null,
                    )),
                const SizedBox(height: 2),
                Text(detail,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Stats card
// ═════════════════════════════════════════════════════════════════════════════

class _StatsCard extends StatelessWidget {
  final AthleteVerificationEntity v;
  const _StatsCard({required this.v});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Seus números',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: _StatTile(
                  label: 'Corridas válidas',
                  value: '${v.validRunsCount}',
                ),
              ),
              Expanded(
                child: _StatTile(
                  label: 'Distância total',
                  value: '${(v.totalDistanceM / 1000).toStringAsFixed(1)} km',
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: _StatTile(
                  label: 'Média por corrida',
                  value: '${(v.avgDistanceM / 1000).toStringAsFixed(1)} km',
                ),
              ),
              Expanded(
                child: _StatTile(
                  label: 'Trust score',
                  value: '${v.trustScore}/100',
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;

  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        Text(label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline)),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Recent sessions card
// ═════════════════════════════════════════════════════════════════════════════

class _RecentSessionsCard extends StatelessWidget {
  final List<WorkoutSessionEntity> sessions;
  const _RecentSessionsCard({required this.sessions});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  'Corridas recentes',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...sessions.map((s) {
              final date =
                  DateTime.fromMillisecondsSinceEpoch(s.startTimeMs);
              final distKm = (s.totalDistanceM ?? 0) / 1000;
              final elapsed =
                  (s.endTimeMs ?? s.startTimeMs) - s.startTimeMs;
              final paceSecPerKm =
                  distKm > 0 ? elapsed / 1000 / distKm : 0.0;
              final paceMin = paceSecPerKm ~/ 60;
              final paceSec = (paceSecPerKm % 60).round();
              final durMin = elapsed ~/ 60000;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 44,
                      child: Text(
                        '${date.day}/${date.month}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.outline,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '${distKm.toStringAsFixed(2)} km',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      '$paceMin:${paceSec.toString().padLeft(2, '0')} /km',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${durMin}min',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.outline,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      s.source == 'strava'
                          ? Icons.watch
                          : Icons.phone_android,
                      size: 14,
                      color: cs.outline,
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Error view
// ═════════════════════════════════════════════════════════════════════════════

class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => context
                  .read<VerificationBloc>()
                  .add(const LoadVerificationState()),
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}
