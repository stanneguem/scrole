import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../centre/repositories/event_repository.dart';
import '../../interne/pages/event_detail_page.dart';
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
      if (context.mounted) Get.to(() => EventDetailPage(event: event, profileUserId: profileUserId));
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
