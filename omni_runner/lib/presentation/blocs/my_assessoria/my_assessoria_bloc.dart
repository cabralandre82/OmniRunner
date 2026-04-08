import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/entities/coaching_group_entity.dart';
import 'package:omni_runner/domain/repositories/i_coaching_group_repo.dart';
import 'package:omni_runner/domain/repositories/i_coaching_member_repo.dart';
import 'package:omni_runner/domain/repositories/i_my_assessoria_remote_source.dart';
import 'package:omni_runner/domain/usecases/coaching/switch_assessoria.dart';
import 'package:omni_runner/presentation/blocs/my_assessoria/my_assessoria_event.dart';
import 'package:omni_runner/presentation/blocs/my_assessoria/my_assessoria_state.dart';

class MyAssessoriaBloc extends Bloc<MyAssessoriaEvent, MyAssessoriaState> {
  final ICoachingGroupRepo _groupRepo;
  final ICoachingMemberRepo _memberRepo;
  final IMyAssessoriaRemoteSource _remote;
  final SwitchAssessoria _switchAssessoria;

  MyAssessoriaBloc({
    required ICoachingGroupRepo groupRepo,
    required ICoachingMemberRepo memberRepo,
    required IMyAssessoriaRemoteSource remote,
    required SwitchAssessoria switchAssessoria,
  })  : _groupRepo = groupRepo,
        _memberRepo = memberRepo,
        _remote = remote,
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
      final members = await _remote.fetchMemberships(event.userId);

      AppLogger.debug(
        'Loaded coaching_members (count=${members.length}) for user ${event.userId}',
        tag: 'MyAssessoria',
      );

      // Sync to local repo for offline access
      for (final m in members) {
        try {
          await _memberRepo.save(m);
        } on Exception catch (e) {
          AppLogger.debug('Member cache write failed',
              tag: 'MyAssessoria', error: e);
        }
      }

      if (members.isEmpty) {
        emit(const MyAssessoriaLoaded());
        return;
      }

      // Prefer athlete membership, but fall back to any staff membership (coach/admin/assistant).
      final current = members.firstWhere(
        (m) => m.isAthlete,
        orElse: () => members.first,
      );

      // Fetch current group
      final group = await _remote.fetchGroup(current.groupId);
      if (group != null) {
        try {
          await _groupRepo.save(group);
        } on Exception catch (e) {
          AppLogger.debug('Group cache write failed',
              tag: 'MyAssessoria', error: e);
        }
      }

      // Build available groups from other memberships
      final otherGroupIds = members
          .where((m) => m.groupId != current.groupId)
          .map((m) => m.groupId)
          .toSet();

      final available = <CoachingGroupEntity>[];
      for (final gid in otherGroupIds) {
        try {
          final g = await _remote.fetchGroup(gid);
          if (g != null) {
            try {
              await _groupRepo.save(g);
            } on Exception catch (e) {
              AppLogger.debug('Available group cache failed',
                  tag: 'MyAssessoria', error: e);
            }
            available.add(g);
          }
        } on Exception catch (e) {
          AppLogger.debug('Available group fetch failed',
              tag: 'MyAssessoria', error: e);
        }
      }

      emit(MyAssessoriaLoaded(
        currentGroup: group,
        membership: current,
        availableGroups: available,
      ));
    } on Exception catch (e) {
      AppLogger.error('Assessoria load failed',
          tag: 'MyAssessoria', error: e);
      emit(const MyAssessoriaError(
          'Não foi possível carregar sua assessoria.'));
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
    } on Exception catch (e) {
      AppLogger.error('Switch assessoria failed',
          tag: 'MyAssessoria', error: e);
      emit(const MyAssessoriaError(
          'Não foi possível trocar de assessoria. Tente novamente.'));
    }
  }
}
