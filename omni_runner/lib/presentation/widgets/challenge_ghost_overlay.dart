import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:omni_runner/presentation/blocs/tracking/tracking_bloc.dart';
import 'package:omni_runner/presentation/blocs/tracking/tracking_state.dart';
import 'package:omni_runner/presentation/widgets/challenge_ghost_provider.dart';

/// Floating overlay shown during an active challenge.
///
/// Displays:
/// - Opponent's relative distance ("X m à frente / atrás")
/// - Visual progress bars for both runners
/// - Stale/offline indicator when opponent hasn't synced recently
///
/// The overlay is compact and sits below the top bar to avoid
/// obstructing the map or bottom tracking panel.
class ChallengeGhostOverlay extends StatefulWidget {
  final ChallengeGhostProvider ghostProvider;
  final double targetDistanceM;
  final String opponentName;

  const ChallengeGhostOverlay({
    super.key,
    required this.ghostProvider,
    required this.targetDistanceM,
    required this.opponentName,
  });

  @override
  State<ChallengeGhostOverlay> createState() => _ChallengeGhostOverlayState();
}

class _ChallengeGhostOverlayState extends State<ChallengeGhostOverlay>
    with SingleTickerProviderStateMixin {
  ChallengeGhostState? _opponentState;
  StreamSubscription<ChallengeGhostState>? _sub;

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _sub = widget.ghostProvider.stream.listen((s) {
      if (mounted) setState(() => _opponentState = s);
    });

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocSelector<TrackingBloc, TrackingState, double>(
      selector: (s) {
        if (s is TrackingActive && s.metrics != null) {
          return s.metrics!.totalDistanceM;
        }
        return 0;
      },
      builder: (_, myDistanceM) {
        final opp = _opponentState;
        final oppDistM = opp?.opponentDistanceM ?? 0;
        final deltaM = myDistanceM - oppDistM;

        return AnimatedBuilder(
          animation: _pulseAnim,
          builder: (ctx, _) => _buildCard(ctx, myDistanceM, oppDistM, deltaM, opp),
        );
      },
    );
  }

  Widget _buildCard(
    BuildContext context,
    double myDistM,
    double oppDistM,
    double deltaM,
    ChallengeGhostState? opp,
  ) {
    final isAhead = deltaM >= 0;
    final absDelta = deltaM.abs();
    final target = widget.targetDistanceM;

    final myPct = target > 0 ? (myDistM / target).clamp(0.0, 1.0) : 0.0;
    final oppPct = target > 0 ? (oppDistM / target).clamp(0.0, 1.0) : 0.0;

    final statusColor = isAhead ? Colors.green : Colors.orange;
    final statusTextColor = isAhead ? Colors.green.shade800 : Colors.orange.shade800;
    final statusText = isAhead
        ? 'Você está ${_fmtDist(absDelta)} à frente'
        : 'Você está ${_fmtDist(absDelta)} atrás';

    final isOffline = opp?.isOffline ?? true;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(30),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: statusColor.withAlpha((200 * _pulseAnim.value).round()),
          width: 1.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                isAhead ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                color: statusColor,
                size: 20,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: statusTextColor,
                  ),
                ),
              ),
              if (isOffline) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: 'Último sync há mais de 2 min',
                  child: Icon(
                    Icons.cloud_off_rounded,
                    size: 16,
                    color: Colors.grey.shade400,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          _ProgressRow(
            label: 'Você',
            pct: myPct,
            distM: myDistM,
            color: Colors.blue,
            isYou: true,
          ),
          const SizedBox(height: 4),
          _ProgressRow(
            label: _shortName(widget.opponentName),
            pct: oppPct,
            distM: oppDistM,
            color: Colors.purple,
            isYou: false,
            isStale: isOffline,
          ),
          if (target > 0) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Meta: ${_fmtDist(target)}',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _fmtDist(double m) {
    if (m >= 1000) return '${(m / 1000).toStringAsFixed(1)} km';
    return '${m.toStringAsFixed(0)} m';
  }

  static String _shortName(String name) {
    if (name.length <= 12) return name;
    return '${name.substring(0, 10)}…';
  }
}

class _ProgressRow extends StatelessWidget {
  final String label;
  final double pct;
  final double distM;
  final Color color;
  final bool isYou;
  final bool isStale;

  const _ProgressRow({
    required this.label,
    required this.pct,
    required this.distM,
    required this.color,
    required this.isYou,
    this.isStale = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 56,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isYou)
                Icon(Icons.person, size: 14, color: color)
              else
                Icon(Icons.directions_run, size: 14, color: color),
              const SizedBox(width: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isYou ? FontWeight.w600 : FontWeight.w400,
                  color: isStale ? Colors.grey : Colors.black87,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: math.max(pct, 0.01),
              minHeight: 8,
              backgroundColor: color.withAlpha(30),
              valueColor: AlwaysStoppedAnimation(
                isStale ? Colors.grey.shade300 : color,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 48,
          child: Text(
            _fmtDist(distM),
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 10,
              color: isStale ? Colors.grey : Colors.black54,
            ),
          ),
        ),
      ],
    );
  }

  static String _fmtDist(double m) {
    if (m >= 1000) return '${(m / 1000).toStringAsFixed(1)} km';
    return '${m.toStringAsFixed(0)} m';
  }
}
