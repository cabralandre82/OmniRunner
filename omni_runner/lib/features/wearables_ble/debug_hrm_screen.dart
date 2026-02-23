import 'dart:async';

import 'package:flutter/material.dart';

import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/domain/failures/ble_failure.dart';
import 'package:omni_runner/domain/usecases/ensure_ble_ready.dart';
import 'package:omni_runner/features/wearables_ble/heart_rate_sample.dart';
import 'package:omni_runner/features/wearables_ble/i_heart_rate_source.dart';

/// Debug screen for BLE Heart Rate Monitor.
///
/// Flow: Check permissions -> Scan -> Select device -> Connect -> Show live BPM.
/// Supports auto-reconnect on drop and "last known device" quick-connect.
/// This screen is for development/QA only.
class DebugHrmScreen extends StatefulWidget {
  const DebugHrmScreen({super.key});

  @override
  State<DebugHrmScreen> createState() => _DebugHrmScreenState();
}

class _DebugHrmScreenState extends State<DebugHrmScreen> {
  final IHeartRateSource _hrSource = sl<IHeartRateSource>();

  // State
  _ScreenPhase _phase = _ScreenPhase.idle;
  String? _error;
  final List<BleHrmDevice> _devices = [];
  HeartRateSample? _lastSample;
  String? _connectedName;
  final List<int> _bpmHistory = [];

  // Last known device
  String? _lastKnownId;
  String? _lastKnownName;

  // Subscriptions
  StreamSubscription<BleHrmDevice>? _scanSub;
  StreamSubscription<HeartRateSample>? _hrSub;
  StreamSubscription<BleHrConnectionState>? _connStateSub;

