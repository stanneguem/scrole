import 'package:flutter/cupertino.dart';
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDark : colors.surface;
    final background = isDark ? AppColors.backgroundDark : AppColors.background;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          'settings_report_bug'.tr,
          style: AppTextStyles.h6.copyWith(
            color: colors.onSurface,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => Get.back(),
          icon: Icon(
            CupertinoIcons.chevron_back,
            size: 22,
            color: colors.onSurface,
          ),
        ),
        actions: [
          Obx(() {
            final busy = controller.isSending.value;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: busy ? null : controller.submitReport,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  disabledForegroundColor: colors.onSurfaceVariant.withOpacity(0.5),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(64, 40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: busy
                      ? Row(
                          key: const ValueKey('sending'),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: 7),
                            Text(
                              'bug_report_sending'.tr,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ],
                        )
                      : Text(
                          'bug_report_send'.tr,
                          key: const ValueKey('send'),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            );
          }),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildIntro(context, isDark),
                    const SizedBox(height: 26),
                    _buildSectionLabel(context, 'bug_report_title'.tr),
                    const SizedBox(height: 9),
                    _buildTextField(
                      context: context,
                      controller: controller.titleController,
                      hint: 'bug_report_title_hint'.tr,
                      surface: surface,
                      maxLength: 100,
                      maxLines: 1,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: 22),
                    _buildSectionLabel(context, 'bug_report_desc'.tr),
                    const SizedBox(height: 9),
                    _buildTextField(
                      context: context,
                      controller: controller.descController,
                      hint: 'bug_report_desc_hint'.tr,
                      surface: surface,
                      maxLength: 2000,
                      maxLines: 6,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: _buildSectionLabel(
                            context,
                            'bug_report_screenshot'.tr,
                          ),
                        ),
                        Text(
                          'bug_report_optional'.tr,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: colors.onSurfaceVariant,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Obx(() => _buildScreenshotSection(
                          context,
                          controller,
                          isDark,
                          surface,
                        )),
                    const SizedBox(height: 18),
                    _buildPrivacyHint(context, isDark),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIntro(BuildContext context, bool isDark) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withOpacity(isDark ? 0.22 : 0.12),
            AppColors.primary.withOpacity(isDark ? 0.08 : 0.035),
          ],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(isDark ? 0.22 : 0.13),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              CupertinoIcons.chat_bubble_text,
              color: AppColors.primary,
              size: 23,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'bug_report_title'.tr,
                  style: AppTextStyles.labelLarge.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'bug_report_desc_hint'.tr,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(BuildContext context, String text) {
    return Text(
      text,
      style: AppTextStyles.labelLarge.copyWith(
        color: Theme.of(context).colorScheme.onSurface,
        fontWeight: FontWeight.w700,
        fontSize: 14,
      ),
    );
  }

  Widget _buildTextField({
    required BuildContext context,
    required TextEditingController controller,
    required String hint,
    required Color surface,
    required int maxLength,
    required int maxLines,
    required TextCapitalization textCapitalization,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: Theme.of(context).brightness == Brightness.dark
            ? const []
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.025),
                  blurRadius: 18,
                  offset: const Offset(0, 5),
                ),
              ],
      ),
      child: TextField(
        controller: controller,
        textCapitalization: textCapitalization,
        maxLength: maxLength,
        maxLines: maxLines,
        minLines: maxLines == 1 ? 1 : 4,
        style: AppTextStyles.bodyLarge.copyWith(
          color: colors.onSurface,
          fontSize: 15,
          height: 1.45,
        ),
        cursorColor: AppColors.primary,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppTextStyles.bodyLarge.copyWith(
            color: colors.onSurfaceVariant.withOpacity(0.68),
            fontSize: 14,
            height: 1.45,
          ),
          counterStyle: AppTextStyles.bodySmall.copyWith(
            color: colors.onSurfaceVariant.withOpacity(0.75),
            fontSize: 11,
          ),
          filled: false,
          contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(
              color: AppColors.primary.withOpacity(0.72),
              width: 1.2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScreenshotSection(
    BuildContext context,
    BugReportController controller,
    bool isDark,
    Color surface,
  ) {
    final colors = Theme.of(context).colorScheme;
    final file = controller.screenshot.value;

    if (file != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            Image.file(
              file,
              width: double.infinity,
              height: 210,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                height: 150,
                color: surface,
                alignment: Alignment.center,
                child: Icon(
                  CupertinoIcons.photo,
                  color: colors.onSurfaceVariant,
                  size: 34,
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.28),
                      Colors.transparent,
                      Colors.black.withOpacity(0.24),
                    ],
                    stops: const [0, 0.38, 1],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: Material(
                color: Colors.black.withOpacity(0.58),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: controller.removeScreenshot,
                  child: const Padding(
                    padding: EdgeInsets.all(9),
                    child: Icon(
                      CupertinoIcons.xmark,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 14,
              bottom: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.checkmark_circle_fill,
                        size: 15, color: Colors.white),
                    SizedBox(width: 7),
                    Text(
                      'bug_report_capture_added'.tr,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: controller.isPickingImage.value
            ? null
            : controller.pickScreenshot,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colors.outlineVariant.withOpacity(isDark ? 0.45 : 0.55),
              width: 0.8,
            ),
          ),
          child: controller.isPickingImage.value
              ? const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  ),
                )
              : Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(isDark ? 0.2 : 0.1),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Icon(
                        CupertinoIcons.photo_on_rectangle,
                        color: AppColors.primary,
                        size: 23,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'bug_report_add_screenshot'.tr,
                            style: AppTextStyles.bodyLarge.copyWith(
                              color: colors.onSurface,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'bug_report_screenshot_help'.tr,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: colors.onSurfaceVariant,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      CupertinoIcons.plus_circle,
                      size: 22,
                      color: colors.onSurfaceVariant,
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildPrivacyHint(BuildContext context, bool isDark) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          CupertinoIcons.lock_shield,
          color: colors.onSurfaceVariant,
          size: 17,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            'bug_report_privacy_hint'.tr,
            style: AppTextStyles.bodySmall.copyWith(
              color: colors.onSurfaceVariant,
              fontSize: 11,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }

}
