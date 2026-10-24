import 'package:flutter/material.dart';
import 'app_cached_image.dart';
import 'user_certified_badge.dart';

class UserIdentityRow extends StatelessWidget {
  final String name;
  final String username;
  final String? avatarUrl;
  final bool isCertified;
  final String? userId;
  final Color? avatarColor;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final double avatarRadius;
  final TextStyle? nameStyle;
  final TextStyle? usernameStyle;
  final Widget? prefixWidget;

  const UserIdentityRow({
    super.key,
    required this.name,
    required this.username,
    this.avatarUrl,
    this.isCertified = false,
    this.userId,
    this.avatarColor,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.avatarRadius = 18,
    this.nameStyle,
    this.usernameStyle,
    this.prefixWidget,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';

    Widget avatarWidget = CircleAvatar(
      radius: avatarRadius,
      backgroundColor: colorScheme.surfaceContainerHighest,
      backgroundImage: avatarUrl != null && avatarUrl!.isNotEmpty ? NetworkImage(avatarUrl!) : null,
      child: avatarUrl == null || avatarUrl!.isEmpty
          ? Text(
              initial,
              style: TextStyle(
                color: avatarColor ?? colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: avatarRadius * 0.75,
              ),
            )
          : null,
    );

    Widget content = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        avatarWidget,
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                runSpacing: 2,
                children: [
                  if (prefixWidget != null) ...[
                    prefixWidget!,
                    const SizedBox(width: 4),
                  ],
                  Text(
                    name,
                    style: nameStyle ?? TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (username.isNotEmpty)
                    Text(
                      username.startsWith('@') ? username : '@$username',
                      style: usernameStyle ?? TextStyle(
                        fontSize: 12.5,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (isCertified)
                    UserCertifiedBadge(size: avatarRadius * 0.8, userId: userId),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing!,
        ],
      ],
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: content,
        ),
      );
    }

    return content;
  }
}
