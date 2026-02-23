import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/domain/usecases/coaching/get_coaching_group_details.dart';
import 'package:omni_runner/presentation/blocs/coaching_group_details/coaching_group_details_event.dart';
import 'package:omni_runner/presentation/blocs/coaching_group_details/coaching_group_details_state.dart';

class CoachingGroupDetailsBloc
    extends Bloc<CoachingGroupDetailsEvent, CoachingGroupDetailsState> {
  final GetCoachingGroupDetails _getDetails;

  String _groupId = '';
  String _callerUserId = '';

  CoachingGroupDetailsBloc({
    required GetCoachingGroupDetails getDetails,
  })  : _getDetails = getDetails,
        super(const CoachingGroupDetailsInitial()) {
    on<LoadCoachingGroupDetails>(_onLoad);
    on<RefreshCoachingGroupDetails>(_onRefresh);
  }

  Future<void> _onLoad(
    LoadCoachingGroupDetails event,
    Emitter<CoachingGroupDetailsState> emit,
  ) async {
    _groupId = event.groupId;
    _callerUserId = event.callerUserId;
    emit(const CoachingGroupDetailsLoading());
    await _fetch(emit);
  }

  Future<void> _onRefresh(
    RefreshCoachingGroupDetails event,
    Emitter<CoachingGroupDetailsState> emit,
  ) async {
    if (_groupId.isEmpty) return;
    await _fetch(emit);
  }

  Future<void> _fetch(Emitter<CoachingGroupDetailsState> emit) async {
    try {
      final details = await _getDetails.call(
        groupId: _groupId,
        callerUserId: _callerUserId,
      );
      emit(CoachingGroupDetailsLoaded(
        details: details,
        callerUserId: _callerUserId,
      ));
    } on Exception catch (e) {
      emit(CoachingGroupDetailsError('Erro ao carregar grupo: $e'));
    }
  }
}
