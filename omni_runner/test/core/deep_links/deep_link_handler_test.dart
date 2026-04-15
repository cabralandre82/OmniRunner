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

    test('Strava exchange_token with code', () {
      final u = Uri.parse(
        'omnirunner://localhost/exchange_token?code=SECRET&scope=read',
      );
      final a = handler.parseUri(u);
      expect(a, isA<StravaCallbackAction>());
      expect((a as StravaCallbackAction).code, 'SECRET');
    });

    test('Strava legacy callback', () {
      final u = Uri.parse('omnirunner://strava/callback?code=LEGACY');
      final a = handler.parseUri(u);
      expect(a, isA<StravaCallbackAction>());
      expect((a as StravaCallbackAction).code, 'LEGACY');
    });

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
  });
}
