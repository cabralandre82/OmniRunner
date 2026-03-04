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

const _tag = 'WrappedScreen';

/// OmniWrapped — retrospective "stories-style" screen.
///
/// Calls the `generate-wrapped` Edge Function, which returns (or caches)
/// aggregated stats for a period. The UI is a horizontal PageView
/// with 6 themed slides.
class WrappedScreen extends StatefulWidget {
  final String periodType;
  final String periodKey;
  final String periodLabel;

  const WrappedScreen({
    super.key,
    required this.periodType,
    required this.periodKey,
    required this.periodLabel,
  });

  @override
  State<WrappedScreen> createState() => _WrappedScreenState();
}

class _WrappedScreenState extends State<WrappedScreen> {
  final _pageCtrl = PageController();
  int _currentPage = 0;
  bool _loading = true;
  String? _error;
  String? _insufficientReason;
  Map<String, dynamic>? _data;

  static const _totalSlides = 6;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'generate-wrapped',
        body: {
          'period_type': widget.periodType,
          'period_key': widget.periodKey,
        },
      );

      final body = res.data as Map<String, dynamic>? ?? {};
      final wrapped = body['wrapped'];

      if (wrapped == null) {
        setState(() {
          _loading = false;
          _insufficientReason = body['reason'] as String? ?? 'insufficient_data';
        });
        return;
      }

      setState(() {
        _loading = false;
        _data = wrapped as Map<String, dynamic>;
      });
    } on Exception catch (e) {
      AppLogger.warn('Wrapped load failed: $e', tag: _tag);
      setState(() {
        _loading = false;
        _insufficientReason = 'no_data';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D2B),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white70),
        title: Text(
          widget.periodLabel,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Gerando sua retrospectiva...',
              style: TextStyle(color: Colors.white60, fontSize: 14),
            ),
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
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Colors.white, fontSize: 16)),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: Text(context.l10n.retry),
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
              Icon(Icons.directions_run_rounded, color: Colors.white24, size: 64),
              SizedBox(height: 16),
              Text(
                'Continue correndo!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Precisamos de pelo menos 3 corridas verificadas\nnesse período para gerar sua retrospectiva.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        PageView(
          controller: _pageCtrl,
          onPageChanged: (i) => setState(() => _currentPage = i),
          physics: const BouncingScrollPhysics(),
          children: [
            _SlideNumbers(data: _data!),
            _SlidePace(data: _data!),
            _SlideChallenges(data: _data!),
            _SlideBadges(data: _data!),
            _SlidePatterns(data: _data!),
            _SlideShare(
              data: _data!,
              periodLabel: widget.periodLabel,
            ),
          ],
        ),
        if (_currentPage == 0)
          Positioned(
            bottom: 90,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              opacity: _currentPage == 0 ? 1 : 0,
              duration: const Duration(milliseconds: 300),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Deslize para ver mais',
                      style: TextStyle(color: Colors.white38, fontSize: 13)),
                  SizedBox(width: 6),
                  Icon(Icons.chevron_right_rounded,
                      color: Colors.white38, size: 18),
                ],
              ),
            ),
          ),
        // Dots indicator
        Positioned(
          bottom: DesignTokens.spacingXxl,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              _totalSlides,
              (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingXs),
                width: i == _currentPage ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: i == _currentPage ? Colors.white : Colors.white30,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// SLIDE 1: Numbers overview
// ─────────────────────────────────────────────────────────────────────

class _SlideNumbers extends StatelessWidget {
  final Map<String, dynamic> data;
  const _SlideNumbers({required this.data});

  @override
  Widget build(BuildContext context) {
    final running = data['running'] as Map<String, dynamic>? ?? {};
    final totalKm = (running['total_distance_km'] as num?)?.toDouble() ?? 0;
    final totalSessions = running['total_sessions'] as int? ?? 0;
    final totalMin = running['total_moving_min'] as int? ?? 0;

    final hours = totalMin ~/ 60;
    final mins = totalMin % 60;
    final timeStr = hours > 0 ? '${hours}h ${mins}min' : '${mins}min';

    return _SlideContainer(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF1A237E), Color(0xFF283593)],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'SEU PERÍODO EM NÚMEROS',
            style: TextStyle(
              color: Colors.white60,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 40),
          _HeroMetric(
            value: totalKm.toStringAsFixed(1),
            unit: 'km',
            label: 'corridos',
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _SecondaryMetric(value: '$totalSessions', label: 'corridas'),
              Container(width: 1, height: 40, color: Colors.white12),
              _SecondaryMetric(value: timeStr, label: 'correndo'),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// SLIDE 2: Pace evolution
// ─────────────────────────────────────────────────────────────────────

class _SlidePace extends StatelessWidget {
  final Map<String, dynamic> data;
  const _SlidePace({required this.data});

  @override
  Widget build(BuildContext context) {
    final running = data['running'] as Map<String, dynamic>? ?? {};
    final evolution =
        (running['pace_evolution'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final improvementPct = (running['pace_improvement_pct'] as num?)?.toDouble();
    final bestPace = (running['best_pace_sec_km'] as num?)?.toDouble();

    return _SlideContainer(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF4A148C), Color(0xFF6A1B9A)],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'EVOLUÇÃO DE PACE',
            style: TextStyle(
              color: Colors.white60,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 32),
          if (evolution.length >= 2)
            SizedBox(
              height: 180,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingLg),
                child: _PaceChart(evolution: evolution),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Text(
                'Dados insuficientes para gráfico',
                style: TextStyle(color: Colors.white38, fontSize: 14),
              ),
            ),
          const SizedBox(height: 24),
          if (improvementPct != null && improvementPct > 0)
            _ImprovementBadge(pct: improvementPct)
          else if (improvementPct != null && improvementPct <= 0)
            const Text(
              'Variação de pace ao longo do período',
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
          if (bestPace != null) ...[
            const SizedBox(height: 16),
            Text(
              'Melhor pace: ${_formatPace(bestPace)}/km',
              style: const TextStyle(
                color: Colors.amberAccent,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PaceChart extends StatelessWidget {
  final List<Map<String, dynamic>> evolution;
  const _PaceChart({required this.evolution});

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[];
    for (int i = 0; i < evolution.length; i++) {
      final pace = (evolution[i]['avgPace'] as num?)?.toDouble() ?? 0;
      spots.add(FlSpot(i.toDouble(), -pace));
    }

    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b) - 20;
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) + 20;

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 50,
              getTitlesWidget: (v, _) => Text(
                _formatPace(-v),
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= evolution.length) return const SizedBox.shrink();
                final key = evolution[i]['month'] as String? ?? '';
                final parts = key.split('-');
                return Text(
                  parts.length >= 2 ? parts[1] : key,
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        minY: minY,
        maxY: maxY,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: Colors.cyanAccent,
            barWidth: 3,
            dotData: FlDotData(
              show: true,
              getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                radius: 4,
                color: Colors.cyanAccent,
                strokeColor: Colors.white24,
                strokeWidth: 1,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.cyanAccent.withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImprovementBadge extends StatelessWidget {
  final double pct;
  const _ImprovementBadge({required this.pct});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.greenAccent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.trending_up_rounded, color: Colors.greenAccent, size: 20),
          const SizedBox(width: 8),
          Text(
            'Pace melhorou ${pct.toStringAsFixed(1)}%',
            style: const TextStyle(
              color: Colors.greenAccent,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// SLIDE 3: Challenges
// ─────────────────────────────────────────────────────────────────────

class _SlideChallenges extends StatelessWidget {
  final Map<String, dynamic> data;
  const _SlideChallenges({required this.data});

  @override
  Widget build(BuildContext context) {
    final ch = data['challenges'] as Map<String, dynamic>? ?? {};
    final total = ch['total'] as int? ?? 0;
    final wins = ch['wins'] as int? ?? 0;
    final losses = ch['losses'] as int? ?? 0;
    final ties = ch['ties'] as int? ?? 0;
    final winRate = total > 0 ? (wins / total * 100).round() : 0;

    return _SlideContainer(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF880E4F), Color(0xFFC2185B)],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'SEUS DESAFIOS',
            style: TextStyle(
              color: Colors.white60,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 32),
          if (total == 0)
            const Text(
              'Nenhum desafio disputado\nnesse período',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 16),
            )
          else ...[
            if (winRate > 50)
              const Icon(Icons.emoji_events_rounded, color: Colors.amberAccent, size: 48),
            const SizedBox(height: 16),
            Text(
              'Você venceu $wins de $total',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Taxa de vitória: $winRate%',
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _SecondaryMetric(value: '$wins', label: 'vitórias'),
                _SecondaryMetric(value: '$losses', label: 'derrotas'),
                _SecondaryMetric(value: '$ties', label: 'empates'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// SLIDE 4: Badges & Progression
// ─────────────────────────────────────────────────────────────────────

class _SlideBadges extends StatelessWidget {
  final Map<String, dynamic> data;
  const _SlideBadges({required this.data});

  @override
  Widget build(BuildContext context) {
    final badges = data['badges'] as Map<String, dynamic>? ?? {};
    final badgeCount = badges['count'] as int? ?? 0;
    final progression = data['progression'] as Map<String, dynamic>? ?? {};
    final totalXp = progression['total_xp'] as int? ?? 0;
    final bestStreak = progression['best_streak'] as int? ?? 0;

    return _SlideContainer(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'CONQUISTAS',
            style: TextStyle(
              color: Colors.white60,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 32),
          if (badgeCount > 0) ...[
            const Icon(Icons.military_tech_rounded, color: Colors.amberAccent, size: 48),
            const SizedBox(height: 16),
            Text(
              '$badgeCount ${badgeCount == 1 ? 'badge desbloqueado' : 'badges desbloqueados'}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ] else
            const Text(
              'Nenhum badge novo\nnesse período',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 16),
            ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _SecondaryMetric(value: '$totalXp', label: 'XP total'),
              Container(width: 1, height: 40, color: Colors.white12),
              _SecondaryMetric(
                value: '$bestStreak',
                label: 'melhor sequência',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// SLIDE 5: Patterns / Curiosidades
// ─────────────────────────────────────────────────────────────────────

class _SlidePatterns extends StatelessWidget {
  final Map<String, dynamic> data;
  const _SlidePatterns({required this.data});

  @override
  Widget build(BuildContext context) {
    final patterns = data['patterns'] as Map<String, dynamic>? ?? {};
    final mostActiveDay = patterns['most_active_day'] as String? ?? '-';
    final mostActiveDayCount = patterns['most_active_day_count'] as int? ?? 0;
    final mostActiveHour = patterns['most_active_hour'] as int? ?? 0;
    final distribution = (patterns['day_distribution'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        [];

    final running = data['running'] as Map<String, dynamic>? ?? {};
    final longestKm = (running['longest_run_km'] as num?)?.toDouble() ?? 0;
    final bestPace = (running['best_pace_sec_km'] as num?)?.toDouble();

    final hourLabel = '${mostActiveHour.toString().padLeft(2, '0')}h';

    return _SlideContainer(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFE65100), Color(0xFFBF360C)],
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 80),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'CURIOSIDADES',
              style: TextStyle(
                color: Colors.white60,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 32),
            _CuriosityRow(
              icon: Icons.calendar_today_rounded,
              text: 'Dia favorito: $mostActiveDay ($mostActiveDayCount corridas)',
            ),
            const SizedBox(height: 12),
            _CuriosityRow(
              icon: Icons.schedule_rounded,
              text: 'Horário preferido: $hourLabel',
            ),
            const SizedBox(height: 12),
            _CuriosityRow(
              icon: Icons.straighten_rounded,
              text: 'Corrida mais longa: ${longestKm.toStringAsFixed(1)} km',
            ),
            if (bestPace != null) ...[
              const SizedBox(height: 12),
              _CuriosityRow(
                icon: Icons.speed_rounded,
                text: 'Melhor pace: ${_formatPace(bestPace)}/km',
              ),
            ],
            if (distribution.length >= 7) ...[
              const SizedBox(height: 32),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingLg),
                child: SizedBox(
                  height: 120,
                  child: _DayDistributionChart(distribution: distribution),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DayDistributionChart extends StatelessWidget {
  final List<Map<String, dynamic>> distribution;
  const _DayDistributionChart({required this.distribution});

  @override
  Widget build(BuildContext context) {
    final maxCount = distribution
        .map((d) => (d['count'] as int?) ?? 0)
        .fold<int>(0, (prev, c) => c > prev ? c : prev);

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxCount > 0 ? maxCount.toDouble() + 1 : 5,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= distribution.length) return const SizedBox.shrink();
                final name = distribution[i]['day'] as String? ?? '';
                return Text(
                  name.substring(0, 3),
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                );
              },
            ),
          ),
        ),
        barGroups: List.generate(distribution.length, (i) {
          final count = (distribution[i]['count'] as int?) ?? 0;
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: count.toDouble(),
                color: Colors.amberAccent,
                width: 20,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _CuriosityRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _CuriosityRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingXl),
      child: Row(
        children: [
          Icon(icon, color: Colors.white60, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// SLIDE 6: Share CTA
// ─────────────────────────────────────────────────────────────────────

class _SlideShare extends StatelessWidget {
  final Map<String, dynamic> data;
  final String periodLabel;
  const _SlideShare({required this.data, required this.periodLabel});

  @override
  Widget build(BuildContext context) {
    final running = data['running'] as Map<String, dynamic>? ?? {};
    final totalKm = (running['total_distance_km'] as num?)?.toDouble() ?? 0;
    final totalSessions = running['total_sessions'] as int? ?? 0;
    final bestPace = (running['best_pace_sec_km'] as num?)?.toDouble();
    final challenges = data['challenges'] as Map<String, dynamic>? ?? {};
    final wins = challenges['wins'] as int? ?? 0;
    final badges = data['badges'] as Map<String, dynamic>? ?? {};
    final badgeCount = badges['count'] as int? ?? 0;

    return _SlideContainer(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF0D47A1), Color(0xFF1565C0)],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'COMPARTILHE',
            style: TextStyle(
              color: Colors.white60,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 24),
          // Preview summary
          Container(
            margin: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingLg),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Column(
              children: [
                Text(
                  '${totalKm.toStringAsFixed(1)} km',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$totalSessions corridas',
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    if (bestPace != null)
                      _MiniStat(label: 'Pace', value: '${_formatPace(bestPace)}/km'),
                    if (wins > 0)
                      _MiniStat(label: 'Vitórias', value: '$wins'),
                    if (badgeCount > 0)
                      _MiniStat(label: 'Badges', value: '$badgeCount'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: () => _shareWrapped(context),
            icon: const Icon(Icons.share_rounded),
            label: Text(context.l10n.share),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingXl, vertical: 14),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _shareWrapped(BuildContext ctx) async {
    final running = data['running'] as Map<String, dynamic>? ?? {};
    final totalKm = (running['total_distance_km'] as num?)?.toDouble() ?? 0;
    final totalSessions = running['total_sessions'] as int? ?? 0;
    final bestPace = (running['best_pace_sec_km'] as num?)?.toDouble();
    final challenges = data['challenges'] as Map<String, dynamic>? ?? {};
    final wins = challenges['wins'] as int? ?? 0;
    final badges = data['badges'] as Map<String, dynamic>? ?? {};
    final badgeCount = badges['count'] as int? ?? 0;

    final userName = sl<UserIdentityProvider>().displayName;

    await _shareWrappedCard(
      ctx,
      periodLabel: periodLabel,
      totalKm: totalKm,
      totalSessions: totalSessions,
      bestPaceSecKm: bestPace,
      wins: wins,
      badgeCount: badgeCount,
      userName: userName,
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Shared UI components
// ─────────────────────────────────────────────────────────────────────

class _SlideContainer extends StatelessWidget {
  final Gradient gradient;
  final Widget child;
  const _SlideContainer({required this.gradient, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: gradient),
      padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingMd),
      child: SafeArea(child: child),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  final String value;
  final String unit;
  final String label;
  const _HeroMetric({required this.value, required this.unit, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 72,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                  letterSpacing: -3,
                ),
              ),
              TextSpan(
                text: ' $unit',
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 28,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 16,
            fontWeight: FontWeight.w300,
            letterSpacing: 4,
          ),
        ),
      ],
    );
  }
}

class _SecondaryMetric extends StatelessWidget {
  final String value;
  final String label;
  const _SecondaryMetric({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Share card (off-screen capture → PNG → share sheet)
// ─────────────────────────────────────────────────────────────────────

Future<void> _shareWrappedCard(
  BuildContext context, {
  required String periodLabel,
  required double totalKm,
  required int totalSessions,
  double? bestPaceSecKm,
  required int wins,
  required int badgeCount,
  String? userName,
}) async {
  final cardKey = GlobalKey();

  final overlay = OverlayEntry(
    builder: (_) => Positioned(
      left: -2000,
      top: -2000,
      child: RepaintBoundary(
        key: cardKey,
        child: _WrappedShareCardContent(
          periodLabel: periodLabel,
          totalKm: totalKm,
          totalSessions: totalSessions,
          bestPaceSecKm: bestPaceSecKm,
          wins: wins,
          badgeCount: badgeCount,
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
    final file = File('${tempDir.path}/omni_wrapped.png');
    await file.writeAsBytes(bytes);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        title: 'Minha Retrospectiva Omni Runner',
      ),
    );

    AppLogger.info('Wrapped card shared (${bytes.length} bytes)', tag: _tag);

    try {
      if (await file.exists()) await file.delete();
    } on Exception {
      // best-effort cleanup
    }
  } on Exception catch (e) {
    AppLogger.warn('Wrapped share failed: $e', tag: _tag);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível compartilhar')),
      );
    }
  } finally {
    overlay.remove();
  }
}

class _WrappedShareCardContent extends StatelessWidget {
  final String periodLabel;
  final double totalKm;
  final int totalSessions;
  final double? bestPaceSecKm;
  final int wins;
  final int badgeCount;
  final String? userName;

  const _WrappedShareCardContent({
    required this.periodLabel,
    required this.totalKm,
    required this.totalSessions,
    this.bestPaceSecKm,
    required this.wins,
    required this.badgeCount,
    this.userName,
  });

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
                Color(0xFF1A237E),
                Color(0xFF4A148C),
                Color(0xFF880E4F),
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
                    child: const Icon(Icons.auto_awesome_rounded,
                        color: Colors.amberAccent, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'OMNI WRAPPED',
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
                  const Spacer(),
                  Text(
                    periodLabel,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),

              const SizedBox(height: 28),

              // Hero distance
              Text(
                totalKm.toStringAsFixed(1),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 64,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                  letterSpacing: -2,
                ),
              ),
              const Text(
                'quilômetros',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 16,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 3,
                ),
              ),

              const SizedBox(height: 24),

              Container(height: 1, color: Colors.white.withValues(alpha: 0.15)),
              const SizedBox(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ShareMetric(label: 'CORRIDAS', value: '$totalSessions'),
                  if (bestPaceSecKm != null) ...[
                    Container(
                      width: 1,
                      height: 36,
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                    _ShareMetric(
                      label: 'MELHOR PACE',
                      value: '${_formatPace(bestPaceSecKm!)}/km',
                    ),
                  ],
                  if (wins > 0) ...[
                    Container(
                      width: 1,
                      height: 36,
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                    _ShareMetric(label: 'VITÓRIAS', value: '$wins'),
                  ],
                ],
              ),

              if (badgeCount > 0) ...[
                const SizedBox(height: 16),
                Text(
                  '$badgeCount ${badgeCount == 1 ? 'badge conquistado' : 'badges conquistados'}',
                  style: const TextStyle(color: Colors.amberAccent, fontSize: 13),
                ),
              ],

              const SizedBox(height: 24),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingMd, vertical: DesignTokens.spacingSm),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome_rounded, color: Colors.amberAccent, size: 14),
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

class _ShareMetric extends StatelessWidget {
  final String label;
  final String value;
  const _ShareMetric({required this.label, required this.value});

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

String _formatPace(double secPerKm) {
  final mins = secPerKm ~/ 60;
  final secs = (secPerKm % 60).round();
  return '$mins:${secs.toString().padLeft(2, '0')}';
}
