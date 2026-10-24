import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:scrole/modules/module_authentification/interne/enums/auth_statut.dart';
import 'app_controller.dart';
import 'package:scrole/modules/module_authentification/interne/pages/auth_screen.dart';
import 'package:scrole/modules/module_bannissement/interne/pages/banned_screen.dart';
import 'package:scrole/modules/module_creation_de_compte/interne/pages/create_account_screen.dart';
import 'package:scrole/modules/module_principale/interne/pages/main_navigation_screen.dart';
import 'package:scrole/modules/module_splash/interne/pages/server_unreachable_screen.dart';
import 'package:scrole/modules/module_splash/interne/pages/splash_screen_view.dart';
import 'package:scrole/modules/module_splash/interne/pages/maintenance_screen.dart';
import 'package:scrole/modules/module_splash/interne/pages/update_required_screen.dart';

class RootPage extends GetView<AppController> {
  const RootPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      switch (controller.status.value) {
        case AppStatus.loading:
          return SplashScreenView();
        case AppStatus.connectionError:
          return const ServerUnreachableScreen();
        case AppStatus.maintenance:
          return const MaintenanceScreen();
        case AppStatus.updateRequired:
          return const UpdateRequiredScreen();
        case AppStatus.unauthenticated:
          return AuthScreen();
        case AppStatus.needsProfile:
          return const CreateAccountScreen();
        case AppStatus.banned:
          return const BannedScreen();
        case AppStatus.authenticated:
          return const MainLayoutPage();
      }
    });
  }
}
