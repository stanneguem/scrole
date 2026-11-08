import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import 'package:scrole/app_controller.dart';
import '../../../../app/routes/app_pages.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/utils/number_formatter.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../../../../shared/widgets/scrole_bottom_sheet.dart';
import '../../../../shared/widgets/entity_certified_badge.dart';
import '../../../../shared/widgets/user_certified_badge.dart';
import '../../../../shared/widgets/expandable_text_widget.dart';
import '../../../../app/utils/supabase_error_mapper.dart';
import '../../centre/models/event_model.dart';
import '../../centre/models/event_preview_model.dart';
import '../../centre/repositories/event_repository.dart';
import '../../centre/services/event_share_poster_service.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../centre/models/event_day_models.dart';
import '../enums/event_enum.dart';
import 'event_days_selector_screen.dart';
import 'event_comments_screen.dart';
import 'event_rating_screen.dart';
import 'event_activities_list_screen.dart';
import 'event_itinerary_overview_screen.dart';
import 'external_event_itinerary_screen.dart';
import 'report_event_sheet.dart';
import 'profile_event_series_screen.dart';

class EventPreviewScreen extends StatefulWidget {
  final EventModel? initialEvent;
  final String? profileUserId;
  final bool archiveTabMode;

  const EventPreviewScreen({super.key, this.initialEvent, this.profileUserId, this.archiveTabMode = false});

  @override
  State<EventPreviewScreen> createState() => _EventPreviewScreenState();
}

class _EventPreviewScreenState extends State<EventPreviewScreen> with SingleTickerProviderStateMixin {
  EventPreviewModel? _preview;
  bool _isLoading = true;
  bool _isCalendarLoading = false;
  bool _isActionBarVisible = true;
  String? _eventId;
  String? _contextRole;
  List<Map<String, dynamic>> _seriesEditions = [];
  List<EventOpenDay> _previewOpenDays = [];
  StreamSubscription<EventModel>? _eventUpdateSubscription;
  late AnimationController _heartsAnimationController;

  @override
  void initState() {
    super.initState();
    _heartsAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _loadData();
    _listenToEventUpdates();
  }

  void _listenToEventUpdates() {
    _eventUpdateSubscription = Get.find<EventRepository>().onEventUpdated.listen((updatedEvent) {
      if (_eventId != null && updatedEvent.id == _eventId) {
        debugPrint('[EventPreviewScreen] Live event update received: $_eventId -> ${updatedEvent.name}');
        if (mounted) {
          setState(() {
            if (_preview != null) {
              _preview = EventPreviewModel(
                event: updatedEvent,
                creator: _preview!.creator,
                isPlatformEvent: _preview!.isPlatformEvent,
                isThirdPartyEvent: _preview!.isThirdPartyEvent,
                canView: _preview!.canView,
                canViewPublicPreview: _preview!.canViewPublicPreview,
                viewerRole: _preview!.viewerRole,
                message: _preview!.message,
                isInMyCalendar: _preview!.isInMyCalendar,
                isLikedByMe: _preview!.isLikedByMe,
                likesCount: _preview!.likesCount,
                attendeeCount: _preview!.attendeeCount,
                amisDansAgenda: _preview!.amisDansAgenda,
                amisDansAgendaCount: _preview!.amisDansAgendaCount,
                amisDansAgendaPhotos: _preview!.amisDansAgendaPhotos,
                ranking: _preview!.ranking,
                tickets: _preview!.tickets,
                cheapestTicket: _preview!.cheapestTicket,
                activitiesLiees: _preview!.activitiesLiees,
                restrictions: _preview!.restrictions,
                canAccess: _preview!.canAccess,
                canInteract: _preview!.canInteract,
                canLike: _preview!.canLike,
                canComment: _preview!.canComment,
                canRate: _preview!.canRate,
                canShare: _preview!.canShare,
                canAddToCalendar: _preview!.canAddToCalendar,
                canRegister: _preview!.canRegister,
                prestigeScore: _preview!.prestigeScore,
                prestigeStars: _preview!.prestigeStars,
              );
            } else {
              _preview = EventPreviewModel(event: updatedEvent);
            }
          });
        }
      }
    });
  }

