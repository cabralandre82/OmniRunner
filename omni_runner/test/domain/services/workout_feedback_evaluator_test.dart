import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/plan_workout_entity.dart';
import 'package:omni_runner/domain/services/workout_feedback_evaluator.dart';
import 'package:omni_runner/domain/value_objects/workout_completion_status.dart';

void main() {
  const evaluator = WorkoutFeedbackEvaluator();

  CompletedWorkoutSummary _completedWith({int? perceivedEffort}) {
    return CompletedWorkoutSummary(
      id: 'cw-1',
      actualDistanceM: 5000,
      actualDurationS: 1800,
      perceivedEffort: perceivedEffort,
    );
  }

  WorkoutFeedbackSummary _feedbackWith({int? mood, int? rating}) {
    return WorkoutFeedbackSummary(mood: mood, rating: rating);
  }

  group('WorkoutFeedbackEvaluator.evaluate', () {
    test('returns pending when no CompletedWorkout', () {
      expect(
        evaluator.evaluate(completed: null, feedback: null),
        WorkoutCompletionStatus.pending,
      );
    });

    test('returns pending even if feedback is filed first', () {
      expect(
        evaluator.evaluate(
          completed: null,
          feedback: _feedbackWith(mood: 4),
        ),
        WorkoutCompletionStatus.pending,
      );
    });

    test('returns partial when RPE missing', () {
      expect(
        evaluator.evaluate(
          completed: _completedWith(perceivedEffort: null),
          feedback: _feedbackWith(mood: 4),
        ),
        WorkoutCompletionStatus.partial,
      );
    });

    test('returns partial when mood missing', () {
      expect(
        evaluator.evaluate(
          completed: _completedWith(perceivedEffort: 6),
          feedback: _feedbackWith(mood: null),
        ),
        WorkoutCompletionStatus.partial,
      );
    });

    test('returns partial when feedback entirely null but completed exists', () {
      expect(
        evaluator.evaluate(
          completed: _completedWith(perceivedEffort: 6),
          feedback: null,
        ),
        WorkoutCompletionStatus.partial,
      );
    });

    test('returns partial when RPE out of range low', () {
      expect(
        evaluator.evaluate(
          completed: _completedWith(perceivedEffort: 0),
          feedback: _feedbackWith(mood: 4),
        ),
        WorkoutCompletionStatus.partial,
      );
    });

    test('returns partial when RPE out of range high', () {
      expect(
        evaluator.evaluate(
          completed: _completedWith(perceivedEffort: 11),
          feedback: _feedbackWith(mood: 4),
        ),
        WorkoutCompletionStatus.partial,
      );
    });

    test('returns partial when mood out of range', () {
      expect(
        evaluator.evaluate(
          completed: _completedWith(perceivedEffort: 6),
          feedback: _feedbackWith(mood: 6),
        ),
        WorkoutCompletionStatus.partial,
      );
    });

    test('returns complete when RPE and mood both in range', () {
      expect(
        evaluator.evaluate(
          completed: _completedWith(perceivedEffort: 5),
          feedback: _feedbackWith(mood: 3),
        ),
        WorkoutCompletionStatus.complete,
      );
    });

    test('rating is not required for complete', () {
      expect(
        evaluator.evaluate(
          completed: _completedWith(perceivedEffort: 7),
          feedback: _feedbackWith(mood: 4, rating: null),
        ),
        WorkoutCompletionStatus.complete,
      );
    });

    test('complete at extreme valid values', () {
      expect(
        evaluator.evaluate(
          completed: _completedWith(perceivedEffort: 1),
          feedback: _feedbackWith(mood: 1),
        ),
        WorkoutCompletionStatus.complete,
      );
      expect(
        evaluator.evaluate(
          completed: _completedWith(perceivedEffort: 10),
          feedback: _feedbackWith(mood: 5),
        ),
        WorkoutCompletionStatus.complete,
      );
    });
  });

  group('WorkoutFeedbackEvaluator.missingFields', () {
    test('empty when pending', () {
      expect(
        evaluator.missingFields(completed: null, feedback: null),
        isEmpty,
      );
    });

    test('empty when complete', () {
      expect(
        evaluator.missingFields(
          completed: _completedWith(perceivedEffort: 7),
          feedback: _feedbackWith(mood: 4),
        ),
        isEmpty,
      );
    });

    test('reports rpe when only rpe missing', () {
      expect(
        evaluator.missingFields(
          completed: _completedWith(perceivedEffort: null),
          feedback: _feedbackWith(mood: 4),
        ),
        {WorkoutFeedbackMissingField.rpe},
      );
    });

    test('reports mood when only mood missing', () {
      expect(
        evaluator.missingFields(
          completed: _completedWith(perceivedEffort: 6),
          feedback: _feedbackWith(mood: null),
        ),
        {WorkoutFeedbackMissingField.mood},
      );
    });

    test('reports both when both missing', () {
      expect(
        evaluator.missingFields(
          completed: _completedWith(perceivedEffort: null),
          feedback: null,
        ),
        {WorkoutFeedbackMissingField.rpe, WorkoutFeedbackMissingField.mood},
      );
    });

    test('reports both when both out of range', () {
      expect(
        evaluator.missingFields(
          completed: _completedWith(perceivedEffort: 0),
          feedback: _feedbackWith(mood: 99),
        ),
        {WorkoutFeedbackMissingField.rpe, WorkoutFeedbackMissingField.mood},
      );
    });
  });

  group('WorkoutCompletionStatus invariants', () {
    test('three values are pinned for CI enforcement', () {
      expect(WorkoutCompletionStatus.values.length, 3);
      expect(
        WorkoutCompletionStatus.values,
        containsAll([
          WorkoutCompletionStatus.pending,
          WorkoutCompletionStatus.partial,
          WorkoutCompletionStatus.complete,
        ]),
      );
    });

    test('only complete is terminal', () {
      expect(WorkoutCompletionStatus.complete.isTerminal, isTrue);
      expect(WorkoutCompletionStatus.partial.isTerminal, isFalse);
      expect(WorkoutCompletionStatus.pending.isTerminal, isFalse);
    });

    test('pending and partial block coach', () {
      expect(WorkoutCompletionStatus.pending.blocksCoach, isTrue);
      expect(WorkoutCompletionStatus.partial.blocksCoach, isTrue);
      expect(WorkoutCompletionStatus.complete.blocksCoach, isFalse);
    });

    test('bronze threshold is 30 days', () {
      expect(WorkoutFeedbackBounds.bronzeStreakDays, 30);
    });

    test('RPE bounds are [1, 10] and mood bounds are [1, 5]', () {
      expect(WorkoutFeedbackBounds.rpeMin, 1);
      expect(WorkoutFeedbackBounds.rpeMax, 10);
      expect(WorkoutFeedbackBounds.moodMin, 1);
      expect(WorkoutFeedbackBounds.moodMax, 5);
    });
  });
}
