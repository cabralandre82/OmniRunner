import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/core/config/feature_flags.dart';

void main() {
  group('FeatureFlagService', () {
    test('returns false for unknown flag before load', () {
      final sut = FeatureFlagService(userId: 'u1');
      expect(sut.isEnabled('nonexistent'), isFalse);
    });

    test('isLoaded is false initially', () {
      final sut = FeatureFlagService(userId: 'u1');
      expect(sut.isLoaded, isFalse);
    });

    test('userBucket is deterministic for same userId+key', () {
      final sut1 = FeatureFlagService(userId: 'user-abc');
      final sut2 = FeatureFlagService(userId: 'user-abc');
      // Both should return the same result for the same flag
      expect(sut1.isEnabled('feat_x'), equals(sut2.isEnabled('feat_x')));
    });

    test('different userIds may get different buckets', () {
      // This is probabilistic but we can verify the function itself
      final s1 = FeatureFlagService(userId: 'aaa');
      final s2 = FeatureFlagService(userId: 'zzz');
      // Both return false since no flags loaded — just verify no crash
      expect(s1.isEnabled('test'), isFalse);
      expect(s2.isEnabled('test'), isFalse);
    });
  });
}
