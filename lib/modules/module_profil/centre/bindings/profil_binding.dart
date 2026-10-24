import 'package:get/get.dart';
import 'package:scrole/modules/module_profil/interne/controllers/profile_controller.dart';

class ProfilBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ProfileController>(
          () => ProfileController(),
    );
  }
}