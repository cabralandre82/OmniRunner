import 'package:omni_runner/domain/value_objects/audio_coach_locale.dart';
import 'package:omni_runner/domain/value_objects/challenge_invite_link.dart';
import 'package:omni_runner/domain/value_objects/challenge_share_channel.dart';

/// Pure, locale-aware share-copy renderer for challenge invites.
///
/// Reuses [AudioCoachLocale] as the locale key (pt-BR/en/es) so the
/// amateur-facing i18n surface stays in one place. The UI layer may
/// still translate labels through `AppLocalizations`, but the
/// shared *message* that leaves the device funnels through this
/// builder to:
///
///   * keep emoji / whitespace / URL-encoding consistent
///   * avoid leaking partial translations (e.g. pt-BR challenge
///     title with English wrapper copy) into WhatsApp chats
///   * make the `audit:challenge-invite-deep-link` CI guard simple
///     to keep honest (one file, one catalogue, one test matrix)
///
/// Finding reference: L22-08.
class ChallengeInviteMessageBuilder {
  final AudioCoachLocale locale;

  const ChallengeInviteMessageBuilder({this.locale = AudioCoachLocale.ptBR});

  /// Build the plain-text body that accompanies the invite URL for
  /// [channel]. The URL itself is produced by [link] and appended
  /// by this method — callers must not concatenate the URL
  /// themselves to avoid double-URL bugs that hurt WhatsApp link
  /// previews.
  ///
  /// [challengeTitle] is optional (null / empty falls back to a
  /// generic "challenge" label per locale). Passing an attacker-
  /// controlled title is safe: this method returns text, never
  /// executes it, and the downstream share gateway URL-encodes the
  /// full body when routing through `wa.me`.
  String build({
    required ChallengeInviteLink link,
    required ChallengeShareChannel channel,
    String? challengeTitle,
    String? inviterDisplayName,
  }) {
    final title =
        (challengeTitle == null || challengeTitle.trim().isEmpty)
            ? _fallbackTitle()
            : challengeTitle.trim();
    final inviter = (inviterDisplayName == null ||
            inviterDisplayName.trim().isEmpty)
        ? null
        : inviterDisplayName.trim();

    switch (channel) {
      case ChallengeShareChannel.whatsapp:
        return _whatsapp(title: title, inviter: inviter, url: link.url);
      case ChallengeShareChannel.native:
        return _native(title: title, inviter: inviter, url: link.url);
      case ChallengeShareChannel.copyLink:
        return link.url;
    }
  }

  /// Build the `https://wa.me/?text=...` URL used by the WhatsApp
  /// "Convidar via WhatsApp" button. URL-encodes the body so
  /// trailing emoji / newlines survive the query string.
  String buildWhatsAppUrl({
    required ChallengeInviteLink link,
    String? challengeTitle,
    String? inviterDisplayName,
  }) {
    final body = build(
      link: link,
      channel: ChallengeShareChannel.whatsapp,
      challengeTitle: challengeTitle,
      inviterDisplayName: inviterDisplayName,
    );
    final encoded = Uri.encodeQueryComponent(body);
    return 'https://wa.me/?text=$encoded';
  }

  String _whatsapp({
    required String title,
    required String? inviter,
    required String url,
  }) {
    switch (locale) {
      case AudioCoachLocale.ptBR:
        final opener = inviter == null
            ? 'Bora correr? '
            : '$inviter chamou: bora correr? ';
        return '$opener🏃‍♂️\n'
            'Te desafiei no Omni Runner: "$title"\n\n'
            '$url';
      case AudioCoachLocale.en:
        final opener = inviter == null
            ? "Let's run! "
            : '$inviter challenged you: ';
        return '$opener🏃‍♂️\n'
            'Take on my Omni Runner challenge: "$title"\n\n'
            '$url';
      case AudioCoachLocale.es:
        final opener = inviter == null
            ? '¡A correr! '
            : '$inviter te retó: ';
        return '$opener🏃‍♂️\n'
            'Acepta mi reto en Omni Runner: "$title"\n\n'
            '$url';
    }
  }

  String _native({
    required String title,
    required String? inviter,
    required String url,
  }) {
    switch (locale) {
      case AudioCoachLocale.ptBR:
        final opener = inviter == null
            ? 'Participe do meu desafio'
            : '$inviter te convidou para o desafio';
        return '$opener "$title" no Omni Runner.\n\n$url';
      case AudioCoachLocale.en:
        final opener = inviter == null
            ? 'Join my challenge'
            : '$inviter invited you to the challenge';
        return '$opener "$title" on Omni Runner.\n\n$url';
      case AudioCoachLocale.es:
        final opener = inviter == null
            ? 'Únete a mi reto'
            : '$inviter te invitó al reto';
        return '$opener "$title" en Omni Runner.\n\n$url';
    }
  }

  String _fallbackTitle() {
    switch (locale) {
      case AudioCoachLocale.ptBR:
        return 'Desafio no Omni Runner';
      case AudioCoachLocale.en:
        return 'Omni Runner challenge';
      case AudioCoachLocale.es:
        return 'Reto Omni Runner';
    }
  }

  /// Locales required to be covered by this builder. Mirrored in
  /// `tools/audit/check-challenge-invite-deep-link.ts` so CI fails
  /// if any locale silently regresses (e.g. a rebase drops `es`).
  static const List<AudioCoachLocale> supportedLocales = [
    AudioCoachLocale.ptBR,
    AudioCoachLocale.en,
    AudioCoachLocale.es,
  ];
}
