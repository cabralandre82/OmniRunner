/// Canonical deep-link for challenge invites.
///
/// Produces the HTTPS URL advertised on Android App Links
/// (`/.well-known/assetlinks.json`) and iOS Universal Links
/// (`/.well-known/apple-app-site-association`). See
/// `docs/UNIVERSAL_LINKS_SETUP.md` for the platform verification
/// contract and `portal/public/.well-known/*` for the served files.
///
/// Kept as a value object (not a free-form string) so every share
/// surface — WhatsApp button, native share sheet, copy-to-clipboard,
/// image card, push notification body — funnels through the same
/// canonical URL. Prevents host drift (e.g. `www.` vs apex, typos
/// like `omni-runner.app`, custom schemes leaking into web shares)
/// which would break the App Links auto-verification.
///
/// Finding reference: L22-08 (Desafio de grupo / viralização entre
/// amigos).
class ChallengeInviteLink {
  /// Canonical HTTPS host bound to the `.well-known/*` proofs.
  ///
  /// Changing this constant is a multi-platform migration: every
  /// released app version parses deep links against
  /// [isCanonicalHost], and the Android App Links verifier only
  /// trusts the host declared in `AndroidManifest.xml`. Coordinate
  /// with `docs/runbooks/CHALLENGE_INVITE_VIRAL_RUNBOOK.md` before
  /// touching.
  static const String canonicalHost = 'omnirunner.app';

  /// Accepted host aliases — `omnirunner.app` is canonical; `www.`
  /// prefix is forwarded by the portal for SEO compatibility.
  static const List<String> acceptedHosts = [
    'omnirunner.app',
    'www.omnirunner.app',
  ];

  /// URL path segment. Kept in sync with the `paths` array in
  /// `portal/public/.well-known/apple-app-site-association` and the
  /// `DeepLinkHandler` parser.
  static const String pathSegment = 'challenge';

  final String challengeId;

  const ChallengeInviteLink._(this.challengeId);

  /// Build a [ChallengeInviteLink] from a non-empty challenge id.
  ///
  /// Throws [ArgumentError] for empty ids to avoid generating the
  /// degenerate URL `https://omnirunner.app/challenge/` which would
  /// land users on a dead page.
  factory ChallengeInviteLink.forId(String challengeId) {
    if (challengeId.isEmpty) {
      throw ArgumentError.value(
        challengeId,
        'challengeId',
        'Challenge id must not be empty.',
      );
    }
    return ChallengeInviteLink._(challengeId);
  }

  /// Fully-qualified HTTPS URL suitable for every share surface.
  String get url => 'https://$canonicalHost/$pathSegment/$challengeId';

  /// Canonical host check used by [ChallengeInviteLink] and the
  /// deep-link parser. Case-insensitive.
  static bool isCanonicalHost(String host) {
    final h = host.toLowerCase();
    return acceptedHosts.contains(h);
  }

  /// Attempt to extract a challenge id from an arbitrary URL string.
  ///
  /// Returns `null` when:
  ///   * the string is not parseable as a [Uri]
  ///   * the host is not one of [acceptedHosts]
  ///   * the first path segment is not [pathSegment]
  ///   * the id segment is empty
  static String? tryExtractId(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    if (!isCanonicalHost(uri.host)) return null;
    if (uri.pathSegments.length < 2) return null;
    if (uri.pathSegments[0] != pathSegment) return null;
    final id = uri.pathSegments[1];
    if (id.isEmpty) return null;
    return id;
  }

  @override
  String toString() => url;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChallengeInviteLink && other.challengeId == challengeId;

  @override
  int get hashCode => challengeId.hashCode;
}
