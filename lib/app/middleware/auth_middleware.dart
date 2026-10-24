import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../modules/module_authentification/centre/services/auth_service.dart';


class AuthMiddleware extends GetMiddleware {
  AuthMiddleware({super.priority = 0});

  final AuthService _authService = Get.find<AuthService>();

  @override
  RouteSettings? redirect(String? route) {
    final user = _authService.currentUser;
    return null;
  }
}