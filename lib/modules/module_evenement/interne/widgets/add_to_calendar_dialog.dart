import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';

enum RecurrenceOption { once, untilRemoved, thisTimeOnly }

class AddToCalendarDialog extends StatefulWidget {
  final String eventName;
  final bool isRecurring;
  final void Function({
  required bool notifyConnections,
  required bool silentAdd,
  required RecurrenceOption recurrence,
  }) onConfirm;
  final VoidCallback onCancel;

  const AddToCalendarDialog({
    super.key,
    required this.eventName,
    this.isRecurring = false,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  State<AddToCalendarDialog> createState() => _AddToCalendarDialogState();
}

class _AddToCalendarDialogState extends State<AddToCalendarDialog> {
  bool _notifyConnections = true;
  bool _silentAdd = false;
  RecurrenceOption _recurrence = RecurrenceOption.once;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.black1,
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.calendar_today, color: AppColors.primary, size: 28),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                'Ajouter à ton calendrier',
                style: AppTextStyles.h4.copyWith(color: AppColors.white),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                '"${widget.eventName}"',
                style: AppTextStyles.body.copyWith(color: AppColors.textSecondaryDark),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 20),

            // Toggle : notifier connexions
            _ToggleRow(
              icon: Icons.notifications_active_outlined,
              label: 'Notifier mes connexions',
              value: _notifyConnections && !_silentAdd,
              onChanged: _silentAdd
                  ? null
                  : (v) => setState(() => _notifyConnections = v),
            ),
            const SizedBox(height: 10),

            // Toggle : ajouter en silence
            _ToggleRow(
              icon: Icons.visibility_off_outlined,
              label: 'Ajouter en silence',
              subtitle: 'Tes connexions verront quand même sur la page',
              value: _silentAdd,
              onChanged: (v) => setState(() {
                _silentAdd = v;
                if (v) _notifyConnections = false;
              }),
            ),
            const SizedBox(height: 16),

            // Info : notifications changements
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.blue.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.blue.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: AppColors.blue, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Scrol te notifiera si la date, le lieu ou les infos changent.',
                      style: AppTextStyles.caption.copyWith(color: AppColors.blue),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Récurrence (si event récurrent)
            if (widget.isRecurring) ...[
              Text(
                'Récurrence',
                style: AppTextStyles.labelLarge.copyWith(color: AppColors.white),
              ),
              const SizedBox(height: 10),
              _RecurrenceOptionTile(
                label: 'Une seule fois',
                subtitle: 'Jusqu\'à ce que l\'event soit supprimé',
                isSelected: _recurrence == RecurrenceOption.once,
                onTap: () => setState(() => _recurrence = RecurrenceOption.once),
              ),
              const SizedBox(height: 6),
              _RecurrenceOptionTile(
                label: 'Juste cette fois',
                subtitle: 'Seulement cette date',
                isSelected: _recurrence == RecurrenceOption.thisTimeOnly,
                onTap: () => setState(() => _recurrence = RecurrenceOption.thisTimeOnly),
              ),
              const SizedBox(height: 16),
            ],

            // Boutons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onCancel,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondaryDark,
                      side: BorderSide(color: AppColors.textSecondaryDark.withOpacity(0.3)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Annuler', style: AppTextStyles.buttonSmall),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      widget.onConfirm(
                        notifyConnections: _notifyConnections,
                        silentAdd: _silentAdd,
                        recurrence: _recurrence,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Confirmer', style: AppTextStyles.buttonSmall),
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

class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _ToggleRow({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.value,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onChanged != null ? () => onChanged!(!value) : null,
      child: Opacity(
        opacity: onChanged != null ? 1 : 0.5,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.backgroundDark,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.textSecondaryDark, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppTextStyles.body.copyWith(color: AppColors.white),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: AppTextStyles.caption.copyWith(color: AppColors.textSecondaryDark),
                      ),
                    ],
                  ],
                ),
              ),
              Switch(
                value: value,
                onChanged: onChanged,
                activeColor: AppColors.primary,
                activeTrackColor: AppColors.primary.withOpacity(0.35),
                inactiveTrackColor: AppColors.textSecondaryDark.withOpacity(0.2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecurrenceOptionTile extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  const _RecurrenceOptionTile({
    required this.label,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(0.12)
              : AppColors.backgroundDark,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? AppColors.primary.withOpacity(0.4)
                : const Color(0xFF2A2D34),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.textSecondaryDark,
                  width: 2,
                ),
                color: isSelected ? AppColors.primary : Colors.transparent,
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 10, color: AppColors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTextStyles.body.copyWith(
                      color: isSelected ? AppColors.white : AppColors.textSecondaryDark,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: AppTextStyles.caption.copyWith(color: AppColors.textSecondaryDark),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}