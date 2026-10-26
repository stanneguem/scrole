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
  final String eventPhoto;
  final String eventLocation;

  const ExternalEventItineraryScreen({
    super.key,
    required this.userId,
    required this.eventId,
    required this.eventName,
    this.eventPhoto = '',
    this.eventLocation = '',
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
      final result = await _repository.getExternalEventItinerary(userId: widget.userId, eventId: widget.eventId);
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
      setState(() { _days = plans; _activityNames = names; _loading = false; });
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

  Map<String, dynamic> _planFor(Map<String, dynamic> entry) =>
      entry['plan'] is Map ? Map<String, dynamic>.from(entry['plan'] as Map) : <String, dynamic>{};

  List<Map<String, dynamic>> _activitiesFor(Map<String, dynamic> entry) {
    final plan = _planFor(entry);
    final raw = plan['activities'] is List ? plan['activities'] as List : const [];
    return raw.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
      ..sort((a, b) => (a['start_time'] ?? '').toString().compareTo((b['start_time'] ?? '').toString()));
  }

  String _formatDate(String key, {String pattern = 'EEEE d MMMM yyyy'}) {
    final date = DateTime.tryParse(key);
    return date == null ? key : DateFormat(pattern, Get.locale?.languageCode ?? 'fr').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('external_event_itinerary_title'.trParams({'event': widget.eventName}), maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.lock_outline_rounded, size: 48, color: colors.onSurfaceVariant),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center, style: AppTextStyles.body),
                  ]),
                ))
              : _days.isEmpty
                  ? Center(child: Text('external_event_itinerary_empty'.tr))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      children: [
                        Row(children: [
                          Expanded(child: Text(widget.eventName, style: AppTextStyles.h3, maxLines: 2, overflow: TextOverflow.ellipsis)),
                          const SizedBox(width: 5),
                          EntityCertifiedBadge(entityType: 'event', entityId: widget.eventId, size: 19),
                        ]),
                        if (widget.eventLocation.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Row(children: [
                            Icon(Icons.location_on_outlined, size: 16, color: colors.onSurfaceVariant),
                            const SizedBox(width: 5),
                            Expanded(child: Text(widget.eventLocation, style: AppTextStyles.bodySmall.copyWith(color: colors.onSurfaceVariant))),
                          ]),
                        ],
                        const SizedBox(height: 8),
                        Text('external_event_itinerary_choose_day'.tr, style: AppTextStyles.bodySmall.copyWith(color: colors.onSurfaceVariant)),
                        const SizedBox(height: 16),
                        ..._days.map((entry) => _buildDateCard(context, entry)),
                      ],
                    ),
    );
  }

  Widget _buildDateCard(BuildContext context, Map<String, dynamic> entry) {
    final colors = Theme.of(context).colorScheme;
    final dateKey = (entry['planned_date'] ?? '').toString();
    final date = DateTime.tryParse(dateKey);
    final plan = _planFor(entry);
    final activities = _activitiesFor(entry);
    final start = (plan['day_start'] ?? '—').toString();
    final end = (plan['day_end'] ?? '—').toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Get.to(() => ExternalEventItineraryDayScreen(
            eventId: widget.eventId,
            eventName: widget.eventName,
            eventPhoto: widget.eventPhoto,
            eventLocation: widget.eventLocation,
            dateKey: dateKey,
            plan: plan,
            activities: activities,
            activityNames: _activityNames,
          )),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.55)),
            ),
            child: Row(children: [
              Container(
                width: 58,
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(14)),
                child: Column(children: [
                  Text(date == null ? '—' : DateFormat('dd').format(date), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                  Text(date == null ? '' : DateFormat('MMM', Get.locale?.languageCode ?? 'fr').format(date).toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                ]),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_formatDate(dateKey), style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 7),
                Row(children: [
                  Icon(Icons.schedule_rounded, size: 14, color: colors.onSurfaceVariant),
                  const SizedBox(width: 5),
                  Expanded(child: Text('$start – $end', style: AppTextStyles.bodySmall.copyWith(color: colors.onSurfaceVariant))),
                ]),
                const SizedBox(height: 5),
                Text('external_event_itinerary_activity_count'.trParams({'count': activities.length.toString()}), style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600)),
              ])),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
            ]),
          ),
        ),
      ),
    );
  }
}

