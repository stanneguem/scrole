import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:scrole/app/theme/app_colors.dart';
import 'package:scrole/app/theme/text_styles.dart';
import '../../centre/models/event_model.dart';
import '../../centre/repositories/event_repository.dart';

/// Écran de gestion des jours ouverts de l'événement par le créateur/gestionnaire.
class EventOpenDaysScreen extends StatefulWidget {
  final EventModel event;

  const EventOpenDaysScreen({
    super.key,
    required this.event,
  });

  @override
  State<EventOpenDaysScreen> createState() => _EventOpenDaysScreenState();
}

class _EventOpenDaysScreenState extends State<EventOpenDaysScreen> {
  final EventRepository _repository = Get.find<EventRepository>();

  List<DateTime> _allEventDates = [];
  Set<String> _openDateStrings = {};
  Map<String, int> _attendanceMap = {};

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _generateAllDates();
    _loadOpenDaysData();
  }

  void _generateAllDates() {
    final start = DateTime(widget.event.startsAt.year, widget.event.startsAt.month, widget.event.startsAt.day);
    final end = widget.event.endsAt != null
        ? DateTime(widget.event.endsAt!.year, widget.event.endsAt!.month, widget.event.endsAt!.day)
        : start;

    List<DateTime> dates = [];
    DateTime current = start;
    while (!current.isAfter(end)) {
      dates.add(current);
      current = current.add(const Duration(days: 1));
    }
    _allEventDates = dates;
  }

  Future<void> _loadOpenDaysData() async {
    setState(() => _isLoading = true);

    try {
      final openDays = await _repository.getEventOpenDays(widget.event.id);
      final attendanceList = await _repository.getEventDayAttendance(widget.event.id);

      final openSet = <String>{};
      for (final day in openDays) {
        if (day.isOpen) {
          openSet.add(day.dateString);
        }
      }

      final attendanceMap = <String, int>{};
      for (final att in attendanceList) {
        attendanceMap[att.dateString] = att.plannedAttendees;
      }

      if (mounted) {
        setState(() {
          _openDateStrings = openSet;
          _attendanceMap = attendanceMap;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[EventOpenDaysScreen] Error loading data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveOpenDays() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);

    try {
      final selectedDates = _allEventDates
          .where((date) => _openDateStrings.contains(DateFormat('yyyy-MM-dd').format(date)))
          .toList();

      await _repository.setEventOpenDays(widget.event.id, selectedDates);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Jours ouverts mis à jour avec succès !',
              style: AppTextStyles.bodySmall.copyWith(color: Colors.white),
            ),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        Get.back();
      }
    } catch (e) {
      debugPrint('[EventOpenDaysScreen] Save Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erreur lors de la mise à jour des jours ouverts.',
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
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: colorScheme.onSurface),
        title: Text(
          'Jours ouverts',
          style: AppTextStyles.h4.copyWith(color: colorScheme.onSurface),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Configuration des jours de l\'événement',
                    style: AppTextStyles.h5.copyWith(color: colorScheme.onSurface),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Définissez les jours où votre événement accueillera du public. Les participants pourront choisir leurs jours de présence parmi ceux activés ci-dessous.',
                    style: AppTextStyles.bodySmall.copyWith(color: colorScheme.onSurfaceVariant, height: 1.4),
                  ),
                  const SizedBox(height: 20),

                  // Liste de tous les jours avec Switch & Stat de présence
                  Container(
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _allEventDates.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                      ),
                      itemBuilder: (context, index) {
                        final date = _allEventDates[index];
                        final dateStr = DateFormat('yyyy-MM-dd').format(date);
                        final isOpen = _openDateStrings.contains(dateStr);
                        final attendees = _attendanceMap[dateStr] ?? 0;
                        final formattedDate = DateFormat('EEEE d MMMM yyyy', 'fr_FR').format(date);

                        return SwitchListTile(
                          value: isOpen,
                          activeColor: AppColors.primary,
                          title: Text(
                            formattedDate[0].toUpperCase() + formattedDate.substring(1),
                            style: AppTextStyles.body.copyWith(
                              color: colorScheme.onSurface,
                              fontWeight: isOpen ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          subtitle: attendees > 0
                              ? Text(
                                  '$attendees personne${attendees > 1 ? 's' : ''} prévue${attendees > 1 ? 's' : ''}',
                                  style: AppTextStyles.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
                                )
                              : null,
                          onChanged: (value) {
                            setState(() {
                              if (value) {
                                _openDateStrings.add(dateStr);
                              } else {
                                _openDateStrings.remove(dateStr);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Bouton d'enregistrement
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveOpenDays,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Enregistrer les jours ouverts'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
