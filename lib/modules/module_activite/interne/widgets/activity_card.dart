import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:scrole/app/theme/app_colors.dart';
import 'package:scrole/app/theme/text_styles.dart';
import 'package:scrole/shared/widgets/scrole_bottom_sheet.dart';
import '../../centre/models/activity_model.dart';

class ActivityCard extends StatelessWidget {
  final Activity activity;
  final bool isJoined;
  final bool isEventAdded;
  final VoidCallback onJoin;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final List<String> avatarUrls;

  const ActivityCard({
    super.key,
    required this.activity,
    required this.isJoined,
    required this.isEventAdded,
    required this.onJoin,
    this.onEdit,
    this.onDelete,
    this.avatarUrls = const [],
  });

  void _showOptionsModal(BuildContext context) {
    ScroleBottomSheet.show(
      context: context,
      showCancel: true,
      cancelLabel: 'cancel'.tr,
      child: ScroleBottomSheetGroup(
        children: [
          if (onEdit != null)
            ScroleBottomSheetAction(
              icon: Icons.edit_outlined,
              label: 'Modifier l\'activité',
              subtitle: 'Ajuster le nom, le tarif ou la devise',
              color: Theme.of(context).colorScheme.primary,
              onTap: () {
                Get.back();
                onEdit!();
              },
            ),
          if (onEdit != null && onDelete != null && !activity.isPendingDeletion)
            const ScroleBottomSheetDivider(),
          if (onDelete != null && !activity.isPendingDeletion)
            ScroleBottomSheetAction(
              icon: Icons.delete_outline_rounded,
              label: 'Supprimer l\'activité',
              subtitle: 'Retirer cette activité de votre liste',
              color: AppColors.error,
              onTap: () {
                Get.back();
                onDelete!();
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLocked = !isEventAdded;
    final colorScheme = Theme.of(context).colorScheme;

    return Opacity(
      opacity: isLocked ? 0.55 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isJoined
                ? AppColors.primary.withValues(alpha: 0.3)
                : colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Icône Badge + Nom + Statut + Options
            Row(
              children: [
                // Icône d'activité dans un carré arrondi teinté
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.local_activity_rounded,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),

                // Nom de l'activité + Statut
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        activity.name,
                        style: AppTextStyles.h4.copyWith(
                          fontSize: 15.5,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      _buildStatusBadge(activity.status, colorScheme),
                    ],
                  ),
                ),

                // Bouton Option ... (Modal Bottom Sheet)
                if (onEdit != null || (onDelete != null && !activity.isPendingDeletion))
                  IconButton(
                    icon: Icon(
                      Icons.more_vert_rounded,
                      size: 20,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    onPressed: () => _showOptionsModal(context),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Row 2: Prix + Utilisation aux événements + Date
            Row(
              children: [
                // Prix avec la devise
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    activity.formattedPrice,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Nombre d'utilisations dans les événements
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${activity.addedCount} ajout${activity.addedCount > 1 ? 's' : ''}',
                    style: AppTextStyles.caption.copyWith(
                      color: const Color(0xFF3B82F6),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const Spacer(),

                // Date de création formatée
                Text(
                  _formatDisplayDate(activity.createdAt),
                  style: AppTextStyles.caption.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),

            // Bandeau de suppression programmée à J+30
            if (activity.isPendingDeletion && activity.scheduledDeletionAt != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Suppression programmée le ${activity.scheduledDeletionAt!.day}/${activity.scheduledDeletionAt!.month}/${activity.scheduledDeletionAt!.year}',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.error,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDisplayDate(DateTime dateTime) {
    final local = dateTime.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateDate = DateTime(local.year, local.month, local.day);
    final diffDays = today.difference(dateDate).inDays;

    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');

    if (diffDays == 0) {
      return 'Aujourd\'hui $hh:$mm';
    } else if (diffDays == 1) {
      return 'Hier $hh:$mm';
    } else if (diffDays > 1 && diffDays < 7) {
      return '$diffDays j';
    } else {
      final months = [
        'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
        'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'
      ];
      return '${local.day} ${months[local.month - 1]}';
    }
  }

  Widget _buildStatusBadge(String status, ColorScheme colorScheme) {
    String label;
    Color color;

    switch (status) {
      case 'active':
        label = 'Active';
        color = AppColors.success;
        break;
      case 'en_attente':
        label = 'En attente de validation';
        color = Colors.amber[800]!;
        break;
      case 'rejected':
        label = 'Rejetée';
        color = AppColors.error;
        break;
      case 'pending_deletion':
        label = 'Suppression programmée';
        color = Colors.orange;
        break;
      default:
        label = status;
        color = colorScheme.onSurfaceVariant;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
