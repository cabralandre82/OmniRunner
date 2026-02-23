import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/presentation/blocs/tracking/tracking_bloc.dart';
import 'package:omni_runner/presentation/blocs/tracking/tracking_event.dart';
import 'package:omni_runner/presentation/blocs/tracking/tracking_state.dart';
import 'package:omni_runner/features/wearables_ble/debug_hrm_screen.dart';
import 'package:omni_runner/presentation/screens/history_screen.dart';
import 'package:omni_runner/presentation/screens/settings_screen.dart';
import 'package:omni_runner/presentation/widgets/debug_gps_point_card.dart';
import 'package:omni_runner/presentation/widgets/debug_metrics_card.dart';

/// Debug screen for GPS tracking. Displays state, metrics, and controls.
class DebugTrackingScreen extends StatelessWidget {
  const DebugTrackingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<TrackingBloc>(
      create: (_) => sl<TrackingBloc>()..add(const AppStarted()),
      child: const _DebugTrackingView(),
    );
  }
}

class _DebugTrackingView extends StatefulWidget {
  const _DebugTrackingView();

  @override
  State<_DebugTrackingView> createState() => _DebugTrackingViewState();
}

class _DebugTrackingViewState extends State<_DebugTrackingView>
    with WidgetsBindingObserver {
  @override
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); }
  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    context.read<TrackingBloc>().add(AppLifecycleChanged(isResumed: state == AppLifecycleState.resumed));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Omni Runner — Debug GPS'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.favorite),
            tooltip: 'BLE Heart Rate',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const DebugHrmScreen(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'History',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const HistoryScreen(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SettingsScreen(),
              ),
            ),
          ),
        ],
      ),
      body: BlocBuilder<TrackingBloc, TrackingState>(
        builder: (context, state) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildStateCard(state),
                const SizedBox(height: 16),
                if (state is TrackingActive)
                  DebugMetricsCard(metrics: state.metrics),
                const SizedBox(height: 8),
                _buildPointData(state),
                const Spacer(),
                _buildActions(context, state),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStateCard(TrackingState state) {
    final (label, color) = switch (state) {
      TrackingIdle() => ('IDLE', Colors.grey),
      TrackingNeedsPermission() => ('NEEDS PERMISSION', Colors.orange),
      TrackingActive() => ('TRACKING', Colors.green),
      TrackingError() => ('ERROR', Colors.red),
    };

    return Card(
      color: color.withAlpha(30),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            if (state is TrackingNeedsPermission)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  state.message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            if (state is TrackingError)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  state.message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: Colors.red),
                ),
              ),
            if (state is TrackingActive)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Points collected: ${state.pointsCount}',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPointData(TrackingState state) {
    if (state is! TrackingActive || state.points.isEmpty) {
      return const DebugGpsPointCard();
    }
    return DebugGpsPointCard(point: state.points.last);
  }

  Widget _buildActions(BuildContext context, TrackingState state) {
    final bloc = context.read<TrackingBloc>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state is TrackingNeedsPermission && state.canRetry)
          FilledButton.icon(
            onPressed: () => bloc.add(const RequestPermission()),
            icon: const Icon(Icons.lock_open),
            label: const Text('Request Permission'),
          ),
        if (state is TrackingIdle) ...[
          FilledButton.icon(
            onPressed: () => bloc.add(const StartTracking()),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start Tracking'),
          ),
        ],
        if (state is TrackingActive)
          FilledButton.icon(
            onPressed: () => bloc.add(const StopTracking()),
            icon: const Icon(Icons.stop),
            label: const Text('Stop Tracking'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
          ),
        if (state is TrackingError)
          FilledButton.icon(
            onPressed: () => bloc.add(const AppStarted()),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
      ],
    );
  }
}
