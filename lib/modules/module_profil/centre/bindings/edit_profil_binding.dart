import 'package:get/get.dart';
import 'package:scrole/modules/module_profil/interne/controllers/edit_profil_controller.dart';

class EditProfilBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<EditProfileController>(
          () => EditProfileController(),
    );
  }
}