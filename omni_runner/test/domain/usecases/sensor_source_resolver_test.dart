import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:omni_runner/domain/entities/health_hr_sample.dart';
import 'package:omni_runner/domain/entities/health_step_sample.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/entities/sensor_resolution.dart';
import 'package:omni_runner/domain/entities/workout_export_result.dart';
import 'package:omni_runner/domain/failures/health_failure.dart';
import 'package:omni_runner/domain/repositories/i_health_provider.dart';
import 'package:omni_runner/domain/usecases/sensor_source_resolver.dart';
import 'package:omni_runner/features/wearables_ble/heart_rate_sample.dart';
import 'package:omni_runner/features/wearables_ble/i_heart_rate_source.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class FakeBleHr implements IHeartRateSource {
  bool connectedResult;
  String? deviceName;
  String? lastDeviceId;
  String? lastDeviceName;
  BleHrConnectionState stateResult;

  FakeBleHr({
    this.connectedResult = false,
    this.deviceName,
    this.lastDeviceId,
    this.lastDeviceName,
    this.stateResult = BleHrConnectionState.disconnected,
  });

  @override
  bool get isConnected => connectedResult;
  @override
  String? get connectedDeviceName => deviceName;
  @override
  BleHrConnectionState get connectionState => stateResult;
  @override
  Stream<BleHrConnectionState> get connectionStateStream =>
      const Stream.empty();
  @override
  Future<String?> get lastKnownDeviceId async => lastDeviceId;
  @override
  Future<String?> get lastKnownDeviceName async => lastDeviceName;

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
  Future<void> clearLastKnownDevice() async {}
  @override
  void dispose() {}
}

class FakeHealthProvider implements IHealthProvider {
  bool availableResult;
  Map<HealthPermissionScope, bool> permissions;

  FakeHealthProvider({
    this.availableResult = true,
    Map<HealthPermissionScope, bool>? permissions,
  }) : permissions = permissions ??
            {
              HealthPermissionScope.readHeartRate: true,
              HealthPermissionScope.readSteps: true,
            };

  @override
  Future<bool> isAvailable() async => availableResult;

  @override
  Future<bool> hasPermissions(List<HealthPermissionScope> scopes) async {
    for (final scope in scopes) {
      if (permissions[scope] != true) return false;
    }
    return true;
  }

  @override
  Future<HealthFailure?> requestPermissions(
          List<HealthPermissionScope> scopes) async =>
      null;
  @override
  Future<List<HealthHrSample>> readHeartRate(
          {required DateTime start, required DateTime end}) async =>
      const [];
  @override
  Future<List<HealthStepSample>> readSteps(
          {required DateTime start, required DateTime end}) async =>
      const [];
  @override
  Future<int?> getTotalSteps(
          {required DateTime start, required DateTime end}) async =>
      null;
  @override
  Future<WorkoutExportResult> writeWorkout({
    required DateTime start,
    required DateTime end,
    required double totalDistanceM,
    int? totalCalories,
    List<LocationPointEntity> route = const [],
    String? title,
  }) async =>
      const WorkoutExportResult(workoutSaved: true);
  @override
  Future<int> writeHrSamples(List<HealthHrSample> samples) async =>
      samples.length;
  @override
  Future<HealthConnectAvailability> getHealthConnectStatus() async =>
      HealthConnectAvailability.notApplicable;
  @override
  Future<void> installHealthConnect() async {}
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('SensorResolution value object', () {
    test('equality by value', () {
      const a = SensorResolution(
        hrSource: SensorSourceType.ble,
        hrReason: 'reason',
        stepsSource: SensorSourceType.healthConnect,
        stepsReason: 'steps reason',
      );
      const b = SensorResolution(
        hrSource: SensorSourceType.ble,
        hrReason: 'reason',
        stepsSource: SensorSourceType.healthConnect,
        stepsReason: 'steps reason',
      );
      expect(a, equals(b));
    });

    test('inequality when hrSource differs', () {
      const a = SensorResolution(
        hrSource: SensorSourceType.ble,
        hrReason: 'r',
        stepsSource: SensorSourceType.none,
        stepsReason: 'r',
      );
      const b = SensorResolution(
        hrSource: SensorSourceType.healthKit,
        hrReason: 'r',
        stepsSource: SensorSourceType.none,
        stepsReason: 'r',
      );
      expect(a, isNot(equals(b)));
    });

    test('hasHr returns true when source is not none', () {
      const r = SensorResolution(
        hrSource: SensorSourceType.ble,
        hrReason: '',
        stepsSource: SensorSourceType.none,
        stepsReason: '',
      );
      expect(r.hasHr, isTrue);
      expect(r.hasSteps, isFalse);
    });

    test('hasSteps returns true when source is not none', () {
      const r = SensorResolution(
        hrSource: SensorSourceType.none,
        hrReason: '',
        stepsSource: SensorSourceType.healthConnect,
        stepsReason: '',
      );
      expect(r.hasHr, isFalse);
      expect(r.hasSteps, isTrue);
    });

    test('toString includes source info', () {
      const r = SensorResolution(
        hrSource: SensorSourceType.ble,
        hrReason: 'connected',
        stepsSource: SensorSourceType.healthConnect,
        stepsReason: 'available',
      );
      expect(r.toString(), contains('ble'));
      expect(r.toString(), contains('healthConnect'));
    });
  });

