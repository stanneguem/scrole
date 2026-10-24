import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/widgets/entity_certified_badge.dart';
import '../../centre/repositories/event_repository.dart';

class ExternalEventItineraryScreen extends StatefulWidget {
  final String userId;
  final String eventId;
  final String eventName;

  const ExternalEventItineraryScreen({
    super.key,
    required this.userId,
    required this.eventId,
    required this.eventName,
  });

  @override
  State<ExternalEventItineraryScreen> createState() => _ExternalEventItineraryScreenState();
}

class _ExternalEventItineraryScreenState extends State<ExternalEventItineraryScreen> {
  final EventRepository _repository = Get.find<EventRepository>();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _days = [];
  Map<String, String> _activityNames = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await _repository.getExternalEventItinerary(
        userId: widget.userId,
        eventId: widget.eventId,
      );
      final rawPlans = result['plans'];
      final activities = await _repository.getEventActivities(widget.eventId);
      final names = <String, String>{};
      for (final activity in activities) {
        names[activity.activityId.isNotEmpty ? activity.activityId : activity.id] = activity.name;
      }
      final plans = rawPlans is List
          ? rawPlans.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
          : <Map<String, dynamic>>[];
      plans.sort((a, b) => (a['planned_date'] ?? '').toString().compareTo((b['planned_date'] ?? '').toString()));
      if (!mounted) return;
      setState(() {
        _days = plans;
        _activityNames = names;
        _loading = false;
      });
    } catch (error) {
      debugPrint('[ExternalEventItineraryScreen] denied or failed: $error');
      if (!mounted) return;
      setState(() {
        _error = error.toString().contains('event_itinerary_private')
            ? 'external_event_itinerary_private'.tr
            : 'external_event_itinerary_unavailable'.tr;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('external_event_itinerary_title'.trParams({'event': widget.eventName}), maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_outline_rounded, size: 48, color: colors.onSurfaceVariant),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center, style: AppTextStyles.body),
                      ],
                    ),
                  ),
                )
              : _days.isEmpty
                  ? Center(child: Text('external_event_itinerary_empty'.tr))
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(child: Text(widget.eventName, style: AppTextStyles.h3, maxLines: 2, overflow: TextOverflow.ellipsis)),
                            EntityCertifiedBadge(entityType: 'event', entityId: widget.eventId, size: 18),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ..._days.map((day) => _buildDay(context, day)),
                      ],
                    ),
    );
  }

  Widget _buildDay(BuildContext context, Map<String, dynamic> entry) {
    final colors = Theme.of(context).colorScheme;
    final dateKey = (entry['planned_date'] ?? '').toString();
    final date = DateTime.tryParse(dateKey);
    final plan = entry['plan'] is Map ? Map<String, dynamic>.from(entry['plan'] as Map) : <String, dynamic>{};
    final dayStart = (plan['day_start'] ?? '—').toString();
    final dayEnd = (plan['day_end'] ?? '—').toString();
    final rawActivities = plan['activities'] is List ? plan['activities'] as List : const [];
    final activities = rawActivities.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
      ..sort((a, b) => (a['start_time'] ?? '').toString().compareTo((b['start_time'] ?? '').toString()));

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: colors.primaryContainer, borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                Icon(Icons.calendar_month_rounded, color: colors.onPrimaryContainer),
                const SizedBox(width: 10),
                Expanded(child: Text(date == null ? dateKey : DateFormat('EEEE d MMMM yyyy', Get.locale?.languageCode ?? 'fr').format(date), style: AppTextStyles.h4.copyWith(color: colors.onPrimaryContainer))),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
            child: Text('${'event_itinerary_arrival'.tr}: $dayStart     ${'event_itinerary_departure'.tr}: $dayEnd', style: AppTextStyles.bodySmall.copyWith(color: colors.onSurfaceVariant)),
          ),
          if (activities.isEmpty)
            Padding(padding: const EdgeInsets.only(left: 8), child: Text('external_event_itinerary_none'.tr, style: AppTextStyles.bodySmall.copyWith(color: colors.onSurfaceVariant))),
          ...activities.map((activity) {
            final id = (activity['activity_id'] ?? '').toString();
            final name = _activityNames[id] ?? (activity['name'] ?? 'Activité').toString();
            final start = (activity['start_time'] ?? '—').toString();
            final end = (activity['end_time'] ?? '—').toString();
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.circle_outlined, color: AppColors.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(name, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600))),
                  Text('$start–$end', style: AppTextStyles.bodySmall.copyWith(color: colors.onSurfaceVariant)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
