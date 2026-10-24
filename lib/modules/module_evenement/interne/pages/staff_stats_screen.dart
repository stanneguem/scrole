import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../controllers/staff_controller.dart';
import '../../centre/models/staff_model.dart';

class StaffStatsScreen extends StatefulWidget {
  final StaffMemberModel staffMember;

  const StaffStatsScreen({
    super.key,
    required this.staffMember,
  });

  @override
  State<StaffStatsScreen> createState() => _StaffStatsScreenState();
}

class _StaffStatsScreenState extends State<StaffStatsScreen> {
  Map<String, dynamic>? _statsData;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final controller = Get.find<StaffController>();
      final staffId = widget.staffMember.id.isNotEmpty ? widget.staffMember.id : widget.staffMember.userId;
      final data = await controller.fetchStaffStats(staffId);
      if (mounted) {
        setState(() {
          _statsData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final member = widget.staffMember;
    final usernameText = member.username != null && member.username!.isNotEmpty ? '@${member.username}' : null;

    num toNum(dynamic val) {
      if (val == null) return 0;
      if (val is num) return val;
      if (val is String) return num.tryParse(val) ?? 0;
      return 0;
    }

    final totalScans = _statsData != null ? toNum(_statsData!['total_scans']).toInt() : 0;
    final activitiesList = _statsData != null && _statsData!['activities'] is List
        ? List<Map<String, dynamic>>.from(_statsData!['activities'] as List)
        : <Map<String, dynamic>>[];

    final eventName = _statsData != null && _statsData!['event'] is Map
        ? (_statsData!['event']['name'] ?? _statsData!['event']['nom'] ?? '').toString()
        : '';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Détails & Statistiques',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        ),
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
                      ? AppCachedImage(imageUrl: member.avatarUrl!, width: 56, height: 58, fit: BoxFit.cover)
                      : Container(
                          width: 56,
                          height: 56,
                          color: AppColors.primary.withValues(alpha: 0.12),
                          child: const Icon(Icons.person, color: AppColors.primary, size: 32),
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
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('Membre du staff', style: AppTextStyles.caption.copyWith(color: AppColors.success, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Événement concerné (si disponible)
          if (eventName.isNotEmpty) ...[
            Text('ÉVÉNEMENT', style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary, letterSpacing: 1.2)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event_rounded, color: AppColors.primary, size: 20),
                  const SizedBox(width: 10),
                  Text(eventName, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Gestion des états Chargement / Erreur / Succès
          if (_isLoading) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
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
                  Text('Impossible de charger les statistiques du staff.', style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _loadStats,
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                    label: const Text('Réessayer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                  ),
                ],
              ),
            ),
          ] else ...[
            // Total Scans
            Text('STATISTIQUES DE CONTRÔLE', style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary, letterSpacing: 1.2)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.qr_code_scanner_rounded, color: AppColors.primary, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Total des scans valides', style: AppTextStyles.bodySmall),
                        Text('$totalScans scan${totalScans > 1 ? 's' : ''}', style: AppTextStyles.h3.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Cartes d'Activités Attribuées & Scans par Activité
            Text('ACTIVITÉS ET SCANS PAR ACTIVITÉ', style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary, letterSpacing: 1.2)),
            const SizedBox(height: 8),

            if (activitiesList.isEmpty && member.assignedActivityNames.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text('Aucune activité attribuée à ce membre du staff.', style: AppTextStyles.bodySmall),
                ),
              )
            else if (activitiesList.isNotEmpty)
              ...activitiesList.map((act) {
                final actName = (act['name'] ?? act['nom'] ?? 'Activité').toString();
                final scanCount = toNum(act['scan_count'] ?? act['scans']).toInt();
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.3)),
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.local_activity_rounded, color: AppColors.primary),
                    title: Text(actName, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
                    trailing: Text('$scanCount scan${scanCount > 1 ? 's' : ''}', style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold, color: AppColors.primary)),
                  ),
                );
              })
            else
              ...member.assignedActivityNames.map((actName) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.3)),
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.local_activity_rounded, color: AppColors.primary),
                      title: Text(actName, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
                      trailing: Text('0 scan', style: AppTextStyles.bodySmall),
                    ),
                  )),
          ],
        ],
      ),
    );
  }
}
