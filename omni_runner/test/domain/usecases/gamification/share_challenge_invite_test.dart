import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/usecases/gamification/share_challenge_invite.dart';
import 'package:omni_runner/domain/value_objects/audio_coach_locale.dart';
import 'package:omni_runner/domain/value_objects/challenge_invite_link.dart';
import 'package:omni_runner/domain/value_objects/challenge_share_channel.dart';

void main() {
  group('ShareChallengeInvite', () {
    test('WhatsApp channel populates platformLaunchUrl with wa.me', () {
      final usecase = ShareChallengeInvite();
      final intent = usecase(
        challengeId: 'abc123',
        channel: ChallengeShareChannel.whatsapp,
        challengeTitle: 'Sprint 10k',
      );
      expect(intent.channel, ChallengeShareChannel.whatsapp);
      expect(intent.url, 'https://omnirunner.app/challenge/abc123');
      expect(intent.platformLaunchUrl, isNotNull);
      expect(intent.platformLaunchUrl, startsWith('https://wa.me/?text='));
      expect(intent.text, contains('Sprint 10k'));
      expect(intent.text, contains(intent.url));
    });

    test('native channel skips platformLaunchUrl', () {
      final usecase = ShareChallengeInvite();
      final intent = usecase(
        challengeId: 'abc123',
        channel: ChallengeShareChannel.native,
        challengeTitle: 'Sprint 10k',
      );
      expect(intent.platformLaunchUrl, isNull);
      expect(intent.url, 'https://omnirunner.app/challenge/abc123');
      expect(intent.text, contains(intent.url));
    });

    test('copyLink channel returns URL verbatim as text', () {
      final usecase = ShareChallengeInvite();
      final intent = usecase(
        challengeId: 'abc123',
        channel: ChallengeShareChannel.copyLink,
        challengeTitle: 'Sprint 10k',
      );
      expect(intent.platformLaunchUrl, isNull);
      expect(intent.text, intent.url);
    });

    test('locale switch actually changes the composed copy', () {
      final ptBr = ShareChallengeInvite()(
        challengeId: 'abc123',
        channel: ChallengeShareChannel.whatsapp,
        challengeTitle: 'T',
      );
      final en = ShareChallengeInvite(locale: AudioCoachLocale.en)(
        challengeId: 'abc123',
        channel: ChallengeShareChannel.whatsapp,
        challengeTitle: 'T',
      );
      final es = ShareChallengeInvite(locale: AudioCoachLocale.es)(
        challengeId: 'abc123',
        channel: ChallengeShareChannel.whatsapp,
        challengeTitle: 'T',
      );
      expect(ptBr.text, isNot(en.text));
      expect(ptBr.text, isNot(es.text));
      expect(en.text, isNot(es.text));
    });

    test('empty challenge id throws ArgumentError (no degenerate URL leaks)',
        () {
      final usecase = ShareChallengeInvite();
      expect(
        () => usecase(
          challengeId: '',
          channel: ChallengeShareChannel.whatsapp,
        ),
        throwsArgumentError,
      );
    });

    test('subject mirrors challenge title when provided', () {
      final intent = ShareChallengeInvite()(
        challengeId: 'abc123',
        channel: ChallengeShareChannel.native,
        challengeTitle: 'Sprint 10k',
      );
      expect(intent.subject, 'Sprint 10k');
    });

    test('ChallengeInviteLink url is always the canonical host', () {
      final intent = ShareChallengeInvite()(
        challengeId: 'abc123',
        channel: ChallengeShareChannel.whatsapp,
      );
      expect(
        intent.url,
        'https://${ChallengeInviteLink.canonicalHost}/challenge/abc123',
      );
    });
  });
}
