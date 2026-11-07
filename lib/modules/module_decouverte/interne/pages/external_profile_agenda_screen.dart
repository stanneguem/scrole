import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../../app/routes/app_pages.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../../../../shared/widgets/entity_certified_badge.dart';
import '../../externe/repositories/external_profile_repository.dart';

class ExternalProfileAgendaScreen extends StatefulWidget {
  const ExternalProfileAgendaScreen({super.key, required this.userId});

  final String userId;

  @override
  State<ExternalProfileAgendaScreen> createState() => _ExternalProfileAgendaScreenState();
}

class _ExternalProfileAgendaScreenState extends State<ExternalProfileAgendaScreen> {
  final ExternalProfileRepository _repository = ExternalProfileRepository();
  late Future<List<Map<String, dynamic>>> _agendaFuture;

  @override
  void initState() {
    super.initState();
    _agendaFuture = _repository.fetchExternalUserAgenda(widget.userId);
  }

  Future<void> _refresh() async {
    final future = _repository.fetchExternalUserAgenda(widget.userId);
    if (!mounted) return;
    setState(() {
      _agendaFuture = future;
    });
    try {
      await future;
    } catch (_) {
      // FutureBuilder displays the error state; refresh should not leak it.
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Agenda')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _agendaFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_off_rounded, size: 42, color: colors.onSurfaceVariant),
                    const SizedBox(height: 12),
                    Text('Impossible de charger l’agenda de cette personne.', textAlign: TextAlign.center,
                        style: TextStyle(color: colors.onSurfaceVariant)),
                    TextButton(onPressed: _refresh, child: Text('profile_action_retry'.tr)),
                  ],
                ),
              ),
            );
          }

          final events = snapshot.data ?? const <Map<String, dynamic>>[];
          if (events.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(height: MediaQuery.sizeOf(context).height * .25),
                  Icon(Icons.calendar_today_outlined, size: 56, color: colors.outline),
                  const SizedBox(height: 14),
                  Center(child: Text('Aucun événement dans l’agenda.', style: TextStyle(color: colors.onSurfaceVariant))),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: events.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final event = events[index];
                final id = (event['id'] ?? '').toString();
                final photo = (event['photo'] ?? '').toString();
                final start = DateTime.tryParse((event['starts_at'] ?? '').toString());
                final date = start == null
                    ? ''
                    : DateFormat('EEE d MMM yyyy · HH:mm', Get.locale?.languageCode ?? 'fr').format(start.toLocal());
                final location = [event['city'], event['country']]
                    .where((value) => value != null && value.toString().trim().isNotEmpty)
                    .join(', ');

                return Material(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: id.isEmpty ? null : () => Get.toNamed(AppPages.eventPreviewPath(id)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (photo.isNotEmpty)
                          SizedBox(
                            height: 150,
                            width: double.infinity,
                            child: AppCachedImage(imageUrl: photo, fit: BoxFit.cover),
                          ),
                        Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      (event['name'] ?? 'profile_tab_event_fallback'.tr).toString(),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: colors.onSurface),
                                    ),
                                  ),
                                  if (id.isNotEmpty) EntityCertifiedBadge(entityType: 'event', entityId: id, size: 17),
                                ],
                              ),
                              if (date.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Row(children: [
                                  Icon(Icons.calendar_month_outlined, size: 16, color: colors.primary),
                                  const SizedBox(width: 7),
                                  Expanded(child: Text(date, style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant))),
                                ]),
                              ],
                              if (location.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Row(children: [
                                  Icon(Icons.location_on_outlined, size: 16, color: colors.primary),
                                  const SizedBox(width: 7),
                                  Expanded(child: Text(location, maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant))),
                                ]),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
