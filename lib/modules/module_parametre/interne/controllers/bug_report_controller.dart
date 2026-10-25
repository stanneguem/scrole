import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../app/repository_global/storage_repository.dart';
import '../../../../app/repository_global/support_repository.dart';
import '../../../module_authentification/centre/services/auth_service.dart';

class BugReportController extends GetxController {
  final SupportRepository _supportRepository = SupportRepository();
  final StorageRepository _storageRepository = StorageRepository();
  final AuthService _authService = Get.find<AuthService>();

  final titleController = TextEditingController();
  final descController = TextEditingController();
  
  final Rxn<File> screenshot = Rxn<File>();
  final RxBool isSending = false.obs;
  final RxBool isPickingImage = false.obs;

  @override
  void onClose() {
    titleController.dispose();
    descController.dispose();
    super.onClose();
  }

  Future<void> pickScreenshot() async {
    isPickingImage.value = true;
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        screenshot.value = File(image.path);
      }
    } catch (e) {
      Get.snackbar('error'.tr, 'bug_report_error_image'.tr);
    } finally {
      isPickingImage.value = false;
    }
  }

  void removeScreenshot() {
    screenshot.value = null;
  }

  Future<void> submitReport() async {
    final title = titleController.text.trim();
    final description = descController.text.trim();

    if (title.isEmpty || description.isEmpty) {
      Get.snackbar('error'.tr, 'bug_report_error_empty'.tr);
      return;
    }

    isSending.value = true;
    try {
      String? screenshotObjectKey;
      final userId = _authService.userId;

      if (screenshot.value != null && userId != null) {
        screenshotObjectKey = await _storageRepository.uploadBugReportScreenshot(
          userId, 
          screenshot.value!,
        );
      }

      await _supportRepository.sendBugReport(
        title: title,
        description: description,
        screenshotObjectKey: screenshotObjectKey,
      );

      Get.back();
      Get.snackbar('profile_success_title'.tr, 'bug_report_success'.tr);
    } catch (e) {
      Get.snackbar('error'.tr, '${'bug_report_error_send'.tr}: $e');
    } finally {
      isSending.value = false;
    }
  }
}
