import 'package:isar/isar.dart';

import 'package:omni_runner/data/models/isar/progress_model.dart';
import 'package:omni_runner/domain/entities/profile_progress_entity.dart';
import 'package:omni_runner/domain/repositories/i_xp_transaction_repo.dart';

final class IsarXpTransactionRepo implements IXpTransactionRepo {
  final Isar _isar;

  const IsarXpTransactionRepo(this._isar);

  @override
  Future<void> append(XpTransactionEntity tx) async {
    await _isar.writeTxn(() async {
      final existing = await _isar.xpTransactionRecords
          .where()
          .txUuidEqualTo(tx.id)
          .findFirst();
      final record = _toRecord(tx);
      if (existing != null) record.isarId = existing.isarId;
      await _isar.xpTransactionRecords.put(record);
    });
  }

  @override
  Future<List<XpTransactionEntity>> getByUserId(String userId) async {
    final records = await _isar.xpTransactionRecords
        .where()
        .userIdEqualTo(userId)
        .sortByCreatedAtMsDesc()
        .findAll();
    return records.map(_toEntity).toList();
  }

  @override
  Future<List<XpTransactionEntity>> getByRefId(String refId) async {
    final records = await _isar.xpTransactionRecords
        .where()
        .refIdEqualTo(refId)
        .findAll();
    return records.map(_toEntity).toList();
  }

  @override
  Future<int> sumSessionXpToday(String userId) async {
    final startMs = _startOfDayUtcMs();
    final records = await _isar.xpTransactionRecords
        .where()
        .userIdEqualTo(userId)
        .filter()
        .createdAtMsGreaterThan(startMs - 1)
        .sourceOrdinalEqualTo(XpSource.session.index)
        .findAll();

    var sum = 0;
    for (final r in records) {
      sum += r.xp;
    }
    return sum;
  }

  @override
  Future<int> sumBonusXpToday(String userId) async {
    final startMs = _startOfDayUtcMs();
    final records = await _isar.xpTransactionRecords
        .where()
        .userIdEqualTo(userId)
        .filter()
        .createdAtMsGreaterThan(startMs - 1)
        .not()
        .sourceOrdinalEqualTo(XpSource.session.index)
        .findAll();

    var sum = 0;
    for (final r in records) {
      sum += r.xp;
    }
    return sum;
  }

  @override
  Future<int> sumByUserId(String userId) async {
    final records = await _isar.xpTransactionRecords
        .where()
        .userIdEqualTo(userId)
        .findAll();

    var sum = 0;
    for (final r in records) {
      sum += r.xp;
    }
    return sum;
  }

  @override
  Future<int> sumByUserIdInRange(String userId, int fromMs, int toMs) async {
    final records = await _isar.xpTransactionRecords
        .where()
        .userIdEqualTo(userId)
        .filter()
        .createdAtMsBetween(fromMs, toMs)
        .findAll();

    var sum = 0;
    for (final r in records) {
      sum += r.xp;
    }
    return sum;
  }

  static int _startOfDayUtcMs() {
    final now = DateTime.now().toUtc();
    return DateTime.utc(now.year, now.month, now.day)
        .millisecondsSinceEpoch;
  }

  static XpTransactionRecord _toRecord(XpTransactionEntity e) =>
      XpTransactionRecord()
        ..txUuid = e.id
        ..userId = e.userId
        ..xp = e.xp
        ..sourceOrdinal = e.source.index
        ..refId = e.refId
        ..createdAtMs = e.createdAtMs;

  static XpTransactionEntity _toEntity(XpTransactionRecord r) =>
      XpTransactionEntity(
        id: r.txUuid,
        userId: r.userId,
        xp: r.xp,
        source: XpSource.values[r.sourceOrdinal],
        refId: r.refId,
        createdAtMs: r.createdAtMs,
      );
}
