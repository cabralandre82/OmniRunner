import 'package:omni_runner/domain/entities/challenge_share_intent_entity.dart';
import 'package:omni_runner/domain/services/challenge_invite_message_builder.dart';
import 'package:omni_runner/domain/value_objects/audio_coach_locale.dart';
import 'package:omni_runner/domain/value_objects/challenge_invite_link.dart';
import 'package:omni_runner/domain/value_objects/challenge_share_channel.dart';

/// Compose a [ChallengeShareIntentEntity] for a given challenge id
/// and share channel.
///
/// Keeps the presentation layer dumb: callers pass the channel the
/// user tapped and receive a fully-composed payload. No platform
/// calls happen here — dispatch is the job of a gateway in the
/// data layer (wrapping `url_launcher` / `share_plus`).
///
/// Finding reference: L22-08.
class ShareChallengeInvite {
  final ChallengeInviteMessageBuilder _builder;

  ShareChallengeInvite({
    ChallengeInviteMessageBuilder? builder,
    AudioCoachLocale locale = AudioCoachLocale.ptBR,
  }) : _builder =
            builder ?? ChallengeInviteMessageBuilder(locale: locale);

  ChallengeShareIntentEntity call({
    required String challengeId,
    required ChallengeShareChannel channel,
    String? challengeTitle,
    String? inviterDisplayName,
  }) {
    final link = ChallengeInviteLink.forId(challengeId);
    final text = _builder.build(
      link: link,
      channel: channel,
      challengeTitle: challengeTitle,
      inviterDisplayName: inviterDisplayName,
    );

    String? platformLaunchUrl;
    if (channel == ChallengeShareChannel.whatsapp) {
      platformLaunchUrl = _builder.buildWhatsAppUrl(
        link: link,
        challengeTitle: challengeTitle,
        inviterDisplayName: inviterDisplayName,
      );
    }

    return ChallengeShareIntentEntity(
      channel: channel,
      url: link.url,
      text: text,
      subject: challengeTitle,
      platformLaunchUrl: platformLaunchUrl,
    );
  }
}
