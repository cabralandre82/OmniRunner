import 'package:drift/drift.dart';
import 'package:omni_runner/core/utils/safe_enum.dart';
import 'package:omni_runner/data/datasources/drift_database.dart';
import 'package:omni_runner/domain/entities/ledger_entry_entity.dart';
import 'package:omni_runner/domain/repositories/i_ledger_repo.dart';

/// Drift implementation of [ILedgerRepo].
///
/// Append-only: entries are never updated or deleted.
/// Deduplication is enforced via unique index on [entryUuid].
final class DriftLedgerRepo implements ILedgerRepo {
  final AppDatabase _db;

  const DriftLedgerRepo(this._db);

  @override
  Future<void> append(LedgerEntryEntity entry) async {
    await _db
        .into(_db.ledgerEntries)
        .insertOnConflictUpdate(_toCompanion(entry));
  }

  @override
  Future<List<LedgerEntryEntity>> getByUserId(String userId) async {
    final query = _db.select(_db.ledgerEntries)
      ..where((t) => t.userId.equals(userId))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAtMs)])
      ..limit(50);
    final rows = await query.get();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<List<LedgerEntryEntity>> getByRefId(String refId) async {
    final query = _db.select(_db.ledgerEntries)
      ..where((t) => t.refId.equals(refId));
    final rows = await query.get();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<int> countCreditsToday(String userId) async {
    final now = DateTime.now().toUtc();
    final startOfDay = DateTime.utc(now.year, now.month, now.day);
    final startMs = startOfDay.millisecondsSinceEpoch;
    final sessionOrdinal = LedgerReason.sessionCompleted.name;

    final query = _db.select(_db.ledgerEntries)
      ..where((t) =>
          t.userId.equals(userId) &
          t.createdAtMs.isBiggerOrEqualValue(startMs) &
          t.reasonOrdinal.equals(sessionOrdinal));
    final rows = await query.get();
    return rows.length;
  }

  @override
  Future<int> sumByUserId(String userId) async {
    final sum = _db.ledgerEntries.deltaCoins.sum();
    final query = _db.selectOnly(_db.ledgerEntries)
      ..addColumns([sum])
      ..where(_db.ledgerEntries.userId.equals(userId));
    final row = await query.getSingle();
    return row.read(sum) ?? 0;
  }

  // ── Mappers ──

  static LedgerEntriesCompanion _toCompanion(LedgerEntryEntity e) {
    return LedgerEntriesCompanion.insert(
      entryUuid: e.id,
      userId: e.userId,
      deltaCoins: e.deltaCoins,
      reasonOrdinal: e.reason.name,
      refId: Value(e.refId),
      issuerGroupId: Value(e.issuerGroupId),
      createdAtMs: e.createdAtMs,
    );
  }

  static LedgerEntryEntity _toEntity(LedgerEntry r) {
    return LedgerEntryEntity(
      id: r.entryUuid,
      userId: r.userId,
      deltaCoins: r.deltaCoins,
      reason: safeByName(LedgerReason.values, r.reasonOrdinal, fallback: LedgerReason.sessionCompleted),
      refId: r.refId,
      issuerGroupId: r.issuerGroupId,
      createdAtMs: r.createdAtMs,
    );
  }
}
