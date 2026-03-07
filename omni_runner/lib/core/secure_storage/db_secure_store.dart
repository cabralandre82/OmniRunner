import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:path_provider/path_provider.dart';

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
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  /// Returns a 32-byte key for database encryption.
  /// Generates and persists a new key on first run.
  /// Migrates legacy key name if present.
  Future<List<int>> getOrCreateKey() async {
    // Try current key first
    var existing = await _storage.read(key: _keyDbEncryption);

    // Migrate from legacy key name if needed
    if (existing == null || existing.isEmpty) {
      existing = await _storage.read(key: _legacyKeyName);
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
      if (await dbFile.exists()) {
        await dbFile.delete();
        AppLogger.debug('Encrypted DB file deleted', tag: _tag);
      }
    } catch (e) {
      AppLogger.warn('Failed to delete DB file: $e', tag: _tag);
    }
    AppLogger.debug('DB encryption key cleared', tag: _tag);
  }
}
