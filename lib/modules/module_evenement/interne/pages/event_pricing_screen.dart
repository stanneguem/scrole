import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/widgets/scrole_bottom_sheet.dart';
import '../../centre/models/event_model.dart';
import '../../centre/repositories/event_repository.dart';

class EventPricingScreen extends StatefulWidget {
  final EventModel? event;

  const EventPricingScreen({super.key, this.event});

  @override
  State<EventPricingScreen> createState() => _EventPricingScreenState();
}

class _EventPricingScreenState extends State<EventPricingScreen> {
  late EventModel _event;
  late bool _selectedIsFree;
  bool _isSaving = false;
  bool _hasExistingTickets = false;

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
    _selectedIsFree = _event.isFree;
    _checkExistingTickets();
  }

  Future<void> _checkExistingTickets() async {
    try {
      final repo = Get.find<EventRepository>();
      final tickets = await repo.getEventTickets(_event.id);
      if (mounted) {
        setState(() {
          _hasExistingTickets = tickets.isNotEmpty;
        });
      }
    } catch (_) {}
  }

  Future<void> _savePricing() async {
    if (_isSaving) return;

    // Avertissement lors du passage de Payant à Gratuit si des billets existent
    if (!_event.isFree && _selectedIsFree && _hasExistingTickets) {
      final confirm = await _showPaidToFreeWarningSheet();
      if (!confirm) return;
    }

    setState(() => _isSaving = true);

    try {
      final repo = Get.find<EventRepository>();
      await repo.updateEventPricing(eventId: _event.id, isFree: _selectedIsFree);

      if (mounted) {
        Get.back();
        Get.snackbar(
          'Tarification mise à jour',
          _selectedIsFree
              ? 'L\'événement est désormais configuré comme gratuit.'
              : 'L\'événement est désormais configuré comme payant.',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } catch (e) {
      debugPrint('[EventPricingScreen] _savePricing error: $e');
      if (mounted) {
        Get.snackbar(
          'Erreur',
          'Impossible de mettre à jour la tarification : $e',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<bool> _showPaidToFreeWarningSheet() async {
    final result = await ScroleBottomSheet.show<bool>(
      context: context,
      showCancel: true,
      cancelLabel: 'Conserver payant',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Passer l\'événement en gratuit ?', style: AppTextStyles.h4),
                  const SizedBox(height: 8),
                  Text(
                    'Cet événement possède déjà des types de billets configurés.\n\nPasser l\'événement en gratuit désactivera la gestion des billets payants. Les billets existants ne seront pas supprimés automatiquement.',
                    style: AppTextStyles.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ScroleBottomSheetGroup(
              children: [
                ScroleBottomSheetAction(
                  icon: Icons.check_circle_outline,
                  label: 'Confirmer et passer en gratuit',
                  color: AppColors.primary,
                  onTap: () => Navigator.of(context).pop(true),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Tarification de l\'événement',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _isSaving ? null : _savePricing,
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                    )
                  : Text(
                      'Enregistrer',
                      style: GoogleFonts.spaceGrotesk(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppColors.primary,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // En-tête de l'événement
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
                  child: const Icon(Icons.payments_outlined, color: AppColors.primary, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_event.name, style: AppTextStyles.h4),
                      const SizedBox(height: 2),
                      Text(
                        'Définissez le mode d\'accès de vos participants',
                        style: AppTextStyles.caption.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Text(
            'MODE D\'ACCÈS',
            style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary, letterSpacing: 1.2),
          ),
          const SizedBox(height: 12),

          // Option Gratuit
          _PricingOptionTile(
            title: 'Gratuit',
            subtitle: 'L\'accès à l\'événement est totalement gratuit. Aucun achat de billet n\'est requis.',
            icon: Icons.money_off_rounded,
            isSelected: _selectedIsFree,
            onTap: () => setState(() => _selectedIsFree = true),
          ),
          const SizedBox(height: 12),

          // Option Payant
          _PricingOptionTile(
            title: 'Payant',
            subtitle: 'Créez des types de billets payants (VIP, Standard, etc.) avec leurs tarifs et quantités.',
            icon: Icons.confirmation_number_outlined,
            isSelected: !_selectedIsFree,
            onTap: () => setState(() => _selectedIsFree = false),
          ),
          const SizedBox(height: 24),

          // Explications sur le choix sélectionné
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _selectedIsFree
                  ? AppColors.success.withValues(alpha: 0.1)
                  : AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _selectedIsFree
                    ? AppColors.success.withValues(alpha: 0.3)
                    : AppColors.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _selectedIsFree ? Icons.check_circle_outline_rounded : Icons.confirmation_number_outlined,
                  color: _selectedIsFree ? AppColors.success : AppColors.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _selectedIsFree
                        ? 'L\'événement sera accessible gratuitement à tous les participants. La création de billets payants sera désactivée.'
                        : 'La création et la gestion de billets payants seront activées pour cet événement.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: _selectedIsFree ? AppColors.success : AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PricingOptionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _PricingOptionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected ? AppColors.primary : colors.outlineVariant.withValues(alpha: 0.3),
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary.withValues(alpha: 0.15)
                      : colors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: isSelected ? AppColors.primary : colors.onSurfaceVariant, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: AppTextStyles.bodySmall.copyWith(color: colors.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? AppColors.primary : Colors.transparent,
                  border: Border.all(
                    color: isSelected ? AppColors.primary : colors.outlineVariant,
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
