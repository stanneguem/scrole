import 'package:get/get.dart';
import '../../shared/models/user_models.dart';
import '../repository_global/device_repository.dart';
import 'notification_service.dart';

class DeviceService extends GetxService {
  final DeviceRepository _repository = DeviceRepository();
  final RxList<DeviceInfos> devices = <DeviceInfos>[].obs;
  final RxBool isLoading = false.obs;

  Future<List<DeviceInfos>> fetchDevices() async {
    if (isLoading.value) return devices.toList(growable: false);
    isLoading.value = true;
    try {
      String? token;
      try { token = await NotificationService.instance.getDeviceToken(); } catch (_) {}
      final result = await _repository.getMyDevices(deviceToken: token);
      devices.assignAll(result);
      return result;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> removeDevice(String deviceId) async {
    final token = await NotificationService.instance.getDeviceToken();
    if (token.trim().isEmpty) throw StateError('current_device_unverified');
    await _repository.deleteDevice(deviceId: deviceId, currentDeviceToken: token);
    devices.removeWhere((d) => d.id == deviceId);
  }
}
