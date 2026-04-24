import 'package:flutter_test/flutter_test.dart';

import 'package:omni_runner/core/deep_links/deep_link_handler.dart';

void main() {
  final handler = DeepLinkHandler();

  group('isOmniRunnerWebHost', () {
    test('accepts apex and www', () {
      expect(DeepLinkHandler.isOmniRunnerWebHost('omnirunner.app'), isTrue);
      expect(DeepLinkHandler.isOmniRunnerWebHost('www.omnirunner.app'), isTrue);
    });

    test('host comparison is case-insensitive', () {
      expect(DeepLinkHandler.isOmniRunnerWebHost('OMNIRUNNER.APP'), isTrue);
      expect(DeepLinkHandler.isOmniRunnerWebHost('WWW.OMNIRUNNER.APP'), isTrue);
    });

    test('rejects other hosts', () {
      expect(DeepLinkHandler.isOmniRunnerWebHost('evil.omnirunner.app'), isFalse);
      expect(DeepLinkHandler.isOmniRunnerWebHost('omnirunner.app.evil'), isFalse);
      expect(DeepLinkHandler.isOmniRunnerWebHost('localhost'), isFalse);
    });
  });

  group('parseUri', () {
    test('invite apex host', () {
      final u = Uri.parse('https://omnirunner.app/invite/ABC123');
      final a = handler.parseUri(u);
      expect(a, isA<InviteAction>());
      expect((a as InviteAction).code, 'ABC123');
    });

    test('invite www host', () {
      final u = Uri.parse('https://www.omnirunner.app/invite/XYZ');
      final a = handler.parseUri(u);
      expect(a, isA<InviteAction>());
      expect((a as InviteAction).code, 'XYZ');
    });

    test('challenge link', () {
      final u = Uri.parse('https://omnirunner.app/challenge/ch-99');
      final a = handler.parseUri(u);
      expect(a, isA<ChallengeAction>());
      expect((a as ChallengeAction).challengeId, 'ch-99');
    });

    test('referral link', () {
      final u = Uri.parse('https://omnirunner.app/refer/user-uuid-1');
      final a = handler.parseUri(u);
      expect(a, isA<ReferralAction>());
      expect((a as ReferralAction).referrerId, 'user-uuid-1');
    });

    // L01-29: legacy `omnirunner://strava/...` and
    // `omnirunner://localhost/exchange_token` paths now classify as
    // UnknownLinkAction. Production OAuth runs via flutter_web_auth_2
    // on the dedicated `omnirunnerauth://` scheme, validated by
    // StravaOAuthStateGuard inside the auth repository.
    test('Strava exchange_token deep-link is now UnknownLinkAction (L01-29)', () {
      final u = Uri.parse(
        'omnirunner://localhost/exchange_token?code=ATTACKER_CODE&scope=read',
      );
      expect(handler.parseUri(u), isA<UnknownLinkAction>());
    });

    test('Strava legacy callback deep-link is now UnknownLinkAction (L01-29)', () {
      final u = Uri.parse('omnirunner://strava/callback?code=ATTACKER_CODE');
      expect(handler.parseUri(u), isA<UnknownLinkAction>());
    });

    test(
      'Strava callback with code + state is still UnknownLinkAction (L01-29)',
      () {
        // Even with a valid-looking state, the deep-link handler is no
        // longer the OAuth callback path. The state guard lives behind
        // FlutterWebAuth2 and is unreachable from here.
        final u = Uri.parse(
          'omnirunner://localhost/exchange_token?code=X&state=Y',
        );
        expect(handler.parseUri(u), isA<UnknownLinkAction>());
      },
    );

    test('unknown https host', () {
      final u = Uri.parse('https://evil.example/invite/x');
      expect(handler.parseUri(u), isA<UnknownLinkAction>());
    });
  });

  group('extractInviteCode', () {
    test('full URL apex', () {
      expect(
        DeepLinkHandler.extractInviteCode('https://omnirunner.app/invite/CODE1'),
        'CODE1',
      );
    });

    test('full URL www', () {
      expect(
        DeepLinkHandler.extractInviteCode(
          'https://www.omnirunner.app/invite/CODE2',
        ),
        'CODE2',
      );
    });

    test('raw code', () {
      expect(DeepLinkHandler.extractInviteCode('RAWCODE'), 'RAWCODE');
    });

    test('non-invite URL returns null', () {
      expect(
        DeepLinkHandler.extractInviteCode('https://omnirunner.app/challenge/x'),
        isNull,
      );
    });

    // L01-28 — random QR text must NOT round-trip as an "invite code"
    test('random QR text is rejected (L01-28)', () {
      expect(DeepLinkHandler.extractInviteCode('BUY BITCOIN'), isNull);
      expect(DeepLinkHandler.extractInviteCode('hello world'), isNull);
      expect(DeepLinkHandler.extractInviteCode('lowercase'), isNull);
      expect(DeepLinkHandler.extractInviteCode('SHORT'), isNull); // < 6
      expect(
        DeepLinkHandler.extractInviteCode('A' * 17),
        isNull, // > 16 → out of band
      );
    });

    test('valid uppercase alnum codes are accepted (L01-28)', () {
      expect(DeepLinkHandler.extractInviteCode('ABCDEF'), 'ABCDEF');
      expect(DeepLinkHandler.extractInviteCode('A1B2C3'), 'A1B2C3');
      expect(
        DeepLinkHandler.extractInviteCode('CLUB-2026_Q1'),
        'CLUB-2026_Q1',
      );
    });

    test('URL with malformed code returns null (L01-28)', () {
      expect(
        DeepLinkHandler.extractInviteCode(
          'https://omnirunner.app/invite/lowercase',
        ),
        isNull,
      );
    });
  });
}
