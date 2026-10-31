import 'package:get/get.dart';
import '../../../../app/service_global/device_service.dart';
import '../../../../shared/models/user_models.dart';

class DeviceController extends GetxController {
  final DeviceService _service = Get.find<DeviceService>();
  RxList<DeviceInfos> get devices => _service.devices;
  RxBool get isLoading => _service.isLoading;
  final RxnString errorMessage = RxnString();
  final RxSet<String> removingDeviceIds = <String>{}.obs;

  Future<void> loadDevices() async {
    if (isLoading.value) return;
    errorMessage.value = null;
    try {
      await _service.fetchDevices();
    } catch (_) {
      errorMessage.value = 'devices_error_generic'.tr;
    }
  }

  Future<void> removeDevice(String deviceId) async {
    if (removingDeviceIds.contains(deviceId)) return;
    errorMessage.value = null;
    removingDeviceIds.add(deviceId);
    try {
      await _service.removeDevice(deviceId);
    } catch (e) {
      final raw = e.toString().toLowerCase();
      errorMessage.value = raw.contains('current_device_unverified')
          ? 'devices_error_current_unverified'.tr
          : raw.contains('cannot_remove_current_device')
              ? 'devices_error_current_remove'.tr
              : raw.contains('device_not_found_or_not_owned')
                  ? 'devices_error_not_found'.tr
                  : raw.contains('not_authenticated') || raw.contains('jwt')
                      ? 'devices_error_auth'.tr
                      : 'devices_error_generic'.tr;
      rethrow;
    } finally {
      removingDeviceIds.remove(deviceId);
    }
  }
}
