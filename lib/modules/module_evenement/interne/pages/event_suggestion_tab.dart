import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import 'package:scrole/app/utils/boot_timing.dart';

import '../../../../../app/theme/app_colors.dart';
import '../../../../../app/theme/text_styles.dart';
import '../../../../../shared/widgets/app_cached_image.dart';
import '../../../../../shared/widgets/entity_certified_badge.dart';
import '../../../../../shared/widgets/shimmer.dart';
import '../../centre/models/event_model.dart';
import '../controllers/event_controller.dart';
import 'event_detail_page.dart';

bool _hasLoggedFirstSuggestionCard = false;

class SuggestionTab extends StatelessWidget {
  const SuggestionTab({super.key});

  @override
  Widget build(BuildContext context) {
    bootLog('SuggestionTab.build');
    final controller = Get.find<EventController>();
    final colorScheme = Theme.of(context).colorScheme;

    return Obx(() {
      final status = controller.suggestionsStatus.value;

      // 1. Loading / Initial -> Realistic Shimmer Placeholder
      if (status == EventSuggestionsStatus.loading ||
          status == EventSuggestionsStatus.initial) {
        return const _SuggestionTabShimmer();
      }

      // 2. Error State (when no suggested events)
      if (status == EventSuggestionsStatus.error && controller.suggestedEvents.isEmpty) {
        return _SuggestionErrorState(
          errorMessage: controller.suggestionsErrorMessage.value,
          onRetry: () => controller.fetchSuggestedEvents(force: true),
        );
      }

      // 3. Success Empty State
      if (status == EventSuggestionsStatus.successEmpty && controller.suggestedEvents.isEmpty) {
        return _EmptySuggestionsState(
          onRefresh: () => controller.fetchSuggestedEvents(force: true),
        );
      }

      // Filter finished events
      final activeSuggestions = controller.suggestedEvents
          .where((e) => !e.isFinished)
          .toList();

      if (activeSuggestions.isEmpty) {
        return _EmptySuggestionsState(
          onRefresh: () => controller.fetchSuggestedEvents(force: true),
        );
      }

      // Helper function to deduplicate by event.id for a specific section
      List<EventModel> uniqueByEventId(Iterable<EventModel> events) {
        final seen = <String>{};
        final result = <EventModel>[];
        for (final e in events) {
          if (e.id.isNotEmpty && seen.add(e.id)) {
            result.add(e);
          }
        }
        return result;
      }

      bool isThisWeek(DateTime date) {
        final now = DateTime.now();
        final startOfWeek = DateTime(now.year, now.month, now.day - (now.weekday - 1));
        final endOfWeek = startOfWeek.add(const Duration(days: 7));
        return date.isAfter(startOfWeek.subtract(const Duration(seconds: 1))) &&
            date.isBefore(endOfWeek);
      }

      // 1. Recommandations principales ("Pour vous")
      final forYouCategoryList = activeSuggestions
          .where((e) => e.category == 'pour_vous')
          .toList();
      final forYouEvents = uniqueByEventId(
        forYouCategoryList.isNotEmpty ? forYouCategoryList : activeSuggestions,
      )..sort((a, b) => b.interestedCount.compareTo(a.interestedCount));
      final topEvents = forYouEvents.take(6).toList();

      // 2. Événements en cours (avec durée restante > 48h)
      final ongoingEvents = uniqueByEventId(
        activeSuggestions.where((e) => e.category == 'en_cours' || e.isOngoingMeaningful).toList(),
      );

      // 3. Découverte sociale ("À découvrir avec vos proches")
      final socialCategoryList = activeSuggestions
          .where((e) => e.category == 'populaires' || e.goingCount > 0 || e.interestedCount > 0)
          .toList();
      final socialEvents = uniqueByEventId(socialCategoryList)
        ..sort((a, b) => (b.goingCount + b.interestedCount).compareTo(a.goingCount + a.interestedCount));
      final socialDiscoveryList = socialEvents.take(5).toList();

      // 4. Cette semaine ("Cette semaine")
      final thisWeekCategoryList = activeSuggestions
          .where((e) => e.category == 'cette_semaine' || isThisWeek(e.startsAt))
          .toList();
      final thisWeekEvents = uniqueByEventId(
        thisWeekCategoryList.isNotEmpty
            ? thisWeekCategoryList
            : activeSuggestions.where((e) => isThisWeek(e.startsAt)).toList(),
      );
      final thisWeekList = thisWeekEvents.take(4).toList();

      // 5. Événements gratuits
      final freeCategoryList = activeSuggestions
          .where((e) => e.category == 'gratuits' || e.isFree)
          .toList();
      final freeEvents = uniqueByEventId(freeCategoryList)
        ..sort((a, b) => b.goingCount.compareTo(a.goingCount));

      // 6. Calendrier personnel de l'utilisateur ("Mon calendrier")
      final personalCalendarEvents = uniqueByEventId(controller.calendarEvents)
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

      return Stack(
        children: [
          RefreshIndicator(
            color: Colors.transparent,
            backgroundColor: Colors.transparent,
            elevation: 0,
            onRefresh: () async {
              await Future.wait([
                controller.fetchSuggestedEvents(force: true),
                controller.fetchCalendarEvents(DateTime.now(), force: true),
              ]);
            },
            child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ===== SECTION ONGOING: EN COURS =====
              if (ongoingEvents.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Lottie.asset(
                          'assets/lotties/live stream.json',
                          width: 28,
                          height: 28,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'events_ongoing'.tr,
                          style: AppTextStyles.h4.copyWith(color: colorScheme.onSurface),
                        ),
                      ],
                    ),
                    Text(
                      'events_count'.trParams({'count': ongoingEvents.length.toString()}),
                      style: AppTextStyles.caption.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 220,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: ongoingEvents.length,
                    itemBuilder: (context, index) {
                      final event = ongoingEvents[index];
                      return Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: _SuggestionCard(
                          event: event,
                          isTrending: true,
                          onTap: () => Get.to(() => EventDetailPage(event: event)),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 28),
              ],

              // ===== SECTION 1: POUR VOUS / TENDANCES =====
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'events_for_you'.tr,
                      style: AppTextStyles.h4.copyWith(color: colorScheme.onSurface),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'events_count'.trParams({'count': topEvents.length.toString()}),
                    style: AppTextStyles.caption.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.6)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 220,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: topEvents.length,
                  itemBuilder: (context, index) {
                    final event = topEvents[index];
                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: _SuggestionCard(
                        event: event,
                        isTrending: true,
                        onTap: () => Get.to(() => EventDetailPage(event: event)),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 28),

              // ===== SECTION 2: À DÉCOUVRIR AVEC VOS PROCHES =====
              if (socialDiscoveryList.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'events_social_discovery'.tr,
                        style: AppTextStyles.h4.copyWith(color: colorScheme.onSurface),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'events_count'.trParams({'count': socialDiscoveryList.length.toString()}),
                      style: AppTextStyles.caption.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 220,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: socialDiscoveryList.length,
                    itemBuilder: (context, index) {
                      final event = socialDiscoveryList[index];
                      return Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: _SuggestionCard(
                          event: event,
                          isTrending: false,
                          onTap: () => Get.to(() => EventDetailPage(event: event)),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 28),
              ],

              // ===== SECTION 3: CETTE SEMAINE =====
              if (thisWeekList.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'events_this_week'.tr,
                        style: AppTextStyles.h4.copyWith(color: colorScheme.onSurface),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'events_count'.trParams({'count': thisWeekList.length.toString()}),
                      style: AppTextStyles.caption.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...thisWeekList.map((event) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _SuggestionListTile(
                    event: event,
                    onTap: () => Get.to(() => EventDetailPage(event: event)),
                  ),
                )),
                const SizedBox(height: 28),
              ],

              // ===== SECTION 4: GRATUITS =====
              if (freeEvents.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'events_free'.tr,
                        style: AppTextStyles.h4.copyWith(color: colorScheme.onSurface),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'events_free_count'.trParams({'count': freeEvents.length.toString()}),
                      style: AppTextStyles.caption.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 180,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: freeEvents.length,
                    itemBuilder: (context, index) {
                      final event = freeEvents[index];
                      return Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: _SuggestionCard(
                          event: event,
                          isTrending: false,
                          compact: true,
                          onTap: () => Get.to(() => EventDetailPage(event: event)),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 28),
              ],

              // ===== SECTION 5: MON CALENDRIER (A LA FIN DE L'ECRAN) =====
              Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.4), height: 1),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today_rounded, color: colorScheme.primary, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'events_my_calendar'.tr,
                            style: AppTextStyles.h4.copyWith(color: colorScheme.onSurface),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (personalCalendarEvents.isNotEmpty)
                    Text(
                      'events_count'.trParams({'count': personalCalendarEvents.length.toString()}),
                      style: AppTextStyles.caption.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.6)),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (personalCalendarEvents.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.event_available_outlined, color: colorScheme.onSurfaceVariant, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'my_agenda_empty'.tr,
                          style: AppTextStyles.bodySmall.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                )
              else
                ...personalCalendarEvents.take(4).map((event) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _SuggestionListTile(
                    event: event,
                    onTap: () => Get.to(() => EventDetailPage(event: event)),
                  ),
                )),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: Center(
              child: Obx(() {
                if (!controller.isLoadingSuggestions.value) return const SizedBox.shrink();
                return Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Lottie.asset(
                    'assets/lotties/Animation - 1791582964132.json',
                    width: 44,
                    height: 44,
                  ),
                );
              }),
            ),
          ),
        ],
      );
    });
  }
}

