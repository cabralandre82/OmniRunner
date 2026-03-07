// ignore_for_file: uri_has_not_been_generated, undefined_identifier, undefined_getter
import 'package:isar/isar.dart';

part 'mission_model.g.dart';

/// Isar collection for user mission progress.
///
/// Maps to/from [MissionProgressEntity].
///
/// MissionProgressStatus ordinal mapping:
///   0 = active, 1 = completed, 2 = expired
@collection
class MissionProgressRecord {
  Id isarId = Isar.autoIncrement;

  @Index(unique: true)
  late String progressUuid;

  @Index()
  late String userId;

  @Index()
  late String missionId;

  /// [MissionProgressStatus] as integer ordinal.
  @Index()
  late int statusOrdinal;

  late double currentValue;
  late double targetValue;

  late int assignedAtMs;
  int? completedAtMs;
  late int completionCount;

  /// Session IDs stored as a JSON-encoded list of strings.
  /// Isar 3.x does not support `List<String>` in all contexts,
  /// so we serialize manually for safety.
  late String contributingSessionIdsJson;
}
