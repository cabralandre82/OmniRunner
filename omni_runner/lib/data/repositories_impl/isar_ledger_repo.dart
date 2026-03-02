import 'package:isar/isar.dart';

import 'package:omni_runner/data/models/isar/ledger_record.dart';
import 'package:omni_runner/domain/entities/ledger_entry_entity.dart';
import 'package:omni_runner/domain/repositories/i_ledger_repo.dart';

/// Isar implementation of [ILedgerRepo].
///
/// Append-only: entries are never updated or deleted.
/// Deduplication is enforced via unique index on [entryUuid].
final class IsarLedgerRepo implements ILedgerRepo {
  final Isar _isar;

  const IsarLedgerRepo(this._isar);

  @override
  Future<void> append(LedgerEntryEntity entry) async {
    await _isar.writeTxn(() async {
      final record = _toRecord(entry);
      final existing = await _isar.ledgerRecords
          .where()
          .entryUuidEqualTo(entry.id)
          .findFirst();
      if (existing != null) record.isarId = existing.isarId;
      await _isar.ledgerRecords.put(record);
    });
  }

  @override
  Future<List<LedgerEntryEntity>> getByUserId(String userId) async {
    final records = await _isar.ledgerRecords
        .where()
        .userIdEqualTo(userId)
        .sortByCreatedAtMsDesc()
        .findAll();
    return records.map(_toEntity).toList();
  }

  @override
  Future<List<LedgerEntryEntity>> getByRefId(String refId) async {
    final records = await _isar.ledgerRecords
        .where()
        .refIdEqualTo(refId)
        .findAll();
    return records.map(_toEntity).toList();
  }

  @override
  Future<int> countCreditsToday(String userId) async {
    final now = DateTime.now().toUtc();
    final startOfDay = DateTime.utc(now.year, now.month, now.day);
    final startMs = startOfDay.millisecondsSinceEpoch;
    final sessionOrdinal = LedgerReason.sessionCompleted.stableOrdinal;

    final records = await _isar.ledgerRecords
        .where()
        .userIdEqualTo(userId)
        .filter()
        .createdAtMsGreaterThan(startMs - 1)
        .reasonOrdinalEqualTo(sessionOrdinal)
        .findAll();

    return records.length;
  }

  @override
  Future<int> sumByUserId(String userId) async {
    final records = await _isar.ledgerRecords
        .where()
        .userIdEqualTo(userId)
        .findAll();

    var sum = 0;
    for (final r in records) {
      sum += r.deltaCoins;
    }
    return sum;
  }

  // ── Mappers ──

  static LedgerRecord _toRecord(LedgerEntryEntity e) => LedgerRecord()
    ..entryUuid = e.id
    ..userId = e.userId
    ..deltaCoins = e.deltaCoins
    ..reasonOrdinal = e.reason.stableOrdinal
    ..refId = e.refId
    ..issuerGroupId = e.issuerGroupId
    ..createdAtMs = e.createdAtMs;

  static LedgerEntryEntity _toEntity(LedgerRecord r) => LedgerEntryEntity(
        id: r.entryUuid,
        userId: r.userId,
        deltaCoins: r.deltaCoins,
        reason: LedgerReason.fromStableOrdinal(r.reasonOrdinal),
        refId: r.refId,
        issuerGroupId: r.issuerGroupId,
        createdAtMs: r.createdAtMs,
      );
}
