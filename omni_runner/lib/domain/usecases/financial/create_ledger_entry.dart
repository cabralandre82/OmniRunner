import 'package:omni_runner/domain/repositories/i_financial_repo.dart';

final class CreateLedgerEntry {
  final IFinancialRepo _repo;

  const CreateLedgerEntry({required IFinancialRepo repo}) : _repo = repo;

  Future<void> call({
    required String groupId,
    required String type,
    required String category,
    required double amount,
    String? description,
  }) {
    return _repo.createLedgerEntry(
      groupId: groupId,
      type: type,
      category: category,
      amount: amount,
      description: description,
    );
  }
}
