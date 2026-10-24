import 'package:flutter/material.dart';
import 'package:get/get.dart';

void showNoInternetSnackbar() {
  Get.snackbar(
    'Pas de connexion',
    'Vérifie ta connexion internet et réessaie.',
    snackPosition: SnackPosition.BOTTOM,
    icon: const Icon(Icons.wifi_off_rounded, color: Colors.white),
    backgroundColor: Colors.red.shade600,
    colorText: Colors.white,
    margin: const EdgeInsets.all(12),
    borderRadius: 12,
    duration: const Duration(seconds: 3),
    animationDuration: const Duration(milliseconds: 300),
    isDismissible: true,
    forwardAnimationCurve: Curves.easeOutBack,
  );
}
