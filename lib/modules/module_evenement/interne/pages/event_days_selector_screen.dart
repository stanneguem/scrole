import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:scrole/app/theme/app_colors.dart';
import 'package:scrole/app/theme/text_styles.dart';
import '../../centre/models/event_day_models.dart';
import '../../centre/repositories/event_repository.dart';

class EventDaysSelectorScreen extends StatefulWidget {
  final String eventId;
  final String eventName;
  final List<EventOpenDay> openDays;
  final List<EventPlannedDay>? preselectedDays;
  final bool isEditing;
  final VoidCallback? onSuccess;

  const EventDaysSelectorScreen({
    super.key,
    required this.eventId,
    required this.eventName,
    required this.openDays,
    this.preselectedDays,
    this.isEditing = false,
    this.onSuccess,
  });

  @override
  State<EventDaysSelectorScreen> createState() => _EventDaysSelectorScreenState();
}

class _EventDaysSelectorScreenState extends State<EventDaysSelectorScreen> {
  final Set<String> _selectedDateStrings = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.preselectedDays != null && widget.preselectedDays!.isNotEmpty) {
      for (final day in widget.preselectedDays!) {
        _selectedDateStrings.add(day.dateString);
      }
    } else {
      for (final day in widget.openDays) {
        if (day.isOpen) {
          _selectedDateStrings.add(day.dateString);
        }
      }
    }
  }

  Future<void> _submitDays() async {
    if (_selectedDateStrings.isEmpty || _isLoading) return;

    setState(() => _isLoading = true);

    try {
      final repository = Get.find<EventRepository>();
      final selectedDates = widget.openDays
          .where((day) => _selectedDateStrings.contains(day.dateString))
          .map((day) => day.date)
          .toList();

      if (widget.isEditing) {
        await repository.updateEventCalendarDays(widget.eventId, selectedDates);
      } else {
        await repository.addEventToCalendarWithDays(widget.eventId, selectedDates);
      }

      if (mounted) {
        Get.back();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.isEditing
                  ? 'event_days_updated_success'.tr
                  : 'event_added_success'.tr,
              style: AppTextStyles.bodySmall.copyWith(color: Colors.white),
            ),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        widget.onSuccess?.call();
      }
    } catch (e) {
      debugPrint('[EventDaysSelectorScreen] Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'save_error'.tr,
              style: AppTextStyles.bodySmall.copyWith(color: Colors.white),
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final Map<String, List<EventOpenDay>> daysByMonth = {};
    for (final day in widget.openDays) {
      final monthKey = DateFormat('yyyy-MM').format(day.date);
      daysByMonth.putIfAbsent(monthKey, () => []).add(day);
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          widget.isEditing ? 'edit_participation_days'.tr : 'select_participation_days'.tr,
          style: AppTextStyles.h4.copyWith(color: colorScheme.onSurface, fontSize: 18),
        ),
        backgroundColor: colorScheme.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: colorScheme.onSurface),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: (_selectedDateStrings.isNotEmpty && !_isLoading) ? _submitDays : null,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                disabledForegroundColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                    )
                  : Text(
                      'save'.tr,
                      style: AppTextStyles.body.copyWith(
                        fontWeight: FontWeight.bold,
                        color: (_selectedDateStrings.isNotEmpty && !_isLoading)
                            ? AppColors.primary
                            : colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'event_days_instruction'.tr,
              style: AppTextStyles.bodySmall.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            ...daysByMonth.entries.map((entry) {
              final monthDate = DateTime.parse('${entry.key}-01');
              final monthTitle = DateFormat('MMMM yyyy', Get.locale?.languageCode ?? 'fr').format(monthDate);
              final openDaysInMonth = entry.value;

              final firstDayOfMonth = DateTime(monthDate.year, monthDate.month, 1);
              final lastDayOfMonth = DateTime(monthDate.year, monthDate.month + 1, 0);
              final startWeekday = firstDayOfMonth.weekday;

              final Map<String, EventOpenDay> openDaysMap = {
                for (var d in openDaysInMonth) d.dateString: d
              };

              return Container(
                margin: const EdgeInsets.only(bottom: 24),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      monthTitle[0].toUpperCase() + monthTitle.substring(1),
                      style: AppTextStyles.h5.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim']
                          .map((day) => SizedBox(
                                width: 36,
                                child: Text(
                                  day,
                                  textAlign: TextAlign.center,
                                  style: AppTextStyles.caption.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 8),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 7,
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 6,
                      ),
                      itemCount: startWeekday - 1 + lastDayOfMonth.day,
                      itemBuilder: (context, index) {
                        if (index < startWeekday - 1) {
                          return const SizedBox.shrink();
                        }
                        final dayNumber = index - (startWeekday - 2);
                        final currentCellDate = DateTime(monthDate.year, monthDate.month, dayNumber);
                        final dateStr = DateFormat('yyyy-MM-dd').format(currentCellDate);
                        final openDay = openDaysMap[dateStr];
                        final isAvailable = openDay != null && openDay.isOpen;
                        final isSelected = _selectedDateStrings.contains(dateStr);

                        return GestureDetector(
                          onTap: isAvailable
                              ? () {
                                  setState(() {
                                    if (isSelected) {
                                      _selectedDateStrings.remove(dateStr);
                                    } else {
                                      _selectedDateStrings.add(dateStr);
                                    }
                                  });
                                }
                              : null,
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.primary
                                  : (isAvailable
                                      ? AppColors.primary.withValues(alpha: 0.08)
                                      : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)),
                              borderRadius: BorderRadius.circular(8),
                              border: isAvailable && !isSelected
                                  ? Border.all(color: AppColors.primary.withValues(alpha: 0.3))
                                  : null,
                            ),
                            child: Text(
                              '$dayNumber',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected || isAvailable ? FontWeight.bold : FontWeight.normal,
                                color: isSelected
                                    ? Colors.white
                                    : (isAvailable
                                        ? colorScheme.onSurface
                                        : colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