  group('SensorSourceType enum', () {
    test('has all 4 values', () {
      expect(SensorSourceType.values, hasLength(4));
      expect(SensorSourceType.values, contains(SensorSourceType.ble));
      expect(SensorSourceType.values, contains(SensorSourceType.healthKit));
      expect(
          SensorSourceType.values, contains(SensorSourceType.healthConnect));
      expect(SensorSourceType.values, contains(SensorSourceType.none));
    });
  });

  group('SensorSourceResolver — HR priority', () {
    test('BLE connected → selects BLE', () async {
      final ble = FakeBleHr(
        connectedResult: true,
        deviceName: 'Polar H10',
      );
      final health = FakeHealthProvider();
      final sut = SensorSourceResolver(bleHr: ble, healthProvider: health);

      final result = await sut.call();

      expect(result.hrSource, SensorSourceType.ble);
      expect(result.hrReason, contains('Polar H10'));
    });

    test('BLE has last known device → selects BLE for auto-connect', () async {
      final ble = FakeBleHr(
        connectedResult: false,
        lastDeviceId: 'AA:BB:CC:DD:EE:FF',
        lastDeviceName: 'Garmin HRM-Pro',
      );
      final health = FakeHealthProvider();
      final sut = SensorSourceResolver(bleHr: ble, healthProvider: health);

      final result = await sut.call();

      expect(result.hrSource, SensorSourceType.ble);
      expect(result.hrReason, contains('Garmin HRM-Pro'));
      expect(result.hrReason, contains('auto-connect'));
    });

    test('BLE not connected, no last known → falls back to health', () async {
      final ble = FakeBleHr(connectedResult: false);
      final health = FakeHealthProvider();
      final sut = SensorSourceResolver(bleHr: ble, healthProvider: health);

      final result = await sut.call();

      // On Linux (not iOS), falls to healthConnect
      expect(result.hrSource, isNot(SensorSourceType.ble));
      expect(result.hrSource, isNot(SensorSourceType.none));
    });

    test('no BLE, health available → selects health', () async {
      final health = FakeHealthProvider();
      final sut = SensorSourceResolver(healthProvider: health);

      final result = await sut.call();

      expect(result.hrSource, isNot(SensorSourceType.ble));
      expect(result.hrSource, isNot(SensorSourceType.none));
    });

    test('no BLE, health unavailable → selects none', () async {
      final health = FakeHealthProvider(availableResult: false);
      final sut = SensorSourceResolver(healthProvider: health);

      final result = await sut.call();

      expect(result.hrSource, SensorSourceType.none);
      expect(result.hrReason, contains('No HR source'));
    });

    test('no BLE, health no HR permission → selects none', () async {
      final health = FakeHealthProvider(
        permissions: {
          HealthPermissionScope.readHeartRate: false,
          HealthPermissionScope.readSteps: true,
        },
      );
      final sut = SensorSourceResolver(healthProvider: health);

      final result = await sut.call();

      expect(result.hrSource, SensorSourceType.none);
    });

    test('no BLE, no health → selects none', () async {
      const sut = SensorSourceResolver();

      final result = await sut.call();

      expect(result.hrSource, SensorSourceType.none);
      expect(result.hrReason, contains('No HR source'));
    });

    test('BLE connected takes priority over health', () async {
      final ble = FakeBleHr(
        connectedResult: true,
        deviceName: 'Wahoo TICKR',
      );
      final health = FakeHealthProvider();
      final sut = SensorSourceResolver(bleHr: ble, healthProvider: health);

      final result = await sut.call();

      expect(result.hrSource, SensorSourceType.ble,
          reason: 'BLE > Health in priority');
    });

    test('BLE last known takes priority over health', () async {
      final ble = FakeBleHr(
        connectedResult: false,
        lastDeviceId: 'some-id',
        lastDeviceName: 'HRM',
      );
      final health = FakeHealthProvider();
      final sut = SensorSourceResolver(bleHr: ble, healthProvider: health);

      final result = await sut.call();

      expect(result.hrSource, SensorSourceType.ble,
          reason: 'BLE with lastKnown > Health');
    });
  });

