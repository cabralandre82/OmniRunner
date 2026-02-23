import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/features/wearables_ble/ble_reconnect_manager.dart';
import 'package:omni_runner/features/wearables_ble/heart_rate_sample.dart';
import 'package:omni_runner/features/wearables_ble/i_heart_rate_source.dart';
import 'package:omni_runner/features/wearables_ble/parse_heart_rate_measurement.dart';

/// BLE Heart Rate Service UUID (Bluetooth SIG standard).
const String _kHrServiceUuid = '0000180d-0000-1000-8000-00805f9b34fb';

/// Heart Rate Measurement Characteristic UUID.
const String _kHrMeasurementUuid = '00002a37-0000-1000-8000-00805f9b34fb';

/// SharedPreferences keys for last known device.
const String _kLastDeviceIdKey = 'ble_hr_last_device_id';
const String _kLastDeviceNameKey = 'ble_hr_last_device_name';

const String _tag = 'BleHR';

/// Concrete [IHeartRateSource] backed by [flutter_blue_plus].
///
/// Features:
/// - Scan with configurable timeout, filtered by HR service UUID 0x180D
/// - Connect and subscribe to HR Measurement characteristic 0x2A37
/// - Automatic reconnection with exponential backoff on unexpected disconnect
/// - Last known device persistence via SharedPreferences
/// - Proper subscription cleanup on disconnect and dispose
class BleHeartRateSource implements IHeartRateSource {
  BluetoothDevice? _device;
  String? _activeDeviceId;
  String? _activeDeviceName;

  // Subscriptions
  StreamSubscription<List<int>>? _hrCharSub;
  StreamSubscription<BluetoothConnectionState>? _connStateSub;
  StreamSubscription<List<ScanResult>>? _scanResultsSub;

  // Controllers
  StreamController<HeartRateSample>? _hrController;
  final StreamController<BleHrConnectionState> _stateController =
      StreamController<BleHrConnectionState>.broadcast();

  // Reconnection
  late final BleReconnectManager _reconnect;
  bool _intentionalDisconnect = false;
  bool _disposed = false;

  // Connection state
  BleHrConnectionState _connectionState = BleHrConnectionState.disconnected;

  BleHeartRateSource() {
    _reconnect = BleReconnectManager(
      reconnectAction: _attemptReconnect,
    )
      ..onReconnected = () {
        AppLogger.info('Auto-reconnected to $_activeDeviceName', tag: _tag);
      }
      ..onGaveUp = () {
        AppLogger.warn('Gave up reconnecting to $_activeDeviceName', tag: _tag);
        _setConnectionState(BleHrConnectionState.disconnected);
      };
  }

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  @override
  bool get isConnected => _device?.isConnected ?? false;

  @override
  String? get connectedDeviceName => isConnected ? _activeDeviceName : null;

  @override
  BleHrConnectionState get connectionState => _connectionState;

  @override
  Stream<BleHrConnectionState> get connectionStateStream =>
      _stateController.stream;

  void _setConnectionState(BleHrConnectionState state) {
    if (_connectionState == state || _disposed) return;
    _connectionState = state;
    _stateController.add(state);
  }

  // ---------------------------------------------------------------------------
  // Last Known Device
  // ---------------------------------------------------------------------------

