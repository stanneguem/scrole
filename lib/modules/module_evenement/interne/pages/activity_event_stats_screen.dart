import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../controllers/event_activity_controller.dart';
import '../../centre/models/activity_model.dart';

class ActivityEventStatsScreen extends StatefulWidget {
  final EventActivityModel eventActivity;

  const ActivityEventStatsScreen({
    super.key,
    required this.eventActivity,
  });

  @override
  State<ActivityEventStatsScreen> createState() => _ActivityEventStatsScreenState();
}

class _ActivityEventStatsScreenState extends State<ActivityEventStatsScreen> {
  late EventActivityModel _activity;

  @override
  void initState() {
    super.initState();
    _activity = widget.eventActivity;
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<EventActivityController>();
    final colors = Theme.of(context).colorScheme;

    final originalPrice = _activity.basePrice ?? _activity.price;
    final currentEventPrice = _activity.price;

    double diffPercent = 0.0;
    if (originalPrice > 0) {
      diffPercent = ((currentEventPrice - originalPrice) / originalPrice) * 100;
    }

    final isReduction = diffPercent < -0.01;
    final isAugmentation = diffPercent > 0.01;

    String variationText = 'Prix inchangé';
    Color variationColor = colors.onSurfaceVariant;
    if (isReduction) {
      variationText = 'Réduction de ${diffPercent.abs().toStringAsFixed(0)} %';
      variationColor = AppColors.success;
    } else if (isAugmentation) {
      variationText = 'Augmentation de ${diffPercent.toStringAsFixed(0)} %';
      variationColor = AppColors.secondary;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Statistiques de l\'activité',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // En-tête Activité
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.bar_chart_rounded, color: AppColors.primary, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_activity.name, style: AppTextStyles.h4),
                      const SizedBox(height: 2),
                      Text(
                        'Statistiques dans cet événement',
                        style: AppTextStyles.caption.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Bloc Prix & Variation (§3)
          Text('CONFIGURATION FINANCIÈRE', style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary, letterSpacing: 1.2)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Prix original', style: AppTextStyles.bodySmall),
                    Text('${originalPrice.toStringAsFixed(originalPrice % 1 == 0 ? 0 : 2)} ${_activity.currency}', style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Prix dans cet événement', style: AppTextStyles.bodySmall),
                    Text(_activity.formattedEventPrice, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold, color: AppColors.primary)),
                  ],
                ),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Variation appliquée', style: AppTextStyles.bodySmall),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: variationColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        variationText,
                        style: AppTextStyles.caption.copyWith(color: variationColor, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Bloc Statistiques
          Text('ACTIVITÉ DU STAFF & SCANS', style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary, letterSpacing: 1.2)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Membres du staff assignés', style: AppTextStyles.bodySmall),
                    Text('${_activity.assignedStaffIds.length}', style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Scans effectués', style: AppTextStyles.bodySmall),
                    Text('0 scan', style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold, color: AppColors.primary)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // État vide
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.2)),
            ),
            child: Column(
              children: [
                const Icon(Icons.analytics_outlined, size: 40, color: AppColors.disabled),
                const SizedBox(height: 12),
                Text('Aucune statistique de scan enregistrée', style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                const SizedBox(height: 4),
                Text(
                  'Les statistiques de scans concernant cette activité dans cet événement apparaîtront ici dès les premiers contrôles d\'accès.',
                  style: AppTextStyles.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
