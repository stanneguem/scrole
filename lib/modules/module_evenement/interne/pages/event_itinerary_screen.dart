import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../centre/models/activity_model.dart';
import '../../centre/models/event_day_models.dart';
import '../../centre/models/event_model.dart';
import '../../centre/repositories/event_repository.dart';

class EventItineraryScreen extends StatefulWidget {
  final EventModel event;

  const EventItineraryScreen({super.key, required this.event});

  @override
  State<EventItineraryScreen> createState() => _EventItineraryScreenState();
}

class _EventItineraryScreenState extends State<EventItineraryScreen> {
  final EventRepository _repository = Get.find<EventRepository>();
  bool _loading = true;
  bool _saving = false;
  List<DateTime> _days = [];
  List<EventActivityModel> _activities = [];
  int _selectedDayIndex = 0;
  final Map<String, _DayPlan> _plans = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _dateKey(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  Future<void> _load() async {
    try {
      final selectedDays = await _repository.getMyEventCalendarDays(widget.event.id);
      final days = selectedDays.map((d) => DateTime(d.date.year, d.date.month, d.date.day)).toList()
        ..sort((a, b) => a.compareTo(b));
      if (days.isEmpty) {
        final start = widget.event.startsAt;
        days.add(DateTime(start.year, start.month, start.day));
      }
      final activities = (await _repository.getEventActivities(widget.event.id))
          .where((a) => a.status.toLowerCase() == 'validee' || a.status.toLowerCase() == 'validated' || a.status.toLowerCase() == 'active')
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      final storedPlans = await _repository.getMyEventItineraryPlans(widget.event.id);
      if (!mounted) return;
      setState(() {
        _days = days;
        _activities = activities;
        for (final day in days) {
          final key = _dateKey(day);
          final saved = storedPlans[key];
          _plans[key] = _DayPlan.fromJson(saved);
        }
        _loading = false;
      });
    } catch (error) {
      debugPrint('[EventItineraryScreen] load failed: $error');
      if (mounted) setState(() => _loading = false);
      Get.snackbar('event_itinerary_title'.tr, 'event_itinerary_load_error'.tr);
    }
  }

  _DayPlan _currentPlan() => _plans[_dateKey(_days[_selectedDayIndex])]!;

  Future<void> _pickTime({required String title, required String initial, required ValueChanged<String> onPicked}) async {
    final parts = initial.split(':');
    final initialTime = TimeOfDay(hour: int.tryParse(parts.first) ?? 9, minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0);
    final picked = await showTimePicker(context: context, initialTime: initialTime, helpText: title);
    if (picked != null && mounted) {
      onPicked('${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
    }
  }

  Future<void> _save() async {
    if (_saving || _days.isEmpty) return;
    setState(() => _saving = true);
    try {
      for (final day in _days) {
        final key = _dateKey(day);
        await _repository.saveMyEventItineraryPlan(
          eventId: widget.event.id,
          plannedDate: key,
          plan: _plans[key]!.toJson(),
        );
      }
      if (mounted) {
        Get.snackbar('event_itinerary_saved_title'.tr, 'event_itinerary_saved_message'.tr, snackPosition: SnackPosition.BOTTOM);
      }
    } catch (error) {
      debugPrint('[EventItineraryScreen] save failed: $error');
      if (mounted) {
        Get.snackbar('error'.tr, 'event_itinerary_save_error'.tr, snackPosition: SnackPosition.BOTTOM);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('event_itinerary_edit'.tr, style: AppTextStyles.h4.copyWith(fontSize: 18)),
        actions: [
          TextButton(
            onPressed: _loading || _saving || _days.isEmpty ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('event_itinerary_save'.tr, style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _days.isEmpty
              ? Center(child: Text('event_itinerary_no_day'.tr))
              : _activities.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.event_busy_rounded, size: 52, color: AppColors.primary),
                            const SizedBox(height: 16),
                            Text('event_itinerary_no_activities_title'.tr, style: AppTextStyles.h4, textAlign: TextAlign.center),
                            const SizedBox(height: 8),
                            Text('event_itinerary_no_activities_hint'.tr, style: AppTextStyles.bodySmall, textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          color: colors.surface,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(widget.event.name, style: AppTextStyles.h5.copyWith(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text('event_itinerary_choose_hint'.tr, style: AppTextStyles.bodySmall.copyWith(color: colors.onSurfaceVariant)),
                              const SizedBox(height: 14),
                              SizedBox(
                                height: 42,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _days.length,
                                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                                  itemBuilder: (context, index) {
                                    final day = _days[index];
                                    final selected = index == _selectedDayIndex;
                                    return ChoiceChip(
                                      selected: selected,
                                      label: Text(DateFormat('EEE d MMM', Get.locale?.languageCode ?? 'fr').format(day)),
                                      onSelected: (_) => setState(() => _selectedDayIndex = index),
                                      selectedColor: AppColors.primary,
                                      labelStyle: TextStyle(color: selected ? Colors.white : colors.onSurface, fontWeight: FontWeight.w600),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              Text('event_itinerary_my_times'.tr, style: AppTextStyles.h5.copyWith(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(child: _timeCard('event_itinerary_day_start'.tr, _currentPlan().dayStart, Icons.wb_sunny_outlined, (value) => setState(() => _currentPlan().dayStart = value), 'event_itinerary_choose_start'.tr)),
                                  const SizedBox(width: 10),
                                  Expanded(child: _timeCard('event_itinerary_day_end'.tr, _currentPlan().dayEnd, Icons.nightlight_outlined, (value) => setState(() => _currentPlan().dayEnd = value), 'event_itinerary_choose_end'.tr)),
                                ],
                              ),
                              const SizedBox(height: 22),
                              Row(
                                children: [
                                  Expanded(child: Text('event_itinerary_proposed_activities'.tr, style: AppTextStyles.h5.copyWith(fontWeight: FontWeight.bold))),
                                  Text('event_itinerary_selected_count'.trParams({'count': _currentPlan().activities.length.toString()}), style: AppTextStyles.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ..._activities.map((activity) => _activityCard(activity, colors)),
                              const SizedBox(height: 90),
                            ],
                          ),
                        ),
                      ],
                    ),
    );
  }

  Widget _timeCard(String title, String value, IconData icon, ValueChanged<String> onChanged, String helpText) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _pickTime(title: helpText, initial: value, onPicked: onChanged),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: colors.surfaceContainerLow, borderRadius: BorderRadius.circular(14), border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.5))),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: AppTextStyles.caption.copyWith(color: colors.onSurfaceVariant)),
              const SizedBox(height: 3),
              Text(value, style: AppTextStyles.h5.copyWith(fontWeight: FontWeight.bold)),
            ])),
          ],
        ),
      ),
    );
  }

  Widget _activityCard(EventActivityModel activity, ColorScheme colors) {
    final plan = _currentPlan();
    final key = activity.activityId.isNotEmpty ? activity.activityId : activity.id;
    final selected = plan.activities.containsKey(key);
    final activityPlan = plan.activities[key] ?? _ActivityPlan();
    final borderColor = selected ? AppColors.primary : colors.outlineVariant.withValues(alpha: 0.55);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: selected ? AppColors.primary.withValues(alpha: 0.055) : colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: selected ? 1.5 : 1),
        boxShadow: selected
            ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => setState(() {
            if (selected) {
              plan.activities.remove(key);
            } else {
              plan.activities.putIfAbsent(key, () => _ActivityPlan());
            }
          }),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: selected ? AppColors.primary : colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: selected ? AppColors.primary : colors.outlineVariant),
                      ),
                      child: Icon(
                        selected ? Icons.check_rounded : Icons.add_rounded,
                        size: 19,
                        color: selected ? Colors.white : colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(activity.name, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                              decoration: BoxDecoration(
                                color: colors.surfaceContainerHighest.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                activity.formattedEventPrice,
                                style: AppTextStyles.caption.copyWith(color: colors.onSurfaceVariant, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (selected)
                      const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 21),
                  ],
                ),
                if (selected) ...[
                  const SizedBox(height: 14),
                  Divider(height: 1, color: colors.outlineVariant.withValues(alpha: 0.6)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.schedule_rounded, size: 16, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'event_itinerary_activity_hours'.tr,
                          style: AppTextStyles.caption.copyWith(color: colors.onSurfaceVariant, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _smallTimeButton('event_itinerary_start'.tr, activityPlan.start, (v) => setState(() => activityPlan.start = v))),
                      const SizedBox(width: 10),
                      Expanded(child: _smallTimeButton('event_itinerary_end'.tr, activityPlan.end, (v) => setState(() => activityPlan.end = v))),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _smallTimeButton(String label, String value, ValueChanged<String> onChanged) {
    return OutlinedButton(
      onPressed: () => _pickTime(title: 'event_itinerary_activity_time'.trParams({'label': label}), initial: value, onPicked: onChanged),
      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11), visualDensity: VisualDensity.compact, side: BorderSide(color: AppColors.primary.withValues(alpha: 0.3)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.access_time_rounded, size: 14, color: AppColors.primary), const SizedBox(width: 5), Flexible(child: Text('$label · $value', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600)))]),
    );
  }
}

