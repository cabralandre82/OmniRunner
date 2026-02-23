import 'package:equatable/equatable.dart';

/// Lifecycle of a friendship request.
///
/// Append-only ordinal rule (DECISAO 018): new values at the end only.
enum FriendshipStatus {
  /// Request sent, awaiting acceptance from [FriendshipEntity.userIdB].
  pending,

  /// Both users confirmed — friendship is active.
  accepted,

  /// Recipient declined the request.
  declined,

  /// One user blocked the other — mutual invisibility.
  blocked,
}

/// A bidirectional friendship link between two users.
///
/// [userIdA] is always the requester; [userIdB] the recipient.
/// The pair (userIdA, userIdB) is unique — enforced by the repository.
///
/// Immutable value object. No logic. No behavior.
/// See `docs/SOCIAL_SPEC.md` §2.
final class FriendshipEntity extends Equatable {
  /// Unique record ID (UUID v4).
  final String id;

  /// User who sent the friend request.
  final String userIdA;

  /// User who received the friend request.
  final String userIdB;

  final FriendshipStatus status;

  /// When the request was sent (ms since epoch, UTC).
  final int createdAtMs;

  /// When the request was accepted (ms since epoch, UTC).
  /// Null if [status] is not [FriendshipStatus.accepted].
  final int? acceptedAtMs;

  const FriendshipEntity({
    required this.id,
    required this.userIdA,
    required this.userIdB,
    required this.status,
    required this.createdAtMs,
    this.acceptedAtMs,
  });

  /// Whether this friendship is currently active.
  bool get isActive => status == FriendshipStatus.accepted;

  /// Returns the other user's ID given [myUserId].
  String otherUserId(String myUserId) =>
      myUserId == userIdA ? userIdB : userIdA;

  FriendshipEntity copyWith({
    FriendshipStatus? status,
    int? acceptedAtMs,
  }) =>
      FriendshipEntity(
        id: id,
        userIdA: userIdA,
        userIdB: userIdB,
        status: status ?? this.status,
        createdAtMs: createdAtMs,
        acceptedAtMs: acceptedAtMs ?? this.acceptedAtMs,
      );

  @override
  List<Object?> get props => [
        id,
        userIdA,
        userIdB,
        status,
        createdAtMs,
        acceptedAtMs,
      ];
}
