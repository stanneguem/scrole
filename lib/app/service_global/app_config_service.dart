import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppConfigService extends GetxService {
  final SupabaseClient _client = Supabase.instance.client;

  final RxString minVersion = '1.0.0'.obs;
  final RxString currentServerVersion = '1.0.0'.obs;
  final RxBool isMaintenance = false.obs;
  final RxBool needsUpdate = false.obs;

  Future<AppConfigService> init() async {
    // Initialisation instantanée sans appel réseau bloquant au démarrage.
    return this;
  }

  Future<void> checkConfig() async {
    try {
      final response = await _client
          .from('app_config')
          .select()
          .order('id', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response != null) {
        final serverMinVersion = response['min_version'] ?? '1.0.0';
        isMaintenance.value = response['is_maintenance'] ?? false;
        minVersion.value = serverMinVersion;
        currentServerVersion.value = response['current_version'] ?? '1.0.0';

        final packageInfo = await PackageInfo.fromPlatform();
        needsUpdate.value = _isVersionLower(packageInfo.version, serverMinVersion);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AppConfigService] Check error: $e');
      }
      needsUpdate.value = false;
      isMaintenance.value = false;
    }
  }

  bool _isVersionLower(String local, String min) {
    try {
      List<int> localParts = local.split('.').map(int.parse).toList();
      List<int> minParts = min.split('.').map(int.parse).toList();
      for (int i = 0; i < 3; i++) {
        if (localParts[i] < minParts[i]) return true;
        if (localParts[i] > minParts[i]) return false;
      }
    } catch (_) {}
    return false;
  }
}
