import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/services/challenge_invite_message_builder.dart';
import 'package:omni_runner/domain/value_objects/audio_coach_locale.dart';
import 'package:omni_runner/domain/value_objects/challenge_invite_link.dart';
import 'package:omni_runner/domain/value_objects/challenge_share_channel.dart';

void main() {
  final inviteLink = ChallengeInviteLink.forId('abc123');

  group('ChallengeInviteMessageBuilder — contract', () {
    test('canonical host is stable', () {
      expect(ChallengeInviteLink.canonicalHost, 'omnirunner.app');
    });

    test('default locale is pt-BR (primary market)', () {
      const builder = ChallengeInviteMessageBuilder();
      expect(builder.locale, AudioCoachLocale.ptBR);
    });

    test('supportedLocales enumerates pt-BR, en, es', () {
      expect(ChallengeInviteMessageBuilder.supportedLocales,
          containsAll(<AudioCoachLocale>[
            AudioCoachLocale.ptBR,
            AudioCoachLocale.en,
            AudioCoachLocale.es,
          ]));
    });

    test('copyLink channel returns URL verbatim in every locale', () {
      for (final locale in ChallengeInviteMessageBuilder.supportedLocales) {
        final b = ChallengeInviteMessageBuilder(locale: locale);
        expect(
          b.build(
            link: inviteLink,
            channel: ChallengeShareChannel.copyLink,
            challengeTitle: 'X',
            inviterDisplayName: 'Maria',
          ),
          inviteLink.url,
          reason: 'locale=${locale.languageTag}',
        );
      }
    });

    test('every locale embeds the deep link URL in WhatsApp copy', () {
      for (final locale in ChallengeInviteMessageBuilder.supportedLocales) {
        final b = ChallengeInviteMessageBuilder(locale: locale);
        final text = b.build(
          link: inviteLink,
          channel: ChallengeShareChannel.whatsapp,
          challengeTitle: 'Sprint 10k',
          inviterDisplayName: 'Maria',
        );
        expect(text, contains(inviteLink.url),
            reason: 'locale=${locale.languageTag}');
        expect(text, contains('Sprint 10k'),
            reason: 'locale=${locale.languageTag}');
      }
    });

    test('every locale embeds the deep link URL in native-share copy', () {
      for (final locale in ChallengeInviteMessageBuilder.supportedLocales) {
        final b = ChallengeInviteMessageBuilder(locale: locale);
        final text = b.build(
          link: inviteLink,
          channel: ChallengeShareChannel.native,
          challengeTitle: 'Sprint 10k',
        );
        expect(text, contains(inviteLink.url),
            reason: 'locale=${locale.languageTag}');
      }
    });

    test('inviter name is embedded when provided, omitted when null', () {
      const b = ChallengeInviteMessageBuilder(locale: AudioCoachLocale.ptBR);
      final withInviter = b.build(
        link: inviteLink,
        channel: ChallengeShareChannel.whatsapp,
        challengeTitle: 'T',
        inviterDisplayName: 'Maria',
      );
      final withoutInviter = b.build(
        link: inviteLink,
        channel: ChallengeShareChannel.whatsapp,
        challengeTitle: 'T',
      );
      expect(withInviter, contains('Maria'));
      expect(withoutInviter, isNot(contains('Maria')));
    });

    test('empty/whitespace title falls back to generic locale label', () {
      for (final locale in ChallengeInviteMessageBuilder.supportedLocales) {
        final b = ChallengeInviteMessageBuilder(locale: locale);
        final a = b.build(
          link: inviteLink,
          channel: ChallengeShareChannel.whatsapp,
          challengeTitle: '',
        );
        final c = b.build(
          link: inviteLink,
          channel: ChallengeShareChannel.whatsapp,
          challengeTitle: '   ',
        );
        final nullTitle = b.build(
          link: inviteLink,
          channel: ChallengeShareChannel.whatsapp,
          challengeTitle: null,
        );
        // All three collapse to the same fallback body.
        expect(a, equals(c));
        expect(a, equals(nullTitle));
      }
    });

    test('pt-BR WhatsApp copy starts with the friendly "Bora correr" opener', () {
      const b = ChallengeInviteMessageBuilder(locale: AudioCoachLocale.ptBR);
      final text = b.build(
        link: inviteLink,
        channel: ChallengeShareChannel.whatsapp,
        challengeTitle: 'T',
      );
      expect(text, startsWith('Bora correr?'));
    });

    test("en WhatsApp copy starts with the friendly \"Let's run\" opener", () {
      const b = ChallengeInviteMessageBuilder(locale: AudioCoachLocale.en);
      final text = b.build(
        link: inviteLink,
        channel: ChallengeShareChannel.whatsapp,
        challengeTitle: 'T',
      );
      expect(text, startsWith("Let's run!"));
    });

    test('es WhatsApp copy starts with "¡A correr!"', () {
      const b = ChallengeInviteMessageBuilder(locale: AudioCoachLocale.es);
      final text = b.build(
        link: inviteLink,
        channel: ChallengeShareChannel.whatsapp,
        challengeTitle: 'T',
      );
      expect(text, startsWith('¡A correr!'));
    });

    test('buildWhatsAppUrl URL-encodes the body onto wa.me', () {
      const b = ChallengeInviteMessageBuilder(locale: AudioCoachLocale.ptBR);
      final url = b.buildWhatsAppUrl(
        link: inviteLink,
        challengeTitle: 'Sprint 10k & friends',
        inviterDisplayName: 'Maria',
      );
      expect(url, startsWith('https://wa.me/?text='));
      // Spaces must never leak into the URL (Uri.encodeQueryComponent
      // uses the x-www-form-urlencoded '+' convention, which WhatsApp
      // accepts; the point is that no raw space escapes).
      expect(url, isNot(contains(' ')));
      // Ampersand in title must be encoded to %26 to avoid truncating
      // the query body.
      expect(url, contains('%26'));
    });
  });
}
