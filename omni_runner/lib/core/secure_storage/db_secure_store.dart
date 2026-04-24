import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:path_provider/path_provider.dart';

/// L01-32 — Hardened FlutterSecureStorage options.
///   * Android: explicit `AndroidOptions()` selects the canonical
///     plugin defaults. Newer plugin versions (>=10) have deprecated
///     `encryptedSharedPreferences: true` in favour of automatic
///     migration to custom ciphers, so we no longer pass it. We do
///     NOT silently fall back to plain SharedPreferences because the
///     `aOptions` value is set explicitly (the ignored flag would
///     re-enable the legacy backend on plugin v9 if anyone downgraded).
///   * iOS: `KeychainAccessibility.first_unlock_this_device` keeps the
///     key out of iCloud Keychain backups while remaining accessible
///     to the app after first unlock.
const FlutterSecureStorage _hardenedStorage = FlutterSecureStorage(
  // ignore: deprecated_member_use
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
);

/// Provides a 256-bit encryption key for local SQLite/SQLCipher database.
///
/// Key is stored in FlutterSecureStorage, generated on first run if absent.
/// Uses cryptographically secure random bytes for key generation.
class DbSecureStore {
  static const _keyDbEncryption = 'db_encryption_key';
  static const _legacyKeyName = 'isar_encryption_key';
  static const _dbFileName = 'omni_runner.sqlite';
  static const _tag = 'DbSecureStore';

  final FlutterSecureStorage _storage;

  const DbSecureStore({
    FlutterSecureStorage storage = _hardenedStorage,
  }) : _storage = storage;

  /// L01-33 — Wrap secure-storage reads in try/catch. On Android a
  /// corrupted Keystore (rare, but documented in the
  /// flutter_secure_storage issue tracker) raises PlatformException.
  /// Without this guard the app crashes at boot and the user is locked
  /// out until reinstall. We treat the error as "key not found", wipe
  /// the encrypted DB (it is unreadable without the key anyway) and
  /// regenerate. The user loses local cache (will resync from
  /// Supabase) but the app is usable again.
  Future<String?> _safeRead(String key) async {
    try {
      return await _storage.read(key: key);
    } on PlatformException catch (e, st) {
      AppLogger.error(
        'L01-33: secure_storage corrupted (key=$key); regenerating',
        tag: _tag,
        error: e,
        stack: st,
      );
      await clearKeyAndDatabase();
      return null;
    }
  }

  /// Returns a 32-byte key for database encryption.
  /// Generates and persists a new key on first run.
  /// Migrates legacy key name if present.
  Future<List<int>> getOrCreateKey() async {
    var existing = await _safeRead(_keyDbEncryption);

    if (existing == null || existing.isEmpty) {
      existing = await _safeRead(_legacyKeyName);
      if (existing != null && existing.isNotEmpty) {
        await _storage.write(key: _keyDbEncryption, value: existing);
        await _storage.delete(key: _legacyKeyName);
        AppLogger.debug('Migrated legacy encryption key', tag: _tag);
      }
    }

    if (existing != null && existing.isNotEmpty) {
      return base64Decode(existing);
    }

    final key = _generateKey();
    await _storage.write(key: _keyDbEncryption, value: base64Encode(key));
    AppLogger.debug('DB encryption key generated and stored', tag: _tag);
    return key;
  }

  List<int> _generateKey() {
    final random = Random.secure();
    final randomBytes = List<int>.generate(32, (_) => random.nextInt(256));
    final digest = sha256.convert(randomBytes);
    return digest.bytes;
  }

  /// Clears the encryption key AND deletes the database file.
  /// Without the key the encrypted DB is unreadable, so keeping it would
  /// only waste disk space.
  Future<void> clearKeyAndDatabase() async {
    await _storage.delete(key: _keyDbEncryption);
    await _storage.delete(key: _legacyKeyName);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final dbFile = File('${dir.path}/$_dbFileName');
      if (dbFile.existsSync()) {
        dbFile.deleteSync();
        AppLogger.debug('Encrypted DB file deleted', tag: _tag);
      }
    } on Object catch (e) {
      AppLogger.warn('Failed to delete DB file: $e', tag: _tag);
    }
    AppLogger.debug('DB encryption key cleared', tag: _tag);
  }
}
