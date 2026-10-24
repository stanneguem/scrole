import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../shared/utils/number_formatter.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../../../../shared/widgets/entity_certified_badge.dart';
import '../../centre/models/discover_models.dart';

class CommunityListTile extends StatelessWidget {
  final CommunitySuggestion community;
  final VoidCallback onTap;

  const CommunityListTile({
    super.key,
    required this.community,
    required this.onTap,
  });

  String? _formatMembersCount(int count) {
    if (count <= 0) return null;
    final formattedNum = NumberFormatter.formatCount(count);
    if (count == 1) return 'discover_members_count_one'.trParams({'count': formattedNum});
    return 'discover_members_count_plural'.trParams({'count': formattedNum});
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final membersText = _formatMembersCount(community.membersCount);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh.withValues(alpha: isDark ? 0.4 : 0.6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Community Image / Avatar
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: community.imageUrl != null && community.imageUrl!.isNotEmpty
                    ? AppCachedImage(
                        imageUrl: community.imageUrl!,
                        width: 68,
                        height: 68,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        width: 68,
                        height: 68,
                        color: colorScheme.primary.withValues(alpha: 0.15),
                        child: Icon(
                          Icons.groups_rounded,
                          color: colorScheme.primary,
                          size: 32,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 16),

            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          community.name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      EntityCertifiedBadge(entityType: 'community', entityId: community.id, size: 16),
                    ],
                  ),
                  if (community.description != null &&
                      community.description!.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      community.description!,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (membersText != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          membersText,
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Action Button / Pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.primary,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                'discover_explore_button'.tr,
                style: TextStyle(
                  color: colorScheme.onPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
