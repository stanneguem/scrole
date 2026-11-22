import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../../../../shared/widgets/entity_certified_badge.dart';
import '../controllers/user_agenda_controller.dart';
import '../../centre/models/event_model.dart';
import 'user_pass_screen.dart';
import 'event_itinerary_screen.dart';
import 'event_itinerary_overview_screen.dart';

class UserAgendaScreen extends GetView<UserAgendaController> {
  const UserAgendaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'my_agenda_title'.tr,
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        ),
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }

        if (controller.myAgenda.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.calendar_today_outlined, size: 64, color: colors.outline),
                const SizedBox(height: 16),
                Text('my_agenda_empty'.tr, style: AppTextStyles.body),
              ],
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (controller.activeEvent != null) ...[
              _buildActiveEventCard(
                context,
                controller.activeEvent!,
                onPassTap: () => Get.to(() => UserPassScreen(event: controller.activeEvent!)),
                onPlanningTap: () => Get.to(() => EventItineraryOverviewScreen(event: controller.activeEvent!)),
                onRemoveTap: () => _confirmRemoveEvent(context, controller.activeEvent!),
              ),
              const SizedBox(height: 24),
              Text('agenda_upcoming'.tr, style: AppTextStyles.labelSmall.copyWith(color: colors.outline)),
              const SizedBox(height: 12),
            ],
            ...controller.myAgenda.map((event) => _AgendaItem(
                  event: event,
                  onTap: () => Get.to(() => EventItineraryOverviewScreen(event: event)),
                  onPassTap: () => Get.to(() => UserPassScreen(event: event)),
                  onPlanningTap: () => Get.to(() => EventItineraryOverviewScreen(event: event)),
                  onRemoveTap: () => _confirmRemoveEvent(context, event),
                )),
          ],
        );
      }),
    );
  }

  void _confirmRemoveEvent(BuildContext context, EventModel event) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Retirer de l\'agenda ?'),
        content: Text('Voulez-vous vraiment retirer "${event.name}" de votre agenda ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('cancel'.tr),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              controller.removeFromAgenda(event.id);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Retirer', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveEventCard(
    BuildContext context,
    EventModel event, {
    required VoidCallback onPassTap,
    required VoidCallback onPlanningTap,
    required VoidCallback onRemoveTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'agenda_live_now'.tr,
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
              const Spacer(),
              const Icon(Icons.flash_on, color: Colors.white, size: 18),
            ],
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: onPlanningTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      fit: FlexFit.loose,
                      child: Text(event.name, style: AppTextStyles.h3.copyWith(color: Colors.white), maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 4),
                    EntityCertifiedBadge(entityType: 'event', entityId: event.id, size: 18),
                  ],
                ),
                const SizedBox(height: 4),
                Text(event.address ?? '', style: AppTextStyles.bodySmall.copyWith(color: Colors.white.withValues(alpha: 0.8))),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onPassTap,
                  icon: const Icon(Icons.qr_code_rounded, size: 17, color: AppColors.primary),
                  label: const Text('QR code', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12)),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onPlanningTap,
                  icon: const Icon(Icons.route_rounded, size: 17, color: AppColors.primary),
                  label: const Text('Mon planning', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12)),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12)),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: onRemoveTap,
                tooltip: "Retirer de l'agenda",
                icon: SvgPicture.asset('assets/svg_icons/trash-bin-minimalistic-2-svgrepo-com.svg', width: 21, height: 21, colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AgendaItem extends StatelessWidget {
  final EventModel event;
  final VoidCallback onTap;
  final VoidCallback onPassTap;
  final VoidCallback onPlanningTap;
  final VoidCallback onRemoveTap;

  const _AgendaItem({
    required this.event,
    required this.onTap,
    required this.onPassTap,
    required this.onPlanningTap,
    required this.onRemoveTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 42,
            child: Column(
              children: [
                Text(event.startsAt.day.toString(), style: AppTextStyles.h3),
                Text(
                  event.startsAt.month.toString(),
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Material(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(9)),
                            clipBehavior: Clip.antiAlias,
                            child: AppCachedImage(imageUrl: event.coverImageUrl ?? '', fit: BoxFit.cover),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      fit: FlexFit.loose,
                                      child: Text(event.name, style: AppTextStyles.h4, maxLines: 2, overflow: TextOverflow.ellipsis),
                                    ),
                                    const SizedBox(width: 4),
                                    EntityCertifiedBadge(entityType: 'event', entityId: event.id, size: 17),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${event.startsAt.hour.toString().padLeft(2, '0')}:${event.startsAt.minute.toString().padLeft(2, '0')}',
                                  style: AppTextStyles.bodySmall.copyWith(color: colors.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _AgendaAction(
                              icon: Icons.qr_code_rounded,
                              label: 'QR code',
                              onTap: onPassTap,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _AgendaAction(
                              icon: Icons.route_rounded,
                              label: 'Mon planning',
                              onTap: onPlanningTap,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _AgendaAction(
                              icon: Icons.delete_outline_rounded,
                              label: 'Retirer',
                              danger: true,
                              onTap: onRemoveTap,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AgendaAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  const _AgendaAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = danger ? AppColors.error : colors.primary;
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.35)),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (danger)
            SvgPicture.asset(
              'assets/svg_icons/trash-bin-minimalistic-2-svgrepo-com.svg',
              width: 18,
              height: 18,
              colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
            )
          else
            Icon(icon, size: 18),
          const SizedBox(height: 3),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
