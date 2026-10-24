import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:scrole/app/theme/app_colors.dart';
import 'package:scrole/app/theme/text_styles.dart';
import 'package:scrole/shared/widgets/scrole_bottom_sheet.dart';
import '../../centre/models/event_day_models.dart';
import '../../centre/repositories/event_repository.dart';

/// Modal de sélection des jours de participation à un événement multi-jours.
class EventDaysSelectorSheet extends StatefulWidget {
  final String eventId;
  final String eventName;
  final List<EventOpenDay> openDays;
  final List<EventPlannedDay>? preselectedDays;
  final bool isEditing;
  final VoidCallback? onSuccess;

  const EventDaysSelectorSheet({
    super.key,
    required this.eventId,
    required this.eventName,
    required this.openDays,
    this.preselectedDays,
    this.isEditing = false,
    this.onSuccess,
  });

  @override
  State<EventDaysSelectorSheet> createState() => _EventDaysSelectorSheetState();
}

class _EventDaysSelectorSheetState extends State<EventDaysSelectorSheet> {
  final Set<String> _selectedDateStrings = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.preselectedDays != null && widget.preselectedDays!.isNotEmpty) {
      for (final day in widget.preselectedDays!) {
        _selectedDateStrings.add(day.dateString);
      }
    } else {
      for (final day in widget.openDays) {
        if (day.isOpen) {
          _selectedDateStrings.add(day.dateString);
        }
      }
    }
  }

  Future<void> _submitDays() async {
    if (_selectedDateStrings.isEmpty || _isLoading) return;

    setState(() => _isLoading = true);

    try {
      final repository = Get.find<EventRepository>();
      final selectedDates = widget.openDays
          .where((day) => _selectedDateStrings.contains(day.dateString))
          .map((day) => day.date)
          .toList();

      if (widget.isEditing) {
        await repository.updateEventCalendarDays(widget.eventId, selectedDates);
      } else {
        await repository.addEventToCalendarWithDays(widget.eventId, selectedDates);
      }

      if (mounted) {
        Get.back();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.isEditing
                  ? 'Vos jours de participation ont été mis à jour.'
                  : 'Événement ajouté à votre agenda !',
              style: AppTextStyles.bodySmall.copyWith(color: Colors.white),
            ),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        widget.onSuccess?.call();
      }
    } catch (e) {
      debugPrint('[EventDaysSelectorSheet] Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erreur lors de la sauvegarde. Veuillez réessayer.',
              style: AppTextStyles.bodySmall.copyWith(color: Colors.white),
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ScroleBottomSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  widget.isEditing ? 'Modifier mes jours' : 'Quels jours comptes-tu participer ?',
                  style: AppTextStyles.h4.copyWith(color: colorScheme.onSurface),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                onPressed: () => Get.back(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Sélectionne les jours où tu prévois de participer à cet événement.',
            style: AppTextStyles.bodySmall.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),

          // Liste des jours ouverts avec Checkbox
          Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: widget.openDays.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
              itemBuilder: (context, index) {
                final openDay = widget.openDays[index];
                final dateStr = openDay.dateString;
                final isSelected = _selectedDateStrings.contains(dateStr);
                final formattedDate = DateFormat('EEEE d MMMM yyyy', 'fr_FR').format(openDay.date);

                return CheckboxListTile(
                  value: isSelected,
                  title: Text(
                    formattedDate[0].toUpperCase() + formattedDate.substring(1),
                    style: AppTextStyles.body.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  activeColor: AppColors.primary,
                  checkboxShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  onChanged: openDay.isOpen
                      ? (checked) {
                          setState(() {
                            if (checked == true) {
                              _selectedDateStrings.add(dateStr);
                            } else {
                              _selectedDateStrings.remove(dateStr);
                            }
                          });
                        }
                      : null,
                );
              },
            ),
          ),
          const SizedBox(height: 24),

          // Bouton d'action
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_selectedDateStrings.isNotEmpty && !_isLoading) ? _submitDays : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(widget.isEditing ? 'Enregistrer mes jours' : 'Ajouter à mon agenda'),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
