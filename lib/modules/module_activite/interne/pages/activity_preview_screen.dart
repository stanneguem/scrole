import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../app/utils/supabase_error_mapper.dart';
import '../../../../shared/widgets/scrole_bottom_sheet.dart';
import '../../centre/models/activity_model.dart';
import '../../centre/services/activity_service.dart';
import '../../externe/repositories/activity_repository.dart';
import 'activity_management_menu_screen.dart';
import 'edit_activity_screen.dart';

class ActivityPreviewScreen extends StatefulWidget {
  final Activity activity;
  final bool isOwner;
  final bool isManager;

  const ActivityPreviewScreen({
    super.key,
    required this.activity,
    this.isOwner = false,
    this.isManager = false,
  });

  @override
  State<ActivityPreviewScreen> createState() => _ActivityPreviewScreenState();
}

class _ActivityPreviewScreenState extends State<ActivityPreviewScreen> {
  final ActivityRepository _repository = ActivityRepository();
  final ActivityService _activityService = Get.find<ActivityService>();

  late Activity _currentActivity;
  Map<String, dynamic>? _stats;

  @override
  void initState() {
    super.initState();
    _currentActivity = widget.activity;
    if (widget.isOwner || widget.isManager) {
      _loadStats();
    }
  }

  Future<void> _loadStats() async {
    try {
      final res = await _repository.getActivityStatsRpc(_currentActivity.id);
      if (mounted) setState(() => _stats = res);
    } catch (e) {
      debugPrint('[ActivityPreviewScreen] Stats load error: $e');
    }
  }

  void _confirmLeaveStaff() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitter le staff ?'),
        content: const Text('Voulez-vous vraiment quitter la gestion de cette activité ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await _repository.leaveActivityStaffRpc(_currentActivity.id);
                Get.back();
                Get.snackbar('Staff', 'Vous avez quitté la gestion de cette activité.');
                _activityService.catchupSync();
              } catch (e) {
                if (Get.context != null) showAppErrorDialog(Get.context!, e);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Quitter'),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelDeletion() async {
    try {
      await _activityService.cancelDeletion(_currentActivity.id);
      Get.snackbar('Annulation', 'La demande de suppression de l\'activité a été annulée.');
      final fresh = await _repository.fetchActivityById(_currentActivity.id);
      if (fresh != null && mounted) {
        setState(() => _currentActivity = fresh);
      }
    } catch (e) {
      if (Get.context != null) showAppErrorDialog(Get.context!, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Aperçu de l\'activité'),
        titleTextStyle: AppTextStyles.h5.copyWith(color: colorScheme.onSurface),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Get.back(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Badge icône + Nom + Statut
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.local_activity_rounded, color: AppColors.primary, size: 30),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _currentActivity.name,
                          style: GoogleFonts.spaceGrotesk(fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        _buildStatusChip(_currentActivity.status),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Tarif
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TARIF DE BASE', style: AppTextStyles.labelSmall.copyWith(letterSpacing: 1.2)),
                    const SizedBox(height: 6),
                    Text(
                      _currentActivity.formattedPrice,
                      style: GoogleFonts.spaceGrotesk(fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.primary),
                    ),
                  ],
                ),
              ),

              if (_currentActivity.description.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('DESCRIPTION', style: AppTextStyles.labelSmall.copyWith(letterSpacing: 1.2)),
                const SizedBox(height: 8),
                Text(_currentActivity.description, style: AppTextStyles.body),
              ],

              // Bandeau de suppression programmée
              if (_currentActivity.isPendingDeletion && _currentActivity.scheduledDeletionAt != null) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: AppColors.error),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Suppression définitive programmée le ${_currentActivity.scheduledDeletionAt!.day}/${_currentActivity.scheduledDeletionAt!.month}/${_currentActivity.scheduledDeletionAt!.year}',
                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.error, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 40),

              // Boutons d'action selon rôle (§4)
              if (_currentActivity.isPendingDeletion && widget.isOwner) ...[
                ElevatedButton.icon(
                  onPressed: _cancelDeletion,
                  icon: const Icon(Icons.restore_from_trash_rounded, color: Colors.white),
                  label: const Text('Annuler la suppression', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    backgroundColor: Colors.amber[800],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              if (widget.isOwner) ...[
                ElevatedButton.icon(
                  onPressed: () async {
                    await Get.to(() => EditActivityScreen(activity: _currentActivity, isManagerOnly: false));
                    final fresh = await _repository.fetchActivityById(_currentActivity.id);
                    if (fresh != null && mounted) setState(() => _currentActivity = fresh);
                  },
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('Éditer l\'activité'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    backgroundColor: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => Get.to(() => ActivityManagementMenuScreen(activity: _currentActivity)),
                  icon: const Icon(Icons.settings_suggest_rounded),
                  label: const Text('Gérer mon activité'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                  ),
                ),
              ] else if (widget.isManager) ...[
                ElevatedButton.icon(
                  onPressed: () async {
                    await Get.to(() => EditActivityScreen(activity: _currentActivity, isManagerOnly: true));
                    final fresh = await _repository.fetchActivityById(_currentActivity.id);
                    if (fresh != null && mounted) setState(() => _currentActivity = fresh);
                  },
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('Éditer l\'activité'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    backgroundColor: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _confirmLeaveStaff,
                  icon: const Icon(Icons.exit_to_app_rounded, color: AppColors.error),
                  label: const Text('Quitter le staff', style: TextStyle(color: AppColors.error)),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    side: const BorderSide(color: AppColors.error),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(String status) {
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
        color = AppColors.textSecondary;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}
