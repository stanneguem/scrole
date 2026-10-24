import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/models/interest_model.dart';

class InterestChipWidget extends StatelessWidget {
  final Interest interest;
  final VoidCallback onTap;
  final bool isSelected;

  const InterestChipWidget({
    super.key,
    required this.interest,
    required this.onTap,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppColors.primary; // Pas de couleur spécifique en BD, on utilise le primaire

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.2)
              : Get.isDarkMode
              ? AppColors.surfaceDark
              : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (interest.iconUrl != null && interest.iconUrl!.isNotEmpty)
              Text(
                interest.iconUrl!,
                style: const TextStyle(fontSize: 18),
              ),
            if (interest.iconUrl != null && interest.iconUrl!.isNotEmpty)
              const SizedBox(width: 6),
            Text(
              interest.name,
              style: AppTextStyles.labelMedium.copyWith(
                color: isSelected
                    ? color
                    : Get.isDarkMode
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.check_circle,
                color: color,
                size: 16,
              ),
            ],
          ],
        ),
      ),
    );
  }
}