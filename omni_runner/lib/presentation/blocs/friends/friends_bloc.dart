import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/domain/entities/friendship_entity.dart';
import 'package:omni_runner/domain/repositories/i_friendship_repo.dart';
import 'package:omni_runner/domain/usecases/social/accept_friend.dart';
import 'package:omni_runner/domain/usecases/social/send_friend_invite.dart';
import 'package:omni_runner/presentation/blocs/friends/friends_event.dart';
import 'package:omni_runner/presentation/blocs/friends/friends_state.dart';
import 'package:uuid/uuid.dart';

class FriendsBloc extends Bloc<FriendsEvent, FriendsState> {
  final IFriendshipRepo _friendshipRepo;
  final SendFriendInvite _sendInvite;
  final AcceptFriend _acceptFriend;

  String _userId = '';

  FriendsBloc({
    required IFriendshipRepo friendshipRepo,
    required SendFriendInvite sendInvite,
    required AcceptFriend acceptFriend,
  })  : _friendshipRepo = friendshipRepo,
        _sendInvite = sendInvite,
        _acceptFriend = acceptFriend,
        super(const FriendsInitial()) {
    on<LoadFriends>(_onLoad);
    on<RefreshFriends>(_onRefresh);
    on<AcceptFriendEvent>(_onAccept);
    on<DeclineFriendEvent>(_onDecline);
    on<SendFriendRequest>(_onSend);
    on<RemoveFriend>(_onRemove);
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

  Future<void> _onAccept(
      AcceptFriendEvent event, Emitter<FriendsState> emit) async {
    try {
      await _acceptFriend.call(
        friendshipId: event.friendshipId,
        acceptingUserId: _userId,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
      await _fetch(emit);
    } on Exception catch (e) {
      emit(FriendsError('Erro ao aceitar convite: $e'));
    }
  }

  Future<void> _onDecline(
      DeclineFriendEvent event, Emitter<FriendsState> emit) async {
    try {
      final friendship = await _friendshipRepo.getById(event.friendshipId);
      if (friendship != null) {
        await _friendshipRepo.update(
          friendship.copyWith(status: FriendshipStatus.declined),
        );
      }
      await _fetch(emit);
    } on Exception catch (e) {
      emit(FriendsError('Erro ao recusar convite: $e'));
    }
  }

  Future<void> _onSend(
      SendFriendRequest event, Emitter<FriendsState> emit) async {
    try {
      await _sendInvite.call(
        fromUserId: _userId,
        toUserId: event.toUserId,
        uuidGenerator: () => const Uuid().v4(),
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
      await _fetch(emit);
    } on Exception catch (e) {
      emit(FriendsError('Erro ao enviar convite: $e'));
    }
  }

  Future<void> _onRemove(
      RemoveFriend event, Emitter<FriendsState> emit) async {
    try {
      await _friendshipRepo.deleteById(event.friendshipId);
      await _fetch(emit);
    } on Exception catch (e) {
      emit(FriendsError('Erro ao remover amigo: $e'));
    }
  }

  Future<void> _fetch(Emitter<FriendsState> emit) async {
    try {
      final all = await _friendshipRepo.getByUserId(_userId);

      final accepted = all
          .where((f) => f.status == FriendshipStatus.accepted)
          .toList();
      final pendingReceived = all
          .where((f) =>
              f.status == FriendshipStatus.pending && !f.isSentBy(_userId))
          .toList();
      final pendingSent = all
          .where((f) =>
              f.status == FriendshipStatus.pending && f.isSentBy(_userId))
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
