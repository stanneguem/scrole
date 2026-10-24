import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../app/service_global/currency_service.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/utils/number_formatter.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../../centre/models/discover_models.dart';

class ActivityListTile extends StatelessWidget {
  final SearchResultItem item;
  final VoidCallback onTap;

  const ActivityListTile({
    super.key,
    required this.item,
    required this.onTap,
  });

  String _formatPriceDisplay() {
    final rawSubtitle = item.subtitle?.trim() ?? '';
    if (rawSubtitle.isEmpty ||
        rawSubtitle == '0' ||
        rawSubtitle == '0.0' ||
        rawSubtitle == '0.00' ||
        rawSubtitle.toLowerCase() == 'gratuit' ||
        rawSubtitle.toLowerCase() == 'free') {
      return 'discover_price_free'.tr;
    }

    final price = double.tryParse(rawSubtitle);
    if (price != null) {
      final currencyCode = Get.isRegistered<CurrencyService>()
          ? Get.find<CurrencyService>().defaultCurrencyCode
          : 'XAF';
      return NumberFormatter.formatPrice(price, currencyCode);
    }

    return rawSubtitle;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final priceDisplay = _formatPriceDisplay();
    final isFree = priceDisplay == 'discover_price_free'.tr;

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
              child: item.photoUrl != null && item.photoUrl!.isNotEmpty
                  ? AppCachedImage(
                      imageUrl: item.photoUrl!,
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      width: 60,
                      height: 60,
                      color: colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.extension_rounded,
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
                  Text(
                    item.title,
                    style: AppTextStyles.labelLarge.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.category_rounded,
                        size: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'discover_tag_activity'.tr,
                        style: AppTextStyles.caption.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
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
              ],
            ),
          ],
        ),
      ),
    );
  }
}