  group('SensorSourceResolver — Steps priority', () {
    test('health available + permission → selects health', () async {
      final health = FakeHealthProvider();
      final sut = SensorSourceResolver(healthProvider: health);

      final result = await sut.call();

      expect(result.stepsSource, isNot(SensorSourceType.none));
      expect(result.stepsReason, contains('steps read permission granted'));
    });

    test('health unavailable → selects none', () async {
      final health = FakeHealthProvider(availableResult: false);
      final sut = SensorSourceResolver(healthProvider: health);

      final result = await sut.call();

      expect(result.stepsSource, SensorSourceType.none);
      expect(result.stepsReason, contains('unavailable'));
    });

    test('health no steps permission → selects none', () async {
      final health = FakeHealthProvider(
        permissions: {
          HealthPermissionScope.readHeartRate: true,
          HealthPermissionScope.readSteps: false,
        },
      );
      final sut = SensorSourceResolver(healthProvider: health);

      final result = await sut.call();

      expect(result.stepsSource, SensorSourceType.none);
      expect(result.stepsReason, contains('not granted'));
    });

    test('no health provider → selects none', () async {
      const sut = SensorSourceResolver();

      final result = await sut.call();

      expect(result.stepsSource, SensorSourceType.none);
      expect(result.stepsReason, contains('No health provider'));
    });
  });

  group('SensorSourceResolver — combined scenarios', () {
    test('BLE + health → BLE for HR, health for steps', () async {
      final ble = FakeBleHr(
        connectedResult: true,
        deviceName: 'Polar H10',
      );
      final health = FakeHealthProvider();
      final sut = SensorSourceResolver(bleHr: ble, healthProvider: health);

      final result = await sut.call();

      expect(result.hrSource, SensorSourceType.ble);
      expect(result.stepsSource, isNot(SensorSourceType.none));
      expect(result.hasHr, isTrue);
      expect(result.hasSteps, isTrue);
    });

    test('nothing available → none for both', () async {
      const sut = SensorSourceResolver();

      final result = await sut.call();

      expect(result.hrSource, SensorSourceType.none);
      expect(result.stepsSource, SensorSourceType.none);
      expect(result.hasHr, isFalse);
      expect(result.hasSteps, isFalse);
    });

    test('BLE only, no health → BLE HR, no steps', () async {
      final ble = FakeBleHr(
        connectedResult: true,
        deviceName: 'HRM',
      );
      final sut = SensorSourceResolver(bleHr: ble);

      final result = await sut.call();

      expect(result.hrSource, SensorSourceType.ble);
      expect(result.stepsSource, SensorSourceType.none);
    });
  });
}
