import 'package:get/get.dart';
import '../../interne/controllers/create_account_controller.dart';

class CreateUserAccountBinding extends Bindings {
  @override
  void dependencies() {
    ensureRegistered();
  }

  static void ensureRegistered() {
    if (!Get.isRegistered<CreateAccountController>()) {
      Get.lazyPut<CreateAccountController>(
        () => CreateAccountController(),
      );
    }
  }
}
