import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../centre/repositories/event_repository.dart';
import '../../interne/pages/event_detail_page.dart';
import '../../interne/pages/event_comments_screen.dart';
import '../../interne/pages/event_itinerary_overview_screen.dart';
import '../../interne/pages/external_event_itinerary_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../centre/models/event_model.dart';
import '../../../../shared/widgets/app_cached_image.dart';

class ProfileEventSeriesScreen extends StatelessWidget {
  final Map<String, dynamic> series;
  final String profileUserId;
  const ProfileEventSeriesScreen({super.key, required this.series, required this.profileUserId});

  Future<void> _openEdition(BuildContext context, Map<String, dynamic> edition) async {
    final id = (edition['id'] ?? '').toString();
    if (id.isEmpty) return;
    try {
      final event = await Get.find<EventRepository>().getEventById(id);
      if (context.mounted) Get.to(() => ArchivedEventEditionScreen(event: event, profileUserId: profileUserId));
    } catch (_) {
      Get.snackbar('Événement', 'Impossible de charger cette édition.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final raw = series['editions'];
    final editions = raw is List
        ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    editions.sort((a, b) => ((b['edition_number'] as num?)?.toInt() ?? 1)
        .compareTo((a['edition_number'] as num?)?.toInt() ?? 1));
    return Scaffold(
      appBar: AppBar(title: Text((series['name'] ?? 'Événement').toString(),
        maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: editions.isEmpty
          ? Center(child: Text('Aucune édition disponible', style: TextStyle(color: colors.onSurfaceVariant)))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: editions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final edition = editions[index];
                final image = (edition['photo'] ?? '').toString();
                final number = (edition['edition_number'] as num?)?.toInt() ?? 1;
                final start = DateTime.tryParse((edition['starts_at'] ?? '').toString());
                final date = start == null ? '' : '${start.day.toString().padLeft(2,'0')}/${start.month.toString().padLeft(2,'0')}/${start.year}';
                return Material(
                  color: colors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _openEdition(context, edition),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (image.isNotEmpty)
                        SizedBox(height: 145, width: double.infinity,
                          child: AppCachedImage(imageUrl: image, fit: BoxFit.cover)),
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Édition $number', style: TextStyle(fontWeight: FontWeight.w700, color: colors.onSurface)),
                            if (date.isNotEmpty) ...[
                              const SizedBox(height: 5),
                              Text(date, style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
                            ],
                            Text((edition['city'] ?? '').toString(),
                              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
                          ])),
                          Icon(Icons.chevron_right_rounded, color: colors.primary),
                        ]),
                      ),
                    ]),
                  ),
                );
              },
            ),
    );
  }
}


class ArchivedEventEditionScreen extends StatelessWidget {
  final EventModel event;
  final String profileUserId;
  const ArchivedEventEditionScreen({super.key, required this.event, required this.profileUserId});

  void _openProgram() {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id ?? '';
    if (currentUserId == profileUserId) {
      Get.to(() => EventItineraryOverviewScreen(event: event, readOnly: true));
    } else {
      Get.to(() => ExternalEventItineraryScreen(
        userId: profileUserId,
        eventId: event.id,
        eventName: event.name,
        eventPhoto: event.coverImageUrl ?? '',
        eventLocation: event.locationDisplay,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(event.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: 'Commentaires',
              onPressed: () => Get.to(() => EventCommentsScreen(eventId: event.id, eventName: event.name)),
              icon: const Icon(Icons.chat_bubble_outline_rounded),
            ),
            IconButton(
              tooltip: 'Revoir mon programme',
              onPressed: _openProgram,
              icon: const Icon(Icons.route_rounded),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.photo_library_outlined), text: 'Galerie'),
              Tab(icon: Icon(Icons.info_outline_rounded), text: 'Détails'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.photo_library_outlined, size: 42, color: colors.onSurfaceVariant),
                    const SizedBox(height: 12),
                    Text(
                      'La galerie des publications liées à cette édition sera disponible ici.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
            EventDetailPage(event: event, profileUserId: profileUserId, archiveTabMode: true),
          ],
        ),
      ),
    );
  }
}

Future<void> openProfileEventSeries(BuildContext context, Map<String, dynamic> series, {required String profileUserId}) async {
  final raw = series['editions'];
  final editions = raw is List
      ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];
  if (editions.length == 1) {
    final id = (editions.first['id'] ?? '').toString();
    if (id.isEmpty) return;
    try {
      final event = await Get.find<EventRepository>().getEventById(id);
      if (context.mounted) Get.to(() => EventDetailPage(event: event, profileUserId: profileUserId));
    } catch (_) {
      Get.snackbar('Événement', 'Impossible de charger cette édition.');
    }
    return;
  }
  if (context.mounted) Get.to(() => ProfileEventSeriesScreen(series: series, profileUserId: profileUserId));
}
