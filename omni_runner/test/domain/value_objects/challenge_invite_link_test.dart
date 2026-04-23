import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/value_objects/challenge_invite_link.dart';

void main() {
  group('ChallengeInviteLink', () {
    test('canonical host is omnirunner.app and must not silently change', () {
      expect(ChallengeInviteLink.canonicalHost, 'omnirunner.app');
    });

    test('accepted hosts include apex and www. alias only', () {
      expect(
        ChallengeInviteLink.acceptedHosts,
        containsAll(<String>['omnirunner.app', 'www.omnirunner.app']),
      );
      expect(ChallengeInviteLink.acceptedHosts.length, 2);
    });

    test('path segment is "challenge" and matches apple-app-site-association', () {
      expect(ChallengeInviteLink.pathSegment, 'challenge');
    });

    test('forId produces canonical HTTPS URL', () {
      final link = ChallengeInviteLink.forId('abc123');
      expect(link.url, 'https://omnirunner.app/challenge/abc123');
      expect(link.toString(), link.url);
    });

    test('forId rejects empty challenge ids', () {
      expect(() => ChallengeInviteLink.forId(''), throwsArgumentError);
    });

    test('isCanonicalHost accepts apex and www. (case-insensitive)', () {
      expect(ChallengeInviteLink.isCanonicalHost('omnirunner.app'), isTrue);
      expect(ChallengeInviteLink.isCanonicalHost('OMNIRUNNER.APP'), isTrue);
      expect(ChallengeInviteLink.isCanonicalHost('www.omnirunner.app'), isTrue);
      expect(ChallengeInviteLink.isCanonicalHost('omni-runner.app'), isFalse);
      expect(ChallengeInviteLink.isCanonicalHost('evil.com'), isFalse);
      expect(ChallengeInviteLink.isCanonicalHost(''), isFalse);
    });

    test('tryExtractId parses well-formed URLs', () {
      expect(
        ChallengeInviteLink.tryExtractId(
          'https://omnirunner.app/challenge/abc123',
        ),
        'abc123',
      );
      expect(
        ChallengeInviteLink.tryExtractId(
          'https://www.omnirunner.app/challenge/xyz',
        ),
        'xyz',
      );
    });

    test('tryExtractId rejects non-canonical hosts and wrong paths', () {
      expect(
        ChallengeInviteLink.tryExtractId('https://evil.com/challenge/abc'),
        isNull,
      );
      expect(
        ChallengeInviteLink.tryExtractId('https://omnirunner.app/invite/abc'),
        isNull,
      );
      expect(
        ChallengeInviteLink.tryExtractId('https://omnirunner.app/challenge/'),
        isNull,
      );
      expect(ChallengeInviteLink.tryExtractId('not a url'), isNull);
      expect(ChallengeInviteLink.tryExtractId(''), isNull);
    });

    test('value equality works (hash + operator==)', () {
      final a = ChallengeInviteLink.forId('abc');
      final b = ChallengeInviteLink.forId('abc');
      final c = ChallengeInviteLink.forId('xyz');
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });
  });
}
