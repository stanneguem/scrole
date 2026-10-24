import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../centre/models/activity_model.dart';
import 'activity_delete_screen.dart';
import 'activity_staff_screen.dart';
import 'activity_stats_screen.dart';
import 'activity_transfer_screen.dart';

class ActivityManagementMenuScreen extends StatelessWidget {
  final Activity activity;

  const ActivityManagementMenuScreen({super.key, required this.activity});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          'Gérer l\'activité',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Get.back(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // En-tête activité
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.local_activity_rounded, color: AppColors.primary, size: 32),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          activity.name,
                          style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          activity.formattedPrice,
                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            Text(
              'OPTIONS DE GESTION',
              style: AppTextStyles.labelSmall.copyWith(letterSpacing: 1.2, color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),

            // Option 1: Staff
            _OptionCard(
              icon: Icons.people_outline_rounded,
              title: 'Gérer le staff',
              subtitle: 'Inviter, afficher ou retirer des gestionnaires',
              color: AppColors.primary,
              onTap: () => Get.to(() => ActivityStaffScreen(activity: activity)),
            ),
            const SizedBox(height: 12),

            // Option 2: Transférer
            _OptionCard(
              icon: Icons.swap_horiz_rounded,
              title: 'Transférer l\'activité',
              subtitle: 'Céder la propriété à un membre éligible du staff',
              color: const Color(0xFF3B82F6),
              onTap: () => Get.to(() => ActivityTransferScreen(activity: activity)),
            ),
            const SizedBox(height: 12),

            // Option 3: Statistiques
            _OptionCard(
              icon: Icons.bar_chart_rounded,
              title: 'Statistiques',
              subtitle: 'Consulter l\'utilisation et le classement plateforme',
              color: Colors.amber[800]!,
              onTap: () => Get.to(() => ActivityStatsScreen(activity: activity)),
            ),
            const SizedBox(height: 24),

            Text(
              'ZONE DE DANGER',
              style: AppTextStyles.labelSmall.copyWith(letterSpacing: 1.2, color: AppColors.error),
            ),
            const SizedBox(height: 12),

            // Option 4: Suppression
            _OptionCard(
              icon: Icons.delete_outline_rounded,
              title: 'Supprimer mon activité',
              subtitle: 'Programmer la suppression (délai de rétention 30 jours)',
              color: AppColors.error,
              isDanger: true,
              onTap: () => Get.to(() => ActivityDeleteScreen(activity: activity)),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool isDanger;
  final VoidCallback onTap;

  const _OptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.isDanger = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.body.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDanger ? AppColors.error : colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTextStyles.bodySmall.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
