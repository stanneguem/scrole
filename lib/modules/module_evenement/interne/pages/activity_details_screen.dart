import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../../../../shared/widgets/scrole_bottom_sheet.dart';
import '../../externe/services/supabase_event_service.dart';
import '../controllers/event_activity_controller.dart';

class ActivityDetailsScreen extends StatefulWidget {
  final String activityId;
  final String eventId;
  final bool isAlreadyAdded;

  const ActivityDetailsScreen({
    super.key,
    required this.activityId,
    required this.eventId,
    this.isAlreadyAdded = false,
  });

  @override
  State<ActivityDetailsScreen> createState() => _ActivityDetailsScreenState();
}

class _ActivityDetailsScreenState extends State<ActivityDetailsScreen> {
  Map<String, dynamic>? _previewData;
  bool _isLoading = true;
  late bool _added;

  @override
  void initState() {
    super.initState();
    _added = widget.isAlreadyAdded;
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    try {
      final service = Get.find<SupabaseEventService>();
      final data = await service.getActivityPreviewRpc(widget.activityId);
      if (mounted) {
        setState(() {
          _previewData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[ActivityDetailsScreen] _loadPreview error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showAddPriceSheet() {
    final activityMap = _previewData != null && _previewData!['activity'] is Map
        ? Map<String, dynamic>.from(_previewData!['activity'] as Map)
        : (_previewData ?? {});

    num toNum(dynamic val) {
      if (val == null) return 0;
      if (val is num) return val;
      if (val is String) return num.tryParse(val) ?? 0;
      return 0;
    }

    final convertedPrice = toNum(_previewData?['prix_converti'] ?? activityMap['base_price_converted'] ?? activityMap['base_price']).toDouble();
    final symbol = (_previewData?['display_currency_symbol'] ?? activityMap['display_currency_symbol'] ?? 'FCFA').toString();
    final code = (_previewData?['display_currency_code'] ?? activityMap['display_currency_code'] ?? 'XAF').toString();

    final priceController = TextEditingController(text: convertedPrice.toStringAsFixed(0));

    ScroleBottomSheet.show(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Ajouter l\'activité', style: AppTextStyles.h4),
            const SizedBox(height: 4),
            Text(
              (activityMap['name'] ?? activityMap['nom'] ?? 'Activité').toString(),
              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold, color: AppColors.primary),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('Prix de base converti : ', style: AppTextStyles.bodySmall),
                Text('$convertedPrice $symbol', style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            Text('Prix de cette activité pour cet événement :', style: AppTextStyles.bodySmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: priceController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Prix appliqué',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(code, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Get.back();
                final price = double.tryParse(priceController.text.trim()) ?? convertedPrice;
                final controller = Get.find<EventActivityController>();
                controller.addActivityToEvent(widget.activityId, price, code);
                setState(() => _added = true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Confirmer l\'ajout', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    if (_added) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          '✓ Déjà ajoutée à cet événement',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 15),
        ),
      );
    }
    return ElevatedButton.icon(
      onPressed: _showAddPriceSheet,
      icon: const Icon(Icons.add_rounded, color: Colors.white),
      label: const Text('Ajouter à l\'événement', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        minimumSize: const Size(double.infinity, 54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  Widget _buildStatColumn(String value, String label) {
    return Column(
      children: [
        Text(value, style: AppTextStyles.h4.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label, style: AppTextStyles.bodySmall),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Détails de l\'activité')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final data = _previewData ?? {};
    final activityMap = data['activity'] is Map ? Map<String, dynamic>.from(data['activity'] as Map) : data;
    final creatorMap = data['creator'] is Map ? Map<String, dynamic>.from(data['creator'] as Map) : null;
    final rankingMap = data['classement'] is Map ? Map<String, dynamic>.from(data['classement'] as Map) : null;

    num toNum(dynamic val) {
      if (val == null) return 0;
      if (val is num) return val;
      if (val is String) return num.tryParse(val) ?? 0;
      return 0;
    }

    final name = (activityMap['name'] ?? activityMap['nom'] ?? 'Activité').toString();
    final description = activityMap['description']?.toString();
    final convertedPrice = toNum(data['prix_converti'] ?? activityMap['base_price_converted'] ?? activityMap['base_price']).toDouble();
    final symbol = (data['display_currency_symbol'] ?? activityMap['display_currency_symbol'] ?? 'FCFA').toString();
    final formattedPrice = '${convertedPrice.toStringAsFixed(convertedPrice % 1 == 0 ? 0 : 2)} $symbol';

    final currentEventsCount = toNum(data['current_events_count'] ?? activityMap['added_count']).toInt();
    final favoritesCount = toNum(data['favorites_count']).toInt();

    final creatorName = creatorMap != null
        ? (creatorMap['full_name'] ?? creatorMap['username'] ?? 'Créateur').toString()
        : 'Créateur';
    final creatorUsername = creatorMap != null ? creatorMap['username']?.toString() : null;
    final creatorPhoto = creatorMap != null ? creatorMap['photo_url']?.toString() : null;

    final hasRanking = rankingMap != null && rankingMap['rang'] != null && toNum(rankingMap['rang']).toInt() > 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          name,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Carte En-tête Activité
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
                      child: const Icon(Icons.local_activity_rounded, color: AppColors.primary, size: 32),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: AppTextStyles.h4),
                          const SizedBox(height: 4),
                          Text(
                            formattedPrice,
                            style: AppTextStyles.h5.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (description != null && description.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('À propos', style: AppTextStyles.labelSmall),
                  const SizedBox(height: 4),
                  Text(description, style: AppTextStyles.body),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Carte Créateur
          if (creatorMap != null) ...[
            Text('Créateur', style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary, letterSpacing: 1.1)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  ClipOval(
                    child: creatorPhoto != null && creatorPhoto.isNotEmpty
                        ? AppCachedImage(imageUrl: creatorPhoto, width: 40, height: 40, fit: BoxFit.cover)
                        : Container(
                            width: 40,
                            height: 40,
                            color: AppColors.primary.withValues(alpha: 0.15),
                            child: const Icon(Icons.person, color: AppColors.primary),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(creatorName, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
                      if (creatorUsername != null) Text('@$creatorUsername', style: AppTextStyles.bodySmall),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Carte Statistiques officielles
          Text('Statistiques', style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary, letterSpacing: 1.1)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatColumn('$currentEventsCount', 'Événements'),
                Container(height: 30, width: 1, color: colors.outlineVariant),
                _buildStatColumn('$favoritesCount', 'Favoris'),
                if (hasRanking) Container(height: 30, width: 1, color: colors.outlineVariant),
                if (hasRanking) _buildStatColumn('#${rankingMap['rang']}', 'Sur ${rankingMap['sur'] ?? 0}'),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(20),
        child: _buildBottomBar(),
      ),
    );
  }
}
