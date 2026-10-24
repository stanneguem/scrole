import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../../app/service_global/currency_service.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/utils/number_formatter.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../../../../shared/widgets/entity_certified_badge.dart';
import '../../../module_evenement/centre/models/event_model.dart';

class EventListTile extends StatelessWidget {
  final EventModel event;
  final String? dateSubtitle;
  final VoidCallback onTap;

  const EventListTile({
    super.key,
    required this.event,
    this.dateSubtitle,
    required this.onTap,
  });

  String _formatPriceDisplay() {
    if (event.isFree || (event.price ?? 0) <= 0) {
      return 'discover_price_free'.tr;
    }
    final currency = (event.currency != null && event.currency!.isNotEmpty)
        ? event.currency!
        : (Get.isRegistered<CurrencyService>()
            ? Get.find<CurrencyService>().defaultCurrencyCode
            : 'XAF');
    return NumberFormatter.formatPrice(event.price!, currency);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final priceDisplay = _formatPriceDisplay();
    final isFree = priceDisplay == 'discover_price_free'.tr;
    final locationText = event.isOnline
        ? 'discover_location_online'.tr
        : (event.address != null && event.address!.trim().isNotEmpty
            ? event.address!.split(',').first.trim()
            : null);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: (event.coverImageUrl != null && event.coverImageUrl!.isNotEmpty)
                  ? AppCachedImage(
                      imageUrl: event.coverImageUrl!,
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      width: 60,
                      height: 60,
                      color: colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.event_rounded,
                        color: colorScheme.onSurfaceVariant,
                        size: 26,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          event.name,
                          style: AppTextStyles.labelLarge.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      EntityCertifiedBadge(entityType: 'event', entityId: event.id, size: 16),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        size: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          dateSubtitle != null && dateSubtitle!.trim().isNotEmpty
                              ? dateSubtitle!
                              : DateFormat('EEEE d MMMM · HH:mm').format(event.startsAt),
                          style: AppTextStyles.caption.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (locationText != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            locationText,
                            style: AppTextStyles.caption.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (isFree)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'discover_price_free'.tr,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.success,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                else
                  Text(
                    priceDisplay,
                    style: AppTextStyles.labelMedium.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (event.goingCount > 0) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.people_alt_rounded,
                        size: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        NumberFormatter.formatCount(event.goingCount),
                        style: AppTextStyles.caption.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
