import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../service_global/supabse_service.dart';

class PreferencesRepository {
  final SupabaseService _supabase = Get.find();
  SupabaseClient get client => _supabase.client;

  /// RPC get_user_settings() : Récupère l'état complet serveur (preferences + privacy + server_cursor)
  Future<Map<String, dynamic>?> getUserSettingsRpc() async {
    try {
      final response = await client.rpc('get_user_settings');
      if (response == null) return null;
      return Map<String, dynamic>.from(response is List ? response.first : response);
    } catch (e) {
      debugPrint('[Error] RPC get_user_settings: $e');
      return null;
    }
  }

  /// RPC update_user_settings(p_changes) : Envoie uniquement les deltas de modifications
  Future<Map<String, dynamic>?> updateUserSettingsRpc(Map<String, dynamic> changes) async {
    if (changes.isEmpty) return null;
    try {
      final response = await client.rpc(
        'update_user_settings',
        params: {'p_changes': changes},
      );

      if (response == null) return null;
      return Map<String, dynamic>.from(response is List ? response.first : response);
    } catch (e) {
      debugPrint('[Error] RPC update_user_settings: $e');
      rethrow;
    }
  }
}
