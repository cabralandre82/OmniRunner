import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/domain/entities/coaching_group_entity.dart';
import 'package:omni_runner/domain/entities/coaching_member_entity.dart';
import 'package:omni_runner/domain/repositories/i_coaching_group_repo.dart';
import 'package:omni_runner/domain/repositories/i_coaching_member_repo.dart';
import 'package:omni_runner/domain/usecases/coaching/switch_assessoria.dart';
import 'package:omni_runner/presentation/blocs/my_assessoria/my_assessoria_event.dart';
import 'package:omni_runner/presentation/blocs/my_assessoria/my_assessoria_state.dart';

class MyAssessoriaBloc extends Bloc<MyAssessoriaEvent, MyAssessoriaState> {
  final ICoachingGroupRepo _groupRepo;
  final ICoachingMemberRepo _memberRepo;
  final SwitchAssessoria _switchAssessoria;

  MyAssessoriaBloc({
    required ICoachingGroupRepo groupRepo,
    required ICoachingMemberRepo memberRepo,
    required SwitchAssessoria switchAssessoria,
  })  : _groupRepo = groupRepo,
        _memberRepo = memberRepo,
        _switchAssessoria = switchAssessoria,
        super(const MyAssessoriaInitial()) {
    on<LoadMyAssessoria>(_onLoad);
    on<ConfirmSwitchAssessoria>(_onSwitch);
  }

  Future<void> _onLoad(
    LoadMyAssessoria event,
    Emitter<MyAssessoriaState> emit,
  ) async {
    emit(const MyAssessoriaLoading());

    try {
      final db = Supabase.instance.client;

      // Query Supabase directly (Isar cache may be stale after join approval)
      final memberRows = await db
          .from('coaching_members')
          .select('id, user_id, group_id, display_name, role, joined_at_ms')
          .eq('user_id', event.userId);

      final members = (memberRows as List)
          .cast<Map<String, dynamic>>()
          .map((r) => CoachingMemberEntity(
                id: r['id'] as String,
                userId: r['user_id'] as String,
                groupId: r['group_id'] as String,
                displayName: (r['display_name'] as String?) ?? '',
                role: coachingRoleFromString(r['role'] as String? ?? ''),
                joinedAtMs: (r['joined_at_ms'] as num?)?.toInt() ?? 0,
              ))
          .toList();

      // Sync to Isar for offline access
      for (final m in members) {
        try { await _memberRepo.save(m); } catch (_) {}
      }

      final atletaMembership = members.where((m) => m.isAtleta).toList();

      if (atletaMembership.isEmpty) {
        emit(const MyAssessoriaLoaded());
        return;
      }

      final current = atletaMembership.first;

      // Fetch group from Supabase
      final groupRow = await db
          .from('coaching_groups')
          .select()
          .eq('id', current.groupId)
          .maybeSingle();

      CoachingGroupEntity? group;
      if (groupRow != null) {
        group = CoachingGroupEntity(
          id: groupRow['id'] as String,
          name: (groupRow['name'] as String?) ?? 'Assessoria',
          logoUrl: groupRow['logo_url'] as String?,
          coachUserId: (groupRow['coach_user_id'] as String?) ?? '',
          description: (groupRow['description'] as String?) ?? '',
          city: (groupRow['city'] as String?) ?? '',
          inviteCode: groupRow['invite_code'] as String?,
          inviteEnabled: (groupRow['invite_enabled'] as bool?) ?? true,
          createdAtMs: (groupRow['created_at_ms'] as num?)?.toInt() ?? 0,
        );
        try { await _groupRepo.save(group); } catch (_) {}
      }

      // Build available groups from other memberships
      final otherGroupIds = members
          .where((m) => m.groupId != current.groupId)
          .map((m) => m.groupId)
          .toSet();

      final available = <CoachingGroupEntity>[];
      for (final gid in otherGroupIds) {
        try {
          final gRow = await db
              .from('coaching_groups')
              .select()
              .eq('id', gid)
              .maybeSingle();
          if (gRow != null) {
            final g = CoachingGroupEntity(
              id: gRow['id'] as String,
              name: (gRow['name'] as String?) ?? '',
              logoUrl: gRow['logo_url'] as String?,
              coachUserId: (gRow['coach_user_id'] as String?) ?? '',
              description: (gRow['description'] as String?) ?? '',
              city: (gRow['city'] as String?) ?? '',
              inviteCode: gRow['invite_code'] as String?,
              inviteEnabled: (gRow['invite_enabled'] as bool?) ?? true,
              createdAtMs: (gRow['created_at_ms'] as num?)?.toInt() ?? 0,
            );
            try { await _groupRepo.save(g); } catch (_) {}
            available.add(g);
          }
        } catch (_) {}
      }

      emit(MyAssessoriaLoaded(
        currentGroup: group,
        membership: current,
        availableGroups: available,
      ));
    } on Exception catch (_) {
      emit(const MyAssessoriaError('Não foi possível carregar sua assessoria.'));
    }
  }

  Future<void> _onSwitch(
    ConfirmSwitchAssessoria event,
    Emitter<MyAssessoriaState> emit,
  ) async {
    emit(const MyAssessoriaSwitching());

    try {
      final newId = await _switchAssessoria(event.newGroupId);
      emit(MyAssessoriaSwitched(newId));
    } on Exception catch (_) {
      emit(const MyAssessoriaError('Não foi possível trocar de assessoria. Tente novamente.'));
    }
  }
}
