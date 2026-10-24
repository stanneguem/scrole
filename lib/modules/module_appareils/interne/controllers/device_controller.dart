import 'package:get/get.dart';
import '../../../../app/service_global/device_service.dart';
import '../../../../shared/models/user_models.dart';

class DeviceController extends GetxController {
  final DeviceService _service = Get.find<DeviceService>();

  RxList<DeviceInfos> get devices => _service.devices;
  RxBool get isLoading => _service.isLoading;
  final RxnString errorMessage = RxnString();

  Future<void> loadDevices() async {
    if (isLoading.value) return;

    errorMessage.value = null;

    try {
      await _service.fetchDevices();
    } catch (e) {
      errorMessage.value = e.toString();
    }
  }

  Future<void> removeDevice(String deviceId) async {
    errorMessage.value = null;

    try {
      await _service.removeDevice(deviceId);
    } catch (e) {
      errorMessage.value = e.toString();
      rethrow;
    }
  }
}
