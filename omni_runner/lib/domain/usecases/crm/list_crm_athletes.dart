import 'package:omni_runner/domain/entities/member_status_entity.dart';
import 'package:omni_runner/domain/repositories/i_crm_repo.dart';

final class ListCrmAthletes {
  final ICrmRepo _repo;

  const ListCrmAthletes({required ICrmRepo repo}) : _repo = repo;

  Future<List<CrmAthleteView>> call({
    required String groupId,
    List<String>? tagIds,
    MemberStatusValue? status,
    int limit = 50,
    int offset = 0,
  }) =>
      _repo.listAthletes(
        groupId: groupId,
        tagIds: tagIds,
        status: status,
        limit: limit,
        offset: offset,
      );
}
