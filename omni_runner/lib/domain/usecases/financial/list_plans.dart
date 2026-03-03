import 'package:omni_runner/domain/entities/coaching_plan_entity.dart';
import 'package:omni_runner/domain/repositories/i_financial_repo.dart';

final class ListPlans {
  final IFinancialRepo _repo;

  const ListPlans({required IFinancialRepo repo}) : _repo = repo;

  Future<List<CoachingPlanEntity>> call({required String groupId}) {
    return _repo.listPlans(groupId);
  }
}
