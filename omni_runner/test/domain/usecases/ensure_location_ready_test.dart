import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/background_permission_state.dart';
import 'package:omni_runner/domain/entities/permission_status_entity.dart';
import 'package:omni_runner/domain/failures/location_failure.dart';
import 'package:omni_runner/domain/repositories/i_location_permission.dart';
import 'package:omni_runner/domain/usecases/ensure_location_ready.dart';

/// Fake implementation of [ILocationPermission] for testing.
///
/// Configurable responses for each method.
final class _FakeLocationPermission implements ILocationPermission {
  final bool serviceEnabled;
  final PermissionStatusEntity initialStatus;
  final PermissionStatusEntity statusAfterRequest;
  bool requestWasCalled = false;
  bool openAppSettingsWasCalled = false;

  _FakeLocationPermission({
    this.serviceEnabled = true,
    this.initialStatus = PermissionStatusEntity.granted,
    this.statusAfterRequest = PermissionStatusEntity.granted,
  });

  @override
  Future<bool> isServiceEnabled() async => serviceEnabled;

  @override
  Future<PermissionStatusEntity> check() async => initialStatus;

  @override
  Future<PermissionStatusEntity> request() async {
    requestWasCalled = true;
    return statusAfterRequest;
  }

  @override
  Future<BackgroundPermissionState> checkBackground() async =>
      BackgroundPermissionState.notNeeded;

  @override
  Future<BackgroundPermissionState> requestBackground() async =>
      BackgroundPermissionState.denied;

  @override
  Future<bool> openAppSettings() async {
    openAppSettingsWasCalled = true;
    return true;
  }
}

void main() {
  group('EnsureLocationReady', () {
    test('returns null when service enabled and permission granted', () async {
      // Arrange
      final permission = _FakeLocationPermission(
        serviceEnabled: true,
        initialStatus: PermissionStatusEntity.granted,
      );
      final useCase = EnsureLocationReady(permission);

      // Act
      final result = await useCase();

      // Assert
      expect(result, isNull);
      expect(permission.requestWasCalled, isFalse);
    });

    test('returns LocationServiceDisabled when service is off', () async {
      // Arrange
      final permission = _FakeLocationPermission(
        serviceEnabled: false,
        initialStatus: PermissionStatusEntity.granted,
      );
      final useCase = EnsureLocationReady(permission);

      // Act
      final result = await useCase();

      // Assert
      expect(result, isA<LocationServiceDisabled>());
    });

    test('requests permission when status is notDetermined', () async {
      // Arrange
      final permission = _FakeLocationPermission(
        serviceEnabled: true,
        initialStatus: PermissionStatusEntity.notDetermined,
        statusAfterRequest: PermissionStatusEntity.granted,
      );
      final useCase = EnsureLocationReady(permission);

      // Act
      final result = await useCase();

      // Assert
      expect(result, isNull);
      expect(permission.requestWasCalled, isTrue);
    });

    test('requests permission when status is denied', () async {
      // Arrange
      final permission = _FakeLocationPermission(
        serviceEnabled: true,
        initialStatus: PermissionStatusEntity.denied,
        statusAfterRequest: PermissionStatusEntity.granted,
      );
      final useCase = EnsureLocationReady(permission);

      // Act
      final result = await useCase();

      // Assert
      expect(result, isNull);
      expect(permission.requestWasCalled, isTrue);
    });

    test('returns LocationPermissionDenied when request is denied', () async {
      // Arrange
      final permission = _FakeLocationPermission(
        serviceEnabled: true,
        initialStatus: PermissionStatusEntity.notDetermined,
        statusAfterRequest: PermissionStatusEntity.denied,
      );
      final useCase = EnsureLocationReady(permission);

      // Act
      final result = await useCase();

      // Assert
      expect(result, isA<LocationPermissionDenied>());
    });

    test(
      'returns LocationPermissionPermanentlyDenied when permanently denied',
      () async {
        // Arrange
        final permission = _FakeLocationPermission(
          serviceEnabled: true,
          initialStatus: PermissionStatusEntity.permanentlyDenied,
        );
        final useCase = EnsureLocationReady(permission);

        // Act
        final result = await useCase();

        // Assert
        expect(result, isA<LocationPermissionPermanentlyDenied>());
        expect(permission.requestWasCalled, isFalse);
      },
    );

    test(
      'returns LocationPermissionPermanentlyDenied when restricted',
      () async {
        // Arrange
        final permission = _FakeLocationPermission(
          serviceEnabled: true,
          initialStatus: PermissionStatusEntity.restricted,
        );
        final useCase = EnsureLocationReady(permission);

        // Act
        final result = await useCase();

        // Assert
        expect(result, isA<LocationPermissionPermanentlyDenied>());
      },
    );

    test('does not request permission when already granted', () async {
      // Arrange
      final permission = _FakeLocationPermission(
        serviceEnabled: true,
        initialStatus: PermissionStatusEntity.granted,
      );
      final useCase = EnsureLocationReady(permission);

      // Act
      await useCase();

      // Assert
      expect(permission.requestWasCalled, isFalse);
    });

    test(
      'does not request permission when permanently denied',
      () async {
        // Arrange
        final permission = _FakeLocationPermission(
          serviceEnabled: true,
          initialStatus: PermissionStatusEntity.permanentlyDenied,
        );
        final useCase = EnsureLocationReady(permission);

        // Act
        await useCase();

        // Assert
        expect(permission.requestWasCalled, isFalse);
      },
    );

    test('does not check permission when service is disabled', () async {
      // Arrange
      final permission = _FakeLocationPermission(
        serviceEnabled: false,
        initialStatus: PermissionStatusEntity.granted,
      );
      final useCase = EnsureLocationReady(permission);

      // Act
      final result = await useCase();

      // Assert
      expect(result, isA<LocationServiceDisabled>());
      expect(permission.requestWasCalled, isFalse);
    });
  });
}
