import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';
import 'package:omni_runner/features/integrations_export/data/export_service_impl.dart';
import 'package:omni_runner/features/integrations_export/domain/export_format.dart';
import 'package:omni_runner/features/integrations_export/domain/export_request.dart';

void main() {
  late ExportServiceImpl sut;

  final session = WorkoutSessionEntity(
    id: 'session-1',
    status: WorkoutStatus.completed,
    startTimeMs: DateTime.utc(2026, 2, 28, 14, 30, 0).millisecondsSinceEpoch,
    endTimeMs: DateTime.utc(2026, 2, 28, 15, 0, 0).millisecondsSinceEpoch,
    totalDistanceM: 5000,
    route: const [],
  );

  setUp(() {
    sut = const ExportServiceImpl();
  });

  group('exportWorkout', () {
    test('GPX export returns bytes and correct filename', () async {
      final request = ExportRequest(
        session: session,
        route: const [],
        format: ExportFormat.gpx,
      );

      final result = await sut.exportWorkout(request);

      expect(result.bytes, isNotEmpty);
      expect(result.filename, 'run_2026-02-28_143000.gpx');
      expect(result.mimeType, 'application/gpx+xml');
      expect(result.format, ExportFormat.gpx);
    });

    test('TCX export returns bytes and correct filename', () async {
      final request = ExportRequest(
        session: session,
        route: const [],
        format: ExportFormat.tcx,
      );

      final result = await sut.exportWorkout(request);

      expect(result.bytes, isNotEmpty);
      expect(result.filename, 'run_2026-02-28_143000.tcx');
      expect(result.mimeType, 'application/vnd.garmin.tcx+xml');
    });

    test('FIT export returns bytes and correct filename', () async {
      final request = ExportRequest(
        session: session,
        route: const [],
        format: ExportFormat.fit,
      );

      final result = await sut.exportWorkout(request);

      expect(result.bytes, isNotEmpty);
      expect(result.filename, 'run_2026-02-28_143000.fit');
      expect(result.mimeType, 'application/vnd.ant.fit');
    });
  });

  group('ExportFormat', () {
    test('extension returns correct value', () {
      expect(ExportFormat.gpx.extension, '.gpx');
      expect(ExportFormat.tcx.extension, '.tcx');
      expect(ExportFormat.fit.extension, '.fit');
    });

    test('label returns correct value', () {
      expect(ExportFormat.gpx.label, 'GPX');
      expect(ExportFormat.tcx.label, 'TCX');
      expect(ExportFormat.fit.label, 'FIT');
    });
  });
}
