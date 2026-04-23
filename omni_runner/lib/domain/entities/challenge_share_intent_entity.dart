import 'package:omni_runner/domain/value_objects/challenge_share_channel.dart';

/// Fully-composed share payload, ready to hand off to a gateway
/// (WhatsApp via `url_launcher`, native share sheet via
/// `share_plus`, or clipboard).
///
/// The domain-layer [ChallengeShareIntentEntity] deliberately
/// carries both [text] and [url] as separate fields even though
/// [text] already contains [url] — downstream gateways may want
/// to split them (e.g. pass [url] as the native share sheet's
/// "subject" or generate an OG preview URL) without re-parsing.
///
/// Finding reference: L22-08.
class ChallengeShareIntentEntity {
  final ChallengeShareChannel channel;

  /// Canonical HTTPS deep-link URL, e.g.
  /// `https://omnirunner.app/challenge/abc123`.
  final String url;

  /// Fully-composed body. For [ChallengeShareChannel.whatsapp]
  /// this is the text to route through `wa.me/?text=<encoded>`.
  /// For [ChallengeShareChannel.copyLink] this equals [url].
  final String text;

  /// Optional "subject" hint for channels that expose one (email,
  /// iOS share sheet). May be `null` for WhatsApp.
  final String? subject;

  /// Pre-built platform URL (WhatsApp `wa.me` link) that the
  /// gateway should `launchUrl`. `null` when no platform URL
  /// applies (native/share-sheet and copy-link channels).
  final String? platformLaunchUrl;

  const ChallengeShareIntentEntity({
    required this.channel,
    required this.url,
    required this.text,
    this.subject,
    this.platformLaunchUrl,
  });
}