class ExternalEventItineraryDayScreen extends StatelessWidget {
  final String eventId;
  final String eventName;
  final String eventPhoto;
  final String eventLocation;
  final String dateKey;
  final Map<String, dynamic> plan;
  final List<Map<String, dynamic>> activities;
  final Map<String, String> activityNames;

  const ExternalEventItineraryDayScreen({
    super.key,
    required this.eventId,
    required this.eventName,
    required this.eventPhoto,
    required this.eventLocation,
    required this.dateKey,
    required this.plan,
    required this.activities,
    required this.activityNames,
  });

  String _formatDate(String key, String pattern) {
    final date = DateTime.tryParse(key);
    return date == null ? key : DateFormat(pattern, Get.locale?.languageCode ?? 'fr').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dayStart = (plan['day_start'] ?? '—').toString();
    final dayEnd = (plan['day_end'] ?? '—').toString();
    return Scaffold(
      appBar: AppBar(title: Text(_formatDate(dateKey, 'EEE d MMM'), maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: ListView(padding: EdgeInsets.zero, children: [
        if (eventPhoto.trim().isNotEmpty)
          SizedBox(
            height: 210,
            width: double.infinity,
            child: Image.network(eventPhoto, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: colors.surfaceContainerHighest, child: const Icon(Icons.event_rounded, size: 56))),
          )
        else
          Container(height: 155, color: colors.surfaceContainerHighest, child: const Center(child: Icon(Icons.event_rounded, size: 52))),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Expanded(child: Text(eventName, style: AppTextStyles.h3, maxLines: 2, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 5),
              EntityCertifiedBadge(entityType: 'event', entityId: eventId, size: 19),
            ]),
            if (eventLocation.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(children: [
                Icon(Icons.location_on_outlined, size: 16, color: colors.onSurfaceVariant),
                const SizedBox(width: 5),
                Expanded(child: Text(eventLocation, style: AppTextStyles.bodySmall.copyWith(color: colors.onSurfaceVariant))),
              ]),
            ],
            const SizedBox(height: 20),
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Container(
                width: 42,
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(12)),
                child: Column(children: [
                  Text(_formatDate(dateKey, 'dd'), style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                  Text(_formatDate(dateKey, 'MMM').toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                ]),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_formatDate(dateKey, 'EEEE d MMMM'), style: AppTextStyles.h4),
                const SizedBox(height: 4),
                Text('${'event_itinerary_arrival'.tr} $dayStart  ·  ${'event_itinerary_departure'.tr} $dayEnd', style: AppTextStyles.bodySmall.copyWith(color: colors.onSurfaceVariant)),
              ])),
            ]),
            const SizedBox(height: 16),
            if (activities.isEmpty)
              Padding(padding: const EdgeInsets.symmetric(vertical: 18), child: Text('external_event_itinerary_none'.tr, style: AppTextStyles.bodySmall.copyWith(color: colors.onSurfaceVariant)))
            else
              ...activities.map((activity) {
                final id = (activity['activity_id'] ?? '').toString();
                final name = activityNames[id] ?? (activity['name'] ?? 'event_itinerary_activity'.tr).toString();
                final start = (activity['start_time'] ?? '—').toString();
                final end = (activity['end_time'] ?? '—').toString();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 44, child: Column(children: [
                      Container(width: 30, height: 30, decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), shape: BoxShape.circle, border: Border.all(color: AppColors.primary.withValues(alpha: 0.45))), child: const Icon(Icons.access_time_rounded, size: 16, color: AppColors.primary)),
                      Container(width: 2, height: 66, color: AppColors.primary.withValues(alpha: 0.35)),
                    ])),
                    Expanded(child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: colors.surfaceContainerLow, borderRadius: BorderRadius.circular(14), border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.45))),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(name, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Row(children: [
                          Icon(Icons.schedule_rounded, size: 13, color: colors.onSurfaceVariant),
                          const SizedBox(width: 5),
                          Expanded(child: Text('$start – $end', style: AppTextStyles.bodySmall.copyWith(color: colors.onSurfaceVariant))),
                          Text('event_itinerary_upcoming'.tr, style: AppTextStyles.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600)),
                        ]),
                      ]),
                    )),
                  ]),
                );
              }),
          ]),
        ),
      ]),
    );
  }
}
