import 'package:equatable/equatable.dart';

enum MemberStatusValue { active, paused, injured, inactive, trial }

MemberStatusValue memberStatusFromString(String value) => switch (value) {
      'active' => MemberStatusValue.active,
      'paused' => MemberStatusValue.paused,
      'injured' => MemberStatusValue.injured,
      'inactive' => MemberStatusValue.inactive,
      'trial' => MemberStatusValue.trial,
      _ => MemberStatusValue.active,
    };

String memberStatusToString(MemberStatusValue s) => switch (s) {
      MemberStatusValue.active => 'active',
      MemberStatusValue.paused => 'paused',
      MemberStatusValue.injured => 'injured',
      MemberStatusValue.inactive => 'inactive',
      MemberStatusValue.trial => 'trial',
    };

final class MemberStatusEntity extends Equatable {
  final String groupId;
  final String userId;
  final MemberStatusValue status;
  final DateTime updatedAt;
  final String? updatedBy;

  const MemberStatusEntity({
    required this.groupId,
    required this.userId,
    required this.status,
    required this.updatedAt,
    this.updatedBy,
  });

  @override
  List<Object?> get props => [groupId, userId, status, updatedAt];
}