  Future<void> _loadData() async {
    final args = Get.arguments;
    if (widget.initialEvent != null) {
      _eventId = widget.initialEvent!.id;
      _contextRole = widget.archiveTabMode ? null : _contextRole;
    }
    if (args is Map) {
      _eventId = (args['id'] ?? args['eventId'])?.toString();
      _contextRole = args['context']?.toString();
      if (_eventId == null && args['event'] is EventModel) {
        _eventId = (args['event'] as EventModel).id;
      }
    } else if (args is EventModel) {
      _eventId = args.id;
    } else if (Get.parameters['id'] != null && _eventId == null) {
      _eventId = Get.parameters['id'];
    }

    if (_eventId == null || _eventId!.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final repo = Get.find<EventRepository>();
    repo.subscribeToEventUpdates(_eventId!);

    try {
      debugPrint('[EventPreview] request eventId=$_eventId');
      EventPreviewModel preview;
      final currentUserId = Get.find<AppController>().authUser.value?.id;

      if (_contextRole == 'owner' || _contextRole == 'managed') {
        preview = await repo.getEventPreviewOwner(_eventId!);
      } else if (_contextRole == 'staff') {
        preview = await repo.getEventPreviewStaff(_eventId!);
      } else {
        try {
          preview = await repo.getEventPreviewPublic(_eventId!);
        } catch (e) {
          debugPrint('[EventPreviewScreen] getEventPreviewPublic error: $e. Falling back to getEventPreview...');
          preview = await repo.getEventPreview(_eventId!);
        }

        // The public-preview RPC deliberately returns a restricted payload for
        // event owners/co-creators/staff (rather than throwing). Retry with the
        // matching privileged preview when the payload identifies that role.
        final returnedRole = (preview.viewerRole ?? '').toLowerCase();
        if (!preview.canViewPublicPreview &&
            (returnedRole == 'owner' ||
             returnedRole == 'creator' ||
             returnedRole == 'fondateur' ||
             returnedRole == 'cofounder' ||
             returnedRole == 'co_founder' ||
             returnedRole == 'co_createur' ||
             returnedRole == 'co_creator')) {
          preview = await repo.getEventPreviewOwner(_eventId!);
        } else if (!preview.canViewPublicPreview && returnedRole == 'staff') {
          preview = await repo.getEventPreviewStaff(_eventId!);
        }
      }

      // Resolve series for every entry point. Prefer an active/upcoming edition;
      // if none remains, open the archive/gallery instead of a stale detail page.
      if (!widget.archiveTabMode) {
        List<Map<String, dynamic>> editions = [];
        try {
          editions = await repo.getPublicEventSeriesEditions(preview.event.id);
        } catch (error) {
          // A series lookup must never prevent the event preview from opening.
          debugPrint('[EventPreviewScreen] series lookup failed: $error');
        }
        final now = DateTime.now();
        _seriesEditions = editions;
        final upcoming = editions.where((edition) {
          final status = (edition['status'] ?? '').toString().toLowerCase();
          final start = DateTime.tryParse((edition['starts_at'] ?? '').toString());
          final end = DateTime.tryParse((edition['ends_at'] ?? '').toString());
          return status == 'active' && start != null &&
              (start.isAfter(now) || (end != null && !end.isBefore(now)));
        }).toList()
          ..sort((a, b) => DateTime.parse(a['starts_at'].toString())
              .compareTo(DateTime.parse(b['starts_at'].toString())));
        final currentAvailable = preview.event.status == EventStatus.published &&
            (preview.event.startsAt.isAfter(now) ||
             (preview.event.endsAt != null && !preview.event.endsAt!.isBefore(now)));
        if (!currentAvailable && upcoming.isNotEmpty) {
          final nextId = (upcoming.first['id'] ?? '').toString();
          if (nextId.isNotEmpty && nextId != preview.event.id) {
            final nextEvent = await repo.getEventById(nextId);
            if (mounted) Get.off(() => EventPreviewScreen(initialEvent: nextEvent));
            return;
          }
        }
        if (!currentAvailable && upcoming.isEmpty &&
            (preview.event.isFinished || preview.event.status == EventStatus.completed)) {
          final userId = Get.find<AppController>().authUser.value?.id ?? '';
          final series = <String, dynamic>{
            'id': preview.event.seriesId ?? preview.event.id,
            'series_id': preview.event.seriesId ?? preview.event.id,
            'name': preview.event.name,
            'photo': preview.event.coverImageUrl,
            'description': preview.event.description,
            'edition_count': editions.length,
            'editions': editions,
          };
          if (mounted) {
            final completedEditions = editions.where((edition) =>
              (edition['status'] ?? '').toString().toLowerCase() == 'completed'
            ).toList();
            final archiveSeries = {...series, 'editions': completedEditions,
              'edition_count': completedEditions.length};
            Get.off(() => ProfileEventSeriesScreen(
              series: archiveSeries,
              profileUserId: userId,
            ));
          }
          return;
        }
      }

      try {
        _previewOpenDays = await repo.getEventOpenDays(preview.event.id);
        _previewOpenDays = _previewOpenDays.where((day) => day.isOpen).toList()
          ..sort((a, b) => a.date.compareTo(b.date));
      } catch (error) {
        _previewOpenDays = [];
        debugPrint('[EventPreviewScreen] open days lookup failed: $error');
      }

            final role = preview.viewerRole ?? preview.event.userRole;
      final normalizedRole = (role ?? '').toLowerCase();
      final isUserOwnedEvent = !preview.event.isAdminCreated;
      if ((isUserOwnedEvent && (
          normalizedRole == 'fondateur' ||
          normalizedRole == 'co_createur' ||
          normalizedRole == 'cofounder' ||
          normalizedRole == 'co_founder' ||
          normalizedRole == 'co_creator' ||
          normalizedRole == 'owner' ||
          normalizedRole == 'managed' ||
          (currentUserId != null &&
              currentUserId.isNotEmpty &&
              preview.event.creatorId == currentUserId)))) {
        _contextRole = 'owner';
      } else if (normalizedRole == 'staff' || normalizedRole == 'member_staff') {
        _contextRole = 'staff';
      } else {
        _contextRole = 'public';
      }

      // Comptabilise une ouverture réelle de la fiche, indépendamment des actions.
      unawaited(repo.recordEventAnalytics(_eventId!, 'detail_open'));
      if (mounted) {
        setState(() {
          _preview = preview;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[EventPreviewScreen] Error loading preview: $e');
      if (mounted) setState(() => _isLoading = false);

      final isNotFound = e is EventNotFoundException ||
          e.toString().toLowerCase().contains('introuvable') ||
          e.toString().toLowerCase().contains('not_found');

      if (isNotFound) {
        debugPrint('[EventPreview] navigation cancelled eventId=$_eventId');
        Get.back();
        if (Get.context != null) {
          showAppErrorDialog(Get.context!, e);
        } else {
          Get.snackbar('Événement introuvable', 'Cet événement n\'existe plus.');
        }
      }
    }
  }

  @override
  void dispose() {
    _heartsAnimationController.dispose();
    _eventUpdateSubscription?.cancel();
    if (_eventId != null) {
      Get.find<EventRepository>().unsubscribeFromEventUpdates(_eventId!);
    }
    super.dispose();
  }

  Future<void> _toggleCalendar() async {
    if (_preview == null) return;

    final repo = Get.find<EventRepository>();
    final userId = Get.find<AppController>().authUser.value?.id ?? '';
    final currentlyInCalendar = _preview!.isInMyCalendar;

    if (currentlyInCalendar) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Retirer de l\'agenda ?'),
          content: Text('Voulez-vous vraiment retirer "${_preview!.event.name}" de votre agenda ?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('cancel'.tr),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('Retirer', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() {
      _preview = EventPreviewModel(
        event: _preview!.event,
        creator: _preview!.creator,
                isPlatformEvent: _preview!.isPlatformEvent,
                isThirdPartyEvent: _preview!.isThirdPartyEvent,
        canView: _preview!.canView,
        canViewPublicPreview: _preview!.canViewPublicPreview,
        viewerRole: _preview!.viewerRole,
        message: _preview!.message,
        isInMyCalendar: !currentlyInCalendar,
        isLikedByMe: _preview!.isLikedByMe,
        likesCount: _preview!.likesCount,
        attendeeCount: _preview!.attendeeCount + (!currentlyInCalendar ? 1 : -1),
        amisDansAgenda: _preview!.amisDansAgenda,
        amisDansAgendaCount: _preview!.amisDansAgendaCount,
        amisDansAgendaPhotos: _preview!.amisDansAgendaPhotos,
        ranking: _preview!.ranking,
        tickets: _preview!.tickets,
        cheapestTicket: _preview!.cheapestTicket,
        activitiesLiees: _preview!.activitiesLiees,
        restrictions: _preview!.restrictions,
        canAccess: _preview!.canAccess,
        canInteract: _preview!.canInteract,
        canLike: _preview!.canLike,
        canComment: _preview!.canComment,
        canRate: _preview!.canRate,
        canShare: _preview!.canShare,
        canAddToCalendar: _preview!.canAddToCalendar,
        canRegister: _preview!.canRegister,
        prestigeScore: _preview!.prestigeScore,
        prestigeStars: _preview!.prestigeStars,
      );
    });

    if (!currentlyInCalendar) {
      final suggestedCommunityId = await repo.addEventToCalendarOptimistic(_eventId!, userId);
      if (suggestedCommunityId != null && suggestedCommunityId.isNotEmpty && mounted) {
        _showJoinCommunityDialog(suggestedCommunityId);
      }
    } else {
      await repo.removeEventFromCalendarOptimistic(_eventId!, userId);
    }
  }

  Future<void> _handleCalendarAction() async {
    if (_isCalendarLoading || _preview == null || !_preview!.canAddToCalendar) return;

    final startDay = DateTime(_preview!.event.startsAt.year, _preview!.event.startsAt.month, _preview!.event.startsAt.day);
    final endDay = _preview!.event.endsAt != null
        ? DateTime(_preview!.event.endsAt!.year, _preview!.event.endsAt!.month, _preview!.event.endsAt!.day)
        : startDay;

    final isMultiDay = endDay.difference(startDay).inDays >= 1;

    if (isMultiDay) {
      final repository = Get.find<EventRepository>();
      try {
        final openDays = await repository.getEventOpenDays(_eventId!);
        if (openDays.isEmpty || !openDays.any((d) => d.isOpen)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Les jours de participation ne sont pas encore définis par l\'organisateur.',
                  style: AppTextStyles.bodySmall.copyWith(color: Colors.white),
                ),
                backgroundColor: AppColors.primary,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            );
          }
          return;
        }

        List<EventPlannedDay>? preselectedDays;
        if (_preview!.isInMyCalendar) {
          preselectedDays = await repository.getMyEventCalendarDays(_eventId!);
        }

        if (mounted) {
          Get.to(
            () => EventDaysSelectorScreen(
              eventId: _eventId!,
              eventName: _preview!.event.name,
              openDays: openDays,
              preselectedDays: preselectedDays,
              isEditing: _preview!.isInMyCalendar,
              onSuccess: () => _loadData(),
            ),
            transition: Transition.rightToLeft,
          );
        }
      } catch (e) {
        debugPrint('[EventPreviewScreen] _handleCalendarAction error: $e');
      }
    } else {
      // Événement d'un seul jour -> Ajout/Retrait direct SANS aucun modal
      final repo = Get.find<EventRepository>();
      final userId = Get.find<AppController>().authUser.value?.id ?? '';
      final currentlyInCalendar = _preview!.isInMyCalendar;

      setState(() {
        _isCalendarLoading = true;
        _preview = EventPreviewModel(
          event: _preview!.event,
          creator: _preview!.creator,
                isPlatformEvent: _preview!.isPlatformEvent,
                isThirdPartyEvent: _preview!.isThirdPartyEvent,
          canView: _preview!.canView,
          canViewPublicPreview: _preview!.canViewPublicPreview,
          viewerRole: _preview!.viewerRole,
          message: _preview!.message,
          isInMyCalendar: !currentlyInCalendar,
          isLikedByMe: _preview!.isLikedByMe,
          likesCount: _preview!.likesCount,
          attendeeCount: _preview!.attendeeCount + (!currentlyInCalendar ? 1 : -1),
          amisDansAgenda: _preview!.amisDansAgenda,
          amisDansAgendaCount: _preview!.amisDansAgendaCount,
          amisDansAgendaPhotos: _preview!.amisDansAgendaPhotos,
          ranking: _preview!.ranking,
          tickets: _preview!.tickets,
          cheapestTicket: _preview!.cheapestTicket,
          activitiesLiees: _preview!.activitiesLiees,
          restrictions: _preview!.restrictions,
          canAccess: _preview!.canAccess,
          canInteract: _preview!.canInteract,
          canLike: _preview!.canLike,
          canComment: _preview!.canComment,
          canRate: _preview!.canRate,
          canShare: _preview!.canShare,
          canAddToCalendar: _preview!.canAddToCalendar,
          canRegister: _preview!.canRegister,
          prestigeScore: _preview!.prestigeScore,
          prestigeStars: _preview!.prestigeStars,
        );
      });

      try {
        if (!currentlyInCalendar) {
          final suggestedCommunityId = await repo.addEventToCalendarOptimistic(_eventId!, userId);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '✓ Événement ajouté au calendrier',
                        style: AppTextStyles.bodySmall.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                backgroundColor: AppColors.success,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            );
          }
          if (suggestedCommunityId != null && suggestedCommunityId.isNotEmpty && mounted) {
            _showJoinCommunityDialog(suggestedCommunityId);
          }
        } else {
          await repo.removeEventFromCalendarOptimistic(_eventId!, userId);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Événement retiré de votre calendrier',
                  style: AppTextStyles.bodySmall.copyWith(color: Colors.white),
                ),
                backgroundColor: AppColors.primary,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            );
          }
        }
        _loadData();
      } catch (e) {
        debugPrint('[EventPreviewScreen] calendar toggle error: $e');
        if (mounted) {
          _loadData();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Impossible de modifier votre agenda. Veuillez réessayer.',
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
          setState(() => _isCalendarLoading = false);
        }
      }
    }
  }

  bool _isLikeLoading = false;

  Future<void> _toggleLike() async {
    if (_isLikeLoading || _preview == null || _eventId == null) return;
    if (!_preview!.canLike) return;

    final oldIsLiked = _preview!.isLikedByMe;
    final oldLikesCount = _preview!.likesCount;
    final newIsLiked = !oldIsLiked;
    final newLikesCount = newIsLiked ? oldLikesCount + 1 : (oldLikesCount > 0 ? oldLikesCount - 1 : 0);

    setState(() {
      _isLikeLoading = true;
      _preview = EventPreviewModel(
        event: _preview!.event,
        creator: _preview!.creator,
                isPlatformEvent: _preview!.isPlatformEvent,
                isThirdPartyEvent: _preview!.isThirdPartyEvent,
        canView: _preview!.canView,
        canViewPublicPreview: _preview!.canViewPublicPreview,
        viewerRole: _preview!.viewerRole,
        message: _preview!.message,
        isInMyCalendar: _preview!.isInMyCalendar,
        isLikedByMe: newIsLiked,
        likesCount: newLikesCount,
        attendeeCount: _preview!.attendeeCount,
        amisDansAgenda: _preview!.amisDansAgenda,
        amisDansAgendaCount: _preview!.amisDansAgendaCount,
        amisDansAgendaPhotos: _preview!.amisDansAgendaPhotos,
        ranking: _preview!.ranking,
        tickets: _preview!.tickets,
        cheapestTicket: _preview!.cheapestTicket,
        activitiesLiees: _preview!.activitiesLiees,
        restrictions: _preview!.restrictions,
        canAccess: _preview!.canAccess,
        canInteract: _preview!.canInteract,
        canLike: _preview!.canLike,
        canComment: _preview!.canComment,
        canRate: _preview!.canRate,
        canShare: _preview!.canShare,
        canAddToCalendar: _preview!.canAddToCalendar,
        canRegister: _preview!.canRegister,
        prestigeScore: _preview!.prestigeScore,
        prestigeStars: _preview!.prestigeStars,
      );
    });

    if (newIsLiked) {
      _heartsAnimationController.forward(from: 0.0);
    } else {
      _heartsAnimationController.reverse(from: 1.0);
    }

    try {
      final repo = Get.find<EventRepository>();
      final updatedIsLiked = await repo.toggleEventLike(_eventId!, oldIsLiked);

      if (mounted) {
        setState(() {
          _isLikeLoading = false;
          _preview = EventPreviewModel(
            event: _preview!.event,
            creator: _preview!.creator,
                isPlatformEvent: _preview!.isPlatformEvent,
                isThirdPartyEvent: _preview!.isThirdPartyEvent,
            canView: _preview!.canView,
            canViewPublicPreview: _preview!.canViewPublicPreview,
            viewerRole: _preview!.viewerRole,
            message: _preview!.message,
            isInMyCalendar: _preview!.isInMyCalendar,
            isLikedByMe: updatedIsLiked,
            likesCount: updatedIsLiked ? (oldIsLiked ? oldLikesCount : oldLikesCount + 1) : (oldIsLiked ? (oldLikesCount > 0 ? oldLikesCount - 1 : 0) : oldLikesCount),
            attendeeCount: _preview!.attendeeCount,
            amisDansAgenda: _preview!.amisDansAgenda,
            amisDansAgendaCount: _preview!.amisDansAgendaCount,
            amisDansAgendaPhotos: _preview!.amisDansAgendaPhotos,
            ranking: _preview!.ranking,
            tickets: _preview!.tickets,
            cheapestTicket: _preview!.cheapestTicket,
            activitiesLiees: _preview!.activitiesLiees,
            restrictions: _preview!.restrictions,
            canAccess: _preview!.canAccess,
            canInteract: _preview!.canInteract,
            canLike: _preview!.canLike,
            canComment: _preview!.canComment,
            canRate: _preview!.canRate,
            canShare: _preview!.canShare,
            canAddToCalendar: _preview!.canAddToCalendar,
            canRegister: _preview!.canRegister,
            prestigeScore: _preview!.prestigeScore,
            prestigeStars: _preview!.prestigeStars,
          );
        });
      }
    } catch (e) {
      debugPrint('[EventPreviewScreen] Error toggling like: $e');
      if (mounted) {
        setState(() {
          _isLikeLoading = false;
          _preview = EventPreviewModel(
            event: _preview!.event,
            creator: _preview!.creator,
                isPlatformEvent: _preview!.isPlatformEvent,
                isThirdPartyEvent: _preview!.isThirdPartyEvent,
            canView: _preview!.canView,
            canViewPublicPreview: _preview!.canViewPublicPreview,
            viewerRole: _preview!.viewerRole,
            message: _preview!.message,
            isInMyCalendar: _preview!.isInMyCalendar,
            isLikedByMe: oldIsLiked,
            likesCount: oldLikesCount,
            attendeeCount: _preview!.attendeeCount,
            amisDansAgenda: _preview!.amisDansAgenda,
            amisDansAgendaCount: _preview!.amisDansAgendaCount,
            amisDansAgendaPhotos: _preview!.amisDansAgendaPhotos,
            ranking: _preview!.ranking,
            tickets: _preview!.tickets,
            cheapestTicket: _preview!.cheapestTicket,
            activitiesLiees: _preview!.activitiesLiees,
            restrictions: _preview!.restrictions,
            canAccess: _preview!.canAccess,
            canInteract: _preview!.canInteract,
            canLike: _preview!.canLike,
            canComment: _preview!.canComment,
            canRate: _preview!.canRate,
            canShare: _preview!.canShare,
            canAddToCalendar: _preview!.canAddToCalendar,
            canRegister: _preview!.canRegister,
            prestigeScore: _preview!.prestigeScore,
            prestigeStars: _preview!.prestigeStars,
          );
        });

        if (oldIsLiked) {
          _heartsAnimationController.forward(from: 1.0);
        } else {
          _heartsAnimationController.reverse(from: 0.0);
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Impossible de modifier votre mention J\'aime. Veuillez réessayer.',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.white),
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  void _shareEvent() {
    if (_preview == null || !_preview!.canShare) return;

    EventSharePosterService.shareEventPoster(
      context: context,
      preview: _preview!,
      repository: Get.find<EventRepository>(),
      isAttending: _preview!.isInMyCalendar,
      profilePhotoUrl: (Get.find<AppController>().profile.value?['photo_url'] ?? '').toString(),
      onShareSuccess: (_) {
        if (mounted) {
          setState(() {});
        }
      },
    );
  }

  void _openCommentSheet() {
    if (_preview != null && !_preview!.canComment) return;
    Get.to(() => EventCommentsScreen(
      eventId: _eventId ?? '',
      eventName: _preview?.event.name ?? '',
    ));
  }

  void _openRatingSheet() {
    if (_preview == null || !_preview!.canRate) return;
    Get.to(() => EventRatingScreen(event: _preview!.event));
  }

  Future<void> _createNextEdition() async {
    final event = _preview?.event;
    if (event == null ||
        event.status != EventStatus.completed ||
        Get.find<AppController>().authUser.value?.id != event.creatorId) {
      return;
    }

    final now = DateTime.now();
    final initial = event.startsAt.isAfter(now)
        ? event.startsAt.add(const Duration(days: 1))
        : now.add(const Duration(days: 1));
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
      helpText: 'Date de la nouvelle édition',
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(event.startsAt),
      helpText: 'Heure de début',
    );
    if (pickedTime == null || !mounted) return;

    final startsAt = DateTime(pickedDate.year, pickedDate.month, pickedDate.day,
        pickedTime.hour, pickedTime.minute);
    if (!startsAt.isAfter(DateTime.now())) {
      Get.snackbar('Date invalide', 'La nouvelle édition doit commencer dans le futur.');
      return;
    }

    try {
      final created = await Get.find<EventRepository>().createNextEventEdition(
        sourceEventId: event.id,
        startsAt: startsAt,
      );
      if (!mounted) return;
      Get.snackbar(
        'Nouvelle édition créée',
        'L’édition n°${created.editionNumber} a été créée. Vous pouvez maintenant personnaliser sa couverture et sa description.',
        snackPosition: SnackPosition.BOTTOM,
      );
      Get.off(() => EventPreviewScreen(initialEvent: created));
      Get.toNamed(AppPages.eventEdit.replaceFirst(':id', created.id), arguments: created);
    } catch (error) {
      if (mounted) {
        Get.snackbar('Création impossible', error.toString(),
            snackPosition: SnackPosition.BOTTOM);
      }
    }
  }

  void _openArchivedItinerary() {
    final event = _preview?.event;
    if (event == null) return;
    final userId = widget.profileUserId ??
        Get.find<AppController>().authUser.value?.id ??
        '';
    if (userId.isEmpty) return;
    final currentUserId = Get.find<AppController>().authUser.value?.id ?? '';
    if (userId == currentUserId) {
      Get.to(() => EventItineraryOverviewScreen(event: event, readOnly: true));
    } else {
      Get.to(() => ExternalEventItineraryScreen(
        userId: userId,
        eventId: event.id,
        eventName: event.name,
        eventPhoto: event.coverImageUrl ?? '',
        eventLocation: event.locationDisplay,
      ));
    }
  }

  void _showReportSheet() {
    final event = _preview?.event;
    if (event == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ReportEventSheet(
        eventName: event.name,
        onSubmit: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'event_detail_report_sent'.tr,
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.white),
              ),
              backgroundColor: AppColors.black1,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        },
      ),
    );
  }

  void _showJoinCommunityDialog(String communityId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => ScroleBottomSheet(
        child: Column(
          children: [
            Text('Rejoindre la communauté ?', style: AppTextStyles.h4),
            const SizedBox(height: 12),
            Text(
              'Cet événement est rattaché à une communauté dont vous n\'êtes pas encore membre.',
              style: AppTextStyles.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ScroleBottomSheetGroup(
              children: [
                ScroleBottomSheetAction(
                  label: 'Voir la communauté',
                  color: AppColors.primary,
                  onTap: () {
                    Get.back();
                    Get.toNamed(AppPages.communityDetailPath(communityId));
                  },
                ),
                ScroleBottomSheetAction(
                  label: 'Plus tard',
                  onTap: () => Get.back(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatEventDateTime(DateTime value) {
    final locale = Get.locale?.toLanguageTag() ?? 'fr_FR';
    try {
      return DateFormat('d MMMM yyyy · HH:mm', locale).format(value);
    } catch (_) {
      return DateFormat('d MMMM yyyy · HH:mm').format(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_preview == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Aperçu de l\'événement')),
        body: const Center(child: Text('Impossible de charger la fiche événement.')),
      );
    }

    final preview = _preview!;

    // Si la preview publique n'est pas autorisée par le backend pour ce rôle/utilisateur
    if (!preview.canViewPublicPreview) {
      return _RestrictedPreviewView(
        preview: preview,
        eventId: _eventId ?? '',
        contextRole: _contextRole,
      );
    }

    final event = preview.event;
    final ranking = preview.ranking;
    final creator = preview.creator;
    final currentUserId = Get.find<AppController>().authUser.value?.id;

    final isOwnerOrCoFounder = (_contextRole == 'owner' || _contextRole == 'managed' ||
        event.userRole == 'fondateur' || event.userRole == 'co_createur' ||
        (currentUserId != null && currentUserId.isNotEmpty && event.creatorId == currentUserId));
    final normalizedRoles = <String>{
      (_contextRole ?? '').trim().toLowerCase(),
      (event.userRole ?? '').trim().toLowerCase(),
      (preview.viewerRole ?? '').trim().toLowerCase(),
    };
    final isStaffMember = normalizedRoles.any((role) => const {
      'staff', 'member_staff', 'membre_staff', 'staff_member',
      'membre du staff', 'event_staff',
    }.contains(role));
    final canManageActivities = isOwnerOrCoFounder || isStaffMember ||
        normalizedRoles.any((role) => const {
          'owner', 'creator', 'fondateur', 'cofounder', 'co_founder',
          'co_createur', 'co_creator', 'managed',
        }.contains(role));

    // Le scan est disponible aux organisateurs/co-fondateurs et à tout
    // membre du staff confirmé, quel que soit le point d'entrée de la preview.
    final canScan = isOwnerOrCoFounder || isStaffMember;

    final showCalendarAction = preview.canAddToCalendar && !isOwnerOrCoFounder;
    final showPublicInteractions = !isOwnerOrCoFounder &&
        (_contextRole == 'public' || _contextRole == null);

    // Calcul du budget total estimé
    final cheapestAmount = preview.cheapestTicket != null
        ? preview.cheapestTicket!.converted.amount
        : (event.isFree ? 0.0 : (event.price ?? 0.0));
    final cheapestSymbol = preview.cheapestTicket != null
        ? preview.cheapestTicket!.converted.symbol
        : (event.currency ?? 'FCFA');

    final activitiesTotal = preview.activitiesLiees.fold<double>(
      0.0,
      (sum, act) => sum + act.converted.amount,
    );
    final estimatedTotalBudget = cheapestAmount + activitiesTotal;

    // Compteur d'ajouts à l'agenda
    final totalAdded = preview.attendeeCount > 0 ? preview.attendeeCount : event.totalAddedCount;

    return Scaffold(
      body: NotificationListener<UserScrollNotification>(
        onNotification: (notification) {
          if (notification.direction == ScrollDirection.reverse && _isActionBarVisible) {
            setState(() => _isActionBarVisible = false);
          } else if (notification.direction == ScrollDirection.forward && !_isActionBarVisible) {
            setState(() => _isActionBarVisible = true);
          }
          return false;
        },
        child: CustomScrollView(
        slivers: [
          if (!widget.archiveTabMode) SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            leading: Center(
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: _HeaderActionButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  tooltip: 'Retour',
                  onPressed: () => Get.back(),
                ),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: event.coverImageUrl != null && event.coverImageUrl!.isNotEmpty
                  ? AppCachedImage(imageUrl: event.coverImageUrl!, fit: BoxFit.cover)
                  : Container(
                      color: const Color(0xFF27272A),
                      child: const Icon(Icons.event_outlined, size: 64, color: AppColors.textSecondary),
                    ),
            ),
            actions: [
              if (!widget.archiveTabMode && _seriesEditions.any((edition) =>
                  (edition['status'] ?? '').toString().toLowerCase() == 'completed'))
                IconButton(
                  tooltip: 'Éditions passées',
                  icon: const Icon(Icons.history_rounded),
                  onPressed: () {
                    final pastEditions = _seriesEditions.where((edition) =>
                      (edition['status'] ?? '').toString().toLowerCase() == 'completed'
                    ).toList();
                    final series = <String, dynamic>{
                      'id': event.seriesId ?? event.id,
                      'series_id': event.seriesId ?? event.id,
                      'name': event.name,
                      'photo': event.coverImageUrl,
                      'description': event.description,
                      'edition_count': pastEditions.length,
                      'editions': pastEditions,
                    };
                    Get.to(() => ProfileEventSeriesScreen(
                      series: series,
                      profileUserId: currentUserId ?? '',
                    ));
                  },
                ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Center(
                  child: _HeaderActionButton(
                    svgPath: 'assets/svg_icons/chat-round-svgrepo-com.svg',
                    tooltip: 'Commentaires',
                    onPressed: preview.canComment ? _openCommentSheet : null,
                  ),
                ),
              ),
              if (_contextRole == 'public')
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Center(
                    child: _HeaderActionButton(
                      icon: Icons.more_vert,
                      tooltip: 'Signaler cet événement',
                      onPressed: _showReportSheet,
                    ),
                  ),
                ),
              if (event.status == EventStatus.completed &&
                  currentUserId != null && currentUserId == event.creatorId)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Center(
                    child: _HeaderActionButton(
                      icon: Icons.add_circle_outline_rounded,
                      tooltip: 'Créer une nouvelle édition',
                      onPressed: _createNextEdition,
                    ),
                  ),
                ),
              if (event.status == EventStatus.completed)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Center(
                    child: _HeaderActionButton(
                      icon: Icons.route_rounded,
                      tooltip: 'Revoir mon programme',
                      onPressed: _openArchivedItinerary,
                    ),
                  ),
                ),
              if (canScan)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Center(
                    child: _HeaderActionButton(
                      icon: Icons.qr_code_scanner_rounded,
                      tooltip: 'Scanner Check-in',
                      onPressed: () => Get.toNamed(
                        AppPages.eventScan.replaceFirst(':id', event.id),
                        arguments: event,
                      ),
                    ),
                  ),
                ),
              if (isOwnerOrCoFounder)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Center(
                    child: _HeaderActionButton(
                      icon: Icons.settings_outlined,
                      tooltip: event.status == EventStatus.draft
                          ? 'Paramètres indisponibles pendant la validation'
                          : 'Paramètres',
                      onPressed: event.status == EventStatus.draft
                          ? null
                          : () => Get.toNamed(
                              AppPages.eventSettings.replaceFirst(':id', event.id),
                              arguments: event,
                            ),
                    ),
                  ),
                ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Bandeau d'état Sync & Validation admin
                  if (event.statutSync == 'echec' || event.statutSync == 'rejected')
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Modification locale non synchronisée. Conservée en cache local.',
                              style: AppTextStyles.bodySmall.copyWith(color: AppColors.error, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (event.status == EventStatus.draft)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber[800]!.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.hourglass_top_rounded, color: Colors.amber[800], size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Événement enregistré ! En attente de validation administrative.',
                              style: AppTextStyles.bodySmall.copyWith(color: Colors.amber[900], fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Metadata Row: Badge Rôle, Statut Événement & Rang Position
                  Row(
                    children: [
                      _buildRoleBadge(isOwnerOrCoFounder ? 'owner' : _contextRole, event.userRole),
                      const SizedBox(width: 8),
                      _buildStatusBadge(event.status),
                      const Spacer(),
                      if (ranking.rang > 0 &&
                          (event.status != EventStatus.completed || ranking.isFrozen))
                        _buildRankBadge(ranking),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Notice événement inaccessible
                  if (!preview.canAccess)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.block_rounded, color: AppColors.error, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Vous ne remplissez pas les conditions d\'accès à cet événement.',
                              style: AppTextStyles.bodySmall.copyWith(color: AppColors.error, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Titre & Slug
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        fit: FlexFit.loose,
                        child: Text(
                          event.name,
                          style: GoogleFonts.spaceGrotesk(fontSize: 26, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 5),
                      EntityCertifiedBadge(
                        entityType: 'event',
                        entityId: event.id,
                        size: 22,
                      ),
                    ],
                  ),
                  Text(
                    '@${event.slug}',
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 16),

                  // Identité de la plateforme ou créateur réel de l'événement.
                  if (preview.isPlatformEvent)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          ClipOval(
                            child: Image.asset(
                              'assets/logos/img.png',
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 44,
                                height: 44,
                                color: AppColors.primary,
                                child: const Icon(Icons.business_rounded, color: Colors.white, size: 22),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Scrole', style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('event_platform_account'.tr, style: AppTextStyles.bodySmall),
                                  const SizedBox(width: 6),
                                  const Icon(Icons.verified_rounded, size: 16, color: Color(0xFF1877F2)),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  else if (creator != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          ClipOval(
                            child: creator.photoUrl != null && creator.photoUrl!.isNotEmpty
                                ? AppCachedImage(imageUrl: creator.photoUrl!, width: 40, height: 40, fit: BoxFit.cover)
                                : Container(
                                    width: 40,
                                    height: 40,
                                    color: AppColors.primary,
                                    child: const Icon(Icons.person, color: Colors.white, size: 20),
                                  ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(creator.fullName, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    creator.isAdminCreator
                                        ? 'event_admin_creator'.tr
                                        : '@${creator.username}',
                                    style: AppTextStyles.bodySmall,
                                  ),
                                  const SizedBox(width: 6),
                                  if (!creator.isAdminCreator)
                                    UserCertifiedBadge(
                                      userId: creator.userId,
                                      type: CertificationBadgeType.basic,
                                      size: 16,
                                    )
                                  else
                                    const Icon(Icons.verified_rounded, size: 16, color: Color(0xFF1877F2)),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                  if (preview.isThirdPartyEvent) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded, color: colorScheme.primary, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'event_platform_third_party_notice'.tr,
                              style: AppTextStyles.bodySmall.copyWith(height: 1.45),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // Dates de début, de fin et jours de participation
                  _InfoRow(
                    icon: Icons.calendar_today_rounded,
                    text: '${'event_detail_start'.tr} : ${_formatEventDateTime(event.startsAt)}',
                  ),
                  const SizedBox(height: 10),
                  if (event.endsAt != null)
                    _InfoRow(
                      icon: Icons.event_available_rounded,
                      text: '${'event_detail_end'.tr} : ${_formatEventDateTime(event.endsAt!)}',
                    ),
                  if (event.endsAt != null) const SizedBox(height: 10),
                  _InfoRow(
                    icon: Icons.calendar_view_day_rounded,
                    text: _previewOpenDays.isEmpty
                        ? 'event_detail_no_days'.tr
                        : 'event_detail_days_count'.trParams({'count': _previewOpenDays.length.toString()}),
                  ),
                  const SizedBox(height: 12),
                  _InfoRow(
                    icon: Icons.location_on_outlined,
                    text: event.locationDisplay,
                  ),

                  const SizedBox(height: 20),

                  // Bloc Tarification: Prix billet minimum & Budget total estimé
                  Row(
                    children: [
                      Expanded(
                        child: _TariffCard(
                          title: 'Prix Billet Min.',
                          amount: cheapestAmount <= 0
                              ? 'Gratuit'
                              : NumberFormatter.formatPrice(cheapestAmount, cheapestSymbol),
                          icon: Icons.confirmation_number_outlined,
                          colorScheme: colorScheme,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            Get.toNamed(
                              AppPages.eventBudget.replaceFirst(':id', event.id),
                              arguments: {
                                'tickets': preview.tickets,
                                'activities': preview.activitiesLiees,
                                'cheapestTicket': preview.cheapestTicket,
                                'eventId': event.id,
                              },
                            );
                          },
                          child: _TariffCard(
                            title: 'Budget Est. Total',
                            amount: estimatedTotalBudget <= 0
                                ? 'Gratuit'
                                : NumberFormatter.formatPrice(estimatedTotalBudget, cheapestSymbol),
                            icon: Icons.account_balance_wallet_outlined,
                            colorScheme: colorScheme,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Statistique Ajout à l'agenda (Concept "Ajout")
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_month_rounded, size: 18, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          '${NumberFormatter.formatCount(totalAdded)} ajouts à l\'agenda',
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Section Amis ayant ajouté l'événement
                  if (preview.amisDansAgendaPhotos.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('Amis ayant ajouté l\'événement', style: AppTextStyles.h4),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        SizedBox(
                          height: 36,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            shrinkWrap: true,
                            itemCount: preview.amisDansAgendaPhotos.length,
                            itemBuilder: (context, index) {
                              final photo = preview.amisDansAgendaPhotos[index];
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: colorScheme.surface, width: 1.5),
                                  ),
                                  child: ClipOval(
                                    child: photo.isNotEmpty
                                        ? AppCachedImage(imageUrl: photo, fit: BoxFit.cover)
                                        : Container(
                                            color: colorScheme.surfaceContainerHighest,
                                            child: Icon(Icons.person, size: 20, color: colorScheme.onSurfaceVariant),
                                          ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        if (preview.amisDansAgendaCount > preview.amisDansAgendaPhotos.length) ...[
                          const SizedBox(width: 6),
                          Text(
                            '+${preview.amisDansAgendaCount - preview.amisDansAgendaPhotos.length}',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],

                  // Les activités sont consultables sur une page dédiée.
                  if (preview.activitiesLiees.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Get.to(
                            () => EventActivitiesListScreen(
                              activities: preview.activitiesLiees,
                            ),
                            transition: Transition.rightToLeft,
                          );
                        },
                        icon: const Icon(Icons.local_activity_outlined),
                        label: Text(
                          'event_detail_activities'.tr,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Description avec 'Voir plus' (max 3 lignes)
                  Text('À propos', style: AppTextStyles.h4),
                  const SizedBox(height: 8),
                  ExpandableText(
                    text: event.description ?? 'Aucune description fournie.',
                    maxLines: 3,
                    style: AppTextStyles.body.copyWith(color: colorScheme.onSurface),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
        ),
      ),
      bottomNavigationBar: (widget.archiveTabMode || event.status == EventStatus.completed ||
              (!showCalendarAction && !showPublicInteractions))
          ? null
          : AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: _isActionBarVisible
                  ? Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3), width: 1)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showCalendarAction)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isCalendarLoading ? null : _handleCalendarAction,
                          icon: Icon(preview.isInMyCalendar ? Icons.check : Icons.calendar_today, size: 18),
                          label: Text(
                            preview.isInMyCalendar
                                ? 'event_added_to_calendar'.tr
                                : 'event_add_to_calendar'.tr,
                            style: AppTextStyles.buttonSmall.copyWith(fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: preview.isInMyCalendar ? AppColors.success : AppColors.primary,
                            foregroundColor: AppColors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                        ),
                      ),
                    if (showCalendarAction && showPublicInteractions)
                      const SizedBox(height: 10),
                    if (showPublicInteractions)
                      Row(
                        children: [
                          // 1. J'AIME
                          Expanded(
                            child: Stack(
                              clipBehavior: Clip.none,
                              alignment: Alignment.center,
                              children: [
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: (_isLikeLoading || !preview.canLike) ? null : _toggleLike,
                                    icon: Icon(
                                      preview.isLikedByMe ? Icons.favorite : Icons.favorite_border,
                                      size: 16,
                                      color: preview.isLikedByMe ? AppColors.error : colorScheme.onSurface,
                                    ),
                                    label: Text(
                                      NumberFormatter.formatCount(preview.likesCount),
                                      style: AppTextStyles.buttonSmall.copyWith(
                                        color: preview.isLikedByMe ? AppColors.error : colorScheme.onSurface,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: preview.isLikedByMe ? AppColors.error : colorScheme.onSurface,
                                      side: BorderSide(
                                        color: preview.isLikedByMe
                                            ? AppColors.error.withValues(alpha: 0.4)
                                            : colorScheme.outlineVariant.withValues(alpha: 0.5),
                                      ),
                                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  bottom: 24,
                                  child: IgnorePointer(
                                    child: Lottie.asset(
                                      'assets/lotties/head.json',
                                      controller: _heartsAnimationController,
                                      width: 140,
                                      height: 140,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // 2. NOTER
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: preview.canRate ? _openRatingSheet : null,
                              icon: Icon(Icons.star_outline_rounded, size: 16, color: colorScheme.onSurface),
                              label: Text(
                                'event_detail_rate'.tr,
                                style: AppTextStyles.buttonSmall.copyWith(color: colorScheme.onSurface),
                                overflow: TextOverflow.ellipsis,
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: colorScheme.onSurface,
                                side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // 3. PARTAGER
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: preview.canShare ? _shareEvent : null,
                              icon: Icon(Icons.share_outlined, size: 16, color: colorScheme.onSurface),
                              label: Text(
                                NumberFormatter.formatCount(preview.shareCount),
                                style: AppTextStyles.buttonSmall.copyWith(color: colorScheme.onSurface),
                                overflow: TextOverflow.ellipsis,
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: colorScheme.onSurface,
                                side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              )
                  : const SizedBox.shrink(),
            ),
    );
  }

  void _showTicketsOrRegistrationSheet(BuildContext context, EventPreviewModel preview) {
    if (preview.tickets.isNotEmpty) {
      Get.toNamed(AppPages.eventPricing.replaceFirst(':id', _eventId!), arguments: preview);
    } else {
      Get.snackbar('Inscription', 'Inscription enregistrée avec succès !', snackPosition: SnackPosition.BOTTOM);
    }
  }

  Widget _buildRoleBadge(String? contextRole, String? userRole) {
    String label = 'Public';
    Color color = Colors.grey;

    if (contextRole == 'owner' || contextRole == 'managed') {
      label = userRole == 'co_createur' ? 'Co-fondateur' : 'Fondateur';
      color = AppColors.primary;
    } else if (contextRole == 'staff') {
      label = 'Staff';
      color = Colors.blue;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Widget _buildStatusBadge(EventStatus status) {
    String label = status.value;
    Color color = Colors.grey;

    if (status == EventStatus.published || status == EventStatus.completed) {
      final now = DateTime.now();
      final event = _preview?.event;
      if (status == EventStatus.completed ||
          (event?.endsAt != null && now.isAfter(event!.endsAt!))) {
        label = 'event_detail_status_completed'.tr;
        color = Colors.grey;
      } else if (event != null && now.isBefore(event.startsAt)) {
        label = 'event_detail_status_upcoming'.tr;
        color = AppColors.primary;
      } else {
        label = 'event_detail_status_ongoing'.tr;
        color = AppColors.success;
      }
    } else if (status == EventStatus.draft) {
      label = 'event_detail_status_pending'.tr;
      color = Colors.amber[800]!;
    } else if (status == EventStatus.pendingDeletion) {
      label = 'event_detail_status_deleting'.tr;
      color = AppColors.error;
    } else if (status == EventStatus.cancelled) {
      label = 'event_detail_status_cancelled'.tr;
      color = AppColors.error;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Widget _buildRankBadge(EventRankingInfo ranking) {
    final label = ranking.isFrozen
        ? 'Rang final #${ranking.rang}'
        : '#${ranking.rang}';
    final tooltip = ranking.sur > 0
        ? '${ranking.rang}e sur ${ranking.sur} événements · score ${ranking.score.toStringAsFixed(0)}'
        : 'Classement global';
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
        ),
      ),
    );
  }
}

class _TariffCard extends StatelessWidget {
  const _TariffCard({
    required this.title,
    required this.amount,
    required this.icon,
    required this.colorScheme,
  });

  final String title;
  final String amount;
  final IconData icon;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            amount,
            style: TextStyle(
              fontSize: 15,
              color: colorScheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _RestrictedPreviewView extends StatelessWidget {
  const _RestrictedPreviewView({
    required this.preview,
    required this.eventId,
    this.contextRole,
  });

  final EventPreviewModel preview;
  final String eventId;
  final String? contextRole;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final event = preview.event;
    final message = preview.message ??
        'Cette prévisualisation publique n\'est pas disponible pour votre rôle actuel (${preview.viewerRole ?? contextRole ?? "organisateur"}).';

    final isOwnerOrStaff = (preview.viewerRole == 'owner' ||
        preview.viewerRole == 'cofounder' ||
        preview.viewerRole == 'staff' ||
        contextRole == 'owner' ||
        contextRole == 'staff');

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              fit: FlexFit.loose,
              child: Text(
                event.name.isNotEmpty ? event.name : 'Aperçu restreint',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            EntityCertifiedBadge(
              entityType: 'event',
              entityId: event.id,
              size: 18,
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Get.back(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.admin_panel_settings_rounded,
                  size: 42,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Prévisualisation publique restreinte',
                style: AppTextStyles.h4.copyWith(color: colorScheme.onSurface),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                message,
                style: AppTextStyles.body.copyWith(color: colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              if (isOwnerOrStaff) ...[
                ElevatedButton.icon(
                  onPressed: () {
                    Get.back();
                    if (preview.viewerRole == 'staff' || contextRole == 'staff') {
                      Get.toNamed(AppPages.eventScan.replaceFirst(':id', eventId));
                    } else {
                      Get.toNamed(AppPages.eventSettings.replaceFirst(':id', eventId));
                    }
                  },
                  icon: const Icon(Icons.dashboard_rounded),
                  label: const Text('Ouvrir l\'espace de gestion'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              OutlinedButton(
                onPressed: () => Get.back(),
                child: const Text('Retour'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: AppTextStyles.body),
        ),
      ],
    );
  }
}

class _HeaderActionButton extends StatelessWidget {
  final IconData? icon;
  final String? svgPath;
  final String tooltip;
  final VoidCallback? onPressed;

  const _HeaderActionButton({
    this.icon,
    this.svgPath,
    required this.tooltip,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.25),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: svgPath != null
                ? SvgPicture.asset(
                    svgPath!,
                    width: 20,
                    height: 20,
                    colorFilter: ColorFilter.mode(
                      onPressed != null ? Colors.white : Colors.white.withValues(alpha: 0.3),
                      BlendMode.srcIn,
                    ),
                  )
                : Icon(
                    icon,
                    color: onPressed != null ? Colors.white : Colors.white.withValues(alpha: 0.3),
                    size: 20,
                  ),
          ),
        ),
      ),
    );
  }
}
