import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppConfigService extends GetxService {
  final SupabaseClient _client = Supabase.instance.client;
  final RxString minVersion = '1.0.0'.obs;
  final RxString currentServerVersion = '1.0.0'.obs;
  final RxBool isMaintenance = false.obs;
  final RxBool forceUpdateEnabled = false.obs;
  final RxBool needsUpdate = false.obs;
  final RxString updateMessage = ''.obs;
  final RxString maintenanceMessage = ''.obs;
  final RxString androidStoreUrl = ''.obs;
  final RxString iosStoreUrl = ''.obs;
  bool _checkInProgress = false;

  Future<AppConfigService> init() async => this;

  Future<void> checkConfig() async {
    if (_checkInProgress) return;
    _checkInProgress = true;
    try {
      final response = await _client.from('app_config').select(
        'min_version,current_version,is_maintenance,maintenance_message,force_update_enabled,update_message,android_store_url,ios_store_url',
      ).order('id', ascending: false).limit(1).maybeSingle();
      if (response == null) {
        needsUpdate.value = false;
        isMaintenance.value = false;
        forceUpdateEnabled.value = false;
        return;
      }
      final serverMin = (response['min_version'] as String?)?.trim();
      minVersion.value = serverMin?.isNotEmpty == true ? serverMin! : '1.0.0';
      final serverCurrent = (response['current_version'] as String?)?.trim();
      currentServerVersion.value = serverCurrent?.isNotEmpty == true ? serverCurrent! : minVersion.value;
      isMaintenance.value = response['is_maintenance'] == true;
      forceUpdateEnabled.value = response['force_update_enabled'] == true;
      updateMessage.value = (response['update_message'] as String?)?.trim() ?? '';
      maintenanceMessage.value = (response['maintenance_message'] as String?)?.trim() ?? '';
      androidStoreUrl.value = (response['android_store_url'] as String?)?.trim() ?? '';
      iosStoreUrl.value = (response['ios_store_url'] as String?)?.trim() ?? '';

      final packageInfo = await PackageInfo.fromPlatform();
      needsUpdate.value = forceUpdateEnabled.value && _isVersionLower(packageInfo.version, minVersion.value);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[AppConfigService] Check error: $e');
        debugPrintStack(stackTrace: st);
      }
      // Fail open if the remote policy cannot be fetched; do not lock users out on network errors.
      needsUpdate.value = false;
      isMaintenance.value = false;
      forceUpdateEnabled.value = false;
    } finally {
      _checkInProgress = false;
    }
  }

  bool _isVersionLower(String local, String minimum) {
    List<int> parse(String value) => value.split('+').first.split('-').first
        .split('.').map((part) => int.tryParse(part) ?? 0).toList();
    final a = parse(local), b = parse(minimum);
    final length = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < length; i++) {
      final av = i < a.length ? a[i] : 0;
      final bv = i < b.length ? b[i] : 0;
      if (av < bv) return true;
      if (av > bv) return false;
    }
    return false;
  }
}
