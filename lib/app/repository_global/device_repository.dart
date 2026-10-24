import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/models/user_models.dart';
import '../service_global/supabse_service.dart';

class DeviceRepository {
  final SupabaseClient _client = Get.find<SupabaseService>().client;

  /// Récupère tous les appareils associés au compte courant.
  ///
  /// Le backend calcule `is_current_device` à partir du token de l'appareil
  /// actuellement utilisé.
  Future<List<DeviceInfos>> getMyDevices({String? deviceToken}) async {
    try {
      final response = await _client.rpc(
        'get_my_devices',
        params: {
          'p_device_token': deviceToken,
        },
      );

      final data = Map<String, dynamic>.from(response as Map);
      final devicesJson = data['devices'];

      if (devicesJson is! List) {
        throw Exception(
          'Réponse invalide lors de la récupération des appareils',
        );
      }

      return devicesJson
          .map(
            (item) => DeviceInfos.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    } catch (e) {
      throw Exception('Échec de la récupération des appareils: $e');
    }
  }

  Future<void> deleteDevice(String deviceId) async {
    try {
      await _client.from('user_devices').delete().eq('id', deviceId);
    } catch (e) {
      throw Exception('Erreur suppression appareil: $e');
    }
  }

  Future<void> updateDevice(Map<String, dynamic> data) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return;

      await _client.from('user_devices').upsert({
        ...data,
        'user_id': userId,
        'last_seen_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id, device_token');
    } catch (e) {
      print('Erreur mise à jour device: $e');
    }
  }
}
