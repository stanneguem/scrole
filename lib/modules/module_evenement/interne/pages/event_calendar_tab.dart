import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import '../../../../../app/theme/app_colors.dart';
import '../../../../../app/theme/text_styles.dart';
import '../../../../../shared/widgets/shimmer.dart';
import '../../centre/models/event_model.dart';
import '../controllers/event_controller.dart';
import '../widgets/event_bottom_sheet.dart';
import '../widgets/event_filter.dart';
import 'event_detail_page.dart';

class CalendarTab extends StatefulWidget {
  const CalendarTab({super.key});

  @override
  State<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<CalendarTab> {
  final EventController controller = Get.find<EventController>();

  DateTime _currentMonth = DateTime.now();

  void _changeMonth(int delta) {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + delta);
    });
    controller.onCalendarMonthChanged(_currentMonth);
  }

  void _onDayTap(DateTime date) {
    // On filtre les événements chargés pour ce jour spécifique
    final rawEvents = controller.calendarEvents.where((e) {
      final localDate = e.startsAt.toLocal();
      return localDate.year == date.year &&
          localDate.month == date.month &&
          localDate.day == date.day;
    }).toList();

    final events = controller.sortEventList(rawEvents);

    if (events.isEmpty) return;

    if (events.length == 1) {
      Get.to(() => EventDetailPage(event: events.first));
    } else {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => EventBottomSheet(
          date: date,
          events: events,
          onEventTap: (event) {
            Navigator.pop(context);
            Get.to(() => EventDetailPage(event: event));
          },
        ),
      );
    }
  }

  void _showSortMenu() {
    final RenderBox box = context.findRenderObject() as RenderBox;
    final offset = box.localToGlobal(Offset.zero);
    final colorScheme = Theme.of(context).colorScheme;

    showMenu<EventSortFilter>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx + box.size.width - 200,
        offset.dy + 100,
        offset.dx + box.size.width,
        offset.dy + 300,
      ),
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: EventSortFilter.values
          .map((f) => PopupMenuItem(
        value: f,
        child: Row(
          children: [
            Obx(() => Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: controller.currentSortFilter.value == f
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                  width: 2,
                ),
                color: controller.currentSortFilter.value == f
                    ? colorScheme.primary
                    : Colors.transparent,
              ),
              child: controller.currentSortFilter.value == f
                  ? const Icon(Icons.check,
                  size: 10, color: Colors.white)
                  : null,
            )),
            const SizedBox(width: 12),
            Text(
              f.label,
              style: AppTextStyles.body.copyWith(
                color: controller.currentSortFilter.value == f
                    ? colorScheme.onSurface
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ))
          .toList(),
    ).then((value) {
      if (value != null) controller.setSortFilter(value);
    });
  }

  int _getHeatLevel(List<EventModel> events) {
    if (events.isEmpty) return 0;
    final total =
    events.fold<int>(0, (s, e) => s + e.goingCount + e.interestedCount);
    if (total >= 1000) return 4;
    if (total >= 300) return 3;
    if (total >= 80) return 2;
    return 1;
  }

  BoxDecoration _getCellDecoration(
      List<EventModel> events, ColorScheme colorScheme) {
    final level = _getHeatLevel(events);
    final baseColor = colorScheme.surfaceContainerLow;

    switch (level) {
      case 0:
        return BoxDecoration(
          color: baseColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colorScheme.outline.withValues(alpha: 0.1)),
        );
      case 1:
        return BoxDecoration(
          color: baseColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
              width: 1.2),
        );
      case 2:
        return BoxDecoration(
          color: baseColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: colorScheme.primary.withValues(alpha: 0.4), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: colorScheme.primary.withValues(alpha: 0.06),
              blurRadius: 8,
              spreadRadius: 0,
            ),
          ],
        );
      case 3:
        return BoxDecoration(
          color: baseColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: colorScheme.primary.withValues(alpha: 0.7), width: 1.8),
          boxShadow: [
            BoxShadow(
              color: colorScheme.primary.withValues(alpha: 0.12),
              blurRadius: 12,
              spreadRadius: 1,
            ),
          ],
        );
      case 4:
        return BoxDecoration(
          color: baseColor,
          borderRadius: BorderRadius.circular(10),
          gradient: LinearGradient(
            colors: [
              colorScheme.primary.withValues(alpha: 0.15),
              baseColor,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: colorScheme.primary, width: 2),
          boxShadow: [
            BoxShadow(
              color: colorScheme.primary.withValues(alpha: 0.2),
              blurRadius: 16,
              spreadRadius: 2,
            ),
          ],
        );
      default:
        return BoxDecoration(
            color: baseColor, borderRadius: BorderRadius.circular(10));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final daysInMonth =
        DateTime(_currentMonth.year, _currentMonth.month + 1, 0).day;
    final firstWeekday =
        DateTime(_currentMonth.year, _currentMonth.month, 1).weekday;
    final startOffset = firstWeekday - 1;
    final prevMonthDays =
        DateTime(_currentMonth.year, _currentMonth.month, 0).day;

    final weekDays = List.generate(7, (index) {
      final date = DateTime(2024, 1, index + 1); // 1er janv 2024 est un lundi
      return DateFormat.E(Get.locale?.languageCode ?? 'fr')
          .format(date)
          .toUpperCase();
    });

    return Obx(() {
      final status = controller.calendarStatus.value;

      if (status == EventCalendarStatus.loading ||
          status == EventCalendarStatus.initial) {
        return const _CalendarTabShimmer();
      }

      if (status == EventCalendarStatus.error &&
          controller.calendarEvents.isEmpty) {
        return _CalendarErrorState(
          errorMessage: controller.calendarErrorMessage.value,
          onRetry: () =>
              controller.fetchCalendarEvents(_currentMonth, force: true),
        );
      }

      return Stack(
        children: [
          RefreshIndicator(
            color: Colors.transparent,
            backgroundColor: Colors.transparent,
            elevation: 0,
            onRefresh: () =>
                controller.fetchCalendarEvents(_currentMonth, force: true),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                children: [
                  // ===== HEADER ROW =====
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      // Month navigator
                      Flexible(
                        flex: 3,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: colorScheme.outline
                                    .withValues(alpha: 0.1)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: () => _changeMonth(-1),
                                child: Icon(Icons.chevron_left,
                                    color: colorScheme.onSurfaceVariant,
                                    size: 20),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  DateFormat('MMMM yyyy',
                                      Get.locale?.languageCode ?? 'fr')
                                      .format(_currentMonth),
                                  style: AppTextStyles.labelLarge
                                      .copyWith(color: colorScheme.onSurface),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => _changeMonth(1),
                                child: Icon(Icons.chevron_right,
                                    color: colorScheme.onSurfaceVariant,
                                    size: 20),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Sort filter dropdown
                      Flexible(
                        flex: 2,
                        child: GestureDetector(
                          onTap: _showSortMenu,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerLow,
                              border: Border.all(
                                  color: colorScheme.outline
                                      .withValues(alpha: 0.1)),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Expanded(
                                  child: Obx(() => Text(
                                    controller
                                        .currentSortFilter.value.label,
                                    style: AppTextStyles.labelMedium
                                        .copyWith(
                                        color: colorScheme.onSurface),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  )),
                                ),
                                const SizedBox(width: 4),
                                Icon(Icons.keyboard_arrow_down,
                                    color: colorScheme.onSurfaceVariant,
                                    size: 16),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // ===== WEEKDAY HEADERS =====
                  Row(
                    children: weekDays
                        .map((d) => Expanded(
                      child: Center(
                        child: Text(
                          d,
                          style: AppTextStyles.labelSmall.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ))
                        .toList(),
                  ),
                  const SizedBox(height: 8),
                  // ===== CALENDAR GRID =====
                  Obx(() {
                    // On s'assure que la grille réagit au changement de filtre de tri
                    // ignore: unused_local_variable
                    final sort = controller.currentSortFilter.value;

                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 7,
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 6,
                        childAspectRatio: 0.82,
                      ),
                      itemCount: startOffset + daysInMonth,
                      itemBuilder: (context, index) {
                        if (index < startOffset) {
                          final day = prevMonthDays - startOffset + index + 1;
                          return _EmptyDayCell(day: day);
                        }

                        final day = index - startOffset + 1;
                        final date = DateTime(
                            _currentMonth.year, _currentMonth.month, day);

                        // Filtrage local depuis le cache global du calendrier
                        final rawEvents =
                        controller.calendarEvents.where((e) {
                          final localDate = e.startsAt.toLocal();
                          return localDate.year == date.year &&
                              localDate.month == date.month &&
                              localDate.day == date.day;
                        }).toList();

                        // Application du tri
                        final events = controller.sortEventList(rawEvents);

                        return _DayCell(
                          day: day,
                          events: events,
                          decoration:
                          _getCellDecoration(events, colorScheme),
                          onTap: () => _onDayTap(date),
                        );
                      },
                    );
                  }),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: Center(
              child: Obx(() {
                if (!controller.isLoadingCalendar.value) {
                  return const SizedBox.shrink();
                }
                return Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Lottie.asset(
                    'assets/lotties/Animation - 1791582964132.json',
                    width: 44,
                    height: 44,
                  ),
                );
              }),
            ),
          ),
        ],
      );
    });
  }
}

class _DayCell extends StatelessWidget {
  final int day;
  final List<EventModel> events;
  final BoxDecoration decoration;
  final VoidCallback onTap;

  const _DayCell({
    required this.day,
    required this.events,
    required this.decoration,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final count = events.length;
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: decoration,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$day',
              style: AppTextStyles.labelLarge.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            // ===== DOTS INDICATOR =====
            if (count > 0)
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (count >= 1)
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _getEventColor(events[0]),
                      ),
                    ),
                  if (count >= 2)
                    Transform.translate(
                      offset: const Offset(-2.5, 0),
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _getEventColor(events[1]),
                          border: Border.all(
                              color: colorScheme.surfaceContainerLow,
                              width: 1.2),
                        ),
                      ),
                    ),
                  if (count >= 3)
                    Transform.translate(
                      offset: const Offset(-5, 0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          '+${count - 2}',
                          style: TextStyle(
                            fontSize: 7,
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Color _getEventColor(EventModel event) {
    final colors = [
      const Color(0xFF3B82F6), // bleu
      const Color(0xFF8B5CF6), // violet
      const Color(0xFF22C55E), // vert
      const Color(0xFFEC4899), // rose
      const Color(0xFFEAB308), // jaune
      const Color(0xFFF97316), // orange
      const Color(0xFF06B6D4), // cyan
      AppColors.primary, // couleur primaire
    ];
    return colors[event.name.hashCode.abs() % colors.length];
  }
}

class _EmptyDayCell extends StatelessWidget {
  final int day;
  const _EmptyDayCell({required this.day});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.05)),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
                painter:
                _DiagonalStripesPainter(colorScheme.surfaceContainerHighest)),
          ),
          Center(
            child: Text(
              '$day',
              style: AppTextStyles.labelLarge.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagonalStripesPainter extends CustomPainter {
  final Color color;
  _DiagonalStripesPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const spacing = 8.0;
    for (double i = -size.height; i < size.width; i += spacing) {
      canvas.drawLine(
          Offset(i, 0), Offset(i + size.height, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// =========================================
// CALENDAR LOADING
// =========================================
class _CalendarTabShimmer extends StatelessWidget {
  const _CalendarTabShimmer();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Lottie.asset(
        'assets/lotties/Animation - 1791582964132.json',
        width: 140,
        height: 140,
      ),
    );
  }
}

// =========================================
// CALENDAR ERROR STATE
// =========================================
class _CalendarErrorState extends StatelessWidget {
  final String errorMessage;
  final VoidCallback onRetry;

  const _CalendarErrorState({
    required this.errorMessage,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.event_busy_rounded,
                size: 56,
                color: colorScheme.error,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'community_error_title'.tr,
              textAlign: TextAlign.center,
              style: AppTextStyles.h3.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              errorMessage.isNotEmpty
                  ? errorMessage
                  : 'community_error_subtitle'.tr,
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(
                'wall_retry'.tr,
                style: AppTextStyles.button,
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}