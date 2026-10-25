import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/models/user_models.dart';
import '../service_global/supabse_service.dart';

class DeviceRepository {
  final SupabaseClient _client = Get.find<SupabaseService>().client;

  Future<List<DeviceInfos>> getMyDevices({String? deviceToken}) async {
    final response = await _client.rpc('get_my_devices', params: {'p_device_token': deviceToken});
    if (response is! Map) throw const FormatException('Invalid devices response');
    final items = response['devices'];
    if (items is! List) throw const FormatException('Missing devices array');
    return items.whereType<Map>().map((item) => DeviceInfos.fromJson(Map<String, dynamic>.from(item))).toList(growable: false);
  }

  Future<void> deleteDevice({required String deviceId, required String currentDeviceToken}) async {
    final result = await _client.rpc('remove_my_device', params: {
      'p_device_id': deviceId, 'p_current_device_token': currentDeviceToken,
    });
    if (result is! Map || result['success'] != true) throw const FormatException('Device removal was not confirmed');
  }

  Future<void> updateDevice(Map<String, dynamic> data) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('not_authenticated');
    await _client.from('user_devices').upsert({
      ...data, 'user_id': userId, 'last_seen_at': DateTime.now().toIso8601String(),
    }, onConflict: 'user_id, device_token');
  }
}
