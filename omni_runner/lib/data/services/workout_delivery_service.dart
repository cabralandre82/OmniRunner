import 'package:supabase_flutter/supabase_flutter.dart';

/// Service wrapping Supabase calls for workout delivery items.
/// Used by [AthleteDeliveryScreen] and [AthleteWorkoutDayScreen].
class WorkoutDeliveryService {
  WorkoutDeliveryService(this._client);

  final SupabaseClient _client;

  /// Fetches published delivery items for the athlete.
  Future<List<Map<String, dynamic>>> listPublishedItems(String athleteUserId) async {
    final rows = await _client
        .from('workout_delivery_items')
        .select()
        .eq('athlete_user_id', athleteUserId)
        .inFilter('status', ['published'])
        .order('created_at', ascending: false)
        .limit(500);
    return List<Map<String, dynamic>>.from(
      (rows as List).map((r) => Map<String, dynamic>.from(r as Map)),
    );
  }

  /// Returns the count of published delivery items for the athlete.
  Future<int> countPublishedItems(String athleteUserId) async {
    final res = await _client
        .from('workout_delivery_items')
        .select()
        .eq('athlete_user_id', athleteUserId)
        .inFilter('status', ['published'])
        .count(CountOption.exact);
    return res.count;
  }

  /// Confirms or marks an item as failed.
  Future<void> confirmItem({
    required String itemId,
    required String result,
    String? reason,
  }) async {
    await _client.rpc('fn_athlete_confirm_item', params: {
      'p_item_id': itemId,
      'p_result': result,
      'p_reason': reason,
    });
  }
}
