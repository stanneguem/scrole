import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../../../../shared/widgets/scrole_bottom_sheet.dart';
import '../../centre/models/staff_model.dart';
import '../controllers/staff_controller.dart';

class AddStaffScreen extends GetView<StaffController> {
  final bool isCoCreator;

  const AddStaffScreen({super.key, this.isCoCreator = false});

  void _showActivitySelection(BuildContext context, String friendId) {
    final activities = controller.eventActivities;
    final selectedActivityIds = <String>{}.obs;

    ScroleBottomSheet.show(
      context: context,
      showCancel: true,
      cancelLabel: 'Annuler',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Assigner des activités au staff', style: AppTextStyles.h4),
                  const SizedBox(height: 4),
                  Text(
                    'Sélectionnez au moins une activité que ce membre du staff sera habilité à scanner / valider.',
                    style: AppTextStyles.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Obx(() {
              if (activities.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Aucune activité rattachée à cet événement. L\'invitation sera envoyée sans restriction.',
                    style: AppTextStyles.bodySmall,
                  ),
                );
              }
              return ScroleBottomSheetGroup(
                children: activities.map((a) {
                  final isSelected = selectedActivityIds.contains(a.id);
                  return CheckboxListTile(
                    title: Text(a.name, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
                    value: isSelected,
                    activeColor: AppColors.primary,
                    onChanged: (val) {
                      if (val == true) {
                        selectedActivityIds.add(a.id);
                      } else {
                        selectedActivityIds.remove(a.id);
                      }
                    },
                  );
                }).toList(),
              );
            }),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Get.back();
                controller.inviteStaff(friendId, activityIds: selectedActivityIds.toList());
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Envoyer l\'invitation', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isCoCreator ? 'Ajouter un co-fondateur' : 'Inviter un membre du staff',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        ),
      ),
      body: Obx(() {
        if (isCoCreator) {
          final staffCandidates = controller.staffMembers
              .where((m) => m.status == StaffStatus.accepted)
              .toList();

          if (staffCandidates.isEmpty) {
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
                      child: const Icon(Icons.people_outline_rounded, size: 48, color: AppColors.primary),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Aucun membre du staff éligible',
                      style: AppTextStyles.h4,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Un co-fondateur doit obligatoirement être un membre confirmé du staff. Invitez d\'abord des membres au staff de cet événement.',
                      style: AppTextStyles.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: staffCandidates.length,
            itemBuilder: (context, index) {
              final member = staffCandidates[index];
              final isAlreadyCoCreator = controller.coCreators.any((c) => c.userId == member.userId);

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.3)),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundImage: member.avatarUrl != null && member.avatarUrl!.isNotEmpty ? NetworkImage(member.avatarUrl!) : null,
                    child: member.avatarUrl == null ? const Icon(Icons.person) : null,
                  ),
                  title: Text(member.name, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Membre du staff confirmé', style: TextStyle(color: Colors.green, fontSize: 12)),
                  trailing: isAlreadyCoCreator
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text('Co-fondateur', style: TextStyle(color: AppColors.success, fontSize: 11, fontWeight: FontWeight.bold)),
                        )
                      : ElevatedButton(
                          onPressed: () => controller.inviteCoCreator(member.userId),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                          child: const Text('Proposer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                ),
              );
            },
          );
        }

        // Cas Inviter un membre du staff (depuis ses contacts/amis)
        if (controller.isLoadingFriends.value && controller.friends.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (controller.friends.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.person_search_outlined, size: 52, color: AppColors.disabled),
                  const SizedBox(height: 16),
                  Text('Aucun ami trouvé', style: AppTextStyles.h4, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(
                    'Vous devez ajouter des contacts dans votre réseau Scrole pour pouvoir les inviter dans votre staff.',
                    style: AppTextStyles.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: controller.friends.length,
          itemBuilder: (context, index) {
            final friend = controller.friends[index];
            final isCoCreator = controller.coCreators.any((c) => c.userId == friend.id);
            final existingStaffMember = controller.staffMembers.firstWhereOrNull((m) => m.userId == friend.id);

            Widget actionWidget;
            if (isCoCreator) {
              actionWidget = Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('Co-fondateur', style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold)),
              );
            } else if (existingStaffMember != null) {
              if (existingStaffMember.status == StaffStatus.accepted) {
                actionWidget = Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('Membre du staff', style: TextStyle(color: AppColors.success, fontSize: 11, fontWeight: FontWeight.bold)),
                );
              } else if (existingStaffMember.status == StaffStatus.pending) {
                actionWidget = Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('Invitation en attente', style: TextStyle(color: AppColors.secondary, fontSize: 11, fontWeight: FontWeight.bold)),
                );
              } else {
                actionWidget = Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: colors.error.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('Invitation refusée', style: TextStyle(color: colors.error, fontSize: 11, fontWeight: FontWeight.bold)),
                );
              }
            } else {
              actionWidget = ElevatedButton.icon(
                onPressed: () => _showActivitySelection(context, friend.id),
                icon: const Icon(Icons.person_add_rounded, size: 16, color: Colors.white),
                label: const Text('Inviter', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
              );
            }

            final usernameText = friend.username.isNotEmpty ? '@${friend.username}' : null;

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.3)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    ClipOval(
                      child: friend.avatarUrl != null && friend.avatarUrl!.isNotEmpty
                          ? AppCachedImage(imageUrl: friend.avatarUrl!, width: 44, height: 44, fit: BoxFit.cover)
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
                          Text(friend.name, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold, fontSize: 15)),
                          if (usernameText != null) ...[
                            const SizedBox(height: 1),
                            Text(usernameText, style: AppTextStyles.caption.copyWith(color: colors.onSurfaceVariant)),
                          ],
                        ],
                      ),
                    ),
                    actionWidget,
                  ],
                ),
              ),
            );
          },
        );
      }),
    );
  }
}
