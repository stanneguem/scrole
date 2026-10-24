import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../centre/models/event_model.dart';
import '../../centre/repositories/event_repository.dart';
import 'event_itinerary_screen.dart';

/// Read-only view of the user's itinerary. Editing belongs to EventItineraryScreen.
class EventItineraryOverviewScreen extends StatefulWidget {
  final EventModel event;

  const EventItineraryOverviewScreen({super.key, required this.event});

  @override
  State<EventItineraryOverviewScreen> createState() => _EventItineraryOverviewScreenState();
}

class _EventItineraryOverviewScreenState extends State<EventItineraryOverviewScreen> {
  final EventRepository _repository = Get.find<EventRepository>();
  bool _loading = true;
  String? _error;
  final Map<String, Map<String, dynamic>> _plans = {};
  final Map<String, String> _activityNames = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _dateKey(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  Future<void> _load() async {
    try {
      final plans = await _repository.getMyEventItineraryPlans(widget.event.id);
      final activities = await _repository.getEventActivities(widget.event.id);
      if (!mounted) return;
      setState(() {
        _plans
          ..clear()
          ..addAll(plans);
        _activityNames
          ..clear()
          ..addEntries(activities.map((activity) => MapEntry(
                activity.activityId.isNotEmpty ? activity.activityId : activity.id,
                activity.name,
              )));
        _loading = false;
      });
    } catch (error) {
      debugPrint('[EventItineraryOverviewScreen] load failed: $error');
      if (mounted) setState(() {
        _error = 'Impossible de charger votre planning.';
        _loading = false;
      });
    }
  }

  DateTime? _timeOn(DateTime day, String time) {
    final parts = time.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return DateTime(day.year, day.month, day.day, hour, minute);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final days = _plans.keys.where((key) => key.isNotEmpty).toList()..sort();
    return Scaffold(
      appBar: AppBar(
        title: Text('Mon planning', style: AppTextStyles.h4.copyWith(fontSize: 18)),
        actions: [
          IconButton(
            tooltip: 'Organiser mon planning',
            onPressed: () async {
              await Get.to(() => EventItineraryScreen(event: widget.event));
              if (mounted) {
                setState(() { _loading = true; _error = null; });
                await _load();
              }
            },
            icon: const Icon(Icons.edit_calendar_rounded),
          ),
          IconButton(
            tooltip: 'Actualiser',
            onPressed: () {
              setState(() {
                _loading = true;
                _error = null;
              });
              _load();
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off_rounded, size: 44),
                        const SizedBox(height: 12),
                        Text(_error ?? 'Une erreur inattendue est survenue.', textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _load, child: const Text('Réessayer')),
                      ],
                    ),
                  ),
                )
              : days.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.route_outlined, size: 52, color: AppColors.primary),
                            const SizedBox(height: 14),
                            Text('Votre planning est encore vide', style: AppTextStyles.h4, textAlign: TextAlign.center),
                            const SizedBox(height: 8),
                            Text(
                              'Ouvrez « Organiser mon parcours » pour choisir vos activités et définir vos horaires.',
                              style: AppTextStyles.bodySmall.copyWith(color: colors.onSurfaceVariant),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                        children: [
                          if (widget.event.coverImageUrl?.isNotEmpty == true)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.network(
                                widget.event.coverImageUrl ?? '',
                                height: 150,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                              ),
                            ),
                          const SizedBox(height: 12),
                          Text(widget.event.name, style: AppTextStyles.h3),
                          if (widget.event.address?.isNotEmpty == true) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.location_on_outlined, size: 16, color: colors.onSurfaceVariant),
                                const SizedBox(width: 4),
                                Expanded(child: Text(widget.event.address ?? '', style: AppTextStyles.bodySmall.copyWith(color: colors.onSurfaceVariant))),
                              ],
                            ),
                          ],
                          const SizedBox(height: 20),
                          ...days.map((key) => _buildDay(context, key, Map<String, dynamic>.from(_plans[key] ?? const <String, dynamic>{}))),
                        ],
                      ),
                    ),
    );
  }

  Widget _buildDay(BuildContext context, String key, Map<String, dynamic> plan) {
    final colors = Theme.of(context).colorScheme;
    final date = DateTime.tryParse(key) ?? DateTime.now();
    final activities = (plan['activities'] is List ? plan['activities'] as List : const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList()
      ..sort((a, b) => (a['start_time'] ?? '99:99').toString().compareTo((b['start_time'] ?? '99:99').toString()));
    final dayStart = (plan['day_start'] ?? '09:00').toString();
    final dayEnd = (plan['day_end'] ?? '18:00').toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(12)),
                child: Column(
                  children: [
                    Text(DateFormat('dd').format(date), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    Text(DateFormat('MMM', Get.locale?.languageCode ?? 'fr').format(date).toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(DateFormat('EEEE d MMMM', Get.locale?.languageCode ?? 'fr').format(date), style: AppTextStyles.h4),
                      const SizedBox(height: 4),
                      Text('Arrivée $dayStart  ·  Départ $dayEnd', style: AppTextStyles.bodySmall.copyWith(color: colors.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (activities.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 60),
              child: Text('Aucune activité prévue ce jour-là.', style: AppTextStyles.bodySmall.copyWith(color: colors.onSurfaceVariant)),
            )
          else
            ...List.generate(activities.length, (index) {
              final item = activities[index];
              final id = (item['activity_id'] ?? '').toString();
              final name = _activityNames[id] ?? 'Activité';
              final start = (item['start_time'] ?? '09:00').toString();
              final end = (item['end_time'] ?? '10:00').toString();
              final now = DateTime.now();
              final endAt = _timeOn(date, end);
              final isPast = endAt != null && now.isAfter(endAt);
              final isFuture = endAt != null && now.isBefore(endAt);
              // Status is read-only. We only show missed after its scheduled end;
              // a completed check requires a trusted attendance/check-in record.
              final statusIcon = isPast ? Icons.close_rounded : isFuture ? Icons.schedule_rounded : Icons.radio_button_unchecked_rounded;
              final statusColor = isPast ? colors.error : AppColors.primary;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 48,
                    child: Column(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.10),
                            shape: BoxShape.circle,
                            border: Border.all(color: statusColor.withValues(alpha: 0.55)),
                          ),
                          child: Icon(statusIcon, size: 19, color: statusColor),
                        ),
                        if (index != activities.length - 1)
                          Container(
                            width: 2,
                            height: 28,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            color: colors.outlineVariant,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.45)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              Icon(Icons.schedule_outlined, size: 14, color: colors.onSurfaceVariant),
                              const SizedBox(width: 5),
                              Text('$start – $end', style: AppTextStyles.bodySmall.copyWith(color: colors.onSurfaceVariant)),
                              const Spacer(),
                              Text(
                                isPast ? 'Non confirmée' : isFuture ? 'À venir' : 'En cours',
                                style: AppTextStyles.caption.copyWith(color: statusColor, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }),
        ],
      ),
    );
  }
}
