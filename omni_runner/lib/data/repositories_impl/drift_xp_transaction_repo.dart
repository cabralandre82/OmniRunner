import 'package:drift/drift.dart';
import 'package:omni_runner/core/utils/safe_enum.dart';
import 'package:omni_runner/data/datasources/drift_database.dart';
import 'package:omni_runner/domain/entities/profile_progress_entity.dart';
import 'package:omni_runner/domain/repositories/i_xp_transaction_repo.dart';

final class DriftXpTransactionRepo implements IXpTransactionRepo {
  final AppDatabase _db;

  const DriftXpTransactionRepo(this._db);

  @override
  Future<void> append(XpTransactionEntity tx) async {
    await _db.into(_db.xpTransactions).insertOnConflictUpdate(
          XpTransactionsCompanion(
            txUuid: Value(tx.id),
            userId: Value(tx.userId),
            xp: Value(tx.xp),
            sourceOrdinal: Value(tx.source.name),
            refId: Value(tx.refId),
            createdAtMs: Value(tx.createdAtMs),
          ),
        );
  }

  @override
  Future<List<XpTransactionEntity>> getByUserId(String userId) async {
    final rows = await (_db.select(_db.xpTransactions)
          ..where((t) => t.userId.equals(userId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAtMs)]))
        .get();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<List<XpTransactionEntity>> getByRefId(String refId) async {
    final rows = await (_db.select(_db.xpTransactions)
          ..where((t) => t.refId.equals(refId)))
        .get();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<int> sumSessionXpToday(String userId) async {
    final startMs = _startOfDayUtcMs();
    final rows = await (_db.select(_db.xpTransactions)
          ..where((t) =>
              t.userId.equals(userId) &
              t.createdAtMs.isBiggerOrEqualValue(startMs) &
              t.sourceOrdinal.equals(XpSource.session.name)))
        .get();
    return rows.fold<int>(0, (sum, r) => sum + r.xp);
  }

  @override
  Future<int> sumBonusXpToday(String userId) async {
    final startMs = _startOfDayUtcMs();
    final rows = await (_db.select(_db.xpTransactions)
          ..where((t) =>
              t.userId.equals(userId) &
              t.createdAtMs.isBiggerOrEqualValue(startMs) &
              t.sourceOrdinal.equals(XpSource.session.name).not()))
        .get();
    return rows.fold<int>(0, (sum, r) => sum + r.xp);
  }

  @override
  Future<int> sumByUserId(String userId) async {
    final rows = await (_db.select(_db.xpTransactions)
          ..where((t) => t.userId.equals(userId)))
        .get();
    return rows.fold<int>(0, (sum, r) => sum + r.xp);
  }

  @override
  Future<int> sumByUserIdInRange(String userId, int fromMs, int toMs) async {
    final rows = await (_db.select(_db.xpTransactions)
          ..where((t) =>
              t.userId.equals(userId) &
              t.createdAtMs.isBiggerOrEqualValue(fromMs) &
              t.createdAtMs.isSmallerOrEqualValue(toMs)))
        .get();
    return rows.fold<int>(0, (sum, r) => sum + r.xp);
  }

  static int _startOfDayUtcMs() {
    final now = DateTime.now().toUtc();
    return DateTime.utc(now.year, now.month, now.day).millisecondsSinceEpoch;
  }

  static XpTransactionEntity _toEntity(XpTransaction r) =>
      XpTransactionEntity(
        id: r.txUuid,
        userId: r.userId,
        xp: r.xp,
        source: safeByName(XpSource.values, r.sourceOrdinal, fallback: XpSource.session),
        refId: r.refId,
        createdAtMs: r.createdAtMs,
      );
}
