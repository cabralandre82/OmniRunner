import 'package:omni_runner/domain/entities/member_status_entity.dart';
import 'package:omni_runner/domain/repositories/i_crm_repo.dart';

final class ManageMemberStatus {
  final ICrmRepo _repo;

  const ManageMemberStatus({required ICrmRepo repo}) : _repo = repo;

  Future<MemberStatusEntity?> get({
    required String groupId,
    required String userId,
  }) =>
      _repo.getStatus(groupId: groupId, userId: userId);

  Future<MemberStatusEntity> upsert({
    required String groupId,
    required String userId,
    required MemberStatusValue status,
  }) =>
      _repo.upsertStatus(groupId: groupId, userId: userId, status: status);
}
