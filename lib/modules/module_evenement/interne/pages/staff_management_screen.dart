import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../../../../shared/widgets/scrole_bottom_sheet.dart';
import '../controllers/staff_controller.dart';
import '../../centre/models/staff_model.dart';
import 'add_staff_screen.dart';
import 'assign_staff_activities_screen.dart';
import 'staff_stats_screen.dart';

class StaffManagementScreen extends GetView<StaffController> {
  const StaffManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Staff',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: () => Get.to(() => const AddStaffScreen(isCoCreator: false)),
              child: Text(
                'Inviter',
                style: GoogleFonts.spaceGrotesk(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Obx(() {
        if (controller.isLoadingStaff.value && controller.staffMembers.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (controller.staffMembers.isEmpty) {
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
                      Icons.people_outline_rounded,
                      size: 52,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Aucun membre du staff pour l\'instant',
                    style: AppTextStyles.h5.copyWith(color: colors.onSurface),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Invitez des personnes pour vous aider à gérer cet événement.',
                    style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => Get.to(() => const AddStaffScreen(isCoCreator: false)),
                    icon: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
                    label: const Text('Inviter un membre du staff', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
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

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (controller.acceptedStaff.isNotEmpty) ...[
              _buildSectionTitle('MEMBRES CONFIRMÉS (${controller.acceptedStaff.length})'),
              ...controller.acceptedStaff.map((m) => _StaffCard(member: m, controller: controller)),
              const SizedBox(height: 16),
            ],
            if (controller.pendingStaff.isNotEmpty) ...[
              _buildSectionTitle('INVITATIONS EN ATTENTE (${controller.pendingStaff.length})'),
              ...controller.pendingStaff.map((m) => _StaffCard(member: m, controller: controller)),
              const SizedBox(height: 16),
            ],
            if (controller.rejectedStaff.isNotEmpty) ...[
              _buildSectionTitle('INVITATIONS REFUSÉES (${controller.rejectedStaff.length})'),
              ...controller.rejectedStaff.map((m) => _StaffCard(member: m, controller: controller)),
              const SizedBox(height: 16),
            ],
          ],
        );
      }),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        title,
        style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary, letterSpacing: 1.2),
      ),
    );
  }
}

class _StaffCard extends StatelessWidget {
  final StaffMemberModel member;
  final StaffController controller;

  const _StaffCard({required this.member, required this.controller});

  void _showStaffOptionsMenu(BuildContext context) {
    ScroleBottomSheet.show(
      context: context,
      showCancel: true,
      cancelLabel: 'Annuler',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('Options du membre', style: AppTextStyles.h4),
            ),
            const SizedBox(height: 12),
            ScroleBottomSheetGroup(
              children: [
                if (member.status == StaffStatus.accepted) ...[
                  ScroleBottomSheetAction(
                    icon: Icons.assignment_ind_outlined,
                    label: 'Attribuer des activités',
                    subtitle: 'Gérer les activités confiées à ce membre',
                    onTap: () {
                      Get.back();
                      Get.to(() => AssignStaffActivitiesScreen(staffMember: member));
                    },
                  ),
                  const ScroleBottomSheetDivider(),
                  ScroleBottomSheetAction(
                    icon: Icons.workspace_premium_rounded,
                    label: 'Promouvoir comme co-fondateur',
                    subtitle: 'Transférer ce membre vers l\'équipe de co-fondateurs',
                    color: AppColors.primary,
                    onTap: () {
                      Get.back();
                      _showPromoteToCoCreatorSheet(context);
                    },
                  ),
                  const ScroleBottomSheetDivider(),
                ],
                ScroleBottomSheetAction(
                  icon: Icons.person_remove_outlined,
                  label: 'Retirer du staff',
                  subtitle: 'Retirer ce membre de cet événement',
                  color: AppColors.error,
                  onTap: () {
                    Get.back();
                    _showRemoveStaffSheet(context);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showPromoteToCoCreatorSheet(BuildContext context) {
    ScroleBottomSheet.show(
      context: context,
      showCancel: true,
      cancelLabel: 'Annuler',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Promouvoir comme co-fondateur ?', style: AppTextStyles.h4),
                  const SizedBox(height: 8),
                  Text(
                    'Ce membre fait actuellement partie du staff.\n\nSi vous le promouvez comme co-fondateur :\n• Il ne sera plus membre du staff ;\n• Toutes les activités qui lui sont actuellement attribuées seront désassignées ;\n• Les activités resteront toutefois disponibles dans cet événement ;\n• Les attributions des autres membres du staff ne seront pas affectées.',
                    style: AppTextStyles.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ScroleBottomSheetGroup(
              children: [
                ScroleBottomSheetAction(
                  icon: Icons.workspace_premium_rounded,
                  label: 'Promouvoir comme co-fondateur',
                  color: AppColors.primary,
                  onTap: () {
                    Get.back();
                    controller.promoteStaffToCoCreator(member.userId);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showRemoveStaffSheet(BuildContext context) {
    ScroleBottomSheet.show(
      context: context,
      showCancel: true,
      cancelLabel: 'Annuler',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Retirer du staff ?', style: AppTextStyles.h4),
                  const SizedBox(height: 4),
                  Text('Voulez-vous vraiment retirer ${member.name} du staff de cet événement ?', style: AppTextStyles.bodySmall),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ScroleBottomSheetGroup(
              children: [
                ScroleBottomSheetAction(
                  icon: Icons.person_remove_outlined,
                  label: 'Retirer du staff',
                  color: AppColors.error,
                  onTap: () {
                    Get.back();
                    controller.removeStaff(member.userId);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    String statusText = 'Membre du staff';
    Color statusColor = AppColors.success;
    if (member.status == StaffStatus.pending) {
      statusText = 'Invitation en attente';
      statusColor = AppColors.secondary;
    } else if (member.status == StaffStatus.rejected) {
      statusText = 'Invitation refusée';
      statusColor = colors.error;
    }

    final usernameText = member.username != null && member.username!.isNotEmpty ? '@${member.username}' : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Get.to(() => StaffStatsScreen(staffMember: member)),
        onLongPress: () => _showStaffOptionsMenu(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipOval(
                child: member.avatarUrl != null && member.avatarUrl!.isNotEmpty
                    ? AppCachedImage(imageUrl: member.avatarUrl!, width: 44, height: 44, fit: BoxFit.cover)
                    : Container(
                        width: 44,
                        height: 44,
                        color: AppColors.primary.withValues(alpha: 0.12),
                        child: const Icon(Icons.person, color: AppColors.primary, size: 24),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(member.name, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold, fontSize: 15)),
                    if (usernameText != null) ...[
                      const SizedBox(height: 1),
                      Text(usernameText, style: AppTextStyles.caption.copyWith(color: colors.onSurfaceVariant)),
                    ],
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        statusText,
                        style: AppTextStyles.caption.copyWith(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ),
                    if (member.assignedActivityNames.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Activités : ${member.assignedActivityNames.join(' · ')}',
                        style: AppTextStyles.caption.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),

              // Bouton '+' ou d'options (§30)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    if (member.status == StaffStatus.accepted) {
                      _showStaffOptionsMenu(context);
                    } else {
                      _showRemoveStaffSheet(context);
                    }
                  },
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHigh,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      member.status == StaffStatus.accepted ? Icons.more_vert_rounded : Icons.more_vert_rounded,
                      size: 22,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
