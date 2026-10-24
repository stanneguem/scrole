import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:scrole/app/routes/app_pages.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../app/utils/supabase_error_mapper.dart';
import '../../centre/models/activity_model.dart';
import '../../centre/services/activity_service.dart';

class ActivityDeleteScreen extends StatefulWidget {
  final Activity activity;

  const ActivityDeleteScreen({super.key, required this.activity});

  @override
  State<ActivityDeleteScreen> createState() => _ActivityDeleteScreenState();
}

class _ActivityDeleteScreenState extends State<ActivityDeleteScreen> {
  final ActivityService _activityService = Get.find<ActivityService>();
  bool _isProcessing = false;

  Future<void> _requestDeletion() async {
    setState(() => _isProcessing = true);
    try {
      await _activityService.requestDeletion(widget.activity.id);
      Get.until((route) => route.isFirst || Get.currentRoute == AppPages.myActivities);
      Get.snackbar('Suppression', 'La demande de suppression de l\'activité a été transmise.');
    } catch (e) {
      if (Get.context != null) showAppErrorDialog(Get.context!, e);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          'Supprimer mon activité',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Get.back(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Processus de suppression :',
                        style: AppTextStyles.h4.copyWith(color: AppColors.error, fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              Text(
                '• Si l\'activité n\'est utilisée par aucun événement et n\'est dans les favoris de personne, elle sera supprimée immédiatement.\n\n'
                '• Si l\'activité est déjà liée à un événement ou ajoutée en favori, elle passera en statut "En attente de suppression" pendant une période de rétention de 30 jours (J+30) avant sa purge définitive.',
                style: AppTextStyles.body,
              ),

              const Spacer(),

              if (widget.activity.isPendingDeletion) ...[
                ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _cancelDeletion,
                  icon: const Icon(Icons.restore_from_trash_rounded, color: Colors.white),
                  label: Text(
                    _isProcessing ? 'Traitement...' : 'Annuler la demande de suppression',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    backgroundColor: Colors.amber[800],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
                const SizedBox(height: 12),
              ] else ...[
                ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _requestDeletion,
                  icon: const Icon(Icons.delete_forever_rounded, color: Colors.white),
                  label: Text(
                    _isProcessing ? 'Traitement...' : 'Confirmer la suppression',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    backgroundColor: AppColors.error,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _cancelDeletion() async {
    setState(() => _isProcessing = true);
    try {
      await _activityService.cancelDeletion(widget.activity.id);
      Get.until((route) => route.isFirst || Get.currentRoute == AppPages.myActivities);
      Get.snackbar('Annulation', 'La demande de suppression de l\'activité a été annulée.');
    } catch (e) {
      if (mounted) showAppErrorDialog(context, e);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }
}
