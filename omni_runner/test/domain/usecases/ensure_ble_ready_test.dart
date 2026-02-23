import 'package:flutter_test/flutter_test.dart';

import 'package:omni_runner/domain/entities/permission_status_entity.dart';
import 'package:omni_runner/domain/failures/ble_failure.dart';
import 'package:omni_runner/domain/repositories/i_ble_permission.dart';
import 'package:omni_runner/domain/usecases/ensure_ble_ready.dart';

/// Fake implementation of [IBlePermission] for testing.
///
/// Allows precise control of each response without any plugin dependency.
class FakeBlePermission implements IBlePermission {
  bool supportedResult;
  bool adapterOnResult;
  PermissionStatusEntity checkScanResult;
  PermissionStatusEntity requestScanResult;
  PermissionStatusEntity checkConnectResult;
  PermissionStatusEntity requestConnectResult;

  int requestScanCalls = 0;
  int requestConnectCalls = 0;

  FakeBlePermission({
    this.supportedResult = true,
    this.adapterOnResult = true,
    this.checkScanResult = PermissionStatusEntity.granted,
    this.requestScanResult = PermissionStatusEntity.granted,
    this.checkConnectResult = PermissionStatusEntity.granted,
    this.requestConnectResult = PermissionStatusEntity.granted,
  });

  @override
  Future<bool> isSupported() async => supportedResult;
  @override
  Future<bool> isAdapterOn() async => adapterOnResult;
  @override
  Future<PermissionStatusEntity> checkScan() async => checkScanResult;
  @override
  Future<PermissionStatusEntity> requestScan() async {
    requestScanCalls++;
    return requestScanResult;
  }

  @override
  Future<PermissionStatusEntity> checkConnect() async => checkConnectResult;
  @override
  Future<PermissionStatusEntity> requestConnect() async {
    requestConnectCalls++;
    return requestConnectResult;
  }

  @override
  Future<bool> openAppSettings() async => true;
}

void main() {
  late FakeBlePermission fakePermission;
  late EnsureBleReady sut;

  setUp(() {
    fakePermission = FakeBlePermission();
    sut = EnsureBleReady(fakePermission);
  });

  group('EnsureBleReady', () {
    test('returns null when everything is ready', () async {
      final result = await sut.call();
      expect(result, isNull);
    });

    test('returns BleNotSupported when hardware not available', () async {
      fakePermission.supportedResult = false;
      final result = await sut.call();
      expect(result, isA<BleNotSupported>());
    });

    test('returns BleAdapterOff when Bluetooth is off', () async {
      fakePermission.adapterOnResult = false;
      final result = await sut.call();
      expect(result, isA<BleAdapterOff>());
    });

    test('does not check adapter if not supported', () async {
      fakePermission.supportedResult = false;
      fakePermission.adapterOnResult = true;
      final result = await sut.call();
      expect(result, isA<BleNotSupported>());
    });

    group('scan permission', () {
      test('requests scan when status is notDetermined', () async {
        fakePermission.checkScanResult = PermissionStatusEntity.notDetermined;
        fakePermission.requestScanResult = PermissionStatusEntity.granted;

        final result = await sut.call();
        expect(result, isNull);
        expect(fakePermission.requestScanCalls, 1);
      });

      test('requests scan when status is denied', () async {
        fakePermission.checkScanResult = PermissionStatusEntity.denied;
        fakePermission.requestScanResult = PermissionStatusEntity.granted;

        final result = await sut.call();
        expect(result, isNull);
        expect(fakePermission.requestScanCalls, 1);
      });

      test('does not request when already granted', () async {
        fakePermission.checkScanResult = PermissionStatusEntity.granted;

        final result = await sut.call();
        expect(result, isNull);
        expect(fakePermission.requestScanCalls, 0);
      });

      test('returns BleScanPermissionDenied when request denied', () async {
        fakePermission.checkScanResult = PermissionStatusEntity.notDetermined;
        fakePermission.requestScanResult = PermissionStatusEntity.denied;

        final result = await sut.call();
        expect(result, isA<BleScanPermissionDenied>());
      });

      test('returns BlePermissionPermanentlyDenied when permanently denied',
          () async {
        fakePermission.checkScanResult =
            PermissionStatusEntity.permanentlyDenied;

        final result = await sut.call();
        expect(result, isA<BlePermissionPermanentlyDenied>());
        expect(fakePermission.requestScanCalls, 0);
      });

      test('returns BlePermissionPermanentlyDenied when restricted', () async {
        fakePermission.checkScanResult = PermissionStatusEntity.restricted;

        final result = await sut.call();
        expect(result, isA<BlePermissionPermanentlyDenied>());
      });
    });

    group('connect permission', () {
      test('requests connect when status is notDetermined', () async {
        fakePermission.checkConnectResult =
            PermissionStatusEntity.notDetermined;
        fakePermission.requestConnectResult = PermissionStatusEntity.granted;

        final result = await sut.call();
        expect(result, isNull);
        expect(fakePermission.requestConnectCalls, 1);
      });

      test('requests connect when status is denied', () async {
        fakePermission.checkConnectResult = PermissionStatusEntity.denied;
        fakePermission.requestConnectResult = PermissionStatusEntity.granted;

        final result = await sut.call();
        expect(result, isNull);
        expect(fakePermission.requestConnectCalls, 1);
      });

      test('does not request when already granted', () async {
        fakePermission.checkConnectResult = PermissionStatusEntity.granted;

        final result = await sut.call();
        expect(result, isNull);
        expect(fakePermission.requestConnectCalls, 0);
      });

      test('returns BleConnectPermissionDenied when request denied', () async {
        fakePermission.checkConnectResult =
            PermissionStatusEntity.notDetermined;
        fakePermission.requestConnectResult = PermissionStatusEntity.denied;

        final result = await sut.call();
        expect(result, isA<BleConnectPermissionDenied>());
      });

      test('returns BlePermissionPermanentlyDenied when permanently denied',
          () async {
        fakePermission.checkConnectResult =
            PermissionStatusEntity.permanentlyDenied;

        final result = await sut.call();
        expect(result, isA<BlePermissionPermanentlyDenied>());
        expect(fakePermission.requestConnectCalls, 0);
      });
    });

    group('flow order', () {
      test('does not check scan if not supported', () async {
        fakePermission.supportedResult = false;

        await sut.call();
        expect(fakePermission.requestScanCalls, 0);
        expect(fakePermission.requestConnectCalls, 0);
      });

      test('does not check scan if adapter off', () async {
        fakePermission.adapterOnResult = false;

        await sut.call();
        expect(fakePermission.requestScanCalls, 0);
        expect(fakePermission.requestConnectCalls, 0);
      });

      test('does not check connect if scan fails', () async {
        fakePermission.checkScanResult =
            PermissionStatusEntity.permanentlyDenied;

        await sut.call();
        expect(fakePermission.requestConnectCalls, 0);
      });

      test('checks connect after scan succeeds', () async {
        fakePermission.checkScanResult = PermissionStatusEntity.granted;
        fakePermission.checkConnectResult = PermissionStatusEntity.granted;

        final result = await sut.call();
        expect(result, isNull);
      });
    });

    group('failure types', () {
      test('all BleFailure subtypes are distinct', () {
        const failures = <BleFailure>[
          BleScanPermissionDenied(),
          BleConnectPermissionDenied(),
          BlePermissionPermanentlyDenied(),
          BleAdapterOff(),
          BleNotSupported(),
        ];
        final types = failures.map((f) => f.runtimeType).toSet();
        expect(types.length, 5);
      });
    });
  });
}
