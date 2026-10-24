import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/widgets/scrole_bottom_sheet.dart';
import '../controllers/event_activity_controller.dart';
import '../../centre/models/activity_model.dart';
import '../../centre/models/staff_model.dart';

class ActivityStaffManagementScreen extends StatefulWidget {
  final EventActivityModel eventActivity;

  const ActivityStaffManagementScreen({
    super.key,
    required this.eventActivity,
  });

  @override
  State<ActivityStaffManagementScreen> createState() => _ActivityStaffManagementScreenState();
}

class _ActivityStaffManagementScreenState extends State<ActivityStaffManagementScreen> {
  late EventActivityModel _activity;
  List<StaffMemberModel> _assignedStaff = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _activity = widget.eventActivity;
    _loadAssignedStaff();
  }

  Future<void> _loadAssignedStaff() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final controller = Get.find<EventActivityController>();
      final actId = _activity.activityId.isNotEmpty ? _activity.activityId : _activity.id;
      final staffList = await controller.fetchEventActivityStaff(actId);
      if (mounted) {
        setState(() {
          _assignedStaff = staffList;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[ActivityStaffManagementScreen] _loadAssignedStaff error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _showAddStaffToActivitySheet(EventActivityController controller) {
    final assignedUserIds = _assignedStaff.map((s) => s.userId).toSet();
    final unassignedStaff = controller.eventStaff
        .where((s) => !assignedUserIds.contains(s.userId) && !_activity.assignedStaffIds.contains(s.id))
        .toList();

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
                  Text('Ajouter au staff de cette activité', style: AppTextStyles.h4),
                  const SizedBox(height: 4),
                  Text('Sélectionnez un membre du staff de cet événement :', style: AppTextStyles.bodySmall),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (unassignedStaff.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Tous les membres du staff de cet événement sont déjà attribués à cette activité.', style: AppTextStyles.bodySmall),
              )
            else
              ScroleBottomSheetGroup(
                children: unassignedStaff.map((staff) => ScroleBottomSheetAction(
                  label: staff.name,
                  icon: Icons.person_add_outlined,
                  onTap: () {
                    Get.back();
                    final actId = _activity.activityId.isNotEmpty ? _activity.activityId : _activity.id;
                    controller.assignStaffToActivity(actId, staff.id);
                    setState(() {
                      _assignedStaff.add(staff);
                    });
                  },
                )).toList(),
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

    final hasEventStaff = controller.eventStaff.isNotEmpty || _assignedStaff.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Staff de l\'activité',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // En-tête avec nom de l'activité (aucun ID technique affiché!)
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
                  child: const Icon(Icons.people_outline_rounded, color: AppColors.primary, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_activity.name, style: AppTextStyles.h4),
                      const SizedBox(height: 2),
                      Text('Prix : ${_activity.formattedEventPrice}', style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          if (_isLoading) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            ),
          ] else if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  const Icon(Icons.error_outline_rounded, size: 40, color: AppColors.error),
                  const SizedBox(height: 12),
                  Text('Impossible de charger le staff de l\'activité.', style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _loadAssignedStaff,
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                    label: const Text('Réessayer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                  ),
                ],
              ),
            ),
          ] else if (!hasEventStaff) ...[
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.people_outline_rounded,
                        size: 48,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Aucun membre du staff',
                      style: AppTextStyles.h5.copyWith(color: colors.onSurface),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Aucun membre du staff n\'est actuellement disponible pour gérer cette activité.\n\nVous pourrez affecter des membres du staff à cette activité une fois qu\'ils auront été ajoutés à cet événement.',
                      style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            Text(
              'MEMBRES ATTRIBUÉS À CETTE ACTIVITÉ',
              style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary, letterSpacing: 1.2),
            ),
            const SizedBox(height: 12),

            if (_assignedStaff.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text('Aucun membre du staff n\'est encore attribué à cette activité.', style: AppTextStyles.bodySmall),
              )
            else
              ..._assignedStaff.map((staff) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                        child: const Icon(Icons.person, color: AppColors.primary),
                      ),
                      title: Text(staff.name, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        staff.username != null ? '@${staff.username}' : 'Staff de l\'activité',
                        style: const TextStyle(color: Colors.green, fontSize: 12),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.person_remove_outlined, color: AppColors.error, size: 20),
                        onPressed: () {
                          final actId = _activity.activityId.isNotEmpty ? _activity.activityId : _activity.id;
                          controller.assignStaffToActivity(actId, staff.id);
                          setState(() {
                            _assignedStaff.removeWhere((s) => s.userId == staff.userId || s.id == staff.id);
                          });
                        },
                      ),
                    ),
                  )).toList(),

            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _showAddStaffToActivitySheet(controller),
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: const Text('Ajouter au staff de cette activité', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