class _DayPlan {
  String dayStart;
  String dayEnd;
  final Map<String, _ActivityPlan> activities;

  _DayPlan({this.dayStart = '09:00', this.dayEnd = '18:00', Map<String, _ActivityPlan>? activities})
      : activities = activities ?? {};

  factory _DayPlan.fromJson(Map<String, dynamic>? json) {
    if (json == null) return _DayPlan();
    final rawActivities = json['activities'];
    final activities = <String, _ActivityPlan>{};
    if (rawActivities is List) {
      for (final item in rawActivities.whereType<Map>()) {
        final map = Map<String, dynamic>.from(item);
        final id = (map['activity_id'] ?? '').toString();
        if (id.isNotEmpty) {
          activities[id] = _ActivityPlan(
            start: (map['start_time'] ?? '09:00').toString(),
            end: (map['end_time'] ?? '10:00').toString(),
          );
        }
      }
    }
    return _DayPlan(
      dayStart: (json['day_start'] ?? '09:00').toString(),
      dayEnd: (json['day_end'] ?? '18:00').toString(),
      activities: activities,
    );
  }

  Map<String, dynamic> toJson() => {
        'day_start': dayStart,
        'day_end': dayEnd,
        'activities': activities.entries.map((entry) => {
              'activity_id': entry.key,
              'start_time': entry.value.start,
              'end_time': entry.value.end,
            }).toList(),
      };
}

class _ActivityPlan {
  String start;
  String end;
  _ActivityPlan({this.start = '09:00', this.end = '10:00'});
}
