import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Service wrapping Supabase calls for profile management.
/// Used by [ProfileScreen].
class ProfileDataService {
  ProfileDataService(this._client);

  final SupabaseClient _client;

  /// Fetches social columns (instagram_handle, tiktok_handle) for a profile.
  Future<Map<String, dynamic>?> getSocialColumns(String profileId) async {
    try {
      final row = await _client
          .from('profiles')
          .select('instagram_handle, tiktok_handle')
          .eq('id', profileId)
          .maybeSingle();
      return row != null ? Map<String, dynamic>.from(row) : null;
    } on Exception {
      return null;
    }
  }

  /// Updates profile fields (display_name, social columns).
  Future<List<Map<String, dynamic>>> updateProfile(
    String profileId,
    Map<String, dynamic> fields,
  ) async {
    final res = await _client
        .from('profiles')
        .update(fields)
        .eq('id', profileId)
        .select();
    return List<Map<String, dynamic>>.from(
      (res as List).map((r) => Map<String, dynamic>.from(r as Map)),
    );
  }

  /// Returns the current Supabase auth user.
  User? get currentUser => _client.auth.currentUser;

  /// Uploads avatar bytes to storage and returns the public URL.
  Future<String> uploadAvatar(String userId, String extension, Uint8List bytes) async {
    final path = 'avatars/$userId.$extension';
    await _client.storage
        .from('avatars')
        .uploadBinary(path, bytes, fileOptions: const FileOptions(upsert: true));
    return _client.storage.from('avatars').getPublicUrl(path);
  }

  /// Invokes the delete-account edge function.
  Future<void> requestDeleteAccount() async {
    await _client.functions.invoke('delete-account', body: {});
  }
}
