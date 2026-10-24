import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/widgets/scrole_bottom_sheet.dart';
import '../../centre/models/event_model.dart';
import '../../centre/repositories/event_repository.dart';
import '../enums/event_enum.dart';

class EventVisibilityScreen extends StatefulWidget {
  const EventVisibilityScreen({super.key});

  @override
  State<EventVisibilityScreen> createState() => _EventVisibilityScreenState();
}

class _EventVisibilityScreenState extends State<EventVisibilityScreen> {
  late final EventModel _event;
  late final EventRepository _repository;

  bool isPublic = true;
  int? minAge;
  int? maxAge;
  String allowedGender = 'Hommes et femmes';
  bool requireIdentity = false;
  bool allowAlcohol = false;
  bool isNightEvent = false;
  bool allowTobacco = false;
  final TextEditingController otherRestrictionsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _repository = Get.find<EventRepository>();
    final args = Get.arguments;
    if (args is EventModel) {
      _event = args;
    } else if (args is Map && args['event'] is EventModel) {
      _event = args['event'] as EventModel;
    } else {
      _event = EventModel(
        id: (Get.parameters['id'] ?? ''),
        creatorId: '',
        name: 'Événement',
        slug: '',
        startsAt: DateTime.now(),
        createdAt: DateTime.now(),
      );
    }

