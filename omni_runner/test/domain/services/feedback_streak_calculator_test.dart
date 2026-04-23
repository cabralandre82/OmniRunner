import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/services/feedback_streak_calculator.dart';

void main() {
  const calc = FeedbackStreakCalculator();

  DateTime day(int y, int m, int d) => DateTime.utc(y, m, d, 12);

  group('FeedbackStreakCalculator.calculate', () {
    test('empty input returns 0/0/false', () {
      final r = calc.calculate(
        completeFeedbackDates: const [],
        referenceDay: day(2026, 4, 21),
      );
      expect(r.currentStreakDays, 0);
      expect(r.longestStreakDays, 0);
      expect(r.badgeBronzeUnlocked, isFalse);
    });

    test('single day at reference counts as current=1', () {
      final r = calc.calculate(
        completeFeedbackDates: [day(2026, 4, 21)],
        referenceDay: day(2026, 4, 21),
      );
      expect(r.currentStreakDays, 1);
      expect(r.longestStreakDays, 1);
      expect(r.badgeBronzeUnlocked, isFalse);
    });

    test('single day yesterday counts as current=1 (1-day tolerance)', () {
      final r = calc.calculate(
        completeFeedbackDates: [day(2026, 4, 20)],
        referenceDay: day(2026, 4, 21),
      );
      expect(r.currentStreakDays, 1);
    });

    test('single day two days ago resets current to 0', () {
      final r = calc.calculate(
        completeFeedbackDates: [day(2026, 4, 19)],
        referenceDay: day(2026, 4, 21),
      );
      expect(r.currentStreakDays, 0);
      expect(r.longestStreakDays, 1);
    });

    test('duplicates on the same UTC day count as one', () {
      final r = calc.calculate(
        completeFeedbackDates: [
          DateTime.utc(2026, 4, 21, 6, 0),
          DateTime.utc(2026, 4, 21, 20, 30),
        ],
        referenceDay: day(2026, 4, 21),
      );
      expect(r.currentStreakDays, 1);
      expect(r.longestStreakDays, 1);
    });

    test('three consecutive days produce current=3', () {
      final r = calc.calculate(
        completeFeedbackDates: [
          day(2026, 4, 19),
          day(2026, 4, 20),
          day(2026, 4, 21),
        ],
        referenceDay: day(2026, 4, 21),
      );
      expect(r.currentStreakDays, 3);
      expect(r.longestStreakDays, 3);
    });

    test('gap of one day breaks the streak', () {
      final r = calc.calculate(
        completeFeedbackDates: [
          day(2026, 4, 10),
          day(2026, 4, 11),
          day(2026, 4, 12),
          day(2026, 4, 14),
          day(2026, 4, 15),
          day(2026, 4, 16),
          day(2026, 4, 17),
          day(2026, 4, 18),
          day(2026, 4, 19),
          day(2026, 4, 20),
          day(2026, 4, 21),
        ],
        referenceDay: day(2026, 4, 21),
      );
      expect(r.currentStreakDays, 8);
      expect(r.longestStreakDays, 8);
    });

    test('longest streak can exceed current streak', () {
      final r = calc.calculate(
        completeFeedbackDates: [
          for (var i = 1; i <= 10; i++) day(2026, 3, i),
          day(2026, 4, 20),
          day(2026, 4, 21),
        ],
        referenceDay: day(2026, 4, 21),
      );
      expect(r.currentStreakDays, 2);
      expect(r.longestStreakDays, 10);
    });

    test('30 consecutive days unlocks the bronze badge', () {
      final r = calc.calculate(
        completeFeedbackDates: [
          for (var i = 0; i < 30; i++)
            day(2026, 3, 23).add(Duration(days: i)),
        ],
        referenceDay: day(2026, 4, 21),
      );
      expect(r.currentStreakDays, 30);
      expect(r.longestStreakDays, 30);
      expect(r.badgeBronzeUnlocked, isTrue);
    });

    test('29 consecutive days does NOT unlock the badge', () {
      final r = calc.calculate(
        completeFeedbackDates: [
          for (var i = 0; i < 29; i++)
            day(2026, 3, 24).add(Duration(days: i)),
        ],
        referenceDay: day(2026, 4, 21),
      );
      expect(r.currentStreakDays, 29);
      expect(r.badgeBronzeUnlocked, isFalse);
    });

    test('badge persists while current streak ≥ 30 even if not at ref day', () {
      final r = calc.calculate(
        completeFeedbackDates: [
          for (var i = 0; i < 31; i++)
            day(2026, 3, 22).add(Duration(days: i)),
        ],
        referenceDay: day(2026, 4, 22),
      );
      expect(r.currentStreakDays, 31);
      expect(r.badgeBronzeUnlocked, isTrue);
    });

    test('non-UTC DateTime input is quantised to UTC day', () {
      final local = DateTime(2026, 4, 21, 23, 30);
      final r = calc.calculate(
        completeFeedbackDates: [local],
        referenceDay: day(2026, 4, 21),
      );
      expect(r.currentStreakDays >= 0, isTrue);
      expect(r.longestStreakDays, 1);
    });

    test('unordered input still produces correct result', () {
      final r = calc.calculate(
        completeFeedbackDates: [
          day(2026, 4, 21),
          day(2026, 4, 19),
          day(2026, 4, 20),
        ],
        referenceDay: day(2026, 4, 21),
      );
      expect(r.currentStreakDays, 3);
      expect(r.longestStreakDays, 3);
    });

    test('future date beyond reference yields current=0 (defensive)', () {
      final r = calc.calculate(
        completeFeedbackDates: [day(2026, 4, 25)],
        referenceDay: day(2026, 4, 21),
      );
      expect(r.currentStreakDays, 0);
    });
  });
}
