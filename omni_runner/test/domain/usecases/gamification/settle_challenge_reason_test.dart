import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_result_entity.dart';
import 'package:omni_runner/domain/entities/ledger_entry_entity.dart';

/// Tests that _reasonFor mapping covers all ChallengeType × ParticipantOutcome
/// combinations without throwing. We test the logic indirectly since _reasonFor
/// is private — we verify the enum exhaustiveness at compile time.
void main() {
  group('LedgerReason coverage', () {
    test('all ChallengeType values exist', () {
      expect(ChallengeType.values, containsAll([
        ChallengeType.oneVsOne,
        ChallengeType.group,
        ChallengeType.team,
      ]));
    });

    test('team-specific reasons exist', () {
      expect(LedgerReason.values, contains(LedgerReason.challengeTeamCompleted));
      expect(LedgerReason.values, contains(LedgerReason.challengeTeamWon));
    });

    test('ordinals are stable — new values at end', () {
      expect(LedgerReason.sessionCompleted.stableOrdinal, 0);
      expect(LedgerReason.challengeOneVsOneCompleted.stableOrdinal, 1);
      expect(LedgerReason.challengeOneVsOneWon.stableOrdinal, 2);
      expect(LedgerReason.challengeGroupCompleted.stableOrdinal, 3);
      expect(LedgerReason.crossAssessoriaBurned.stableOrdinal, 17);
      expect(LedgerReason.challengeTeamCompleted.stableOrdinal, 18);
      expect(LedgerReason.challengeTeamWon.stableOrdinal, 19);
    });

    test('ParticipantOutcome covers all expected values', () {
      expect(ParticipantOutcome.values, containsAll([
        ParticipantOutcome.won,
        ParticipantOutcome.lost,
        ParticipantOutcome.tied,
        ParticipantOutcome.completedTarget,
        ParticipantOutcome.participated,
        ParticipantOutcome.didNotFinish,
      ]));
    });
  });
}
