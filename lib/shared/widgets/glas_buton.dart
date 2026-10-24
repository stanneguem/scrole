import 'package:flutter/material.dart';
import 'dart:ui';

class GlassmorphismButton extends StatelessWidget {
  final Widget icon;
  final VoidCallback? onTap;
  final double size;
  final double blur;
  final Color? backgroundColor;
  final double? badgeCount;

  const GlassmorphismButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 44,
    this.blur = 12,
    this.backgroundColor,
    this.badgeCount,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color:
                    backgroundColor ??
                    colorScheme.onSurface.withValues(alpha: 0.05),
                border: Border.all(
                  color: colorScheme.onSurface.withValues(alpha: 0.08),
                  width: 1,
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  icon,
                  if (badgeCount != null && badgeCount! > 0)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.red,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          badgeCount!.toInt().toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
