import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ScroleBottomSheet extends StatelessWidget {
  const ScroleBottomSheet({
    super.key,
    required this.child,
    this.showCancel = false,
    this.cancelLabel,
    this.onCancel,
    this.padding = const EdgeInsets.fromLTRB(8, 0, 8, 8),
  });

  final Widget child;
  final bool showCancel;
  final String? cancelLabel;
  final VoidCallback? onCancel;
  final EdgeInsetsGeometry padding;

  static Future<T?> show<T>({
    required BuildContext context,
    required Widget child,
    bool isScrollControlled = true,
    bool useSafeArea = true,
    bool showCancel = false,
    String? cancelLabel,
    VoidCallback? onCancel,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.transparent,
      elevation: 0,
      isScrollControlled: isScrollControlled,
      useSafeArea: useSafeArea,
      builder: (sheetContext) => ScroleBottomSheet(
        showCancel: showCancel,
        cancelLabel: cancelLabel,
        onCancel: onCancel,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _ScroleBottomSheetHandle(),
            child,
            if (showCancel) ...[
              const SizedBox(height: 8),
              ScroleBottomSheetAction(
                label: cancelLabel ?? 'cancel'.tr,
                onTap: onCancel ?? () => Navigator.of(context).pop(),
                color: scheme.primary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScroleBottomSheetHandle extends StatelessWidget {
  const _ScroleBottomSheetHandle();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: scheme.onSurfaceVariant.withValues(alpha: .3),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class ScroleBottomSheetGroup extends StatelessWidget {
  const ScroleBottomSheetGroup({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class ScroleBottomSheetAction extends StatelessWidget {
  const ScroleBottomSheetAction({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.subtitle,
    this.trailing,
    this.color,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final String? subtitle;
  final Widget? trailing;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final actionColor = color ?? scheme.onSurface;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: actionColor, size: 22),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: actionColor,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

class ScroleBottomSheetDivider extends StatelessWidget {
  const ScroleBottomSheetDivider({super.key});

  @override
  Widget build(BuildContext context) => Divider(
        height: 1,
        thickness: .6,
        color: Theme.of(context).colorScheme.outlineVariant,
      );
}
