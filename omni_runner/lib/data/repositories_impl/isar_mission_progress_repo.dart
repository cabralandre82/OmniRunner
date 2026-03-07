// ignore_for_file: uri_has_not_been_generated, undefined_identifier, undefined_getter
import 'dart:convert';

import 'package:isar/isar.dart';

import 'package:omni_runner/data/models/isar/mission_model.dart';
import 'package:omni_runner/domain/entities/mission_progress_entity.dart';
import 'package:omni_runner/domain/repositories/i_mission_progress_repo.dart';

final class IsarMissionProgressRepo implements IMissionProgressRepo {
  final Isar _isar;

  const IsarMissionProgressRepo(this._isar);

  @override
  Future<void> save(MissionProgressEntity progress) async {
    await _isar.writeTxn(() async {
      final existing = await _isar.missionProgressRecords
          .where()
          .progressUuidEqualTo(progress.id)
          .findFirst();

      final record = _toRecord(progress);
      if (existing != null) record.isarId = existing.isarId;

      await _isar.missionProgressRecords.put(record);
    });
  }

  @override
  Future<List<MissionProgressEntity>> getByUserId(String userId) async {
    final records = await _isar.missionProgressRecords
        .where()
        .userIdEqualTo(userId)
        .findAll();
    return records.map(_toEntity).toList();
  }

  @override
  Future<List<MissionProgressEntity>> getActiveByUserId(String userId) async {
    final records = await _isar.missionProgressRecords
        .where()
        .userIdEqualTo(userId)
        .filter()
        .statusOrdinalEqualTo(MissionProgressStatus.active.index)
        .findAll();
    return records.map(_toEntity).toList();
  }

  @override
  Future<MissionProgressEntity?> getById(String id) async {
    final record = await _isar.missionProgressRecords
        .where()
        .progressUuidEqualTo(id)
        .findFirst();
    return record != null ? _toEntity(record) : null;
  }

  @override
  Future<MissionProgressEntity?> getByUserAndMission(
      String userId, String missionId) async {
    final record = await _isar.missionProgressRecords
        .where()
        .userIdEqualTo(userId)
        .filter()
        .missionIdEqualTo(missionId)
        .statusOrdinalEqualTo(MissionProgressStatus.active.index)
        .findFirst();
    return record != null ? _toEntity(record) : null;
  }

  static MissionProgressRecord _toRecord(MissionProgressEntity e) =>
      MissionProgressRecord()
        ..progressUuid = e.id
        ..userId = e.userId
        ..missionId = e.missionId
        ..statusOrdinal = e.status.index
        ..currentValue = e.currentValue
        ..targetValue = e.targetValue
        ..assignedAtMs = e.assignedAtMs
        ..completedAtMs = e.completedAtMs
        ..completionCount = e.completionCount
        ..contributingSessionIdsJson =
            jsonEncode(e.contributingSessionIds);

  static MissionProgressEntity _toEntity(MissionProgressRecord r) =>
      MissionProgressEntity(
        id: r.progressUuid,
        userId: r.userId,
        missionId: r.missionId,
        status: MissionProgressStatus.values[r.statusOrdinal],
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
