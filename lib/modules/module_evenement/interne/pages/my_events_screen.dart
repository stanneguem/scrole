import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../app/routes/app_pages.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../../../../shared/widgets/entity_certified_badge.dart';
import '../../centre/models/event_model.dart';
import '../controllers/event_controller.dart';
import '../enums/event_enum.dart';

class MyEventsScreen extends StatefulWidget {
  const MyEventsScreen({super.key});

  @override
  State<MyEventsScreen> createState() => _MyEventsScreenState();
}

class _MyEventsScreenState extends State<MyEventsScreen> {
  late final EventController controller;

  @override
  void initState() {
    super.initState();
    controller = Get.isRegistered<EventController>()
        ? Get.find<EventController>()
        : Get.put(EventController());
    controller.fetchMyEvents();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'my_events_title'.tr,
            style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
          ),
          bottom: TabBar(
            tabs: [
              Tab(text: 'my_events_tab_creations'.tr),
              Tab(text: 'my_events_tab_staff'.tr),
            ],
            labelStyle: AppTextStyles.labelLarge,
            unselectedLabelStyle: AppTextStyles.labelLarge,
            indicatorColor: AppColors.primary,
            labelColor: AppColors.primary,
          ),
        ),
        body: RefreshIndicator(
          onRefresh: controller.fetchMyEvents,
          color: AppColors.primary,
          child: Obx(() {
            // Le cache local reste visible pendant la synchronisation distante.
            // On évite un écran de chargement qui masquerait les événements déjà disponibles.
            return TabBarView(
              children: [
                _buildEventList(context, controller.managedEvents, 'my_events_empty_creations'.tr, contextRole: 'owner'),
                _buildEventList(context, controller.staffEvents, 'my_events_empty_staff'.tr, contextRole: 'staff'),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _buildEventList(BuildContext context, List<EventModel> events, String emptyMessage, {required String contextRole}) {
    final colors = Theme.of(context).colorScheme;

    if (events.isEmpty) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.6,
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.event_busy_outlined, size: 64, color: colors.outline),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(emptyMessage, textAlign: TextAlign.center, style: AppTextStyles.body),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: events.length,
      itemBuilder: (context, index) {
        final event = events[index];
        final creationDateStr = _formatDisplayDate(event.createdAt);

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            contentPadding: const EdgeInsets.all(12),
            leading: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: colors.surfaceContainerHigh,
              ),
              clipBehavior: Clip.antiAlias,
              child: event.coverImageUrl != null && event.coverImageUrl!.isNotEmpty
                  ? AppCachedImage(
                      imageUrl: event.coverImageUrl!,
                      fit: BoxFit.cover,
                    )
                  : Icon(Icons.event_outlined, color: colors.outline, size: 30),
            ),
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  fit: FlexFit.loose,
                  child: Text(
                    event.name,
                    style: AppTextStyles.h4,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                EntityCertifiedBadge(
                  entityType: 'event',
                  entityId: event.id,
                  size: 17,
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 2),
                Text(
                  'Créé le $creationDateStr',
                  style: AppTextStyles.bodySmall.copyWith(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 6),
                _buildStatusChip(event),
              ],
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Get.toNamed(
                AppPages.eventPreview.replaceFirst(':id', event.id),
                arguments: {
                  'id': event.id,
                  'event': event,
                  'context': contextRole,
                },
              );
              if (mounted) await controller.fetchMyEvents();
            },
          ),
        );
      },
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
      return 'Aujourd\'hui à $hh:$mm';
    } else if (diffDays == 1) {
      return 'Hier à $hh:$mm';
    } else if (diffDays > 1 && diffDays < 7) {
      return 'il y a $diffDays jours';
    } else {
      final months = [
        'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
        'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'
      ];
      return '${local.day} ${months[local.month - 1]} ${local.year}';
    }
  }

  Widget _buildStatusChip(EventModel event) {
    if (event.statutSync == 'pending_push' || event.statutSync == 'en_attente') {
      return _chip('En cours de sync...', Colors.orange);
    }
    if (event.statutSync == 'echec' || event.statutSync == 'rejected') {
      return _chip('Erreur de sync', Colors.red);
    }
    
    final status = event.status;
    if (status == EventStatus.draft) {
      return _chip('En attente de validation', Colors.orange);
    }
    if (status == EventStatus.published) {
      return _chip('Actif', Colors.green);
    }
    if (status == EventStatus.pendingDeletion) {
      return _chip('Suppression programmée', Colors.red);
    }
    if (status == EventStatus.cancelled) {
      return _chip('Rejeté', Colors.red);
    }
    if (status == EventStatus.deleted) {
      return _chip('Supprimé', Colors.grey);
    }
    return _chip(status.value, Colors.grey);
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }
}
