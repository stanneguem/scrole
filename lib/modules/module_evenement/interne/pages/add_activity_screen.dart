import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../app/routes/app_pages.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/widgets/scrole_bottom_sheet.dart';
import '../controllers/event_activity_controller.dart';
import '../../centre/models/activity_model.dart';
import 'activity_details_screen.dart';

class AddActivityScreen extends GetView<EventActivityController> {
  const AddActivityScreen({super.key});

  void _showSingleAddPriceSheet(BuildContext context, AvailableActivityModel activity) {
    final priceController = TextEditingController(
      text: activity.basePriceConverted > 0
          ? activity.basePriceConverted.toStringAsFixed(0)
          : activity.basePrice.toStringAsFixed(0),
    );
    final currency = activity.displayCurrencyCode.isNotEmpty ? activity.displayCurrencyCode : activity.currencyCode;

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
            Text(activity.name, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold, color: AppColors.primary)),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('Prix de base converti : ', style: AppTextStyles.bodySmall),
                Text(activity.formattedConvertedPrice, style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.bold)),
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
                  child: Text(currency, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Get.back();
                final price = double.tryParse(priceController.text.trim()) ?? activity.basePriceConverted;
                controller.addActivityToEvent(activity.id, price, currency);
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

  void _showMultiSelectConfirmSheet(BuildContext context) {
    final selectedCount = controller.selectedActivityIds.length;
    final selectedList = controller.availableActivities
        .toList()
        .where((a) => controller.selectedActivityIds.contains(a.id))
        .toList();

    ScroleBottomSheet.show(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Ajouter $selectedCount activités ?', style: AppTextStyles.h4),
            const SizedBox(height: 8),
            Text('Vous êtes sur le point d\'ajouter les activités suivantes à votre événement :', style: AppTextStyles.bodySmall),
            const SizedBox(height: 16),
            ScroleBottomSheetGroup(
              children: selectedList.map((a) => ListTile(
                title: Text(a.name, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
                subtitle: Text(a.formattedConvertedPrice, style: AppTextStyles.bodySmall),
              )).toList(),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: controller.isSaving.value
                  ? null
                  : () => controller.addMultipleActivitiesToEvent(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: controller.isSaving.value
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Ajouter ces activités', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Obx(() {
      final isMultiMode = controller.isMultiSelectMode.value;
      final selectedCount = controller.selectedActivityIds.length;

      return Scaffold(
        appBar: AppBar(
          title: Text(
            isMultiMode ? '$selectedCount sélectionnée(s)' : 'Ajouter une activité',
            style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
          ),
          leading: isMultiMode
              ? IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: controller.exitMultiSelectMode,
                )
              : null,
          bottom: !isMultiMode
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(60),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: TextField(
                      onChanged: controller.searchGlobalActivities,
                      decoration: InputDecoration(
                        hintText: 'Rechercher une activité...',
                        prefixIcon: const Icon(Icons.search),
                        contentPadding: const EdgeInsets.symmetric(vertical: 0),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
                      ),
                    ),
                  ),
                )
              : null,
        ),
        body: Obx(() {
          if (controller.isLoading.value && controller.availableActivities.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (controller.availableActivities.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.search_off_rounded, size: 64, color: AppColors.disabled),
                    const SizedBox(height: 16),
                    Text('Aucune activité trouvée.', style: AppTextStyles.h4, textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text(
                      'Si l\'activité souhaitée n\'existe pas encore sur la plateforme, vous pouvez la créer.',
                      style: AppTextStyles.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () => Get.toNamed(
                        AppPages.createactivite,
                        arguments: {'eventId': controller.eventId},
                      ),
                      icon: const Icon(Icons.add_rounded, color: Colors.white),
                      label: const Text('Créer ma propre activité', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        minimumSize: const Size(220, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: controller.availableActivities.length,
            itemBuilder: (context, index) {
              final activity = controller.availableActivities[index];
              final alreadyInEvent = activity.isAlreadyAdded || controller.eventActivities.any((a) => a.activityId == activity.id);
              final isSelected = controller.selectedActivityIds.contains(activity.id);

              final creatorText = activity.creatorFullName ?? (activity.creatorUsername != null ? '@${activity.creatorUsername}' : '');

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: isSelected
                        ? AppColors.primary
                        : colors.outlineVariant.withValues(alpha: 0.3),
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    if (isMultiMode) {
                      if (!alreadyInEvent) {
                        controller.toggleSelection(activity.id);
                      }
                    } else {
                      Get.to(() => ActivityDetailsScreen(
                            activityId: activity.id,
                            eventId: controller.eventId,
                            isAlreadyAdded: alreadyInEvent,
                          ));
                    }
                  },
                  onLongPress: () {
                    if (!alreadyInEvent) {
                      if (!isMultiMode) {
                        controller.enterMultiSelectMode(activity.id);
                      } else {
                        controller.toggleSelection(activity.id);
                      }
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        if (isMultiMode && !alreadyInEvent)
                          Checkbox(
                            value: isSelected,
                            activeColor: AppColors.primary,
                            onChanged: (_) => controller.toggleSelection(activity.id),
                          )
                        else
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.local_activity_rounded, color: AppColors.primary, size: 22),
                          ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(activity.name, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
                              if (creatorText.isNotEmpty)
                                Text('Par $creatorText', style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text(
                                    activity.formattedConvertedPrice,
                                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    '${activity.addedCount} évt${activity.addedCount > 1 ? 's' : ''} • ${activity.favoritesCount} fav',
                                    style: AppTextStyles.caption.copyWith(color: colors.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (alreadyInEvent)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text('✓ Déjà ajoutée', style: TextStyle(color: AppColors.success, fontSize: 11, fontWeight: FontWeight.bold)),
                          )
                        else if (!isMultiMode)
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.primary, size: 26),
                            onPressed: () => _showSingleAddPriceSheet(context, activity),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        }),
        bottomNavigationBar: isMultiMode && selectedCount > 0
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton(
                  onPressed: () => _showMultiSelectConfirmSheet(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text('Ajouter $selectedCount activité(s)', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              )
            : null,
        floatingActionButton: !isMultiMode
            ? FloatingActionButton.extended(
                onPressed: () => Get.toNamed(
                  AppPages.createactivite,
                  arguments: {'eventId': controller.eventId},
                ),
                backgroundColor: AppColors.primary,
                icon: const Icon(Icons.add_rounded, color: Colors.white),
                label: const Text('Créer mon activité', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              )
            : null,
      );
    });
  }
}
