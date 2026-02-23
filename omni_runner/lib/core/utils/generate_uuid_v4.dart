import 'dart:math';

/// Generate an RFC 4122 version 4 UUID using a cryptographic RNG.
///
/// Returns a lowercase string in the format `xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx`.
/// Uses [Random.secure] backed by `/dev/urandom` (Linux/Android) or
/// `SecRandomCopyBytes` (iOS).
String generateUuidV4() {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10
  return '${_hex(bytes, 0, 4)}-${_hex(bytes, 4, 6)}-'
      '${_hex(bytes, 6, 8)}-${_hex(bytes, 8, 10)}-'
      '${_hex(bytes, 10, 16)}';
}

String _hex(List<int> bytes, int start, int end) {
  return bytes
      .sublist(start, end)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}
