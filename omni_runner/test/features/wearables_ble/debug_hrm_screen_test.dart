import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:omni_runner/features/wearables_ble/heart_rate_sample.dart';
import 'package:omni_runner/features/wearables_ble/i_heart_rate_source.dart';
import 'package:omni_runner/features/wearables_ble/debug_hrm_screen.dart';

import '../../helpers/pump_app.dart';

final _sl = GetIt.instance;

class _FakeHeartRateSource implements IHeartRateSource {
  @override
  Stream<BleHrmDevice> startScan({Duration timeout = const Duration(seconds: 10)}) =>
      const Stream.empty();

  @override
  Future<void> stopScan() async {}

  @override
  Stream<HeartRateSample> connectAndListen(String deviceId) =>
      const Stream.empty();

  @override
  Future<void> disconnect() async {}

  @override
  bool get isConnected => false;

  @override
  String? get connectedDeviceName => null;

  @override
  BleHrConnectionState get connectionState => BleHrConnectionState.disconnected;

  @override
  Stream<BleHrConnectionState> get connectionStateStream =>
      StreamController<BleHrConnectionState>.broadcast().stream;

  @override
  Future<String?> get lastKnownDeviceId async => null;

  @override
  Future<String?> get lastKnownDeviceName async => null;

  @override
  Future<void> clearLastKnownDevice() async {}

  @override
  void dispose() {}
}

void main() {
  group('DebugHrmScreen', () {
    final origOnError = FlutterError.onError;

    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
      _sl.registerFactory<IHeartRateSource>(() => _FakeHeartRateSource());
    });
    tearDown(() {
      FlutterError.onError = origOnError;
      _sl.reset();
    });

    testWidgets('renders without crash', (tester) async {
      await tester.pumpApp(
        const DebugHrmScreen(),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows AppBar with correct title', (tester) async {
      await tester.pumpApp(
        const DebugHrmScreen(),
        wrapScaffold: false,
      );

      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Debug — BLE Heart Rate'), findsOneWidget);
    });

    testWidgets('shows idle state with scan button', (tester) async {
      await tester.pumpApp(
        const DebugHrmScreen(),
        wrapScaffold: false,
      );

      expect(find.text('BLE Heart Rate Monitor'), findsOneWidget);
      expect(find.text('Start Scan'), findsOneWidget);
      expect(find.byIcon(Icons.bluetooth), findsOneWidget);
    });
  });
}
