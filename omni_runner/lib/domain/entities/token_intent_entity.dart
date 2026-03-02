import 'dart:convert';

/// The three backend-supported token intent operations.
///
/// Maps to `token_intents.type` column CHECK constraint.
enum TokenIntentType {
  issueToAthlete,
  burnFromAthlete,
  champBadgeActivate,
}

String tokenIntentTypeToString(TokenIntentType t) => switch (t) {
      TokenIntentType.issueToAthlete => 'ISSUE_TO_ATHLETE',
      TokenIntentType.burnFromAthlete => 'BURN_FROM_ATHLETE',
      TokenIntentType.champBadgeActivate => 'CHAMP_BADGE_ACTIVATE',
    };

TokenIntentType tokenIntentTypeFromString(String s) => switch (s) {
      'ISSUE_TO_ATHLETE' => TokenIntentType.issueToAthlete,
      'BURN_FROM_ATHLETE' => TokenIntentType.burnFromAthlete,
      'CHAMP_BADGE_ACTIVATE' => TokenIntentType.champBadgeActivate,
      _ => throw ArgumentError('Unknown TokenIntentType: $s'),
    };

/// UI label for each intent type.
String tokenIntentLabel(TokenIntentType t) => switch (t) {
      TokenIntentType.issueToAthlete => 'Emitir OmniCoins',
      TokenIntentType.burnFromAthlete => 'Recolher OmniCoins',
      TokenIntentType.champBadgeActivate => 'Ativar Badge de Campeonato',
    };

/// Snapshot of the group's token inventory for emission capacity display.
final class EmissionCapacity {
  final int availableTokens;
  final int lifetimeIssued;
  final int lifetimeBurned;

  const EmissionCapacity({
    required this.availableTokens,
    required this.lifetimeIssued,
    required this.lifetimeBurned,
  });

  static const empty = EmissionCapacity(
    availableTokens: 0,
    lifetimeIssued: 0,
    lifetimeBurned: 0,
  );
}

/// QR payload containing all data needed to consume a token intent.
///
/// Serialized as JSON → base64url for the QR code content.
/// Includes [nonce] and [expiresAtMs] for anti-replay protection.
final class StaffQrPayload {
  final String intentId;
  final TokenIntentType type;
  final String groupId;
  final int amount;
  final String nonce;
  final int expiresAtMs;

  /// Optional: championship ID for CHAMP_BADGE_ACTIVATE intents.
  final String? championshipId;

  const StaffQrPayload({
    required this.intentId,
    required this.type,
    required this.groupId,
    required this.amount,
    required this.nonce,
    required this.expiresAtMs,
    this.championshipId,
  });

  bool get isExpired =>
      DateTime.now().millisecondsSinceEpoch >= expiresAtMs;

  Duration get remainingDuration {
    final delta = expiresAtMs - DateTime.now().millisecondsSinceEpoch;
    return delta > 0 ? Duration(milliseconds: delta) : Duration.zero;
  }

  Map<String, dynamic> toJson() => {
        'iid': intentId,
        'typ': tokenIntentTypeToString(type),
        'gid': groupId,
        'amt': amount,
        'non': nonce,
        'exp': expiresAtMs,
        if (championshipId != null) 'cid': championshipId,
      };

  factory StaffQrPayload.fromJson(Map<String, dynamic> json) =>
      StaffQrPayload(
        intentId: json['iid'] as String,
        type: tokenIntentTypeFromString(json['typ'] as String),
        groupId: json['gid'] as String,
        amount: json['amt'] as int,
        nonce: json['non'] as String,
        expiresAtMs: json['exp'] as int,
        championshipId: json['cid'] as String?,
      );

  /// Encode to base64url string for embedding in a QR code.
  String encode() => base64Url.encode(utf8.encode(jsonEncode(toJson())));

  /// Decode from a base64url QR code string.
  factory StaffQrPayload.decode(String encoded) {
    final json = jsonDecode(utf8.decode(base64Url.decode(encoded)))
        as Map<String, dynamic>;
    return StaffQrPayload.fromJson(json);
  }
}
