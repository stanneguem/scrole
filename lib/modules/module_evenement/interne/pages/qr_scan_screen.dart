import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../centre/models/activity_model.dart';
import '../../centre/models/checkin_model.dart';
import '../controllers/qr_scan_controller.dart';

class QrScanScreen extends GetView<QrScanController> {
  const QrScanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(controller.eventActivityId != null ? 'scan_title_activity'.tr : 'scan_title_entry'.tr),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          MobileScanner(
            controller: controller.mobileScannerController,
            onDetect: controller.onScan,
          ),
          // Target box
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),

          // Instructions at bottom
          Positioned(
            bottom: 60,
            left: 20,
            right: 20,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'scan_hint'.tr,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),

          // Reactive State Modal/Overlay
          Obx(() {
            final state = controller.scanState.value;
            final isBusy = controller.isProcessing.value ||
                state == ScanState.checkingPresence ||
                state == ScanState.activityValidating;

            if (isBusy) {
              return Container(
                color: Colors.black.withValues(alpha: 0.6),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: AppColors.primary),
                      const SizedBox(height: 16),
                      Text(
                        'checkin_verifying'.tr,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              );
            }

            if (state == ScanState.presenceValidated) {
              return _buildResultModal(
                context,
                colorScheme,
                icon: Icons.check_circle_rounded,
                iconColor: AppColors.success,
                title: 'checkin_presence_confirmed_title'.tr,
                message: 'checkin_presence_confirmed_msg'.tr,
              );
            }

            if (state == ScanState.activityValidated) {
              final actName = controller.selectedActivity.value?.name ?? '';
              return _buildResultModal(
                context,
                colorScheme,
                icon: Icons.check_circle_rounded,
                iconColor: AppColors.success,
                title: 'checkin_activity_confirmed_title'.tr,
                message: 'checkin_activity_confirmed_msg'.trParams({'name': actName}),
              );
            }

            if (state == ScanState.activitySelection) {
              final result = controller.lastResult.value;
              final activities = result?.availableActivities ?? [];
              return _buildActivitySelectionModal(context, colorScheme, activities);
            }

            if (state == ScanState.alreadyPresent) {
              return _buildResultModal(
                context,
                colorScheme,
                icon: Icons.info_rounded,
                iconColor: Colors.blue,
                title: 'checkin_already_present_title'.tr,
                message: 'checkin_no_activity_available_msg'.tr,
              );
            }

            if (state == ScanState.userNotRegistered) {
              return _buildResultModal(
                context,
                colorScheme,
                icon: Icons.person_off_rounded,
                iconColor: AppColors.error,
                title: 'checkin_not_registered_title'.tr,
                message: controller.errorMessage.value ?? 'checkin_not_registered_msg'.tr,
              );
            }

            if (state == ScanState.eventNotStarted) {
              return _buildResultModal(
                context,
                colorScheme,
                icon: Icons.hourglass_top_rounded,
                iconColor: Colors.amber[800]!,
                title: 'checkin_not_started_title'.tr,
                message: controller.errorMessage.value ?? 'checkin_not_started_msg'.tr,
              );
            }

            if (state == ScanState.permissionDenied) {
              return _buildResultModal(
                context,
                colorScheme,
                icon: Icons.lock_outline_rounded,
                iconColor: AppColors.error,
                title: 'checkin_permission_denied_title'.tr,
                message: controller.errorMessage.value ?? 'checkin_permission_denied_msg'.tr,
              );
            }

            if (state == ScanState.activityUnavailable ||
                state == ScanState.scanError ||
                state == ScanState.networkError) {
              return _buildResultModal(
                context,
                colorScheme,
                icon: Icons.error_outline_rounded,
                iconColor: AppColors.error,
                title: 'wall_error_loading'.tr,
                message: controller.errorMessage.value ?? 'checkin_generic_error_msg'.tr,
              );
            }

            return const SizedBox.shrink();
          }),
        ],
      ),
    );
  }

  Widget _buildResultModal(
    BuildContext context,
    ColorScheme colorScheme, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String message,
  }) {
    return Container(
      color: Colors.black.withValues(alpha: 0.65),
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54, color: iconColor),
            const SizedBox(height: 16),
            Text(
              title,
              style: AppTextStyles.h4.copyWith(color: colorScheme.onSurface),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: AppTextStyles.body.copyWith(color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: controller.resetScan,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: Text('checkin_next_scan_action'.tr),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                backgroundColor: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivitySelectionModal(
    BuildContext context,
    ColorScheme colorScheme,
    List<AvailableActivityModel> activities,
  ) {
    return Container(
      color: Colors.black.withValues(alpha: 0.65),
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxHeight: 450),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.stars_rounded, color: AppColors.primary, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'checkin_select_activity_title'.tr,
                    style: AppTextStyles.h4.copyWith(color: colorScheme.onSurface),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'checkin_select_activity_subtitle'.tr,
              style: AppTextStyles.bodySmall.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: activities.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final activity = activities[index];
                  return Material(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: () => controller.validateActivity(activity),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(
                          children: [
                            const Icon(Icons.local_activity_rounded, color: AppColors.primary, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                activity.name,
                                style: AppTextStyles.body.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded, color: colorScheme.onSurfaceVariant),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: controller.resetScan,
              style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 44)),
              child: Text('checkin_cancel_action'.tr),
            ),
          ],
        ),
      ),
    );
  }
}
