import 'package:omni_runner/features/wearables_ble/heart_rate_sample.dart';

/// Discovered BLE Heart Rate device info for UI display.
final class BleHrmDevice {
  /// Platform device identifier (opaque, unique per device).
  final String id;

  /// Advertised device name (e.g. "Polar H10 A1B2C3").
  final String name;

  /// RSSI signal strength in dBm. Lower (more negative) = farther away.
  final int rssi;

  const BleHrmDevice({
    required this.id,
    required this.name,
    required this.rssi,
  });
}

/// Current connection state of the BLE HR source.
enum BleHrConnectionState {
  /// No device connected, not attempting to connect.
  disconnected,

  /// Actively scanning for devices.
  scanning,

  /// Attempting to connect to a device.
  connecting,

  /// Connected and receiving HR data.
  connected,

  /// Lost connection, attempting automatic reconnection.
  reconnecting,
}

/// Contract for a heart rate data source with reconnection support.
///
/// Domain-facing interface. Implementation uses BLE, but domain code
/// only sees this contract and pure Dart types.
///
/// Lifecycle: [startScan] -> user picks device -> [connectAndListen] ->
///            auto-reconnect on drop -> [disconnect].
abstract interface class IHeartRateSource {
  /// Scan for nearby BLE devices advertising the Heart Rate service (0x180D).
  ///
  /// Scan stops automatically after [timeout]. Call [stopScan] to stop early.
  /// Returns a broadcast stream of discovered devices.
  Stream<BleHrmDevice> startScan({Duration timeout});

  /// Stop an active BLE scan.
  Future<void> stopScan();

  /// Connect to [deviceId] and subscribe to HR notifications.
  ///
  /// Saves the device as "last known" for future auto-reconnect.
  /// Returns a broadcast stream of [HeartRateSample].
  /// On unexpected disconnect, automatically attempts reconnection.
  /// Call [disconnect] to cleanly terminate (stops reconnection).
  Stream<HeartRateSample> connectAndListen(String deviceId);

  /// Disconnect from the currently connected device.
  ///
  /// Stops any reconnection attempts.
  /// Clears all active subscriptions.
  /// Safe to call even if not connected (no-op).
  Future<void> disconnect();

  /// Whether a device is currently connected and streaming HR data.
  bool get isConnected;

  /// Name of the currently connected device, or `null` if not connected.
  String? get connectedDeviceName;

  /// Current connection state for UI display.
  BleHrConnectionState get connectionState;

  /// Stream of connection state changes for reactive UI updates.
  Stream<BleHrConnectionState> get connectionStateStream;

  /// The last successfully connected device ID, persisted across sessions.
  ///
  /// Returns `null` if no device has been connected before.
  Future<String?> get lastKnownDeviceId;

  /// The last successfully connected device name, persisted across sessions.
  Future<String?> get lastKnownDeviceName;

  /// Clear the saved last known device.
  Future<void> clearLastKnownDevice();

  /// Dispose all resources (subscriptions, controllers, timers).
  ///
  /// Call when the source is no longer needed.
  void dispose();
}
