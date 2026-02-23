import 'package:flutter_test/flutter_test.dart';

import 'package:omni_runner/core/errors/health_export_failures.dart';
import 'package:omni_runner/domain/entities/health_hr_sample.dart';
import 'package:omni_runner/domain/entities/workout_export_result.dart';
import 'package:omni_runner/features/health_export/domain/i_health_export_service.dart';
import 'package:omni_runner/features/health_export/presentation/health_export_controller.dart';

// =============================================================================
// Fakes
// =============================================================================

// Fake service that delegates to test-configurable behavior.
class _FakeHealthExportService implements IHealthExportService {
  bool supportedResult = true;
  bool ensurePermissionsResult = true;
  HealthExportFailure? ensurePermissionsError;
  WorkoutExportResult exportResult = const WorkoutExportResult(
    workoutSaved: true,
    routeAttached: true,
    routePointCount: 5,
    message: 'OK',
  );
  HealthExportFailure? exportError;

  @override
  Future<bool> isSupported() async => supportedResult;

  @override
  Future<bool> ensurePermissions({bool requestIfMissing = true}) async {
    if (ensurePermissionsError != null) throw ensurePermissionsError!;
    return ensurePermissionsResult;
  }

  @override
  Future<WorkoutExportResult> exportWorkout({
    required String sessionId,
    required int startMs,
    required int endMs,
    required double totalDistanceM,
    int? totalCalories,
    int? avgBpm,
    int? maxBpm,
    List<HealthHrSample> hrSamples = const [],
  }) async {
    if (exportError != null) throw exportError!;
    return exportResult;
  }
}

// =============================================================================
// Tests
// =============================================================================

