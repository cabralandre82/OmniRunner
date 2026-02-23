import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/domain/repositories/i_coaching_group_repo.dart';
import 'package:omni_runner/domain/repositories/i_coaching_member_repo.dart';
import 'package:omni_runner/presentation/blocs/coaching_groups/coaching_groups_event.dart';
import 'package:omni_runner/presentation/blocs/coaching_groups/coaching_groups_state.dart';

class CoachingGroupsBloc
    extends Bloc<CoachingGroupsEvent, CoachingGroupsState> {
  final ICoachingGroupRepo _groupRepo;
  final ICoachingMemberRepo _memberRepo;

  String _userId = '';

  CoachingGroupsBloc({
    required ICoachingGroupRepo groupRepo,
    required ICoachingMemberRepo memberRepo,
  })  : _groupRepo = groupRepo,
        _memberRepo = memberRepo,
        super(const CoachingGroupsInitial()) {
    on<LoadCoachingGroups>(_onLoad);
    on<RefreshCoachingGroups>(_onRefresh);
  }

  Future<void> _onLoad(
    LoadCoachingGroups event,
    Emitter<CoachingGroupsState> emit,
  ) async {
    _userId = event.userId;
    emit(const CoachingGroupsLoading());
    await _fetch(emit);
  }

  Future<void> _onRefresh(
    RefreshCoachingGroups event,
    Emitter<CoachingGroupsState> emit,
  ) async {
    if (_userId.isEmpty) return;
    await _fetch(emit);
  }

  Future<void> _fetch(Emitter<CoachingGroupsState> emit) async {
    try {
      final memberships = await _memberRepo.getByUserId(_userId);

      final items = <CoachingGroupItem>[];
      for (final m in memberships) {
        final group = await _groupRepo.getById(m.groupId);
        if (group == null) continue;
        final count = await _memberRepo.countByGroupId(m.groupId);
        items.add(CoachingGroupItem(
          group: group,
          membership: m,
          memberCount: count,
        ));
      }

      emit(CoachingGroupsLoaded(groups: items));
    } on Exception catch (e) {
      emit(CoachingGroupsError('Erro ao carregar assessorias: $e'));
    }
  }
}
