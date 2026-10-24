import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../controllers/event_activity_controller.dart';
import '../../centre/models/activity_model.dart';

class ActivityUpdatePriceScreen extends StatefulWidget {
  final EventActivityModel eventActivity;

  const ActivityUpdatePriceScreen({
    super.key,
    required this.eventActivity,
  });

  @override
  State<ActivityUpdatePriceScreen> createState() => _ActivityUpdatePriceScreenState();
}

class _ActivityUpdatePriceScreenState extends State<ActivityUpdatePriceScreen> {
  late EventActivityModel _activity;
  late TextEditingController _priceController;
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _activity = widget.eventActivity;
    _priceController = TextEditingController(text: _activity.price.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  double get _currentEnteredPrice {
    return double.tryParse(_priceController.text.trim()) ?? _activity.price;
  }

  Future<void> _savePrice() async {
    if (_formKey.currentState?.validate() == true) {
      setState(() => _isSaving = true);
      final newPrice = double.parse(_priceController.text.trim());
      final controller = Get.find<EventActivityController>();
      try {
        await controller.updateEventActivityPrice(_activity.id, newPrice, activityId: _activity.activityId);
        if (mounted) Get.back();
      } catch (e) {
        if (mounted) setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final originalPrice = _activity.basePrice ?? _activity.price;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Modifier le prix',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _isSaving ? null : _savePrice,
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
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
          // En-tête Activité
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.edit_outlined, color: AppColors.primary, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_activity.name, style: AppTextStyles.h4),
                          const SizedBox(height: 2),
                          Text(
                            'Activité dans cet événement',
                            style: AppTextStyles.caption.copyWith(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Prix original de l\'activité :', style: AppTextStyles.bodySmall),
                    Text(
                      '${originalPrice.toStringAsFixed(originalPrice % 1 == 0 ? 0 : 2)} ${_activity.currency}',
                      style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Prix actuel dans cet événement :', style: AppTextStyles.bodySmall),
                    Text(
                      _activity.formattedEventPrice,
                      style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold, color: AppColors.primary),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Carte de variation calculée (§2)
          AnimatedBuilder(
            animation: _priceController,
            builder: (context, _) {
              final newEnteredPrice = double.tryParse(_priceController.text.trim()) ?? _activity.price;
              double pct = 0.0;
              if (originalPrice > 0) {
                pct = ((newEnteredPrice - originalPrice) / originalPrice) * 100;
              }
              final red = pct < -0.01;
              final aug = pct > 0.01;

              Color badgeBg = colors.surfaceContainerHigh;
              Color badgeFg = colors.onSurfaceVariant;
              String badgeTitle = 'Prix inchangé';
              String badgeSub = 'Le prix de l\'activité est identique à son prix original.';
              IconData badgeIcon = Icons.drag_handle_rounded;

              if (red) {
                badgeBg = AppColors.success.withValues(alpha: 0.12);
                badgeFg = AppColors.success;
                badgeTitle = 'Réduction de ${pct.abs().toStringAsFixed(0)} %';
                badgeSub = 'Le prix de cette activité a été réduit pour cet événement.';
                badgeIcon = Icons.trending_down_rounded;
              } else if (aug) {
                badgeBg = AppColors.secondary.withValues(alpha: 0.12);
                badgeFg = AppColors.secondary;
                badgeTitle = 'Augmentation de ${pct.toStringAsFixed(0)} %';
                badgeSub = 'Le prix de cette activité a été augmenté pour cet événement.';
                badgeIcon = Icons.trending_up_rounded;
              }

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: badgeFg.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(badgeIcon, color: badgeFg, size: 32),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(badgeTitle, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold, color: badgeFg)),
                          const SizedBox(height: 2),
                          Text(badgeSub, style: AppTextStyles.bodySmall.copyWith(color: colors.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 24),

          // Formulaire de saisie du nouveau prix
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Saisir le nouveau prix :', style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary)),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _priceController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Nouveau prix appliqué',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Veuillez saisir un prix';
                          }
                          final parsed = double.tryParse(value.trim());
                          if (parsed == null || parsed < 0) {
                            return 'Veuillez saisir un montant positif valide';
                          }
                          return null;
                        },
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_activity.currency, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