  @override
  void initState() {
    super.initState();
    _loadLastKnownDevice();
    _listenConnectionState();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _hrSub?.cancel();
    _connStateSub?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Init helpers
  // ---------------------------------------------------------------------------

  Future<void> _loadLastKnownDevice() async {
    final id = await _hrSource.lastKnownDeviceId;
    final name = await _hrSource.lastKnownDeviceName;
    if (mounted) {
      setState(() {
        _lastKnownId = id;
        _lastKnownName = name;
      });
    }
  }

  void _listenConnectionState() {
    _connStateSub = _hrSource.connectionStateStream.listen((state) {
      if (!mounted) return;
      switch (state) {
        case BleHrConnectionState.reconnecting:
          setState(() => _phase = _ScreenPhase.reconnecting);
        case BleHrConnectionState.connected:
          if (_phase == _ScreenPhase.reconnecting) {
            setState(() => _phase = _ScreenPhase.streaming);
          }
        case BleHrConnectionState.disconnected:
          if (_phase == _ScreenPhase.reconnecting) {
            setState(() {
              _phase = _ScreenPhase.error;
              _error = 'Lost connection to $_connectedName.\n'
                  'Auto-reconnect exhausted. Tap Retry.';
            });
          }
        case BleHrConnectionState.scanning:
        case BleHrConnectionState.connecting:
          break;
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _checkPermissionsAndScan() async {
    setState(() {
      _phase = _ScreenPhase.checkingPermissions;
      _error = null;
      _devices.clear();
    });

    final failure = await sl<EnsureBleReady>().call();
    if (failure != null) {
      setState(() {
        _phase = _ScreenPhase.error;
        _error = _failureMessage(failure);
      });
      return;
    }

    _startScan();
  }

  void _startScan() {
    setState(() {
      _phase = _ScreenPhase.scanning;
      _devices.clear();
    });

    _scanSub?.cancel();
    _scanSub = _hrSource.startScan().listen(
      (device) {
        final exists = _devices.any((d) => d.id == device.id);
        if (!exists) {
          setState(() => _devices.add(device));
        } else {
          final idx = _devices.indexWhere((d) => d.id == device.id);
          setState(() => _devices[idx] = device);
        }
      },
      onError: (Object e) {
        setState(() {
          _phase = _ScreenPhase.error;
          _error = 'Scan error: $e';
        });
      },
      onDone: () {
        if (_phase == _ScreenPhase.scanning) {
          setState(() => _phase = _ScreenPhase.scanDone);
        }
      },
    );
  }

  Future<void> _connectTo(BleHrmDevice device) async {
    _scanSub?.cancel();
    await _hrSource.stopScan();

    setState(() {
      _phase = _ScreenPhase.connecting;
      _connectedName = device.name;
      _bpmHistory.clear();
      _lastSample = null;
    });

    _subscribeHr(device.id, device.name);
  }

  Future<void> _connectToLastKnown() async {
    final id = _lastKnownId;
    final name = _lastKnownName;
    if (id == null) return;

    final failure = await sl<EnsureBleReady>().call();
    if (failure != null) {
      setState(() {
        _phase = _ScreenPhase.error;
        _error = _failureMessage(failure);
      });
      return;
    }

    setState(() {
      _phase = _ScreenPhase.connecting;
      _connectedName = name ?? id;
      _bpmHistory.clear();
      _lastSample = null;
    });

    _subscribeHr(id, name ?? id);
  }

  void _subscribeHr(String deviceId, String displayName) {
    _hrSub?.cancel();
    _hrSub = _hrSource.connectAndListen(deviceId).listen(
      (sample) {
        setState(() {
          _phase = _ScreenPhase.streaming;
          _lastSample = sample;
          _connectedName = _hrSource.connectedDeviceName ?? displayName;
          _bpmHistory.add(sample.bpm);
          if (_bpmHistory.length > 60) _bpmHistory.removeAt(0);
        });
      },
      onError: (Object e) {
        if (_phase != _ScreenPhase.reconnecting) {
          setState(() {
            _phase = _ScreenPhase.error;
            _error = 'Connection error: $e';
          });
        }
      },
      onDone: () {
        if (_phase != _ScreenPhase.reconnecting) {
          setState(() {
            _phase = _ScreenPhase.idle;
            _connectedName = null;
          });
        }
      },
    );
  }

  Future<void> _disconnect() async {
    _hrSub?.cancel();
    await _hrSource.disconnect();
    await _loadLastKnownDevice();
    setState(() {
      _phase = _ScreenPhase.idle;
      _connectedName = null;
      _lastSample = null;
    });
  }

  Future<void> _clearLastDevice() async {
    await _hrSource.clearLastKnownDevice();
    setState(() {
      _lastKnownId = null;
      _lastKnownName = null;
    });
  }

  String _failureMessage(BleFailure failure) {
    return switch (failure) {
      BleNotSupported() => 'This device does not support Bluetooth LE.',
      BleAdapterOff() => 'Bluetooth is turned off. Please enable it.',
      BleScanPermissionDenied() => 'Bluetooth scan permission denied.',
      BleConnectPermissionDenied() => 'Bluetooth connect permission denied.',
      BlePermissionPermanentlyDenied() =>
        'Bluetooth permission permanently denied.\nPlease enable in Settings.',
    };
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug — BLE Heart Rate'),
        backgroundColor: Colors.red.shade100,
        actions: [
          if (_phase == _ScreenPhase.streaming ||
              _phase == _ScreenPhase.reconnecting)
            IconButton(
              icon: const Icon(Icons.link_off),
              tooltip: 'Disconnect',
              onPressed: _disconnect,
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: switch (_phase) {
          _ScreenPhase.idle => _buildIdle(),
          _ScreenPhase.checkingPermissions =>
            _buildLoading('Checking BLE permissions...'),
          _ScreenPhase.scanning => _buildScanning(),
          _ScreenPhase.scanDone => _buildScanning(),
          _ScreenPhase.connecting =>
            _buildLoading('Connecting to $_connectedName...'),
          _ScreenPhase.streaming => _buildStreaming(),
          _ScreenPhase.reconnecting => _buildReconnecting(),
          _ScreenPhase.error => _buildError(),
        },
      ),
    );
  }

  Widget _buildIdle() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bluetooth, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text(
            'BLE Heart Rate Monitor',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Scan for nearby heart rate sensors\n(Garmin HRM, Polar, Wahoo, Coros)',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: _checkPermissionsAndScan,
            icon: const Icon(Icons.bluetooth_searching),
            label: const Text('Start Scan'),
          ),
          if (_lastKnownId != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _connectToLastKnown,
              icon: const Icon(Icons.replay),
              label: Text('Reconnect: ${_lastKnownName ?? _lastKnownId}'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _clearLastDevice,
              child: const Text(
                'Clear saved device',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLoading(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(message),
        ],
      ),
    );
  }

  Widget _buildScanning() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (_phase == _ScreenPhase.scanning) ...[
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              const Text('Scanning...'),
            ] else
              const Text('Scan complete'),
            const Spacer(),
            TextButton.icon(
              onPressed: _phase == _ScreenPhase.scanning
                  ? () async {
                      _scanSub?.cancel();
                      await _hrSource.stopScan();
                      setState(() => _phase = _ScreenPhase.scanDone);
                    }
                  : _checkPermissionsAndScan,
              icon: Icon(_phase == _ScreenPhase.scanning
                  ? Icons.stop
                  : Icons.refresh),
              label: Text(
                  _phase == _ScreenPhase.scanning ? 'Stop' : 'Rescan'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_devices.isEmpty)
          const Expanded(
            child: Center(
              child: Text(
                'No HR devices found yet...',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: _devices.length,
              itemBuilder: (_, i) {
                final d = _devices[i];
                final isLastKnown = d.id == _lastKnownId;
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.favorite, color: Colors.red),
                    title: Text(d.name),
                    subtitle: Text(
                      'RSSI: ${d.rssi} dBm'
                      '${isLastKnown ? '  (last used)' : ''}',
                    ),
                    trailing: FilledButton(
                      onPressed: () => _connectTo(d),
                      child: const Text('Connect'),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildStreaming() {
    final sample = _lastSample;
    final bpm = sample?.bpm ?? 0;
    final avgBpm = _bpmHistory.isEmpty
        ? 0
        : (_bpmHistory.reduce((a, b) => a + b) / _bpmHistory.length).round();
    final minBpm =
        _bpmHistory.isEmpty ? 0 : _bpmHistory.reduce((a, b) => a < b ? a : b);
    final maxBpm =
        _bpmHistory.isEmpty ? 0 : _bpmHistory.reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: Colors.red.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.bluetooth_connected,
                    color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _connectedName ?? 'Unknown',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
                if (sample?.sensorContact == true)
                  const Chip(
                    label: Text('Contact'),
                    avatar: Icon(Icons.check_circle,
                        color: Colors.green, size: 16),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                if (sample?.sensorContact == false)
                  Chip(
                    label: const Text('No contact'),
                    avatar: Icon(Icons.warning_amber,
                        color: Colors.orange.shade700, size: 16),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Big BPM display
        Center(
          child: Column(
            children: [
              Text(
                '$bpm',
                style: TextStyle(
                  fontSize: 96,
                  fontWeight: FontWeight.w900,
                  color: _bpmColor(bpm),
                  height: 1.0,
                ),
              ),
              const Text(
                'BPM',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Stats row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _StatCol(label: 'AVG', value: '$avgBpm'),
            _StatCol(label: 'MIN', value: '$minBpm'),
            _StatCol(label: 'MAX', value: '$maxBpm'),
            _StatCol(label: 'SAMPLES', value: '${_bpmHistory.length}'),
          ],
        ),
        const SizedBox(height: 24),

        // RR intervals
        if (sample != null && sample.rrIntervalsMs.isNotEmpty) ...[
          const Text('RR Intervals (ms):',
              style: TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(sample.rrIntervalsMs.join(', ')),
          const SizedBox(height: 16),
        ],

        // Energy
        if (sample?.energyExpendedKj != null) ...[
          Text('Energy: ${sample!.energyExpendedKj} kJ'),
          const SizedBox(height: 16),
        ],

        const Spacer(),
        OutlinedButton.icon(
          onPressed: _disconnect,
          icon: const Icon(Icons.link_off),
          label: const Text('Disconnect'),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
        ),
      ],
    );
  }

  Widget _buildReconnecting() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: Colors.orange),
          const SizedBox(height: 24),
          Icon(Icons.bluetooth_searching,
              size: 48, color: Colors.orange.shade700),
          const SizedBox(height: 16),
          Text(
            'Reconnecting to $_connectedName...',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            'Connection lost. Attempting auto-reconnect.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          if (_lastSample != null)
            Text(
              'Last BPM: ${_lastSample!.bpm}',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade500,
              ),
            ),
          const SizedBox(height: 32),
          OutlinedButton.icon(
            onPressed: _disconnect,
            icon: const Icon(Icons.link_off),
            label: const Text('Stop & Disconnect'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          Text(
            _error ?? 'Unknown error',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _checkPermissionsAndScan,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Color _bpmColor(int bpm) {
    if (bpm < 100) return Colors.green.shade700;
    if (bpm < 140) return Colors.orange.shade700;
    if (bpm < 170) return Colors.deepOrange;
    return Colors.red.shade800;
  }
}

class _StatCol extends StatelessWidget {
  final String label;
  final String value;
  const _StatCol({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}

enum _ScreenPhase {
  idle,
  checkingPermissions,
  scanning,
  scanDone,
  connecting,
  streaming,
  reconnecting,
  error,
}
