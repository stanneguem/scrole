import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../controllers/staff_controller.dart';
import '../../centre/models/staff_model.dart';
import '../../centre/models/activity_model.dart';

class AssignStaffActivitiesScreen extends StatefulWidget {
  final StaffMemberModel staffMember;

  const AssignStaffActivitiesScreen({
    super.key,
    required this.staffMember,
  });

  @override
  State<AssignStaffActivitiesScreen> createState() => _AssignStaffActivitiesScreenState();
}

class _AssignStaffActivitiesScreenState extends State<AssignStaffActivitiesScreen> {
  late Set<String> _initialAssignedActivityIds;
  late Set<String> _selectedActivityIds;
  bool _isSaving = false;
  bool _isSaved = false;

  @override
  void initState() {
    super.initState();
    _initialAssignedActivityIds = Set<String>.from(widget.staffMember.assignedActivityIds);
    _selectedActivityIds = Set<String>.from(_initialAssignedActivityIds);
  }

  Future<void> _saveAssignments() async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
      _isSaved = false;
    });

    final controller = Get.find<StaffController>();
    final selectedIdsList = _selectedActivityIds.toList();
    final selectedNamesList = controller.eventActivities
        .where((a) => _selectedActivityIds.contains(a.id))
        .map((a) => a.name)
        .toList();

    try {
      await controller.updateStaffActivities(
        staffId: widget.staffMember.id.isNotEmpty ? widget.staffMember.id : widget.staffMember.userId,
        activityIds: selectedIdsList,
        activityNames: selectedNamesList,
      );

      if (mounted) {
        setState(() {
          _isSaving = false;
          _isSaved = true;
        });
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) Get.back();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _isSaved = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<StaffController>();
    final colors = Theme.of(context).colorScheme;

    final member = widget.staffMember;
    final usernameText = member.username != null && member.username!.isNotEmpty ? '@${member.username}' : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Attribuer des activités',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _isSaving ? null : _saveAssignments,
              child: _isSaving
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Enregistrement...',
                          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.primary),
                        ),
                      ],
                    )
                  : _isSaved
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.success),
                            const SizedBox(width: 4),
                            Text(
                              'Enregistré',
                              style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.success),
                            ),
                          ],
                        )
                      : Text(
                          'Enregistrer',
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
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // En-tête Membre du Staff
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                ClipOval(
                  child: member.avatarUrl != null && member.avatarUrl!.isNotEmpty
                      ? AppCachedImage(imageUrl: member.avatarUrl!, width: 48, height: 48, fit: BoxFit.cover)
                      : Container(
                          width: 48,
                          height: 48,
                          color: AppColors.primary.withValues(alpha: 0.12),
                          child: const Icon(Icons.person, color: AppColors.primary, size: 28),
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(member.name, style: AppTextStyles.h4),
                      if (usernameText != null) ...[
                        const SizedBox(height: 2),
                        Text(usernameText, style: AppTextStyles.bodySmall.copyWith(color: colors.onSurfaceVariant)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Text(
            'ACTIVITÉS DE L\'ÉVÉNEMENT',
            style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary, letterSpacing: 1.2),
          ),
          const SizedBox(height: 8),

          // Liste des activités de l'événement avec cases à cocher style Apple
          Obx(() {
            final activities = controller.eventActivities;

            if (activities.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.2)),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.local_activity_outlined, size: 40, color: AppColors.disabled),
                    const SizedBox(height: 12),
                    Text('Aucune activité sur cet événement', style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                    const SizedBox(height: 4),
                    Text(
                      'Ajoutez d\'abord des activités à cet événement pour pouvoir les attribuer à votre staff.',
                      style: AppTextStyles.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }

            return Column(
              children: activities.map((activity) {
                if (widget.staffMember.assignedActivityNames.contains(activity.name) ||
                    widget.staffMember.assignedActivityIds.contains(activity.id) ||
                    widget.staffMember.assignedActivityIds.contains(activity.activityId)) {
                  _selectedActivityIds.add(activity.id);
                  _initialAssignedActivityIds.add(activity.id);
                }

                final isSelected = _selectedActivityIds.contains(activity.id);
                final isInitiallyAssigned = _initialAssignedActivityIds.contains(activity.id);

                return _AppleCheckboxTile(
                  title: activity.name,
                  subtitle: activity.formattedEventPrice,
                  isSelected: isSelected,
                  isAssigned: isInitiallyAssigned && isSelected,
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _selectedActivityIds.remove(activity.id);
                      } else {
                        _selectedActivityIds.add(activity.id);
                      }
                      _isSaved = false;
                    });
                  },
                );
              }).toList(),
            );
          }),
        ],
      ),
    );
  }
}

/// Case à cocher style Apple / iOS avec Badge 'Attribuée' (§5)
class _AppleCheckboxTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool isSelected;
  final bool isAssigned;
  final VoidCallback onTap;

  const _AppleCheckboxTile({
    required this.title,
    this.subtitle,
    required this.isSelected,
    this.isAssigned = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected ? AppColors.primary : colors.outlineVariant.withValues(alpha: 0.3),
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(title, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold, fontSize: 15)),
                        ),
                        if (isAssigned) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'Attribuée',
                              style: AppTextStyles.caption.copyWith(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 11),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: AppTextStyles.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Contrôle de sélection Style Apple (cercle animé avec coche)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? AppColors.primary : Colors.transparent,
                  border: Border.all(
                    color: isSelected ? AppColors.primary : colors.outlineVariant,
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? const Icon(
                        Icons.check_rounded,
                        size: 18,
                        color: Colors.white,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
