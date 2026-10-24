import 'package:get/get.dart';
import '../../shared/models/user_models.dart';
import '../repository_global/device_repository.dart';
import 'notification_service.dart';

class DeviceService extends GetxService {
  final DeviceRepository _repository = DeviceRepository();

  final RxList<DeviceInfos> devices = <DeviceInfos>[].obs;
  final RxBool isLoading = false.obs;

  Future<List<DeviceInfos>> fetchDevices() async {
    try {
      isLoading.value = true;

      String? deviceToken;
      try {
        deviceToken = await NotificationService.instance.getDeviceToken();
      } catch (_) {
        // Le token push n'est pas indispensable pour récupérer la liste.
      }

      final data = await _repository.getMyDevices(deviceToken: deviceToken);
      devices.assignAll(data);
      return data;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> removeDevice(String deviceId) async {
    await _repository.deleteDevice(deviceId);
    devices.removeWhere((d) => d.id == deviceId);
  }
}
