import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/core/errors/integrations_failures.dart';
import 'package:omni_runner/features/integrations_export/domain/export_format.dart';
import 'package:omni_runner/features/integrations_export/domain/export_result.dart';

void main() {
  group('ExportFormat filename/mimeType mapping', () {
    test('GPX format has correct extension', () {
      expect(ExportFormat.gpx.extension, '.gpx');
    });

    test('TCX format has correct extension', () {
      expect(ExportFormat.tcx.extension, '.tcx');
    });

    test('FIT format has correct extension', () {
      expect(ExportFormat.fit.extension, '.fit');
    });

    test('GPX format has correct MIME type', () {
      expect(ExportFormat.gpx.mimeType, 'application/gpx+xml');
    });

    test('TCX format has correct MIME type', () {
      expect(ExportFormat.tcx.mimeType, 'application/vnd.garmin.tcx+xml');
    });

    test('FIT format has correct MIME type', () {
      expect(ExportFormat.fit.mimeType, 'application/vnd.ant.fit');
    });

    test('GPX format has correct label', () {
      expect(ExportFormat.gpx.label, 'GPX');
    });

    test('TCX format has correct label', () {
      expect(ExportFormat.tcx.label, 'TCX');
    });

    test('FIT format has correct label', () {
      expect(ExportFormat.fit.label, 'FIT');
    });
  });

  group('ExportResult construction', () {
    test('GPX result has correct filename and mimeType', () {
      final result = ExportResult(
        bytes: Uint8List.fromList([0x3C, 0x3F]),
        filename: 'run_2026-02-17_060000.gpx',
        mimeType: ExportFormat.gpx.mimeType,
        format: ExportFormat.gpx,
      );

      expect(result.filename, endsWith('.gpx'));
      expect(result.mimeType, 'application/gpx+xml');
      expect(result.format, ExportFormat.gpx);
      expect(result.bytes, hasLength(2));
    });

    test('TCX result has correct filename and mimeType', () {
      final result = ExportResult(
        bytes: Uint8List.fromList([0x3C, 0x3F]),
        filename: 'run_2026-02-17_060000.tcx',
        mimeType: ExportFormat.tcx.mimeType,
        format: ExportFormat.tcx,
      );

      expect(result.filename, endsWith('.tcx'));
      expect(result.mimeType, 'application/vnd.garmin.tcx+xml');
      expect(result.format, ExportFormat.tcx);
    });

    test('FIT result has correct filename and mimeType', () {
      final result = ExportResult(
        bytes: Uint8List.fromList([0x0E, 0x10]),
        filename: 'run_2026-02-17_060000.fit',
        mimeType: ExportFormat.fit.mimeType,
        format: ExportFormat.fit,
      );

      expect(result.filename, endsWith('.fit'));
      expect(result.mimeType, 'application/vnd.ant.fit');
      expect(result.format, ExportFormat.fit);
    });
  });

  group('IntegrationFailure — file export', () {
    test('ExportWriteFailed carries path and reason', () {
      const failure = ExportWriteFailed('/tmp/file.gpx', 'disk full');

      expect(failure, isA<IntegrationFailure>());
      expect(failure.path, '/tmp/file.gpx');
      expect(failure.reason, 'disk full');
    });

    test('ExportGenerationFailed carries format and reason', () {
      const failure = ExportGenerationFailed('GPX', 'empty route');

      expect(failure, isA<IntegrationFailure>());
      expect(failure.format, 'GPX');
      expect(failure.reason, 'empty route');
    });

    test('ExportNotImplemented carries format', () {
      const failure = ExportNotImplemented('FIT');

      expect(failure, isA<IntegrationFailure>());
      expect(failure.format, 'FIT');
    });
  });

  group('ExportFormat covers all values', () {
    test('all formats have non-empty extension starting with dot', () {
      for (final format in ExportFormat.values) {
        expect(format.extension, startsWith('.'));
        expect(format.extension.length, greaterThan(1));
      }
    });

    test('all formats have non-empty mimeType containing "/"', () {
      for (final format in ExportFormat.values) {
        expect(format.mimeType, contains('/'));
        expect(format.mimeType.length, greaterThan(5));
      }
    });

    test('all formats have non-empty label', () {
      for (final format in ExportFormat.values) {
        expect(format.label.isNotEmpty, isTrue);
      }
    });
  });
}
