import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/repository_global/centre_interets_repository.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/models/interest_model.dart';
import '../../../module_activite/interne/widgets/interest_chip_widget.dart';
import '../../../module_profil/interne/pages/interest_selection_screen.dart';
import '../../centre/models/event_model.dart';
import '../../centre/repositories/event_repository.dart';

class EventInterestsScreen extends StatefulWidget {
  final EventModel? event;

  const EventInterestsScreen({super.key, this.event});

  @override
  State<EventInterestsScreen> createState() => _EventInterestsScreenState();
}

class _EventInterestsScreenState extends State<EventInterestsScreen> {
  late EventModel _event;
  List<Interest> _allInterests = [];
  List<Interest> _selectedInterests = [];
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final args = widget.event ?? Get.arguments;
    if (args is EventModel) {
      _event = args;
    } else {
      _event = EventModel(
        id: Get.parameters['id'] ?? '',
        creatorId: '',
        name: 'Événement',
        slug: '',
        startsAt: DateTime.now(),
        createdAt: DateTime.now(),
      );
    }
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final interestRepo = InterestRepository(Supabase.instance.client);
      final eventRepo = Get.find<EventRepository>();

      final all = await interestRepo.getInterests();
      final selected = await eventRepo.getEventInterests(_event.id);

      if (mounted) {
        setState(() {
          _allInterests = all;
          _selectedInterests = selected;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[EventInterestsScreen] _loadData error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openInterestSelection() async {
    final selectedIds = _selectedInterests.map((e) => e.id).toList();

    final result = await Get.to<List<String>>(
      () => const InterestSelectionScreen(),
      arguments: {
        'allInterests': _allInterests,
        'selectedIds': selectedIds,
        'maxSelection': 0,
      },
    );

    if (result != null) {
      _saveInterests(result);
    }
  }

  Future<void> _saveInterests(List<String> newSelectedIds) async {
    setState(() => _isSaving = true);

    try {
      final repo = Get.find<EventRepository>();
      await repo.updateEventInterests(eventId: _event.id, interestIds: newSelectedIds);

      final updatedSelected = _allInterests.where((i) => newSelectedIds.contains(i.id)).toList();

      if (mounted) {
        setState(() {
          _selectedInterests = updatedSelected;
          _isSaving = false;
        });
        Get.snackbar(
          'Centres d\'intérêt',
          'Centres d\'intérêt enregistrés avec succès !',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } catch (e) {
      debugPrint('[EventInterestsScreen] _saveInterests error: $e');
      if (mounted) {
        setState(() => _isSaving = false);
        Get.snackbar(
          'Erreur',
          'Impossible d\'enregistrer les centres d\'intérêt : $e',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Centres d\'intérêt',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _isSaving ? null : _openInterestSelection,
              child: const Text(
                'Modifier',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // En-tête événement
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.interests_rounded, color: AppColors.primary, size: 28),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_event.name, style: AppTextStyles.h4),
                            const SizedBox(height: 2),
                            Text(
                              'Aidez les participants à découvrir votre événement en sélectionnant ses thématiques et passions.',
                              style: AppTextStyles.caption.copyWith(color: colors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'CENTRES D\'INTÉRÊT SÉLECTIONNÉS',
                      style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary, letterSpacing: 1.2),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_selectedInterests.length} sélectionné${_selectedInterests.length > 1 ? 's' : ''}',
                        style: AppTextStyles.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                if (_selectedInterests.isEmpty) ...[
                  InkWell(
                    onTap: _isSaving ? null : _openInterestSelection,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.2)),
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.interests_outlined, size: 48, color: AppColors.disabled),
                          const SizedBox(height: 16),
                          Text(
                            'Aucun centre d\'intérêt sélectionné',
                            style: AppTextStyles.h4,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Appuyez ici ou sur « Modifier » en haut à droite pour ajouter des centres d\'intérêt.',
                            style: AppTextStyles.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  InkWell(
                    onTap: _isSaving ? null : _openInterestSelection,
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 10,
                        children: _selectedInterests.map((interest) {
                          return InterestChipWidget(
                            interest: interest,
                            isSelected: true,
                            onTap: _openInterestSelection,
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
