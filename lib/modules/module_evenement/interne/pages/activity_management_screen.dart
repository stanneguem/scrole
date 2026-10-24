import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../app/routes/app_pages.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/widgets/scrole_bottom_sheet.dart';
import '../controllers/event_activity_controller.dart';
import '../../centre/models/activity_model.dart';
import 'activity_event_management_screen.dart';

class ActivityManagementScreen extends GetView<EventActivityController> {
  const ActivityManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Gérer les activités',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        ),
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }

        if (controller.eventActivities.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.local_activity_outlined,
                      size: 48,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Aucune activité liée à cet événement',
                    style: AppTextStyles.h5.copyWith(color: colors.onSurface),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Ajoutez des activités pour enrichir votre événement.',
                    style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => Get.toNamed(
                      AppPages.eventActivityAdd.replaceFirst(':id', controller.eventId),
                    ),
                    icon: const Icon(Icons.add_rounded, color: Colors.white),
                    label: const Text('Ajouter une activité', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: controller.eventActivities.length,
          itemBuilder: (context, index) {
            final activity = controller.eventActivities[index];
            return _ActivityCard(activity: activity);
          },
        );
      }),
      floatingActionButton: Obx(() => controller.eventActivities.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () => Get.toNamed(
                AppPages.eventActivityAdd.replaceFirst(':id', controller.eventId),
              ),
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: const Text('Ajouter une activité', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            )
          : const SizedBox.shrink()),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  final EventActivityModel activity;
  const _ActivityCard({required this.activity});

  void _showActivityDetailSheet(BuildContext context, EventActivityController controller) {
    ScroleBottomSheet.show(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.local_activity_rounded, color: AppColors.primary, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(activity.name, style: AppTextStyles.h4),
                      Text(
                        '${activity.price} ${activity.currency}',
                        style: AppTextStyles.h5.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (activity.description != null && activity.description!.isNotEmpty) ...[
              Text('Description', style: AppTextStyles.labelSmall),
              const SizedBox(height: 4),
              Text(activity.description!, style: AppTextStyles.body),
              const SizedBox(height: 16),
            ],
            ScroleBottomSheetGroup(
              children: [
                ScroleBottomSheetAction(
                  icon: Icons.people_outline,
                  label: 'Assigner du staff',
                  subtitle: 'Attribuer un membre du staff à cette activité',
                  onTap: () {
                    Get.back();
                    _showAssignStaffSheet(context, controller, activity.id);
                  },
                ),
                const ScroleBottomSheetDivider(),
                ScroleBottomSheetAction(
                  icon: Icons.qr_code_scanner,
                  label: 'Scanner les pass',
                  subtitle: 'Contrôler les entrées pour cette activité',
                  onTap: () {
                    Get.back();
                    Get.toNamed(
                      AppPages.eventScan.replaceFirst(':id', controller.eventId),
                      arguments: {'activityId': activity.id},
                    );
                  },
                ),
                const ScroleBottomSheetDivider(),
                ScroleBottomSheetAction(
                  icon: Icons.delete_outline_rounded,
                  label: 'Retirer de l\'événement',
                  color: AppColors.error,
                  onTap: () {
                    Get.back();
                    controller.removeActivity(activity);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showAssignStaffSheet(BuildContext context, EventActivityController controller, String eventActivityId) {
    ScroleBottomSheet.show(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Assigner du staff', style: AppTextStyles.h4),
            const SizedBox(height: 16),
            if (controller.eventStaff.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text('Aucun staff accepté pour cet événement.', style: AppTextStyles.bodySmall),
              )
            else
              ScroleBottomSheetGroup(
                children: controller.eventStaff.map((staff) => ScroleBottomSheetAction(
                  label: staff.name,
                  onTap: () {
                    controller.assignStaffToActivity(eventActivityId, staff.id);
                    Get.back();
                  },
                )).toList(),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<EventActivityController>();
    final colors = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Get.to(() => ActivityEventManagementScreen(eventActivity: activity)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.local_activity_rounded, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(activity.name, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold, fontSize: 15)),
                    if (activity.creatorFullName != null || activity.creatorUsername != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Créée par ${activity.creatorFullName ?? '@${activity.creatorUsername}'}',
                        style: AppTextStyles.caption.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            activity.formattedEventPrice,
                            style: AppTextStyles.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
