import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/theme/text_styles.dart';

class SheetOption<T> {
  const SheetOption({
    required this.value,
    required this.label,
    required this.icon,
    this.subtitle,
  });

  final T value;
  final String label;
  final IconData icon;
  final String? subtitle;
}

/// Champ tappable (style cohérent avec TextInputField) qui ouvre un bottom
/// sheet façon iOS (groupe arrondi, séparateurs fins, bouton Annuler
/// détaché). Les couleurs viennent de `Theme.of(context).colorScheme`,
/// donc s'adaptent automatiquement au thème clair/sombre de l'app.
class SelectableField<T> extends StatelessWidget {
  const SelectableField({
    super.key,
    required this.label,
    required this.selected,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final SheetOption<T> selected;
  final List<SheetOption<T>> options;
  final ValueChanged<T> onChanged;

  void _openSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .35),
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: scheme.onSurfaceVariant.withValues(alpha: .3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Groupe d'options, style action sheet iOS
                Container(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          label,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Divider(height: 1, thickness: .6, color: scheme.outlineVariant),
                      for (int i = 0; i < options.length; i++) ...[
                        if (i > 0)
                          Divider(height: 1, thickness: .6, color: scheme.outlineVariant),
                        _SheetRow<T>(
                          option: options[i],
                          isSelected: options[i].value == selected.value,
                          scheme: scheme,
                          onTap: () {
                            Navigator.of(ctx).pop();
                            onChanged(options[i].value);
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Bouton Annuler détaché, façon action sheet iOS
                Container(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  clipBehavior: Clip.antiAlias,
                  width: double.infinity,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => Navigator.of(ctx).pop(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: Text(
                            'cancel'.tr,
                            style: AppTextStyles.labelMedium.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.inputLabel.copyWith(color: scheme.onSurface),
        ),
        const SizedBox(height: 8),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _openSheet(context),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: .4),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Icon(selected.icon, color: scheme.primary, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      selected.label,
                      style: AppTextStyles.labelMedium.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Icon(Icons.unfold_more, color: scheme.onSurfaceVariant, size: 18),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SheetRow<T> extends StatelessWidget {
  const _SheetRow({
    required this.option,
    required this.isSelected,
    required this.scheme,
    required this.onTap,
  });

  final SheetOption<T> option;
  final bool isSelected;
  final ColorScheme scheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(
                option.icon,
                color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
                size: 22,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.label,
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: isSelected ? scheme.primary : scheme.onSurface,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    if (option.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        option.subtitle!,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (isSelected) Icon(Icons.check, color: scheme.primary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}