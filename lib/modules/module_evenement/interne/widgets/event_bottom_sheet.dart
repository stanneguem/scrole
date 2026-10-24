import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/widgets/scrole_bottom_sheet.dart';
import '../../../../shared/widgets/entity_certified_badge.dart';
import '../../centre/models/event_model.dart';

class EventBottomSheet extends StatelessWidget {
  final DateTime date;
  final List<EventModel> events;
  final Function(EventModel) onEventTap;

  const EventBottomSheet({
    super.key,
    required this.date,
    required this.events,
    required this.onEventTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ScroleBottomSheet(
      child: ScroleBottomSheetGroup(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    DateFormat('d MMMM yyyy').format(date),
                    style: AppTextStyles.h4.copyWith(color: colorScheme.onSurface),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: colorScheme.onSurfaceVariant, size: 18),
                ),
              ],
            ),
          ),
          ...events.map(
            (event) => Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: GestureDetector(
                onTap: () => onEventTap(event),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: colorScheme.outline.withValues(alpha: isDark ? 0.1 : 0.05),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(child: Text(
                                event.name,
                                style: AppTextStyles.labelLarge.copyWith(
                                  color: colorScheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              )),
                              EntityCertifiedBadge(entityType: 'event', entityId: event.id, size: 16),
                            ]),
                            const SizedBox(height: 4),
                            Text(
                              '${event.timeString ?? 'Toute la journée'} · ${event.isOnline ? 'En ligne' : (event.address?.split(',').first ?? 'Paris')}',
                              style: AppTextStyles.bodySmall.copyWith(color: colorScheme.onSurfaceVariant),
                            ),
                            if (!event.isFree) ...[
                              const SizedBox(height: 4),
                              Text(
                                '${event.price?.toStringAsFixed(2)} ${event.currency}',
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                        size: 14,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
