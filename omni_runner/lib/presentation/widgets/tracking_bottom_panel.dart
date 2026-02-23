import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:omni_runner/core/utils/format_pace.dart';
import 'package:omni_runner/presentation/blocs/tracking/tracking_bloc.dart';
import 'package:omni_runner/presentation/blocs/tracking/tracking_event.dart';
import 'package:omni_runner/presentation/blocs/tracking/tracking_state.dart';

/// Bottom panel showing live metrics and an action button.
///
/// Sits at the bottom of the TrackingScreen over the map.
class TrackingBottomPanel extends StatelessWidget {
  final TrackingState state;
  const TrackingBottomPanel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.only(bottom: pad + 16, top: 16, left: 16, right: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(blurRadius: 8, color: Colors.black26)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state is TrackingActive)
            _MetricsRow(state: state as TrackingActive),
          if (state is TrackingNeedsPermission)
            Text(
              (state as TrackingNeedsPermission).message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.orange),
            ),
          if (state is TrackingError)
            Text(
              (state as TrackingError).message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
          const SizedBox(height: 12),
          _ActionButton(state: state),
        ],
      ),
    );
  }
}

/// Metrics row: distance, time, pace, and optionally HR and ghost.
class _MetricsRow extends StatelessWidget {
  final TrackingActive state;
  const _MetricsRow({required this.state});

  @override
  Widget build(BuildContext context) {
    final m = state.metrics;
    final gd = state.ghostDeltaM;
    final bpm = state.currentBpm;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _metric('Distância', _fmtDist(m?.totalDistanceM ?? 0)),
        _metric('Tempo', _fmtTime(m?.elapsedMs ?? 0)),
        _metric('Pace', formatPace(m?.currentPaceSecPerKm)),
        if (bpm != null) _hrMetric(bpm, state.hrConnectionState),
        if (gd != null) _metric('Fantasma', _fmtGhost(gd)),
      ],
    );
  }

  Widget _metric(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _hrMetric(int bpm, String? connState) {
    final color = _bpmColor(bpm);
    final isReconnecting = connState == 'reconnecting';
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isReconnecting ? Icons.heart_broken : Icons.favorite,
              size: 16,
              color: isReconnecting ? Colors.grey : color,
            ),
            const SizedBox(width: 2),
            Text(
              isReconnecting ? '--' : '$bpm',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: isReconnecting ? Colors.grey : color,
              ),
            ),
          ],
        ),
        const Text(
          'BPM',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  static Color _bpmColor(int bpm) {
    if (bpm < 100) return Colors.green.shade700;
    if (bpm < 140) return Colors.orange.shade700;
    if (bpm < 170) return Colors.deepOrange;
    return Colors.red.shade800;
  }

  static String _fmtGhost(double deltaM) {
    final s = deltaM >= 0 ? '+' : '';
    if (deltaM.abs() >= 1000) return '$s${(deltaM / 1000).toStringAsFixed(1)} km';
    return '$s${deltaM.toStringAsFixed(0)} m';
  }

  static String _fmtDist(double meters) {
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(2)} km';
    return '${meters.toStringAsFixed(0)} m';
  }

  static String _fmtTime(int ms) {
    final total = ms ~/ 1000;
    final min = total ~/ 60;
    final sec = total % 60;
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }
}

/// Context-aware action button (start / stop / retry / request).
class _ActionButton extends StatelessWidget {
  final TrackingState state;
  const _ActionButton({required this.state});

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<TrackingBloc>();
    return switch (state) {
      TrackingIdle() => _btn(
          'Iniciar corrida', Icons.play_arrow, Colors.green,
          () => bloc.add(const StartTracking()),
        ),
      TrackingNeedsPermission(canRetry: final r) => r
          ? _btn(
              'Permitir GPS', Icons.lock_open, Colors.orange,
              () => bloc.add(const RequestPermission()),
            )
          : const SizedBox.shrink(),
      TrackingActive() => _btn(
          'Parar', Icons.stop, Colors.red,
          () => bloc.add(const StopTracking()),
        ),
      TrackingError() => _btn(
          'Tentar novamente', Icons.refresh, Colors.blue,
          () => bloc.add(const AppStarted()),
        ),
    };
  }

  Widget _btn(String label, IconData icon, Color color, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}
