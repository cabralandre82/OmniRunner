import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:omni_runner/core/utils/safe_enum.dart';
import 'package:omni_runner/data/datasources/drift_database.dart';
import 'package:omni_runner/domain/entities/mission_progress_entity.dart';
import 'package:omni_runner/domain/repositories/i_mission_progress_repo.dart';

final class DriftMissionProgressRepo implements IMissionProgressRepo {
  final AppDatabase _db;

  const DriftMissionProgressRepo(this._db);

  @override
  Future<void> save(MissionProgressEntity progress) async {
    await _db.into(_db.missionProgresses).insertOnConflictUpdate(
          MissionProgressesCompanion(
            progressUuid: Value(progress.id),
            userId: Value(progress.userId),
            missionId: Value(progress.missionId),
            statusOrdinal: Value(progress.status.name),
            currentValue: Value(progress.currentValue),
            targetValue: Value(progress.targetValue),
            assignedAtMs: Value(progress.assignedAtMs),
            completedAtMs: Value(progress.completedAtMs),
            completionCount: Value(progress.completionCount),
            contributingSessionIdsJson:
                Value(jsonEncode(progress.contributingSessionIds)),
          ),
        );
  }

  @override
  Future<List<MissionProgressEntity>> getByUserId(String userId) async {
    final rows = await (_db.select(_db.missionProgresses)
          ..where((t) => t.userId.equals(userId)))
        .get();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<List<MissionProgressEntity>> getActiveByUserId(String userId) async {
    final rows = await (_db.select(_db.missionProgresses)
          ..where((t) =>
              t.userId.equals(userId) &
              t.statusOrdinal.equals(MissionProgressStatus.active.name)))
        .get();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<MissionProgressEntity?> getById(String id) async {
    final row = await (_db.select(_db.missionProgresses)
          ..where((t) => t.progressUuid.equals(id)))
        .getSingleOrNull();
    return row != null ? _toEntity(row) : null;
  }

  @override
  Future<MissionProgressEntity?> getByUserAndMission(
      String userId, String missionId) async {
    final row = await (_db.select(_db.missionProgresses)
          ..where((t) =>
              t.userId.equals(userId) &
              t.missionId.equals(missionId) &
              t.statusOrdinal.equals(MissionProgressStatus.active.name)))
        .getSingleOrNull();
    return row != null ? _toEntity(row) : null;
  }

  static MissionProgressEntity _toEntity(MissionProgress r) =>
      MissionProgressEntity(
        id: r.progressUuid,
        userId: r.userId,
        missionId: r.missionId,
        status: safeByName(MissionProgressStatus.values, r.statusOrdinal, fallback: MissionProgressStatus.active),
        currentValue: r.currentValue,
        targetValue: r.targetValue,
        assignedAtMs: r.assignedAtMs,
        completedAtMs: r.completedAtMs,
        completionCount: r.completionCount,
        contributingSessionIds:
            (jsonDecode(r.contributingSessionIdsJson) as List<dynamic>)
                .cast<String>(),
      );
}
