import 'package:get/get.dart';
import '../../interne/controllers/create_activity_controller.dart';

class CreateActiviteBinding  extends Bindings{
  @override
  void dependencies() {
    Get.lazyPut<CreateActivityController>(
          () => CreateActivityController(),
    );
  }

}