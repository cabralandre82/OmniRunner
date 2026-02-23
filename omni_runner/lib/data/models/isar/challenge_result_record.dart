import 'package:isar/isar.dart';

part 'challenge_result_record.g.dart';

/// Isar collection for finalized challenge results.
///
/// One record per completed challenge. Created by [EvaluateChallenge],
/// never updated.
///
/// Participant results are stored as JSON strings (same rationale
/// as [ChallengeRecord.participantsJson]).
@collection
class ChallengeResultRecord {
  Id isarId = Isar.autoIncrement;

  /// The challenge this result belongs to.
  @Index(unique: true)
  late String challengeId;

  /// ChallengeMetric ordinal: 0=distance, 1=pace, 2=time.
  late int metricOrdinal;

  /// Total Coins distributed across all participants.
  late int totalCoinsDistributed;

  /// When results were calculated (ms epoch UTC).
  late int calculatedAtMs;

  /// Each element is a JSON string representing one [ParticipantResult].
  List<String> resultsJson = const [];
}
