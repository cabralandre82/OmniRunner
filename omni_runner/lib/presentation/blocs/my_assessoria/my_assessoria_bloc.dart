import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:omni_runner/domain/entities/coaching_group_entity.dart';
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
      final memberships = await _memberRepo.getByUserId(event.userId);

      // Find athlete membership (current assessoria)
      final atletaMembership = memberships
          .where((m) => m.isAtleta)
          .toList();

      if (atletaMembership.isEmpty) {
        emit(const MyAssessoriaLoaded());
        return;
      }

      final current = atletaMembership.first;
      final group = await _groupRepo.getById(current.groupId);

      // Build available groups from other memberships the user has
      final otherGroupIds = memberships
          .where((m) => m.groupId != current.groupId)
          .map((m) => m.groupId)
          .toSet();

      final available = <CoachingGroupEntity>[];
      for (final gid in otherGroupIds) {
        final g = await _groupRepo.getById(gid);
        if (g != null) available.add(g);
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
