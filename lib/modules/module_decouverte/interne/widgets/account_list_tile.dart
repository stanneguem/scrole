import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/utils/number_formatter.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../../../../shared/widgets/user_certified_badge.dart';
import '../../../../shared/widgets/relation_button_widget.dart';
import '../../centre/models/discover_models.dart';

class AccountListTile extends StatelessWidget {
  final AccountSuggestion account;
  final VoidCallback onTap;

  const AccountListTile({
    super.key,
    required this.account,
    required this.onTap,
  });

  String? _formatFriendCount(int? count) {
    if (count == null) return null;
    final formattedNum = NumberFormatter.formatCount(count);
    if (count == 0) return 'discover_friends_count_zero'.trParams({'count': formattedNum});
    if (count == 1) return 'discover_friends_count_one'.trParams({'count': formattedNum});
    return 'discover_friends_count_plural'.trParams({'count': formattedNum});
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final friendText = _formatFriendCount(account.friendCount);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: account.avatarUrl != null && account.avatarUrl!.isNotEmpty
                  ? AppCachedImage(
                      imageUrl: account.avatarUrl!,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      width: 52,
                      height: 52,
                      color: colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.person_rounded,
                        color: colorScheme.onSurfaceVariant,
                        size: 25,
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          account.displayName,
                          style: AppTextStyles.labelLarge.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (account.isVerified) ...[
                        const SizedBox(width: 4),
                        const UserCertifiedBadge(size: 15),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@${account.username}',
                    style: AppTextStyles.caption.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (account.followsMe) ...[
                    const SizedBox(height: 3),
                    Text('follow_te_follows_you'.tr, style: AppTextStyles.caption.copyWith(color: colorScheme.primary, fontWeight: FontWeight.w600)),
                  ],
                  if (friendText != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.people_alt_rounded,
                          size: 13,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          friendText,
                          style: AppTextStyles.caption.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (account.bio != null && account.bio!.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      account.bio!,
                      style: AppTextStyles.caption.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            RelationButtonWidget(targetUserId: account.id, compact: true),
            const SizedBox(width: 2),
            Icon(
              Icons.chevron_right_rounded,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
