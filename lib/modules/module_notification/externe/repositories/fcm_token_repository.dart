import 'package:supabase_flutter/supabase_flutter.dart';

class FcmTokenRepository {
  FcmTokenRepository(this._client);
  final SupabaseClient _client;

  Future<List<Map<String, dynamic>>> registerToken({required String token, required String platform, String? osVersion, String? appVersion, String? deviceBrand, String? deviceModel}) async {
    if (_client.auth.currentUser?.id == null) return const [];
    final response = await _client.rpc('register_user_device_token', params: {'p_token': token, 'p_platform': platform, 'p_os_version': osVersion, 'p_app_version': appVersion, 'p_device_brand': deviceBrand, 'p_device_model': deviceModel});
    if (response is! Map) return const [];
    final raw = response['missed_notifications'];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
  }

  Future<void> unregisterToken(String token) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    
    try {
      // Tentative via RPC pour une désactivation propre côté serveur
      await _client.rpc('desactiver_device_token', params: {'p_device_token': token});
    } catch (_) {
      // Repli sur mise à jour directe de la table si la RPC n'existe pas encore
      await _client.from('user_devices').update({'push_enabled': false}).eq('user_id', userId).eq('device_token', token);
    }
  }
}