void main() {
  // --------------------------------------------------------------------------
  // HealthExportFailure hierarchy
  // --------------------------------------------------------------------------
  group('HealthExportFailure', () {
    test('sealed hierarchy has 6 subtypes', () {
      const List<HealthExportFailure> all = [
        HealthExportNotAvailable('test'),
        HealthExportNeedsUpdate(),
        HealthExportPermissionDenied(),
        HealthExportRouteAttachFailed('test'),
        HealthExportWriteFailed('test'),
        HealthExportHrWriteFailed(attempted: 10, written: 5),
      ];
      expect(all.length, 6);
    });

    test('pattern matching is exhaustive', () {
      const HealthExportFailure f = HealthExportPermissionDenied();
      final result = switch (f) {
        HealthExportNotAvailable() => 'a',
        HealthExportNeedsUpdate() => 'b',
        HealthExportPermissionDenied() => 'c',
        HealthExportRouteAttachFailed() => 'd',
        HealthExportWriteFailed() => 'e',
        HealthExportHrWriteFailed() => 'f',
      };
      expect(result, 'c');
    });

    test('HealthExportPermissionDenied stores missing scopes', () {
      const f = HealthExportPermissionDenied(
        missingScopes: ['writeWorkout', 'writeDistance'],
      );
      expect(f.missingScopes, ['writeWorkout', 'writeDistance']);
    });

    test('HealthExportHrWriteFailed stores counts', () {
      const f = HealthExportHrWriteFailed(attempted: 100, written: 80);
      expect(f.attempted, 100);
      expect(f.written, 80);
    });
  });

  // --------------------------------------------------------------------------
  // HealthExportController
  // --------------------------------------------------------------------------
  group('HealthExportController', () {
    late _FakeHealthExportService fakeService;
    late HealthExportController controller;

    setUp(() {
      fakeService = _FakeHealthExportService();
      controller = HealthExportController(service: fakeService);
    });

    test('isPlatformSupported returns true when service says supported',
        () async {
      fakeService.supportedResult = true;
      expect(await controller.isPlatformSupported(), isTrue);
    });

    test('isPlatformSupported returns false when service says unsupported',
        () async {
      fakeService.supportedResult = false;
      expect(await controller.isPlatformSupported(), isFalse);
    });

    test('exportWorkout returns success with route message', () async {
      fakeService.exportResult = const WorkoutExportResult(
        workoutSaved: true,
        routeAttached: true,
        routePointCount: 50,
        message: 'OK',
      );

      final result = await controller.exportWorkout(
        sessionId: 'abc',
        startMs: 1000,
        endMs: 2000,
        totalDistanceM: 5000,
      );

      expect(result.success, isTrue);
      expect(result.message, contains('rota GPS'));
      expect(result.result!.routeAttached, isTrue);
    });

    test('exportWorkout returns success without route message', () async {
      fakeService.exportResult = const WorkoutExportResult(
        workoutSaved: true,
        routeAttached: false,
        routePointCount: 0,
        message: 'No route',
      );

      final result = await controller.exportWorkout(
        sessionId: 'abc',
        startMs: 1000,
        endMs: 2000,
        totalDistanceM: 5000,
      );

      expect(result.success, isTrue);
      expect(result.message, contains('sem rota'));
    });

    test('exportWorkout maps HealthExportNotAvailable to failure', () async {
      fakeService.exportError =
          const HealthExportNotAvailable('Not available');

      final result = await controller.exportWorkout(
        sessionId: 'abc',
        startMs: 1000,
        endMs: 2000,
        totalDistanceM: 5000,
      );

      expect(result.success, isFalse);
      expect(result.message, 'Not available');
    });

    test('exportWorkout maps HealthExportNeedsUpdate to update message',
        () async {
      fakeService.exportError = const HealthExportNeedsUpdate();

      final result = await controller.exportWorkout(
        sessionId: 'abc',
        startMs: 1000,
        endMs: 2000,
        totalDistanceM: 5000,
      );

      expect(result.success, isFalse);
      expect(result.message, contains('Health Connect'));
      expect(result.message, contains('atualizado'));
    });

    test('exportWorkout maps PermissionDenied to permission message',
        () async {
      fakeService.exportError = const HealthExportPermissionDenied(
        missingScopes: ['writeWorkout'],
      );

      final result = await controller.exportWorkout(
        sessionId: 'abc',
        startMs: 1000,
        endMs: 2000,
        totalDistanceM: 5000,
      );

      expect(result.success, isFalse);
      expect(result.message, contains('Permissão negada'));
    });

    test('exportWorkout maps WriteFailed to failure', () async {
      fakeService.exportError =
          const HealthExportWriteFailed('Plugin error');

      final result = await controller.exportWorkout(
        sessionId: 'abc',
        startMs: 1000,
        endMs: 2000,
        totalDistanceM: 5000,
      );

      expect(result.success, isFalse);
      expect(result.message, contains('Plugin error'));
    });

    test('exportWorkout maps RouteAttachFailed to partial success', () async {
      fakeService.exportError =
          const HealthExportRouteAttachFailed('UUID not found');

      final result = await controller.exportWorkout(
        sessionId: 'abc',
        startMs: 1000,
        endMs: 2000,
        totalDistanceM: 5000,
      );

      expect(result.success, isTrue);
      expect(result.message, contains('rota GPS não foi anexada'));
    });

    test('exportWorkout maps HrWriteFailed to partial success', () async {
      fakeService.exportError =
          const HealthExportHrWriteFailed(attempted: 100, written: 50);

      final result = await controller.exportWorkout(
        sessionId: 'abc',
        startMs: 1000,
        endMs: 2000,
        totalDistanceM: 5000,
      );

      expect(result.success, isTrue);
      expect(result.message, contains('50/100'));
    });

    test('exportWorkout catches generic exceptions gracefully', () async {
      fakeService.exportError = null;
      // Override to throw a non-HealthExportFailure exception.
      final badService = _ThrowingExportService();
      final ctrl = HealthExportController(service: badService);

      final result = await ctrl.exportWorkout(
        sessionId: 'abc',
        startMs: 1000,
        endMs: 2000,
        totalDistanceM: 5000,
      );

      expect(result.success, isFalse);
      expect(result.message, contains('inesperado'));
    });
  });

  // --------------------------------------------------------------------------
  // HealthExportUiResult
  // --------------------------------------------------------------------------
  group('HealthExportUiResult', () {
    test('stores all fields', () {
      const r = HealthExportUiResult(
        success: true,
        message: 'OK',
        result: WorkoutExportResult(workoutSaved: true),
      );
      expect(r.success, isTrue);
      expect(r.message, 'OK');
      expect(r.result, isNotNull);
    });

    test('result can be null on failure', () {
      const r = HealthExportUiResult(success: false, message: 'error');
      expect(r.result, isNull);
    });
  });
}

/// A fake service that throws a generic exception (not HealthExportFailure).
class _ThrowingExportService implements IHealthExportService {
  @override
  Future<bool> isSupported() async => true;

  @override
  Future<bool> ensurePermissions({bool requestIfMissing = true}) async => true;

  @override
  Future<WorkoutExportResult> exportWorkout({
    required String sessionId,
    required int startMs,
    required int endMs,
    required double totalDistanceM,
    int? totalCalories,
    int? avgBpm,
    int? maxBpm,
    List<HealthHrSample> hrSamples = const [],
  }) async {
    throw Exception('Something went wrong');
  }
}
