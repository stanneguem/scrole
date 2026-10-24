import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/widgets/scrole_bottom_sheet.dart';
import '../controllers/event_activity_controller.dart';
import '../../centre/models/activity_model.dart';
import 'activity_staff_management_screen.dart';
import 'activity_update_price_screen.dart';
import 'activity_event_stats_screen.dart';

class ActivityEventManagementScreen extends StatefulWidget {
  final EventActivityModel eventActivity;

  const ActivityEventManagementScreen({
    super.key,
    required this.eventActivity,
  });

  @override
  State<ActivityEventManagementScreen> createState() => _ActivityEventManagementScreenState();
}

class _ActivityEventManagementScreenState extends State<ActivityEventManagementScreen> {
  late EventActivityModel _activity;

  @override
  void initState() {
    super.initState();
    _activity = widget.eventActivity;
  }

  void _showRemoveBottomSheet(EventActivityController controller) {
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
                  Text('Retirer cette activité ?', style: AppTextStyles.h4),
                  const SizedBox(height: 4),
                  Text(
                    'L\'activité "${_activity.name}" sera retirée de cet événement.',
                    style: AppTextStyles.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ScroleBottomSheetGroup(
              children: [
                ScroleBottomSheetAction(
                  icon: Icons.delete_forever_rounded,
                  label: 'Retirer de l\'événement',
                  subtitle: 'Confirmer le retrait de "${_activity.name}"',
                  color: AppColors.error,
                  onTap: () {
                    Get.back(); // Ferme le Modal Bottom Sheet
                    controller.removeActivity(_activity);
                    Get.back(); // Retourne à l'écran "Gérer les activités"
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
    final controller = Get.find<EventActivityController>();
    final colors = Theme.of(context).colorScheme;

    final creatorDisplay = _activity.creatorFullName ?? (_activity.creatorUsername != null ? '@${_activity.creatorUsername}' : null);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _activity.name,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Carte En-tête de l'activité dans cet événement
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
                      child: const Icon(Icons.local_activity_rounded, color: AppColors.primary, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_activity.name, style: AppTextStyles.h4),
                          const SizedBox(height: 4),
                          if (_activity.basePrice != null) ...[
                            Text(
                              'Prix global de l\'activité : ${_activity.basePrice!.toStringAsFixed(_activity.basePrice! % 1 == 0 ? 0 : 2)} ${_activity.currency}',
                              style: AppTextStyles.caption.copyWith(color: colors.onSurfaceVariant),
                            ),
                            const SizedBox(height: 2),
                          ],
                          Text(
                            'Prix pour cet événement',
                            style: AppTextStyles.caption.copyWith(color: colors.onSurfaceVariant, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            _activity.formattedEventPrice,
                            style: AppTextStyles.h4.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_activity.description != null && _activity.description!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('Description', style: AppTextStyles.labelSmall),
                  const SizedBox(height: 4),
                  Text(_activity.description!, style: AppTextStyles.body),
                ],
                if (creatorDisplay != null) ...[
                  const SizedBox(height: 12),
                  Text('Créateur : $creatorDisplay', style: AppTextStyles.caption.copyWith(color: colors.onSurfaceVariant)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),

          Text(
            'GESTION DE L\'ACTIVITÉ',
            style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary, letterSpacing: 1.2),
          ),
          const SizedBox(height: 8),

          // Menu d'options (Pages dédiées + Modal Bottom Sheet pour "Retirer")
          ScroleBottomSheetGroup(
            children: [
              ScroleBottomSheetAction(
                icon: Icons.people_outline_rounded,
                label: 'Assigner du staff',
                subtitle: 'Attribuer un ou plusieurs membres du staff à cette activité.',
                onTap: () => Get.to(() => ActivityStaffManagementScreen(eventActivity: _activity)),
              ),
              const ScroleBottomSheetDivider(),
              ScroleBottomSheetAction(
                icon: Icons.edit_outlined,
                label: 'Modifier le prix',
                subtitle: 'Modifier le prix appliqué à cette activité dans cet événement.',
                onTap: () => Get.to(() => ActivityUpdatePriceScreen(eventActivity: _activity)),
              ),
              const ScroleBottomSheetDivider(),
              ScroleBottomSheetAction(
                icon: Icons.bar_chart_rounded,
                label: 'Statistiques',
                subtitle: 'Consulter les statistiques de cette activité dans cet événement.',
                onTap: () => Get.to(() => ActivityEventStatsScreen(eventActivity: _activity)),
              ),
              const ScroleBottomSheetDivider(),
              ScroleBottomSheetAction(
                icon: Icons.delete_outline_rounded,
                label: 'Retirer de l\'événement',
                subtitle: 'Retirer cette activité de cet événement.',
                color: colors.error,
                onTap: () => _showRemoveBottomSheet(controller),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