class _EmptySuggestionsState extends StatelessWidget {
  final VoidCallback onRefresh;

  const _EmptySuggestionsState({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      color: AppColors.primary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
        child: Column(
          children: [
            const SizedBox(height: 20),
            // Illustration / Badge discovery symbol
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                size: 56,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),

            // Title
            Text(
              'suggestions_empty_title'.tr,
              textAlign: TextAlign.center,
              style: AppTextStyles.h3.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),

            // Description
            Text(
              'suggestions_empty_subtitle'.tr,
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 32),

            // Tip Container (non-button, informative card)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        size: 18,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'suggestions_empty_tip_title'.tr,
                        style: AppTextStyles.labelLarge.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'suggestions_empty_tip_full'.tr,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  final EventModel event;
  final bool isTrending;
  final bool compact;
  final VoidCallback onTap;

  const _SuggestionCard({
    required this.event,
    this.isTrending = false,
    this.compact = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (!_hasLoggedFirstSuggestionCard) {
      _hasLoggedFirstSuggestionCard = true;
      bootLog('Premier _SuggestionCard construit');
    }
    final width = compact ? 160.0 : 260.0;
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image + Badge "En cours" avec Lottie animation
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                  child: event.coverImageUrl != null
                      ? AppCachedImage(
                          imageUrl: event.coverImageUrl!,
                          height: compact ? 90 : 130,
                          width: width,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          height: compact ? 90 : 130,
                          width: width,
                          color: colorScheme.surfaceContainerHighest,
                          child: Icon(Icons.event, color: colorScheme.onSurfaceVariant),
                        ),
                ),
                if (event.category == 'en_cours' || event.isOngoingMeaningful)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.8), width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Lottie.asset(
                            'assets/lotties/live stream.json',
                            width: 18,
                            height: 18,
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'EN COURS',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        fit: FlexFit.loose,
                        child: Text(
                          event.name,
                          style: AppTextStyles.labelLarge.copyWith(color: colorScheme.onSurface),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      EntityCertifiedBadge(entityType: 'event', entityId: event.id, size: 16),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('EEE d MMM · HH:mm').format(event.startsAt),
                    style: AppTextStyles.caption.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.6)),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (isTrending) ...[
                        Icon(Icons.local_fire_department, color: colorScheme.primary, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          '${event.interestedCount}',
                          style: AppTextStyles.caption.copyWith(color: colorScheme.primary),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Icon(Icons.people_outline, color: colorScheme.onSurface.withValues(alpha: 0.6), size: 14),
                      const SizedBox(width: 4),
                      Text(
                        '${event.goingCount}',
                        style: AppTextStyles.caption.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.6)),
                      ),
                      const Spacer(),
                      if (event.isFree)
                        Text(
                          'events_is_free'.tr,
                          style: AppTextStyles.caption.copyWith(color: AppColors.success),
                        )
                      else
                        Text(
                          event.priceDisplay,
                          style: AppTextStyles.caption.copyWith(color: colorScheme.onSurface),
                        ),
                    ],
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

class _SuggestionListTile extends StatelessWidget {
  final EventModel event;
  final VoidCallback onTap;

  const _SuggestionListTile({
    required this.event,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: event.coverImageUrl != null
                  ? AppCachedImage(
                      imageUrl: event.coverImageUrl!,
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      width: 60,
                      height: 60,
                      color: colorScheme.surfaceContainerHighest,
                      child: Icon(Icons.event, color: colorScheme.onSurfaceVariant, size: 24),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        fit: FlexFit.loose,
                        child: Text(
                          event.name,
                          style: AppTextStyles.labelLarge.copyWith(color: colorScheme.onSurface),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      EntityCertifiedBadge(entityType: 'event', entityId: event.id, size: 16),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('EEEE d MMMM · HH:mm').format(event.startsAt),
                    style: AppTextStyles.caption.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.6)),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined, size: 12, color: colorScheme.onSurface.withValues(alpha: 0.6)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          event.isOnline
                              ? 'events_is_online'.tr
                              : (event.address?.split(',').first ?? 'Paris'),
                          style: AppTextStyles.caption.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.6)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (event.isFree)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'events_is_free'.tr,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.success,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else
                  Text(
                    event.priceDisplay,
                    style: AppTextStyles.labelMedium.copyWith(color: colorScheme.onSurface),
                  ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.people_outline, size: 12, color: colorScheme.onSurface.withValues(alpha: 0.6)),
                    const SizedBox(width: 3),
                    Text(
                      '${event.goingCount}',
                      style: AppTextStyles.caption.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =========================================
// REALISTIC SHIMMER SKELETON
// =========================================
class _SuggestionTabShimmer extends StatelessWidget {
  const _SuggestionTabShimmer();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Lottie.asset(
        'assets/lotties/Animation - 1791582964132.json',
        width: 140,
        height: 140,
      ),
    );
  }
}

class _ShimmerSectionHeader extends StatelessWidget {
  const _ShimmerSectionHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        SkeletonShimmer(width: 160, height: 20, borderRadius: 6),
        SkeletonShimmer(width: 40, height: 16, borderRadius: 12),
      ],
    );
  }
}

class _ShimmerCard extends StatelessWidget {
  final double width;
  final double height;
  final bool compact;

