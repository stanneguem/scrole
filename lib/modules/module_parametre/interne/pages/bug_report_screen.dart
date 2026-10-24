import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../controllers/bug_report_controller.dart';

class BugReportScreen extends StatelessWidget {
  const BugReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(BugReportController());
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.background,
      appBar: AppBar(
        title: Text(
          'settings_report_bug'.tr,
          style: AppTextStyles.h6.copyWith(fontWeight: FontWeight.w700),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        centerTitle: true,
        actions: [
          Obx(() => controller.isSending.value
              ? const Padding(
                  padding: EdgeInsets.only(right: 16.0),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.send_rounded, color: AppColors.primary),
                  onPressed: controller.submitReport,
                  tooltip: 'bug_report_send'.tr,
                )),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'bug_report_title'.tr,
              style: AppTextStyles.labelLarge.copyWith(color: colorScheme.onSurface),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller.titleController,
              style: AppTextStyles.bodyLarge,
              decoration: InputDecoration(
                hintText: 'bug_report_title_hint'.tr,
                hintStyle: AppTextStyles.bodyLarge.copyWith(color: colorScheme.onSurfaceVariant.withOpacity(0.5)),
                filled: true,
                fillColor: isDark ? AppColors.surfaceDark : AppColors.white1,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'bug_report_desc'.tr,
              style: AppTextStyles.labelLarge.copyWith(color: colorScheme.onSurface),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller.descController,
              style: AppTextStyles.bodyLarge,
              maxLines: 8,
              decoration: InputDecoration(
                hintText: 'bug_report_desc_hint'.tr,
                hintStyle: AppTextStyles.bodyLarge.copyWith(color: colorScheme.onSurfaceVariant.withOpacity(0.5)),
                filled: true,
                fillColor: isDark ? AppColors.surfaceDark : AppColors.white1,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'bug_report_screenshot'.tr,
              style: AppTextStyles.labelLarge.copyWith(color: colorScheme.onSurface),
            ),
            const SizedBox(height: 12),
            Obx(() => _buildScreenshotSection(controller, isDark)),
          ],
        ),
      ),
    );
  }

  Widget _buildScreenshotSection(BugReportController controller, bool isDark) {
    if (controller.screenshot.value != null) {
      return Stack(
        children: [
          Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              image: DecorationImage(
                image: FileImage(controller.screenshot.value!),
                fit: BoxFit.cover,
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: controller.removeScreenshot,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      );
    }

    return InkWell(
      onTap: controller.pickScreenshot,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 120,
        width: double.infinity,
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.white1,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.primary.withOpacity(0.3),
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_photo_alternate_outlined, color: AppColors.primary, size: 32),
            const SizedBox(height: 8),
            Text(
              'bug_report_add_screenshot'.tr,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}
