import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/domain/entities/friendship_entity.dart';
import 'package:omni_runner/domain/repositories/i_friendship_repo.dart';

/// Supabase-backed implementation of [IFriendshipRepo].
///
/// Uses the `friendships` table with RLS policies that allow
/// read/write only for involved users.
class SupabaseFriendshipRepo implements IFriendshipRepo {
  SupabaseClient get _db => Supabase.instance.client;

  FriendshipEntity _fromRow(Map<String, dynamic> r) => FriendshipEntity(
        id: r['id'] as String,
        userIdA: r['user_id_a'] as String,
        userIdB: r['user_id_b'] as String,
        status: _parseStatus(r['status'] as String? ?? 'pending'),
        createdAtMs: r['created_at_ms'] as int,
        acceptedAtMs: r['accepted_at_ms'] as int?,
      );

  static FriendshipStatus _parseStatus(String s) => switch (s) {
        'accepted' => FriendshipStatus.accepted,
        'declined' => FriendshipStatus.declined,
        'blocked' => FriendshipStatus.blocked,
        _ => FriendshipStatus.pending,
      };

  @override
  Future<void> save(FriendshipEntity f) async {
    final a = f.userIdA.compareTo(f.userIdB) < 0 ? f.userIdA : f.userIdB;
    final b = f.userIdA.compareTo(f.userIdB) < 0 ? f.userIdB : f.userIdA;
    await _db.from('friendships').insert({
      'id': f.id,
      'user_id_a': a,
      'user_id_b': b,
      'status': f.status.name,
      'created_at_ms': f.createdAtMs,
      'invited_by': f.userIdA,
    });
  }

  @override
  Future<void> update(FriendshipEntity f) async {
    await _db.from('friendships').update({
      'status': f.status.name,
      if (f.acceptedAtMs != null) 'accepted_at_ms': f.acceptedAtMs,
    }).eq('id', f.id);
  }

  @override
  Future<FriendshipEntity?> getById(String id) async {
    final r = await _db
        .from('friendships')
        .select()
        .eq('id', id)
        .maybeSingle();
    return r == null ? null : _fromRow(r);
  }

  @override
  Future<List<FriendshipEntity>> getByUserId(String userId) async {
    final rowsA = await _db
        .from('friendships')
        .select()
        .eq('user_id_a', userId)
        .neq('status', 'blocked');
    final rowsB = await _db
        .from('friendships')
        .select()
        .eq('user_id_b', userId)
        .neq('status', 'blocked');
    final all = <FriendshipEntity>[];
    for (final r in rowsA) {
      all.add(_fromRow(r));
    }
    for (final r in rowsB) {
      all.add(_fromRow(r));
    }
    return all;
  }

  @override
  Future<List<FriendshipEntity>> getAcceptedByUserId(String userId) async {
    final rows = await getByUserId(userId);
    return rows.where((f) => f.status == FriendshipStatus.accepted).toList();
  }

  @override
  Future<List<FriendshipEntity>> getPendingForUser(String userId) async {
    final rows = await _db
        .from('friendships')
        .select()
        .eq('user_id_b', userId)
        .eq('status', 'pending');
    return rows.map(_fromRow).toList();
  }

  @override
  Future<FriendshipEntity?> findBetween(String userIdA, String userIdB) async {
    final a = userIdA.compareTo(userIdB) < 0 ? userIdA : userIdB;
    final b = userIdA.compareTo(userIdB) < 0 ? userIdB : userIdA;
    final r = await _db
        .from('friendships')
        .select()
        .eq('user_id_a', a)
        .eq('user_id_b', b)
        .neq('status', 'blocked')
        .maybeSingle();
    return r == null ? null : _fromRow(r);
  }

  @override
  Future<bool> isBlocked(String userIdA, String userIdB) async {
    final a = userIdA.compareTo(userIdB) < 0 ? userIdA : userIdB;
    final b = userIdA.compareTo(userIdB) < 0 ? userIdB : userIdA;
    final r = await _db
        .from('friendships')
        .select('id')
        .eq('user_id_a', a)
        .eq('user_id_b', b)
        .eq('status', 'blocked')
        .maybeSingle();
    return r != null;
  }

  @override
  Future<int> countAccepted(String userId) async {
    final rows = await getAcceptedByUserId(userId);
    return rows.length;
  }

  @override
  Future<int> countPendingSent(String userId) async {
    final rows = await _db
        .from('friendships')
        .select('id')
        .or('user_id_a.eq.$userId,user_id_b.eq.$userId')
        .eq('status', 'pending')
        .eq('invited_by', userId);
    return (rows as List).length;
  }

  @override
  Future<void> deleteById(String id) async {
    await _db.from('friendships').delete().eq('id', id);
  }
}
