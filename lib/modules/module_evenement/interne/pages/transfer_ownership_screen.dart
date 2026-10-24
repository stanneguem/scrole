import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../../../../shared/widgets/scrole_bottom_sheet.dart';
import '../controllers/transfer_ownership_controller.dart';
import '../../centre/models/co_creator_model.dart';
import '../../centre/models/event_transfer_model.dart';

class TransferOwnershipScreen extends GetView<TransferOwnershipController> {
  const TransferOwnershipScreen({super.key});

  void _showConfirmSendProposalSheet(BuildContext context, CoCreatorModel candidate) {
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
                  Text('Envoyer la proposition ?', style: AppTextStyles.h4),
                  const SizedBox(height: 8),
                  Text(
                    'Vous proposez à ${candidate.name} de devenir le nouveau propriétaire de cet événement.\n\nS\'il accepte, il deviendra le fondateur de l\'événement et vous deviendrez co-fondateur.\n\nVous pourrez annuler cette proposition tant qu\'elle n\'aura pas été acceptée.',
                    style: AppTextStyles.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ScroleBottomSheetGroup(
              children: [
                ScroleBottomSheetAction(
                  icon: Icons.send_rounded,
                  label: 'Envoyer la proposition',
                  color: AppColors.primary,
                  onTap: () {
                    Get.back();
                    controller.proposeTransfer(candidate.userId, candidate.name);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showConfirmCancelProposalSheet(BuildContext context, EventTransferModel transfer, String candidateName) {
    ScroleBottomSheet.show(
      context: context,
      showCancel: true,
      cancelLabel: 'Conserver la proposition',
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
                  Text('Annuler la proposition ?', style: AppTextStyles.h4),
                  const SizedBox(height: 8),
                  Text(
                    'Cette proposition de transfert envoyée à $candidateName sera annulée. Le co-fondateur pourra recevoir une nouvelle proposition plus tard.',
                    style: AppTextStyles.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ScroleBottomSheetGroup(
              children: [
                ScroleBottomSheetAction(
                  icon: Icons.cancel_outlined,
                  label: 'Annuler la proposition',
                  color: AppColors.error,
                  onTap: () {
                    Get.back();
                    controller.cancelTransfer(transfer.id, transfer.proposedTo);
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

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Transfert de propriété',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // En-tête explicatif
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.swap_horiz_rounded, color: AppColors.primary, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Transférer la propriété', style: AppTextStyles.h4),
                          const SizedBox(height: 2),
                          Text('Proposer la gestion globale à un co-fondateur', style: AppTextStyles.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Sélectionnez un co-fondateur à qui vous souhaitez proposer le transfert de propriété de cet événement.\n\nVous pouvez envoyer la proposition à plusieurs co-fondateurs. Le premier à l\'accepter devient le nouveau fondateur. Les autres propositions en attente seront alors automatiquement annulées.',
                  style: AppTextStyles.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Avertissement rôle actuel
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.secondary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.secondary.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: AppColors.secondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Lorsqu\'un co-fondateur acceptera le transfert, vous ne serez plus le fondateur. Vous deviendrez co-fondateur.',
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.secondary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Text(
            'CO-FONDATEURS ÉLIGIBLES',
            style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary, letterSpacing: 1.2),
          ),
          const SizedBox(height: 12),

          // Liste des co-fondateurs éligibles
          Obx(() {
            if (controller.isLoadingCoCreators.value && controller.acceptedCoCreators.isEmpty) {
              return const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 32), child: CircularProgressIndicator()));
            }

            if (controller.acceptedCoCreators.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.people_outline_rounded, size: 48, color: AppColors.disabled),
                    const SizedBox(height: 16),
                    Text('Aucun co-fondateur éligible', style: AppTextStyles.h4, textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text(
                      'Le transfert de propriété est possible uniquement vers un co-fondateur confirmé de cet événement. Invitez d\'abord des co-fondateurs.',
                      style: AppTextStyles.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }

            return Column(
              children: controller.acceptedCoCreators.map((candidate) {
                final pendingProposal = controller.getActiveProposalForUser(candidate.userId);
                final latestProposal = controller.getLatestProposalForUser(candidate.userId);
                final isProcessing = controller.processingCandidateIds[candidate.userId] == true;

                final usernameText = candidate.username != null && candidate.username!.isNotEmpty ? '@${candidate.username}' : null;

                Widget statusActionWidget;

                if (pendingProposal != null) {
                  statusActionWidget = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.secondary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('En attente', style: TextStyle(color: AppColors.secondary, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: isProcessing ? null : () => _showConfirmCancelProposalSheet(context, pendingProposal, candidate.name),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colors.error,
                          side: BorderSide(color: colors.error.withValues(alpha: 0.5)),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: isProcessing
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Annuler', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  );
                } else if (latestProposal?.status == TransferStatus.rejected) {
                  statusActionWidget = Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: colors.error.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('Proposition refusée', style: TextStyle(color: colors.error, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 4),
                      ElevatedButton(
                        onPressed: isProcessing ? null : () => _showConfirmSendProposalSheet(context, candidate),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: isProcessing
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Proposer à nouveau', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ],
                  );
                } else {
                  statusActionWidget = ElevatedButton(
                    onPressed: isProcessing ? null : () => _showConfirmSendProposalSheet(context, candidate),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    child: isProcessing
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Proposer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  );
                }

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.3)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        ClipOval(
                          child: candidate.avatarUrl != null && candidate.avatarUrl!.isNotEmpty
                              ? AppCachedImage(imageUrl: candidate.avatarUrl!, width: 44, height: 44, fit: BoxFit.cover)
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
                              Text(candidate.name, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold, fontSize: 15)),
                              if (usernameText != null) ...[
                                const SizedBox(height: 1),
                                Text(usernameText, style: AppTextStyles.caption.copyWith(color: colors.onSurfaceVariant)),
                              ],
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text('Co-fondateur', style: AppTextStyles.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 11)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        statusActionWidget,
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          }),
        ],
      ),
    );
  }
}