  @override
  Future<String?> get lastKnownDeviceId async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kLastDeviceIdKey);
  }

  @override
  Future<String?> get lastKnownDeviceName async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kLastDeviceNameKey);
  }

  @override
  Future<void> clearLastKnownDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kLastDeviceIdKey);
    await prefs.remove(_kLastDeviceNameKey);
  }

  Future<void> _saveLastKnownDevice(String id, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastDeviceIdKey, id);
    await prefs.setString(_kLastDeviceNameKey, name);
  }

  // ---------------------------------------------------------------------------
  // Scan
  // ---------------------------------------------------------------------------

  @override
  Stream<BleHrmDevice> startScan({
    Duration timeout = const Duration(seconds: 15),
  }) {
    // ignore: close_sinks — closed via onCancel when caller stops listening
    final controller = StreamController<BleHrmDevice>.broadcast();
    _setConnectionState(BleHrConnectionState.scanning);

    _scanResultsSub?.cancel();
    _scanResultsSub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        final hasHr = r.advertisementData.serviceUuids.any(
          (uuid) => uuid.str.toLowerCase() == _kHrServiceUuid,
        );
        if (!hasHr) continue;

        final name = r.device.platformName.isNotEmpty
            ? r.device.platformName
            : r.advertisementData.advName;
        if (name.isEmpty) continue;

        controller.add(BleHrmDevice(
          id: r.device.remoteId.str,
          name: name,
          rssi: r.rssi,
        ));
      }
    }, onError: (Object e) {
      AppLogger.error('Scan stream error', tag: _tag, error: e);
    });

    FlutterBluePlus.startScan(
      withServices: [Guid(_kHrServiceUuid)],
      timeout: timeout,
    ).catchError((Object e) {
      AppLogger.error('startScan failed', tag: _tag, error: e);
      controller.addError(e);
    });

    controller.onCancel = () {
      _scanResultsSub?.cancel();
      _scanResultsSub = null;
      FlutterBluePlus.stopScan();
      if (_connectionState == BleHrConnectionState.scanning) {
        _setConnectionState(BleHrConnectionState.disconnected);
      }
    };

    return controller.stream;
  }

  @override
  Future<void> stopScan() async {
    _scanResultsSub?.cancel();
    _scanResultsSub = null;
    await FlutterBluePlus.stopScan();
    if (_connectionState == BleHrConnectionState.scanning) {
      _setConnectionState(BleHrConnectionState.disconnected);
    }
  }

  // ---------------------------------------------------------------------------
  // Connect + Listen
  // ---------------------------------------------------------------------------

  @override
  Stream<HeartRateSample> connectAndListen(String deviceId) {
    _cancelHrStream();
    _hrController = StreamController<HeartRateSample>.broadcast();
    _intentionalDisconnect = false;
    _activeDeviceId = deviceId;

    _connectAndSubscribe(deviceId);

    return _hrController!.stream;
  }

  Future<void> _connectAndSubscribe(String deviceId) async {
    _setConnectionState(BleHrConnectionState.connecting);
    try {
      _device = BluetoothDevice.fromId(deviceId);
      AppLogger.info('Connecting to $deviceId', tag: _tag);

      await _device!.connect(
        license: License.free,
        autoConnect: false,
        mtu: null,
      );

      _activeDeviceName =
          _device!.platformName.isNotEmpty ? _device!.platformName : deviceId;
      AppLogger.info('Connected to $_activeDeviceName', tag: _tag);

      await _saveLastKnownDevice(deviceId, _activeDeviceName!);

      final services = await _device!.discoverServices();
      final hrService = services.firstWhere(
        (s) => s.uuid.str.toLowerCase() == _kHrServiceUuid,
        orElse: () => throw StateError('HR service 0x180D not found'),
      );

      final hrChar = hrService.characteristics.firstWhere(
        (c) => c.uuid.str.toLowerCase() == _kHrMeasurementUuid,
        orElse: () => throw StateError('HR characteristic 0x2A37 not found'),
      );

      await hrChar.setNotifyValue(true);
      AppLogger.info('Subscribed to HR notifications', tag: _tag);

      _setConnectionState(BleHrConnectionState.connected);

      _hrCharSub?.cancel();
      _hrCharSub = hrChar.onValueReceived.listen(
        (value) {
          final sample = parseHeartRateMeasurement(Uint8List.fromList(value));
          if (sample != null) {
            _hrController?.add(sample);
          }
        },
        onError: (Object e) {
          AppLogger.error('HR notification error', tag: _tag, error: e);
          _hrController?.addError(e);
        },
      );

      _connStateSub?.cancel();
      _connStateSub = _device!.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _onUnexpectedDisconnect();
        }
      });
    } on Exception catch (e, st) {
      AppLogger.error('Connect failed', tag: _tag, error: e, stack: st);
      _hrController?.addError(e);
      _setConnectionState(BleHrConnectionState.disconnected);
      _cleanupBleResources();
    }
  }

  // ---------------------------------------------------------------------------
  // Reconnection
  // ---------------------------------------------------------------------------

  void _onUnexpectedDisconnect() {
    if (_intentionalDisconnect || _disposed) return;

    AppLogger.info('Unexpected disconnect from $_activeDeviceName', tag: _tag);
    _cleanupBleResources();

    final deviceId = _activeDeviceId;
    if (deviceId == null) return;

    _setConnectionState(BleHrConnectionState.reconnecting);
    _reconnect.start();
  }

  Future<bool> _attemptReconnect() async {
    final deviceId = _activeDeviceId;
    if (deviceId == null || _disposed) return false;

    try {
      _device = BluetoothDevice.fromId(deviceId);
      await _device!.connect(
        license: License.free,
        autoConnect: false,
        mtu: null,
        timeout: const Duration(seconds: 10),
      );

      _activeDeviceName =
          _device!.platformName.isNotEmpty ? _device!.platformName : deviceId;

      final services = await _device!.discoverServices();
      final hrService = services.firstWhere(
        (s) => s.uuid.str.toLowerCase() == _kHrServiceUuid,
        orElse: () => throw StateError('HR service 0x180D not found'),
      );

      final hrChar = hrService.characteristics.firstWhere(
        (c) => c.uuid.str.toLowerCase() == _kHrMeasurementUuid,
        orElse: () => throw StateError('HR characteristic 0x2A37 not found'),
      );

      await hrChar.setNotifyValue(true);

      _setConnectionState(BleHrConnectionState.connected);

      _hrCharSub?.cancel();
      _hrCharSub = hrChar.onValueReceived.listen(
        (value) {
          final sample = parseHeartRateMeasurement(Uint8List.fromList(value));
          if (sample != null) {
            _hrController?.add(sample);
          }
        },
        onError: (Object e) {
          AppLogger.error('HR notification error', tag: _tag, error: e);
          _hrController?.addError(e);
        },
      );

      _connStateSub?.cancel();
      _connStateSub = _device!.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _onUnexpectedDisconnect();
        }
      });

      return true;
    } on Exception catch (e) {
      AppLogger.warn('Reconnect attempt failed: $e', tag: _tag);
      _cleanupBleResources();
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Disconnect
  // ---------------------------------------------------------------------------

  @override
  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    _reconnect.cancel();

    final name = _activeDeviceName;

    try {
      _hrCharSub?.cancel();
      _connStateSub?.cancel();
      await _device?.disconnect();
    } on Exception catch (e) {
      AppLogger.warn('Disconnect error (non-fatal): $e', tag: _tag);
    }

    _cleanupAll();

    if (name != null) {
      AppLogger.info('Disconnected from $name', tag: _tag);
    }
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  /// Clean up BLE-level resources without closing the HR stream controller.
  void _cleanupBleResources() {
    _hrCharSub?.cancel();
    _hrCharSub = null;
    _connStateSub?.cancel();
    _connStateSub = null;
    _device = null;
  }

  /// Cancel the HR sample stream (but not the connection state stream).
  void _cancelHrStream() {
    _hrCharSub?.cancel();
    _hrCharSub = null;
    _hrController?.close();
    _hrController = null;
  }

  /// Full cleanup: BLE resources + HR stream + state reset.
  void _cleanupAll() {
    _cleanupBleResources();
    _cancelHrStream();
    _activeDeviceId = null;
    _activeDeviceName = null;
    _setConnectionState(BleHrConnectionState.disconnected);
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnect.dispose();
    _cleanupAll();
    _stateController.close();
  }
}
