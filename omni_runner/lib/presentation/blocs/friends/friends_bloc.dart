import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/domain/entities/friendship_entity.dart';
import 'package:omni_runner/domain/repositories/i_friendship_repo.dart';
import 'package:omni_runner/presentation/blocs/friends/friends_event.dart';
import 'package:omni_runner/presentation/blocs/friends/friends_state.dart';

class FriendsBloc extends Bloc<FriendsEvent, FriendsState> {
  final IFriendshipRepo _friendshipRepo;

  String _userId = '';

  FriendsBloc({required IFriendshipRepo friendshipRepo})
      : _friendshipRepo = friendshipRepo,
        super(const FriendsInitial()) {
    on<LoadFriends>(_onLoad);
    on<RefreshFriends>(_onRefresh);
  }

  Future<void> _onLoad(LoadFriends event, Emitter<FriendsState> emit) async {
    _userId = event.userId;
    emit(const FriendsLoading());
    await _fetch(emit);
  }

  Future<void> _onRefresh(
      RefreshFriends event, Emitter<FriendsState> emit) async {
    if (_userId.isEmpty) return;
    await _fetch(emit);
  }

  Future<void> _fetch(Emitter<FriendsState> emit) async {
    try {
      final all = await _friendshipRepo.getByUserId(_userId);

      final accepted = all
          .where((f) => f.status == FriendshipStatus.accepted)
          .toList();
      final pendingReceived = all
          .where((f) =>
              f.status == FriendshipStatus.pending && f.userIdB == _userId)
          .toList();
      final pendingSent = all
          .where((f) =>
              f.status == FriendshipStatus.pending && f.userIdA == _userId)
          .toList();

      emit(FriendsLoaded(
        userId: _userId,
        accepted: accepted,
        pendingReceived: pendingReceived,
        pendingSent: pendingSent,
      ));
    } on Exception catch (e) {
      emit(FriendsError('Erro ao carregar amigos: $e'));
    }
  }
}
