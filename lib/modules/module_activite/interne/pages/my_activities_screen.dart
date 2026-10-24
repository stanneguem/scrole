import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:scrole/app/routes/app_pages.dart';
import 'package:scrole/app/theme/app_colors.dart';
import 'package:scrole/app/theme/text_styles.dart';
import '../../centre/models/activity_model.dart';
import '../../centre/services/activity_service.dart';
import '../widgets/activity_card.dart';
import 'activity_preview_screen.dart';
import 'edit_activity_screen.dart';

enum MyActivitiesFilter { all, active, pending, subscribed }

class MyActivitiesScreen extends StatefulWidget {
  const MyActivitiesScreen({super.key});

  @override
  State<MyActivitiesScreen> createState() => _MyActivitiesScreenState();
}

class _MyActivitiesScreenState extends State<MyActivitiesScreen> {
  final ActivityService _activityService = Get.find<ActivityService>();
  MyActivitiesFilter _activeFilter = MyActivitiesFilter.all;

  @override
  void initState() {
    super.initState();
    _activityService.catchupSync();
  }

  List<Activity> _getFilteredActivities(List<Activity> activities) {
    switch (_activeFilter) {
      case MyActivitiesFilter.all:
        return activities;
      case MyActivitiesFilter.active:
        return activities.where((a) => a.isActive).toList();
      case MyActivitiesFilter.pending:
        return activities.where((a) => a.isPending).toList();
      case MyActivitiesFilter.subscribed:
        return activities.where((a) => a.addedCount > 0).toList();
    }
  }

  void _confirmDeleteActivity(Activity activity) {
    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Supprimer l\'activité ?'),
        content: const Text(
          'Si l\'activité n\'a pas encore été utilisée dans un événement, elle sera supprimée immédiatement.\n\nSi elle est déjà liée à des événements, sa suppression sera programmée sous 30 jours.',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text('cancel'.tr),
          ),
          TextButton(
            onPressed: () {
              Get.back();
              _activityService.requestDeletion(activity.id);
            },
            child: Text(
              'delete'.tr,
              style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
          centerTitle: true,
          title: const Text('Mes Activités'),
          titleTextStyle: AppTextStyles.h5.copyWith(color: colorScheme.onSurface),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => Get.back(),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.add_rounded, size: 28, color: AppColors.primary),
              onPressed: () => Get.toNamed(AppPages.createactivite),
            ),
          ],
          bottom: TabBar(
            labelColor: AppColors.primary,
            unselectedLabelColor: colorScheme.onSurfaceVariant,
            indicatorColor: AppColors.primary,
            tabs: const [
              Tab(text: 'Créées'),
              Tab(text: 'Gérées (Staff)'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildCreatedTab(colorScheme),
            _buildManagedTab(colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _buildCreatedTab(ColorScheme colorScheme) {
    return Column(
      children: [
        Container(
          height: 44,
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _buildFilterTab(MyActivitiesFilter.all, 'Toutes'),
              const SizedBox(width: 8),
              _buildFilterTab(MyActivitiesFilter.active, 'Actives'),
              const SizedBox(width: 8),
              _buildFilterTab(MyActivitiesFilter.pending, 'En attente'),
              const SizedBox(width: 8),
              _buildFilterTab(MyActivitiesFilter.subscribed, 'Utilisées'),
            ],
          ),
        ),
        Expanded(
          child: Obx(() {
            if (_activityService.isLoading.value && _activityService.myActivities.isEmpty) {
              return const Center(child: CircularProgressIndicator(color: AppColors.primary));
            }

            final filtered = _getFilteredActivities(_activityService.myActivities);

            if (filtered.isEmpty) {
              return _buildEmptyState(colorScheme);
            }

            return RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () => _activityService.catchupSync(),
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: filtered.length,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final activity = filtered[index];
                  return GestureDetector(
                    onTap: () => Get.to(() => ActivityPreviewScreen(activity: activity, isOwner: true)),
                    child: ActivityCard(
                      activity: activity,
                      isJoined: true,
                      isEventAdded: true,
                      onJoin: () => Get.to(() => ActivityPreviewScreen(activity: activity, isOwner: true)),
                      onEdit: () => Get.to(() => EditActivityScreen(activity: activity)),
                      onDelete: () => _confirmDeleteActivity(activity),
                    ),
                  );
                },
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildManagedTab(ColorScheme colorScheme) {
    return Obx(() {
      if (_activityService.isLoading.value && _activityService.managedActivities.isEmpty) {
        return const Center(child: CircularProgressIndicator(color: AppColors.primary));
      }

      if (_activityService.managedActivities.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.badge_outlined, size: 56, color: colorScheme.outlineVariant),
                const SizedBox(height: 16),
                Text('Aucune activité gérée comme staff.', style: AppTextStyles.body),
              ],
            ),
          ),
        );
      }

      return RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () => _activityService.catchupSync(),
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: _activityService.managedActivities.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final activity = _activityService.managedActivities[index];
            return GestureDetector(
              onTap: () => Get.to(() => ActivityPreviewScreen(activity: activity, isManager: true)),
              child: ActivityCard(
                activity: activity,
                isJoined: true,
                isEventAdded: true,
                onJoin: () => Get.to(() => ActivityPreviewScreen(activity: activity, isManager: true)),
                onEdit: () => Get.to(() => EditActivityScreen(activity: activity, isManagerOnly: true)),
              ),
            );
          },
        ),
      );
    });
  }

  Widget _buildFilterTab(MyActivitiesFilter filter, String label) {
    final colorScheme = Theme.of(context).colorScheme;
    final isActive = _activeFilter == filter;

    return GestureDetector(
      onTap: () => setState(() => _activeFilter = filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary : colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
              color: isActive ? Colors.white : colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.local_activity_outlined,
                size: 48,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Aucune activité disponible',
              style: AppTextStyles.h5.copyWith(color: colorScheme.onSurface),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Créez vos propres activités pour les proposer lors de la planification d\'événements !',
              style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => Get.toNamed(AppPages.createactivite),
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: const Text('Créer une activité', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