    isPublic = _event.visibility != EventVisibility.private;
    _loadExistingRestrictions();
  }

  @override
  void dispose() {
    otherRestrictionsController.dispose();
    super.dispose();
  }

  Future<void> _loadExistingRestrictions() async {
    try {
      final preview = await _repository.getEventPreviewOwner(_event.id);
      final r = preview.restrictions;
      if (mounted) {
        setState(() {
          minAge = r.minAge;
          maxAge = r.maxAge;
          if (r.allowedGenders.length == 1) {
            if (r.allowedGenders.first.toLowerCase() == 'homme') {
              allowedGender = 'Hommes uniquement';
            } else if (r.allowedGenders.first.toLowerCase() == 'femme') {
              allowedGender = 'Femmes uniquement';
            } else {
              allowedGender = 'Hommes et femmes';
            }
          } else {
            allowedGender = 'Hommes et femmes';
          }
          requireIdentity = r.idRequired;
          allowAlcohol = r.servesAlcohol;
          isNightEvent = r.overnightEvent;
          allowTobacco = r.smokingAllowed;
          if (r.otherRestrictions != null) {
            otherRestrictionsController.text = r.otherRestrictions!;
          }
        });
      }
    } catch (_) {}
  }

  void _saveRestrictions() {
    if (minAge != null && minAge! < 0) {
      Get.snackbar('Validation d\'âge', 'L\'âge minimum ne peut pas être négatif.',
          backgroundColor: Colors.red, colorText: Colors.white);
      return;
    }
    if (maxAge != null && maxAge! < 0) {
      Get.snackbar('Validation d\'âge', 'L\'âge maximum ne peut pas être négatif.',
          backgroundColor: Colors.red, colorText: Colors.white);
      return;
    }
    if (minAge != null && maxAge != null && minAge! > maxAge!) {
      Get.snackbar('Validation d\'âge', 'L\'âge minimum doit être inférieur ou égal à l\'âge maximum.',
          backgroundColor: Colors.red, colorText: Colors.white);
      return;
    }

    List<String> genders = ['homme', 'femme'];
    if (allowedGender == 'Hommes uniquement') {
      genders = ['homme'];
    } else if (allowedGender == 'Femmes uniquement') {
      genders = ['femme'];
    }

    // Sauvegarde optimiste immédiate & Envoi backend en arrière-plan
    _repository.setEventRestrictions(
      eventId: _event.id,
      minAge: minAge,
      maxAge: maxAge,
      allowedGenders: genders,
      idRequired: requireIdentity,
      servesAlcohol: allowAlcohol,
      overnightEvent: isNightEvent,
      smokingAllowed: allowTobacco,
      otherRestrictions: otherRestrictionsController.text.trim(),
      isPublic: isPublic,
    );

    // FERMETURE IMMÉDIATE DE L'ÉCRAN
    Get.back();
    Get.snackbar(
      'Enregistrement en cours…',
      'Les conditions d\'accès et la visibilité ont été enregistrées localement.',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 3),
    );
  }

  void _showMinAgePicker() {
    ScroleBottomSheet.show(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Âge minimum', style: AppTextStyles.h4),
          ),
          ScroleBottomSheetGroup(
            children: [
              ScroleBottomSheetAction(
                label: 'Aucune restriction',
                onTap: () {
                  setState(() => minAge = null);
                  Get.back();
                },
              ),
              const ScroleBottomSheetDivider(),
              ...[16, 18, 21].map((age) => Column(
                    children: [
                      ScroleBottomSheetAction(
                        label: '$age ans',
                        onTap: () {
                          setState(() => minAge = age);
                          Get.back();
                        },
                      ),
                      const ScroleBottomSheetDivider(),
                    ],
                  )),
              ScroleBottomSheetAction(
                label: 'Saisir un âge précis...',
                onTap: () {
                  Get.back();
                  _showCustomAgeDialog('Âge minimum', (val) => setState(() => minAge = val));
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showMaxAgePicker() {
    ScroleBottomSheet.show(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Âge maximum', style: AppTextStyles.h4),
          ),
          ScroleBottomSheetGroup(
            children: [
              ScroleBottomSheetAction(
                label: 'Aucune restriction',
                onTap: () {
                  setState(() => maxAge = null);
                  Get.back();
                },
              ),
              const ScroleBottomSheetDivider(),
              ...[25, 35, 50, 60].map((age) => Column(
                    children: [
                      ScroleBottomSheetAction(
                        label: '$age ans',
                        onTap: () {
                          setState(() => maxAge = age);
                          Get.back();
                        },
                      ),
                      const ScroleBottomSheetDivider(),
                    ],
                  )),
              ScroleBottomSheetAction(
                label: 'Saisir un âge précis...',
                onTap: () {
                  Get.back();
                  _showCustomAgeDialog('Âge maximum', (val) => setState(() => maxAge = val));
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showCustomAgeDialog(String title, ValueChanged<int?> onSelected) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: 'Ex: 25',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              final parsed = int.tryParse(controller.text.trim());
              onSelected(parsed);
              Navigator.of(ctx).pop();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Valider'),
          ),
        ],
      ),
    );
  }

  void _showGenderPicker() {
    ScroleBottomSheet.show(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Personnes autorisées', style: AppTextStyles.h4),
          ),
          ScroleBottomSheetGroup(
            children: [
              ScroleBottomSheetAction(
                label: 'Hommes et femmes',
                onTap: () {
                  setState(() => allowedGender = 'Hommes et femmes');
                  Get.back();
                },
              ),
              const ScroleBottomSheetDivider(),
              ScroleBottomSheetAction(
                label: 'Hommes uniquement',
                onTap: () {
                  setState(() => allowedGender = 'Hommes uniquement');
                  Get.back();
                },
              ),
              const ScroleBottomSheetDivider(),
              ScroleBottomSheetAction(
                label: 'Femmes uniquement',
                onTap: () {
                  setState(() => allowedGender = 'Femmes uniquement');
                  Get.back();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showVisibilityPicker() {
    ScroleBottomSheet.show(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Visibilité de l\'événement', style: AppTextStyles.h4),
          ),
          ScroleBottomSheetGroup(
            children: [
              ScroleBottomSheetAction(
                icon: Icons.public_rounded,
                label: 'Public',
                subtitle: 'Visible sur Scrole par tout le monde',
                onTap: () {
                  setState(() => isPublic = true);
                  Get.back();
                },
              ),
              const ScroleBottomSheetDivider(),
              ScroleBottomSheetAction(
                icon: Icons.lock_outline_rounded,
                label: 'Privé',
                subtitle: 'Visible uniquement sur lien ou invitation',
                onTap: () {
                  setState(() => isPublic = false);
                  Get.back();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Conditions d\'accès & Visibilité',
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: _saveRestrictions,
            child: const Text(
              'Enregistrer',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primary),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ================= SECTION 1: CONDITIONS D'ACCÈS =================
          _buildSectionHeader('CONDITIONS D\'ACCÈS'),
          const SizedBox(height: 8),

          // Grouped Settings: Âge
          Text('Âge', style: AppTextStyles.labelSmall.copyWith(color: colors.onSurfaceVariant)),
          const SizedBox(height: 6),
          ScroleBottomSheetGroup(
            children: [
              ScroleBottomSheetAction(
                label: 'Âge minimum',
                subtitle: minAge != null ? '$minAge ans' : 'Aucune restriction',
                trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                onTap: _showMinAgePicker,
              ),
              const ScroleBottomSheetDivider(),
              ScroleBottomSheetAction(
                label: 'Âge maximum',
                subtitle: maxAge != null ? '$maxAge ans' : 'Aucune restriction',
                trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                onTap: _showMaxAgePicker,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Grouped Settings: Genre
          Text('Personnes autorisées', style: AppTextStyles.labelSmall.copyWith(color: colors.onSurfaceVariant)),
          const SizedBox(height: 6),
          ScroleBottomSheetGroup(
            children: [
              ScroleBottomSheetAction(
                label: 'Genre autorisé',
                subtitle: allowedGender,
                trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                onTap: _showGenderPicker,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Grouped Settings: Toggles supplémentaires
          Text('Conditions supplémentaires', style: AppTextStyles.labelSmall.copyWith(color: colors.onSurfaceVariant)),
          const SizedBox(height: 6),
          ScroleBottomSheetGroup(
            children: [
              _buildSwitchRow(
                icon: '🪪',
                title: 'Pièce d\'identité obligatoire',
                subtitle: 'Contrôle à l\'entrée requis par le staff',
                value: requireIdentity,
                onChanged: (v) => setState(() => requireIdentity = v),
              ),
              const ScroleBottomSheetDivider(),
              _buildSwitchRow(
                icon: '🍷',
                title: 'Alcool autorisé',
                subtitle: 'Vente ou consommation d\'alcool sur place',
                value: allowAlcohol,
                onChanged: (v) => setState(() => allowAlcohol = v),
              ),
              const ScroleBottomSheetDivider(),
              _buildSwitchRow(
                icon: '🌙',
                title: 'Événement de nuit',
                subtitle: 'Se déroule principalement après minuit',
                value: isNightEvent,
                onChanged: (v) => setState(() => isNightEvent = v),
              ),
              const ScroleBottomSheetDivider(),
              _buildSwitchRow(
                icon: '🚬',
                title: 'Tabac autorisé',
                subtitle: 'Zone tabac/fumeur autorisée',
                value: allowTobacco,
                onChanged: (v) => setState(() => allowTobacco = v),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Grouped Settings: Autres restrictions
          Text('Autres restrictions', style: AppTextStyles.labelSmall.copyWith(color: colors.onSurfaceVariant)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(14),
            ),
            child: TextField(
              controller: otherRestrictionsController,
              maxLines: 3,
              style: AppTextStyles.body,
              decoration: const InputDecoration(
                hintText: 'Ajoutez une précision concernant l\'accès à l\'événement...',
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 28),

          // ================= SECTION 2: VISIBILITÉ =================
          _buildSectionHeader('VISIBILITÉ'),
          const SizedBox(height: 8),

          ScroleBottomSheetGroup(
            children: [
              ScroleBottomSheetAction(
                label: 'Visibilité de l\'événement',
                subtitle: isPublic
                    ? '🌍 Public (Visible sur Scrole par tout le monde)'
                    : '🔒 Privé (Visible uniquement sur lien ou invitation)',
                trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                onTap: _showVisibilityPicker,
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: AppTextStyles.labelSmall.copyWith(
        color: AppColors.primary,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildSwitchRow({
    required String icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(subtitle, style: AppTextStyles.bodySmall.copyWith(color: colors.onSurfaceVariant)),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}
