import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:omni_runner/core/logging/logger.dart';

/// Provides a 256-bit encryption key for Isar database encryption.
///
/// Key is stored in FlutterSecureStorage, generated on first run if absent.
/// Uses cryptographically secure random bytes for key generation.
///
/// Note: Isar 3.1.0 does not yet expose an encryptionKey parameter in Isar.open().
/// This store prepares the infrastructure; when Isar adds encryption support,
/// pass [getOrCreateKey] to Isar.open(encryptionKey: ...).
class IsarSecureStore {
  static const _keyIsarEncryption = 'isar_encryption_key';
  static const _tag = 'IsarSecureStore';

  final FlutterSecureStorage _storage;

  const IsarSecureStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  /// Returns a 32-byte key for Isar encryption.
  /// Generates and persists a new key on first run.
  Future<List<int>> getOrCreateKey() async {
    final existing = await _storage.read(key: _keyIsarEncryption);
    if (existing != null && existing.isNotEmpty) {
      return base64Decode(existing);
    }

    final key = _generateKey();
    await _storage.write(key: _keyIsarEncryption, value: base64Encode(key));
    AppLogger.debug('Isar encryption key generated and stored', tag: _tag);
    return key;
  }

  List<int> _generateKey() {
    final random = Random.secure();
    final randomBytes = List<int>.generate(32, (_) => random.nextInt(256));
    final digest = sha256.convert(randomBytes);
    return digest.bytes;
  }

  /// Clears the stored key. Call on logout to prevent key reuse across accounts.
  Future<void> clearKey() async {
    await _storage.delete(key: _keyIsarEncryption);
    AppLogger.debug('Isar encryption key cleared', tag: _tag);
  }
}