  const _ShimmerCard({
    required this.width,
    required this.height,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final imageHeight = compact ? 90.0 : 125.0;
    final padding = compact ? 8.0 : 12.0;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonShimmer(
            width: width,
            height: imageHeight,
            borderRadius: 14,
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SkeletonShimmer(width: width * 0.75, height: 14, borderRadius: 4),
                  SkeletonShimmer(width: width * 0.5, height: 12, borderRadius: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      SkeletonShimmer(width: 40, height: 12, borderRadius: 4),
                      SkeletonShimmer(width: 35, height: 12, borderRadius: 4),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShimmerListTile extends StatelessWidget {
  const _ShimmerListTile();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const SkeletonShimmer(width: 60, height: 60, borderRadius: 10),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonShimmer(width: 160, height: 14, borderRadius: 4),
                SizedBox(height: 6),
                SkeletonShimmer(width: 110, height: 12, borderRadius: 4),
                SizedBox(height: 6),
                SkeletonShimmer(width: 80, height: 12, borderRadius: 4),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const SkeletonShimmer(width: 48, height: 20, borderRadius: 10),
        ],
      ),
    );
  }
}

// =========================================
// ERROR STATE
// =========================================
class _SuggestionErrorState extends StatelessWidget {
  final String errorMessage;
  final VoidCallback onRetry;

  const _SuggestionErrorState({
    required this.errorMessage,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.wifi_off_rounded,
                size: 56,
                color: colorScheme.error,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'community_error_title'.tr,
              textAlign: TextAlign.center,
              style: AppTextStyles.h3.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              errorMessage.isNotEmpty
                  ? errorMessage
                  : 'community_error_subtitle'.tr,
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(
                'wall_retry'.tr,
                style: AppTextStyles.button,
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

