import 'dart:io';

import 'package:omni_runner/core/errors/integrations_failures.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/features/integrations_export/domain/export_result.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

const _tag = 'ShareExport';

/// Share a workout export file via the OS share sheet ("Open In…").
///
/// Flow:
/// 1. Write [ExportResult.bytes] to a temporary file in the cache directory
/// 2. Open the native share sheet via `share_plus`
/// 3. Clean up the temp file best-effort after sharing
///
/// Throws [ExportWriteFailed] if the temp file cannot be written.
/// Does NOT throw on share cancellation — that is the user's choice.
///
/// This is a standalone function (not a class) because it has no state
/// and no injected dependencies beyond platform APIs.
Future<void> shareExportFile(ExportResult result) async {
  final tempPath = await _writeTempFile(result);

  try {
    final xFile = XFile(
      tempPath,
      mimeType: result.mimeType,
      name: result.filename,
    );

    await SharePlus.instance.share(
      ShareParams(files: [xFile], title: result.filename),
    );

    AppLogger.info(
      'Shared ${result.filename} (${result.bytes.length} bytes)',
      tag: _tag,
    );
  } on Exception catch (e) {
    AppLogger.warn('Share sheet error (non-fatal): $e', tag: _tag);
  } finally {
    _cleanupTempFile(tempPath);
  }
}

/// Write [ExportResult.bytes] to a temp file and return the path.
///
/// Uses the app's cache directory so the OS can reclaim space if needed.
/// Throws [ExportWriteFailed] if writing fails.
Future<String> _writeTempFile(ExportResult result) async {
  try {
    final cacheDir = await getTemporaryDirectory();
    final file = File('${cacheDir.path}/${result.filename}');
    await file.writeAsBytes(result.bytes, flush: true);

    AppLogger.debug(
      'Temp file written: ${file.path} (${result.bytes.length} bytes)',
      tag: _tag,
    );

    return file.path;
  } on Exception catch (e) {
    throw ExportWriteFailed(
      result.filename,
      'Failed to write temp file: $e',
    );
  }
}

/// Best-effort cleanup of the temporary file.
///
/// Runs asynchronously and swallows all errors — the OS will also
/// reclaim cache files eventually.
void _cleanupTempFile(String path) {
  Future<void>.microtask(() async {
    try {
      final file = File(path);
      // ignore: avoid_slow_async_io
      if (await file.exists()) {
        await file.delete();
        AppLogger.debug('Temp file cleaned: $path', tag: _tag);
      }
    } on Exception {
      // Best-effort — ignore cleanup failures
    }
  });
}
