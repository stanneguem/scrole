import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../controllers/sponsor_invitation_controller.dart';

class InviteSponsorCandidateScreen extends StatelessWidget {
  final SponsorInvitationController controller;

  const InviteSponsorCandidateScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Inviter un Sponsor',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          // Barre de recherche
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              onChanged: (v) => controller.searchQuery.value = v,
              decoration: InputDecoration(
                hintText: 'Rechercher un profil public...',
                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primary),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                filled: true,
                fillColor: colors.surfaceContainerLow,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                ),
              ),
            ),
          ),

          Expanded(
            child: Obx(() {
              if (controller.isLoadingCandidates.value) {
                return const Center(child: CircularProgressIndicator());
              }

              final candidates = controller.filteredCandidates;

              if (candidates.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.person_search_outlined, size: 56, color: AppColors.disabled),
                        const SizedBox(height: 16),
                        Text('Aucun candidat sponsor éligible trouvé', style: AppTextStyles.h4, textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        Text(
                          'Les profils affichés sont publics et non encore enregistrés comme sponsors.',
                          style: AppTextStyles.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: candidates.length,
                itemBuilder: (context, index) {
                  final candidate = candidates[index];

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: candidate.avatarUrl != null && candidate.avatarUrl!.isNotEmpty
                            ? AppCachedImage(imageUrl: candidate.avatarUrl!, width: 48, height: 48, fit: BoxFit.cover)
                            : Container(
                                width: 48,
                                height: 48,
                                color: AppColors.primary.withValues(alpha: 0.12),
                                child: const Icon(Icons.workspace_premium_rounded, color: AppColors.primary),
                              ),
                      ),
                      title: Text(candidate.name, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
                      subtitle: candidate.username.isNotEmpty
                          ? Text('@${candidate.username}', style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary))
                          : null,
                      trailing: ElevatedButton.icon(
                        onPressed: () => _confirmInvite(context, candidate.name, candidate.id),
                        icon: const Icon(Icons.send_rounded, size: 16, color: Colors.white),
                        label: const Text('Inviter', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
  }

  void _confirmInvite(BuildContext context, String name, String userId) {
    Get.dialog(
      AlertDialog(
        title: Text('Inviter $name ?'),
        content: Text(
          'Envoyer une invitation sponsor à $name pour cet événement ? En acceptant, l\'événement sera associé à son profil sponsor.',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              Get.back();
              controller.inviteSponsor(userId);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Envoyer l\'invitation', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
