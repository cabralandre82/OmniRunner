import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/domain/repositories/i_group_repo.dart';
import 'package:omni_runner/presentation/blocs/groups/groups_event.dart';
import 'package:omni_runner/presentation/blocs/groups/groups_state.dart';

class GroupsBloc extends Bloc<GroupsEvent, GroupsState> {
  final IGroupRepo _groupRepo;

  String _userId = '';

  GroupsBloc({required IGroupRepo groupRepo})
      : _groupRepo = groupRepo,
        super(const GroupsInitial()) {
    on<LoadGroups>(_onLoad);
    on<RefreshGroups>(_onRefresh);
  }

  Future<void> _onLoad(LoadGroups event, Emitter<GroupsState> emit) async {
    _userId = event.userId;
    emit(const GroupsLoading());
    await _fetch(emit);
  }

  Future<void> _onRefresh(
      RefreshGroups event, Emitter<GroupsState> emit) async {
    if (_userId.isEmpty) return;
    await _fetch(emit);
  }

  Future<void> _fetch(Emitter<GroupsState> emit) async {
    try {
      final groups = await _groupRepo.getGroupsByUserId(_userId);
      emit(GroupsLoaded(groups: groups));
    } on Exception catch (e) {
      emit(GroupsError('Erro ao carregar grupos: $e'));
    }
  }
}
