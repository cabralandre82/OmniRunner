import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:omni_runner/data/mappers/permission_mapper.dart';
import 'package:omni_runner/domain/entities/background_permission_state.dart';
import 'package:omni_runner/domain/entities/permission_status_entity.dart';

void main() {
  group('PermissionMapper.toForeground', () {
    test('maps granted to PermissionStatusEntity.granted', () {
      final result = PermissionMapper.toForeground(PermissionStatus.granted);

      expect(result, PermissionStatusEntity.granted);
    });

    test('maps limited to PermissionStatusEntity.granted', () {
      final result = PermissionMapper.toForeground(PermissionStatus.limited);

      expect(result, PermissionStatusEntity.granted);
    });

    test('maps denied to PermissionStatusEntity.denied', () {
      final result = PermissionMapper.toForeground(PermissionStatus.denied);

      expect(result, PermissionStatusEntity.denied);
    });

    test('maps permanentlyDenied to PermissionStatusEntity.permanentlyDenied',
        () {
      final result = PermissionMapper.toForeground(
        PermissionStatus.permanentlyDenied,
      );

      expect(result, PermissionStatusEntity.permanentlyDenied);
    });

    test('maps restricted to PermissionStatusEntity.restricted', () {
      final result = PermissionMapper.toForeground(PermissionStatus.restricted);

      expect(result, PermissionStatusEntity.restricted);
    });

    test('maps provisional to PermissionStatusEntity.granted', () {
      final result = PermissionMapper.toForeground(
        PermissionStatus.provisional,
      );

      expect(result, PermissionStatusEntity.granted);
    });

    test('granted, limited, and provisional all map to granted', () {
      final grantedResult = PermissionMapper.toForeground(
        PermissionStatus.granted,
      );
      final limitedResult = PermissionMapper.toForeground(
        PermissionStatus.limited,
      );
      final provisionalResult = PermissionMapper.toForeground(
        PermissionStatus.provisional,
      );

      expect(grantedResult, PermissionStatusEntity.granted);
      expect(limitedResult, PermissionStatusEntity.granted);
      expect(provisionalResult, PermissionStatusEntity.granted);
      expect(grantedResult, equals(limitedResult));
      expect(grantedResult, equals(provisionalResult));
    });

    test('denied and permanentlyDenied map to different statuses', () {
      final denied = PermissionMapper.toForeground(PermissionStatus.denied);
      final permanentlyDenied = PermissionMapper.toForeground(
        PermissionStatus.permanentlyDenied,
      );

      expect(denied, isNot(equals(permanentlyDenied)));
      expect(denied, PermissionStatusEntity.denied);
      expect(permanentlyDenied, PermissionStatusEntity.permanentlyDenied);
    });

    test('all PermissionStatus values are mapped (exhaustive)', () {
      for (final value in PermissionStatus.values) {
        final result = PermissionMapper.toForeground(value);
        expect(result, isA<PermissionStatusEntity>());
      }
    });
  });

  group('PermissionMapper.toBackground', () {
    test('maps granted to BackgroundPermissionState.granted', () {
      final result = PermissionMapper.toBackground(PermissionStatus.granted);

      expect(result, BackgroundPermissionState.granted);
    });

    test('maps limited to BackgroundPermissionState.granted', () {
      final result = PermissionMapper.toBackground(PermissionStatus.limited);

      expect(result, BackgroundPermissionState.granted);
    });

    test('maps denied to BackgroundPermissionState.rationaleRequired', () {
      final result = PermissionMapper.toBackground(PermissionStatus.denied);

      expect(result, BackgroundPermissionState.rationaleRequired);
    });

    test('maps permanentlyDenied to BackgroundPermissionState.denied', () {
      final result = PermissionMapper.toBackground(
        PermissionStatus.permanentlyDenied,
      );

      expect(result, BackgroundPermissionState.denied);
    });

    test('maps restricted to BackgroundPermissionState.denied', () {
      final result = PermissionMapper.toBackground(PermissionStatus.restricted);

      expect(result, BackgroundPermissionState.denied);
    });

    test('maps provisional to BackgroundPermissionState.granted', () {
      final result = PermissionMapper.toBackground(
        PermissionStatus.provisional,
      );

      expect(result, BackgroundPermissionState.granted);
    });

    test(
        'denied maps to rationaleRequired (user can still be asked), '
        'permanentlyDenied maps to denied (must go to settings)', () {
      final denied = PermissionMapper.toBackground(PermissionStatus.denied);
      final permanentlyDenied = PermissionMapper.toBackground(
        PermissionStatus.permanentlyDenied,
      );

      expect(denied, BackgroundPermissionState.rationaleRequired);
      expect(permanentlyDenied, BackgroundPermissionState.denied);
      expect(denied, isNot(equals(permanentlyDenied)));
    });

    test('permanentlyDenied and restricted both map to denied', () {
      final permanentlyDenied = PermissionMapper.toBackground(
        PermissionStatus.permanentlyDenied,
      );
      final restricted = PermissionMapper.toBackground(
        PermissionStatus.restricted,
      );

      expect(permanentlyDenied, BackgroundPermissionState.denied);
      expect(restricted, BackgroundPermissionState.denied);
      expect(permanentlyDenied, equals(restricted));
    });

    test('all PermissionStatus values are mapped (exhaustive)', () {
      for (final value in PermissionStatus.values) {
        final result = PermissionMapper.toBackground(value);
        expect(result, isA<BackgroundPermissionState>());
      }
    });
  });
}
