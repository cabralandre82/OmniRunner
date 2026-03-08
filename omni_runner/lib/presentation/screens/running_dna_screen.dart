import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/l10n/l10n.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

const _tag = 'RunningDnaScreen';

/// Running DNA — 6-axis radar profile of the athlete.
///
/// Calls `generate-running-dna` EF which returns (or caches) the
/// athlete's radar scores, natural-language insights, and PR predictions.
class RunningDnaScreen extends StatefulWidget {
  const RunningDnaScreen({super.key});

  @override
  State<RunningDnaScreen> createState() => _RunningDnaScreenState();
}

class _RunningDnaScreenState extends State<RunningDnaScreen> {
  bool _loading = true;
  String? _error;
  String? _insufficientReason;
  Map<String, dynamic>? _data;
  bool _isPreview = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await sl<SupabaseClient>().functions.invoke(
        'generate-running-dna',
        body: {},
      ).timeout(const Duration(seconds: 15));

      final body = res.data as Map<String, dynamic>? ?? {};
      final dna = body['dna'];

      if (dna == null) {
        setState(() {
          _loading = false;
          _insufficientReason =
              body['reason'] as String? ?? 'insufficient_data';
        });
        return;
      }

      setState(() {
        _loading = false;
        _data = dna as Map<String, dynamic>;
        _isPreview = body['preview'] as bool? ?? false;
      });
    } on TimeoutException {
      AppLogger.warn('DNA load timed out', tag: _tag);
      setState(() {
        _loading = false;
        _error = 'A requisição demorou demais. Tente novamente.';
      });
    } on Exception catch (e) {
      AppLogger.warn('DNA load failed: $e', tag: _tag);
      setState(() {
        _loading = false;
        _error = 'Algo deu errado. Tente novamente.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.myRunnerDna),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar DNA',
            onPressed: _load,
          ),
        ],
      ),
      body: _buildBody(cs),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Analisando seus dados...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spacingXl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: cs.error),
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: cs.error)),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    if (_insufficientReason != null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(DesignTokens.spacingXl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.science_outlined, size: 64, color: DesignTokens.textMuted),
              SizedBox(height: 16),
              Text(
                'Continue correndo!',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Precisamos de pelo menos 3 corridas verificadas\npara gerar seu perfil preliminar.',
                textAlign: TextAlign.center,
                style: TextStyle(color: DesignTokens.textMuted),
              ),
            ],
          ),
        ),
      );
    }

    final radar = _data!['radar_scores'] as Map<String, dynamic>? ?? {};
    final insights =
        (_data!['insights'] as List<dynamic>?)?.cast<String>() ?? [];
    final predictions = (_data!['pr_predictions'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    final stats = _data!['stats'] as Map<String, dynamic>? ?? {};

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: DesignTokens.spacingXxl),
        children: [
          if (_isPreview)
            Container(
              margin: const EdgeInsets.fromLTRB(
                DesignTokens.spacingMd, DesignTokens.spacingMd,
                DesignTokens.spacingMd, 0,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.spacingMd,
                vertical: DesignTokens.spacingSm,
              ),
              decoration: BoxDecoration(
                color: DesignTokens.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                border: Border.all(
                  color: DesignTokens.warning.withValues(alpha: 0.4),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 20, color: DesignTokens.warning),
                  SizedBox(width: DesignTokens.spacingSm),
                  Expanded(
                    child: Text(
                      'Perfil preliminar — Complete 10 corridas para DNA completo',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: DesignTokens.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          _RadarCard(scores: radar),
          _ScoresBreakdown(scores: radar),
          if (insights.isNotEmpty) _InsightsCard(insights: insights),
          if (predictions.isNotEmpty) _PrPredictionsCard(predictions: predictions),
          _StatsCard(stats: stats),
          _ShareButton(data: _data!),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Radar chart card
// ─────────────────────────────────────────────────────────────────────

class _RadarCard extends StatelessWidget {
  final Map<String, dynamic> scores;
  const _RadarCard({required this.scores});

  static const _axes = [
    ('speed', 'Velocidade'),
    ('endurance', 'Resistência'),
    ('consistency', 'Consistência'),
    ('evolution', 'Evolução'),
    ('versatility', 'Versatilidade'),
    ('competitiveness', 'Competitividade'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final values = _axes.map((a) => (scores[a.$1] as num?)?.toDouble() ?? 0).toList();

    return Card(
      margin: const EdgeInsets.all(DesignTokens.spacingMd),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.hexagon_outlined, color: cs.primary),
                const SizedBox(width: 8),
                const Text(
                  'Seu DNA',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 260,
              child: RadarChart(
                RadarChartData(
                  radarTouchData: RadarTouchData(enabled: false),
                  dataSets: [
                    RadarDataSet(
                      dataEntries:
                          values.map((v) => RadarEntry(value: v)).toList(),
                      fillColor: cs.primary.withValues(alpha: 0.2),
                      borderColor: cs.primary,
                      borderWidth: 2.5,
                      entryRadius: 3,
                    ),
                  ],
                  radarBackgroundColor: Colors.transparent,
                  borderData: FlBorderData(show: false),
                  radarBorderData:
                      BorderSide(color: cs.outlineVariant, width: 0.5),
                  titlePositionPercentageOffset: 0.18,
                  tickCount: 4,
                  ticksTextStyle: const TextStyle(
                      color: Colors.transparent, fontSize: 0),
                  tickBorderData:
                      BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
                  gridBorderData:
                      BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
                  getTitle: (i, _) => RadarChartTitle(
                    text: _axes[i].$2,
                    angle: 0,
                  ),
                  titleTextStyle: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Scores breakdown
// ─────────────────────────────────────────────────────────────────────

class _ScoresBreakdown extends StatelessWidget {
  final Map<String, dynamic> scores;
  const _ScoresBreakdown({required this.scores});

  static const _axes = [
    ('speed', 'Velocidade', Icons.speed_rounded, 'Pace médio e sprints'),
    ('endurance', 'Resistência', Icons.straighten_rounded, 'Distâncias longas e volume'),
    ('consistency', 'Consistência', Icons.calendar_month_rounded, 'Frequência e regularidade'),
    ('evolution', 'Evolução', Icons.trending_up_rounded, 'Melhora ao longo do tempo'),
    ('versatility', 'Versatilidade', Icons.shuffle_rounded, 'Variedade de distâncias e terrenos'),
    ('competitiveness', 'Competitividade', Icons.emoji_events_rounded, 'Desempenho em desafios'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingMd, vertical: DesignTokens.spacingXs),
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _axes.map((a) {
            final value = (scores[a.$1] as num?)?.toDouble() ?? 0;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(a.$3, size: 18, color: cs.primary),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 110,
                        child: Text(
                          a.$2,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: value / 100,
                            minHeight: 8,
                            backgroundColor: cs.surfaceContainerHighest,
                            color: _barColor(value),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 72,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              '${value.round()}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _barColor(value),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _levelLabel(value),
                              style: TextStyle(
                                fontSize: 9,
                                color: _barColor(value).withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 26, top: 2),
                    child: Text(
                      a.$4,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Color _barColor(double v) {
    if (v >= 80) return DesignTokens.success;
    if (v >= 60) return DesignTokens.success;
    if (v >= 40) return DesignTokens.warning;
    if (v >= 20) return DesignTokens.warning;
    return Colors.redAccent;
  }

  static String _levelLabel(double v) {
    if (v >= 80) return 'Elite';
    if (v >= 60) return 'Avançado';
    if (v >= 40) return 'Intermediário';
    if (v >= 20) return 'Iniciante';
    return 'Iniciante';
  }
}

// ─────────────────────────────────────────────────────────────────────
// Insights card
// ─────────────────────────────────────────────────────────────────────

class _InsightsCard extends StatelessWidget {
  final List<String> insights;
  const _InsightsCard({required this.insights});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingMd, vertical: DesignTokens.spacingXs),
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lightbulb_outline_rounded, color: cs.tertiary),
                const SizedBox(width: 8),
                const Text(
                  'Insights',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...insights.map(
              (i) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ', style: TextStyle(color: cs.tertiary, fontSize: 16)),
                    Expanded(
                      child: Text(i, style: const TextStyle(fontSize: 14)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// PR predictions card
// ─────────────────────────────────────────────────────────────────────

class _PrPredictionsCard extends StatelessWidget {
  final List<Map<String, dynamic>> predictions;
  const _PrPredictionsCard({required this.predictions});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingMd, vertical: DesignTokens.spacingXs),
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.track_changes_rounded, color: cs.secondary),
                const SizedBox(width: 8),
                const Text(
                  'Previsão de PR',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...predictions.map((p) => _PrRow(prediction: p)),
          ],
        ),
      ),
    );
  }
}

class _PrRow extends StatelessWidget {
  final Map<String, dynamic> prediction;
  const _PrRow({required this.prediction});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = prediction['distance_label'] as String? ?? '';
    final currentBest =
        (prediction['current_best_pace'] as num?)?.toDouble() ?? 0;
    final weeksToPr = prediction['weeks_to_pr'] as int?;
    final confidence = prediction['confidence'] as int? ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              Text(
                'Atual: ${_formatPace(currentBest)}/km',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: DesignTokens.spacingSm, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                ),
                child: Text(
                  '$confidence%',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (weeksToPr != null)
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    width: 120,
                    height: 6,
                    child: LinearProgressIndicator(
                      value: confidence / 100,
                      backgroundColor: cs.surfaceContainerHighest,
                      color: cs.secondary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'PR previsto em ~$weeksToPr ${weeksToPr == 1 ? "semana" : "semanas"}',
                  style: TextStyle(fontSize: 12, color: cs.secondary),
                ),
              ],
            )
          else
            Text(
              'Dados insuficientes para previsão',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Stats card
// ─────────────────────────────────────────────────────────────────────

class _StatsCard extends StatelessWidget {
  final Map<String, dynamic> stats;
  const _StatsCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sessions = stats['sessions_analyzed'] as int? ?? 0;
    final totalKm = (stats['total_km'] as num?)?.toDouble() ?? 0;
    final avgPerWeek = (stats['avg_sessions_per_week'] as num?)?.toDouble() ?? 0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingMd, vertical: DesignTokens.spacingXs),
      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Base de análise — ${_dateRange()}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatChip(value: '$sessions', label: 'sessões'),
                _StatChip(
                    value: '${totalKm.toStringAsFixed(0)} km', label: 'total'),
                _StatChip(
                    value: '${avgPerWeek.toStringAsFixed(1)}/sem',
                    label: 'frequência'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String value;
  final String label;
  const _StatChip({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        Text(label,
            style: const TextStyle(fontSize: 11, color: DesignTokens.textMuted)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Share button + share card
// ─────────────────────────────────────────────────────────────────────

class _ShareButton extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ShareButton({required this.data});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingMd, vertical: 12),
      child: FilledButton.icon(
        onPressed: () => _shareDna(context),
        icon: const Icon(Icons.share_rounded),
        label: const Text('Compartilhar meu DNA'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Future<void> _shareDna(BuildContext ctx) async {
    final radar = data['radar_scores'] as Map<String, dynamic>? ?? {};
    final stats = data['stats'] as Map<String, dynamic>? ?? {};
    final userName = sl<UserIdentityProvider>().displayName;

    await _shareDnaCard(
      ctx,
      scores: radar,
      totalKm: (stats['total_km'] as num?)?.toDouble() ?? 0,
      totalSessions: stats['sessions_analyzed'] as int? ?? 0,
      userName: userName,
    );
  }
}

Future<void> _shareDnaCard(
  BuildContext context, {
  required Map<String, dynamic> scores,
  required double totalKm,
  required int totalSessions,
  String? userName,
}) async {
  final cardKey = GlobalKey();

  final overlay = OverlayEntry(
    builder: (_) => Positioned(
      left: -2000,
      top: -2000,
      child: RepaintBoundary(
        key: cardKey,
        child: _DnaShareCardContent(
          scores: scores,
          totalKm: totalKm,
          totalSessions: totalSessions,
          userName: userName,
        ),
      ),
    ),
  );

  Overlay.of(context).insert(overlay);
  await Future<void>.delayed(const Duration(milliseconds: 200));

  try {
    final boundary =
        cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;

    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;

    final bytes = byteData.buffer.asUint8List();
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/omni_dna.png');
    await file.writeAsBytes(bytes);

    final scoresSummary = [
      'VEL ${(scores['speed'] as num?)?.round() ?? 0}',
      'RES ${(scores['endurance'] as num?)?.round() ?? 0}',
      'CON ${(scores['consistency'] as num?)?.round() ?? 0}',
      'EVO ${(scores['evolution'] as num?)?.round() ?? 0}',
      'VER ${(scores['versatility'] as num?)?.round() ?? 0}',
      'COM ${(scores['competitiveness'] as num?)?.round() ?? 0}',
    ].join(' | ');

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        title: 'Meu DNA de Corredor — Omni Runner',
        text: 'Meu DNA de Corredor no Omni Runner: $scoresSummary. '
            'Descubra o seu em https://omnirunner.app/dna',
      ),
    );

    AppLogger.info('DNA card shared (${bytes.length} bytes)', tag: _tag);

    try {
      if (await file.exists()) await file.delete();
    } on Exception {
      // best-effort cleanup
    }
  } on Exception catch (e) {
    AppLogger.warn('DNA share failed: $e', tag: _tag);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível compartilhar')),
      );
    }
  } finally {
    overlay.remove();
  }
}

class _DnaShareCardContent extends StatelessWidget {
  final Map<String, dynamic> scores;
  final double totalKm;
  final int totalSessions;
  final String? userName;

  const _DnaShareCardContent({
    required this.scores,
    required this.totalKm,
    required this.totalSessions,
    this.userName,
  });

  static const _axes = [
    ('speed', 'VEL'),
    ('endurance', 'RES'),
    ('consistency', 'CON'),
    ('evolution', 'EVO'),
    ('versatility', 'VER'),
    ('competitiveness', 'COM'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 360,
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF0D47A1),
                Color(0xFF1B5E20),
                Color(0xFF004D40),
              ],
            ),
          ),
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(DesignTokens.spacingSm),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                    ),
                    child: const Icon(Icons.hexagon_outlined,
                        color: Colors.cyanAccent, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'DNA DE CORREDOR',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 2,
                        ),
                      ),
                      if (userName != null)
                        Text(
                          userName!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Scores as horizontal bars
              ..._axes.map((a) {
                final v = (scores[a.$1] as num?)?.toDouble() ?? 0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 36,
                        child: Text(
                          a.$2,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          height: 8,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: v / 100,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.cyanAccent,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 24,
                        child: Text(
                          '${v.round()}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),

              const SizedBox(height: 20),
              Container(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.15)),
              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ShareStat(label: 'KM (6M)', value: totalKm.toStringAsFixed(0)),
                  Container(
                    width: 1,
                    height: 30,
                    color: Colors.white.withValues(alpha: 0.15),
                  ),
                  _ShareStat(label: 'CORRIDAS', value: '$totalSessions'),
                ],
              ),

              const SizedBox(height: 20),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingMd, vertical: DesignTokens.spacingSm),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.hexagon_outlined,
                        color: Colors.cyanAccent, size: 14),
                    SizedBox(width: 6),
                    Text(
                      'Omni Runner',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShareStat extends StatelessWidget {
  final String label;
  final String value;
  const _ShareStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────

String _dateRange() {
  const months = [
    '', 'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun',
    'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez',
  ];
  final now = DateTime.now();
  final sixAgo = DateTime(now.year, now.month - 6, now.day);
  return '${months[sixAgo.month]}/${sixAgo.year} – ${months[now.month]}/${now.year}';
}

String _formatPace(double secPerKm) {
  final mins = secPerKm ~/ 60;
  final secs = (secPerKm % 60).round();
  return '$mins:${secs.toString().padLeft(2, '0')}';
}
