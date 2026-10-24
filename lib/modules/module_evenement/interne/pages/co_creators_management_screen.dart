import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../controllers/staff_controller.dart';
import '../../centre/models/co_creator_model.dart';
import 'add_staff_screen.dart';

class CoCreatorsManagementScreen extends GetView<StaffController> {
  const CoCreatorsManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Gestion des Co-fondateurs',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        ),
      ),
      body: Obx(() {
        final isFounder = controller.isCurrentUserFounder;

        if (controller.isLoadingCoCreators.value) {
          return const Center(child: CircularProgressIndicator());
        }

        if (controller.coCreators.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.stars_outlined, size: 64, color: AppColors.textSecondary),
                const SizedBox(height: 16),
                Text('Aucun co-fondateur invité', style: AppTextStyles.body),
                if (isFounder) ...[
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => Get.to(() => const AddStaffScreen(isCoCreator: true)),
                    icon: const Icon(Icons.group_add_rounded),
                    label: const Text('Ajouter un co-fondateur'),
                  ),
                ],
              ],
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (controller.acceptedCoCreators.isNotEmpty) ...[
              _buildSectionTitle('CO-FONDATEURS ACCEPTÉS'),
              ...controller.acceptedCoCreators.map((c) => _CoCreatorTile(coCreator: c, controller: controller)),
            ],
            if (controller.pendingCoCreators.isNotEmpty) ...[
              const SizedBox(height: 20),
              _buildSectionTitle('INVITATIONS EN ATTENTE'),
              ...controller.pendingCoCreators.map((c) => _CoCreatorTile(coCreator: c, controller: controller)),
            ],
            if (isFounder) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => Get.to(() => const AddStaffScreen(isCoCreator: true)),
                icon: const Icon(Icons.group_add_rounded),
                label: const Text('Ajouter un co-fondateur'),
              ),
            ],
          ],
        );
      }),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        title,
        style: AppTextStyles.labelSmall.copyWith(letterSpacing: 1.2),
      ),
    );
  }
}

class _CoCreatorTile extends StatelessWidget {
  final CoCreatorModel coCreator;
  final StaffController controller;
  const _CoCreatorTile({required this.coCreator, required this.controller});

  void _showRevokeDialog(BuildContext context, bool isAccepted) {
    Get.dialog(
      AlertDialog(
        title: Text(isAccepted ? 'Révoquer le rôle ?' : 'Annuler l\'invitation ?'),
        content: Text(
          isAccepted
              ? 'Voulez-vous vraiment révoquer le rôle de co-fondateur de ${coCreator.name} ?'
              : 'Voulez-vous vraiment annuler l\'invitation envoyée à ${coCreator.name} ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () {
              Get.back();
              controller.removeCoCreator(coCreator.userId);
            },
            child: Text(
              isAccepted ? 'Révoquer' : 'Annuler la demande',
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  void _showLeaveDialog(BuildContext context) {
    Get.dialog(
      AlertDialog(
        title: const Text('Quitter le rôle ?'),
        content: const Text(
          'Voulez-vous vraiment quitter votre rôle de co-fondateur pour cet événement ? Vous n\'aurez plus accès aux fonctionnalités de gestion.',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () {
              Get.back();
              controller.leaveCoCreatorRole();
            },
            child: const Text(
              'Quitter',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAccepted = coCreator.status == CoCreatorStatus.accepted;
    final currentUserId = controller.currentUserId;
    final founderId = controller.eventCreatorId.value;

    final isFounder = controller.isCurrentUserFounder;
    final isCoFounder = controller.isCurrentUserCoFounder;

    final isTargetSelf = coCreator.userId == currentUserId;
    final isTargetFounder = coCreator.userId == founderId;

    Widget? trailingWidget;

    if (isFounder) {
      // 1. Le fondateur voit les autres co-fondateurs
      if (!isTargetFounder) {
        trailingWidget = TextButton(
          onPressed: () => _showRevokeDialog(context, isAccepted),
          child: Text(
            isAccepted ? 'Révoquer le rôle' : 'Annuler la demande',
            style: const TextStyle(color: AppColors.error, fontSize: 12),
          ),
        );
      }
    } else if (isCoFounder) {
      // 2. Un co-fondateur se voit lui-même
      if (isTargetSelf) {
        trailingWidget = TextButton(
          onPressed: () => _showLeaveDialog(context),
          child: const Text(
            'Quitter le rôle',
            style: TextStyle(color: AppColors.error, fontSize: 12),
          ),
        );
      }
      // Pour les autres co-fondateurs ou le fondateur : trailingWidget reste null (AUCUNE ACTION)
    }
    // 3. Tout autre membre : trailingWidget reste null (AUCUNE ACTION)

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.amber.withValues(alpha: 0.15),
          backgroundImage: coCreator.avatarUrl != null ? NetworkImage(coCreator.avatarUrl!) : null,
          child: coCreator.avatarUrl == null ? Icon(Icons.star_rounded, color: Colors.amber[800]) : null,
        ),
        title: Text(coCreator.name, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
        subtitle: Text(
          isAccepted ? 'Co-fondateur accepté' : 'Invitation en attente',
          style: AppTextStyles.bodySmall.copyWith(
            color: isAccepted ? Colors.green : Colors.orange,
          ),
        ),
        trailing: trailingWidget,
      ),
    );
  }
}
