import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import '../../../../app/routes/app_pages.dart';
import '../../../../shared/utils/number_formatter.dart';
import '../../../../shared/widgets/scrole_bottom_sheet.dart';
import '../../../../shared/widgets/entity_certified_badge.dart';
import '../../../../shared/widgets/expandable_text_widget.dart';
import 'package:scrole/modules/module_evenement/interne/pages/report_event_sheet.dart';
import '../../../../../app_controller.dart';
import '../../../../../app/theme/app_colors.dart';
import '../../../../../app/theme/text_styles.dart';
import '../../../../../shared/widgets/app_cached_image.dart';
import '../../centre/models/event_model.dart';
import '../../centre/models/event_preview_model.dart';
import '../../centre/repositories/event_repository.dart';
import '../../centre/services/event_share_poster_service.dart';
import '../controllers/event_controller.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../centre/models/event_day_models.dart';
import '../enums/event_enum.dart';
import '../widgets/add_to_calendar_dialog.dart';
import 'event_days_selector_screen.dart';
import 'event_itinerary_screen.dart';
import 'event_comments_screen.dart';
import 'event_rating_screen.dart';
import '../widgets/event_share_options_sheet.dart';
import '../widgets/event_share_card_design_picker.dart';
import '../../../module_principale/interne/pages/create_story_screen.dart';
import '../../../module_communautes/interne/pages/create_community_post_screen.dart';

class EventDetailPage extends StatefulWidget {
  final EventModel event;

  const EventDetailPage({super.key, required this.event});

  @override
  State<EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends State<EventDetailPage> with SingleTickerProviderStateMixin {
  EventPreviewModel? _preview;
  bool _isLoading = true;
  bool _isLiked = false;
  int _likesCount = 0;
  bool _isLikeLoading = false;
  bool _isEventAdded = false;
  bool _descriptionExpanded = false;
  final Map<String, bool> _joinedActivities = {};

  StreamSubscription<EventModel>? _eventUpdateSubscription;
  late AnimationController _heartsAnimationController;

  bool _isCalendarLoading = false;

  @override
  void initState() {
    super.initState();
    _heartsAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _loadPreview();
    _listenToEventUpdates();
  }

  void _listenToEventUpdates() {
    _eventUpdateSubscription = Get.find<EventRepository>().onEventUpdated.listen((updatedEvent) {
      if (updatedEvent.id == widget.event.id) {
        debugPrint('[EventDetailPage] Live update for ${updatedEvent.id}');
        if (mounted) {
          setState(() {
            if (_preview != null) {
              _preview = EventPreviewModel(
                event: updatedEvent,
                creator: _preview!.creator,
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
            }
          });
        }
      }
    });
  }

  Future<void> _loadPreview() async {
    setState(() => _isLoading = true);
    try {
      final repo = Get.find<EventRepository>();
      repo.subscribeToEventUpdates(widget.event.id);

      EventPreviewModel preview;
      try {
        preview = await repo.getEventPreviewPublic(widget.event.id);
        // La RPC publique renvoie volontairement un aperçu restreint aux membres
        // de l'équipe. Pour le propriétaire/co-créateur/staff, récupérer le bon
        // payload afin de ne pas perdre les activités liées à l'événement.
        if (!preview.canViewPublicPreview) {
          final role = (preview.viewerRole ?? '').toLowerCase();
          if (['owner', 'creator', 'fondateur', 'cofounder', 'co_founder', 'co_createur', 'co_creator', 'managed'].contains(role)) {
            preview = await repo.getEventPreviewOwner(widget.event.id);
          } else if (role == 'staff') {
            preview = await repo.getEventPreviewStaff(widget.event.id);
          }
        }
      } catch (e) {
        debugPrint('[EventDetailPage] getEventPreviewPublic error: $e. Falling back to getEventPreview...');
        preview = await repo.getEventPreview(widget.event.id);
      }

      if (mounted) {
        setState(() {
          _preview = preview;
          _isLiked = preview.isLikedByMe;
          _likesCount = preview.likesCount;
          _isEventAdded = preview.isInMyCalendar;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[EventDetailPage] _loadPreview final error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  bool _hasAccessConditions(EventRestrictionsInfo restrictions) {
    return restrictions.minAge != null ||
        restrictions.maxAge != null ||
        restrictions.allowedGenders.isNotEmpty ||
        restrictions.idRequired ||
        restrictions.servesAlcohol ||
        restrictions.overnightEvent ||
        restrictions.smokingAllowed ||
        (restrictions.otherRestrictions?.trim().isNotEmpty ?? false);
  }

  Widget _buildAccessConditions(EventRestrictionsInfo restrictions, ColorScheme colorScheme) {
    final conditions = <({IconData icon, String label})>[];

    if (restrictions.minAge != null && restrictions.maxAge != null) {
      conditions.add((icon: Icons.cake_outlined, label: 'Âge autorisé : ${restrictions.minAge}–${restrictions.maxAge} ans'));
    } else if (restrictions.minAge != null) {
      conditions.add((icon: Icons.cake_outlined, label: 'Âge minimum : ${restrictions.minAge} ans'));
    } else if (restrictions.maxAge != null) {
      conditions.add((icon: Icons.cake_outlined, label: 'Âge maximum : ${restrictions.maxAge} ans'));
    }

    final genders = restrictions.allowedGenders.map((g) => g.toLowerCase()).toSet();
    if (genders.isNotEmpty && !(genders.contains('homme') && genders.contains('femme') && genders.length == 2)) {
      final labels = <String>[];
      if (genders.contains('homme')) labels.add('Hommes');
      if (genders.contains('femme')) labels.add('Femmes');
      if (labels.isNotEmpty) {
        conditions.add((icon: Icons.people_outline, label: 'Accès réservé : ${labels.join(' et ')}'));
      }
    }

    if (restrictions.idRequired) {
      conditions.add((icon: Icons.badge_outlined, label: 'Pièce d’identité obligatoire'));
    }
    if (restrictions.servesAlcohol) {
      conditions.add((icon: Icons.local_bar_outlined, label: 'Boissons alcoolisées servies'));
    }
    if (restrictions.overnightEvent) {
      conditions.add((icon: Icons.nightlight_outlined, label: 'Événement de nuit'));
    }
    if (restrictions.smokingAllowed) {
      conditions.add((icon: Icons.smoking_rooms_outlined, label: 'Tabac autorisé'));
    }

    final other = restrictions.otherRestrictions?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Conditions d’accès',
          style: AppTextStyles.h5.copyWith(color: colorScheme.onSurface),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...conditions.map((condition) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(condition.icon, size: 20, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        condition.label,
                        style: AppTextStyles.body.copyWith(color: colorScheme.onSurface),
                      ),
                    ),
                  ],
                ),
              )),
              if (other != null && other.isNotEmpty)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, size: 20, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(other, style: AppTextStyles.body.copyWith(color: colorScheme.onSurface)),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  void _showTicketsSheet() {
    final tickets = _preview?.tickets ?? [];
    if (tickets.isEmpty) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => ScroleBottomSheet(
        child: Column(
          children: [
            Text('Billets disponibles', style: AppTextStyles.h4),
            const SizedBox(height: 20),
            ScroleBottomSheetGroup(
              children: tickets.map((t) => ScroleBottomSheetAction(
                label: t.name,
                trailing: Text(t.converted.displayString, style: AppTextStyles.h5.copyWith(color: AppColors.primary)),
                onTap: () {},
              )).toList(),
            ),
          ],
        ),
      ),
    );
  }

  void _showReportSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ReportEventSheet(
        eventName: widget.event.name,
        onSubmit: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Signalement envoyé', style: AppTextStyles.bodySmall.copyWith(color: AppColors.white)),
              backgroundColor: AppColors.black1,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        },
      ),
    );
  }

  void _showAddToCalendarDialog() {
    if (_preview != null && !_preview!.canAddToCalendar) return;

    showDialog(
      context: context,
      builder: (_) => AddToCalendarDialog(
        eventName: widget.event.name,
        isRecurring: widget.event.isRecurring,
        onConfirm: ({required notifyConnections, required silentAdd, required recurrence}) async {
          Navigator.pop(context);
          final wasAdded = _isEventAdded;
          setState(() {
            _isCalendarLoading = true;
          });

          try {
            final controller = Get.find<EventController>();
            final suggestedCommunityId = await controller.addToCalendar(widget.event.id);
            if (!mounted) return;
            setState(() => _isEventAdded = true);

          if (suggestedCommunityId != null && suggestedCommunityId.isNotEmpty) {
            Get.snackbar(
              'Communauté associée',
              'Cet événement est lié à une communauté ! Souhaitez-vous la rejoindre ?',
              backgroundColor: Colors.black87,
              colorText: Colors.white,
              mainButton: TextButton(
                onPressed: () => Get.toNamed(AppPages.communityDetailPath(suggestedCommunityId)),
                child: const Text('Rejoindre', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
              ),
              duration: const Duration(seconds: 5),
            );
          } else {
            Get.snackbar(
              'Calendrier',
              'Événement ajouté à votre agenda avec succès !',
              backgroundColor: Colors.black87,
              colorText: Colors.white,
            );
          }
          } catch (e) {
            debugPrint('[EventDetailPage] add to calendar rejected: $e');
            if (mounted) {
              setState(() => _isEventAdded = wasAdded);
              Get.snackbar(
                'Calendrier',
                Get.find<EventRepository>().agendaRestrictionMessageKey(e).tr,
                backgroundColor: AppColors.error,
                colorText: Colors.white,
                duration: const Duration(seconds: 6),
              );
            }
          } finally {
            if (mounted) setState(() => _isCalendarLoading = false);
          }
        },
        onCancel: () => Navigator.pop(context),
      ),
    );
  }

  Future<void> _toggleLike() async {
    if (_isLikeLoading) return;
    if (_preview != null && !_preview!.canLike) return;

    final oldIsLiked = _isLiked;
    final oldLikesCount = _likesCount;

    setState(() {
      _isLikeLoading = true;
      _isLiked = !oldIsLiked;
      _likesCount = _isLiked ? oldLikesCount + 1 : (oldLikesCount > 0 ? oldLikesCount - 1 : 0);
    });

    if (_isLiked) {
      _heartsAnimationController.forward(from: 0.0);
    } else {
      _heartsAnimationController.reverse(from: 1.0);
    }

    try {
      final repo = Get.find<EventRepository>();
      final newIsLiked = await repo.toggleEventLike(widget.event.id, oldIsLiked);

      if (mounted) {
        setState(() {
          _isLiked = newIsLiked;
          _isLikeLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[EventDetailPage] Error toggling like: $e');
      if (mounted) {
        setState(() {
          _isLiked = oldIsLiked;
          _likesCount = oldLikesCount;
          _isLikeLoading = false;
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

  Future<void> _handleCalendarAction() async {
    if (_isCalendarLoading || (_preview != null && !_preview!.canAddToCalendar)) return;

    final startDay = DateTime(widget.event.startsAt.year, widget.event.startsAt.month, widget.event.startsAt.day);
    final endDay = widget.event.endsAt != null
        ? DateTime(widget.event.endsAt!.year, widget.event.endsAt!.month, widget.event.endsAt!.day)
        : startDay;

    final isMultiDay = endDay.difference(startDay).inDays >= 1;

    if (isMultiDay) {
      final repository = Get.find<EventRepository>();
      try {
        final openDays = await repository.getEventOpenDays(widget.event.id);
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
        if (_isEventAdded) {
          preselectedDays = await repository.getMyEventCalendarDays(widget.event.id);
        }

        if (mounted) {
          Get.to(
            () => EventDaysSelectorScreen(
              eventId: widget.event.id,
              eventName: widget.event.name,
              openDays: openDays,
              preselectedDays: preselectedDays,
              isEditing: _isEventAdded,
              onSuccess: () => _loadPreview(),
            ),
            transition: Transition.rightToLeft,
          );
        }
      } catch (e) {
        debugPrint('[EventDetailPage] _handleCalendarAction error: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                Get.find<EventRepository>().agendaRestrictionMessageKey(e).tr,
                style: AppTextStyles.bodySmall.copyWith(color: Colors.white),
              ),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      }
    } else {
      // Événement d'un seul jour -> Ajout/Retrait direct SANS aucun modal
      final repository = Get.find<EventRepository>();
      final userId = Get.find<AppController>().authUser.value?.id ?? '';
      final oldIsAdded = _isEventAdded;

      setState(() {
        _isCalendarLoading = true;
        _isEventAdded = !oldIsAdded;
      });

      try {
        if (!oldIsAdded) {
          await repository.addEventToCalendarOptimistic(widget.event.id, userId);
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
        } else {
          await repository.removeEventFromCalendarOptimistic(widget.event.id, userId);
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
        _loadPreview();
      } catch (e) {
        debugPrint('[EventDetailPage] calendar action error: $e');
        if (mounted) {
          setState(() {
            _isEventAdded = oldIsAdded;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                Get.find<EventRepository>().agendaRestrictionMessageKey(e).tr,
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

  void _showTicketsOrRegistrationSheet(BuildContext context, EventPreviewModel? preview) {
    if (preview != null && preview.tickets.isNotEmpty) {
      Get.toNamed(AppPages.eventPricing.replaceFirst(':id', widget.event.id), arguments: preview);
    } else {
      Get.snackbar('Inscription', 'Inscription enregistrée avec succès !', snackPosition: SnackPosition.BOTTOM);
    }
  }

  String _eventShareText() {
    final event = _preview?.event ?? widget.event;
    final details = <String>[
      'Découvre cet événement : ${event.name}',
      if ((event.description ?? '').trim().isNotEmpty) event.description!.trim(),
    ];
    return details.join('\n\n');
  }

  Future<void> _openEventShareCardPicker({
    required String destination,
    Map<String, dynamic>? community,
  }) async {
    final preview = _preview;
    if (preview == null || !mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (pickerContext) => EventShareCardDesignPicker(
        preview: preview,
        onSelected: (designIndex) async {
          Navigator.of(pickerContext).pop();
          try {
            final cardFile = await EventShareCardRenderer.renderToFile(
              context: context,
              preview: preview,
              designIndex: designIndex,
            );
            if (!mounted) return;
            final caption = _eventShareText();
            if (destination == 'story') {
              Get.to(() => CreateStoryScreen(
                    prefilledText: caption,
                    prefilledMediaUrl: cardFile.path,
                  ));
            } else {
              Get.to(() => CreateCommunityPostScreen(
                    communityId: community == null ? null : (community['id'] ?? '').toString(),
                    communityName: community == null ? 'Mon fil' : (community['name'] ?? 'Communauté').toString(),
                    prefilledText: caption,
                    prefilledMediaUrl: cardFile.path,
                  ));
            }
          } catch (error) {
            if (mounted) {
              Get.snackbar('Partage impossible', 'La carte de l’événement n’a pas pu être créée.');
            }
            debugPrint('[EventShare] Could not render event card: $error');
          }
        },
      ),
    );
  }

  void _shareEvent() {
    if (_preview == null || !_preview!.canShare) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => EventShareOptionsSheet(
        preview: _preview!,
        onFeed: () {
          Navigator.of(sheetContext).pop();
          _openEventShareCardPicker(destination: 'feed');
        },
        onCommunity: () {
          Navigator.of(sheetContext).pop();
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (pickerContext) => EventShareCommunityPicker(
              onSelected: (community) {
                Navigator.of(pickerContext).pop();
                final communityId = (community['id'] ?? '').toString();
                if (communityId.isEmpty) {
                  Get.snackbar('Partage', 'Cette communauté est introuvable.');
                  return;
                }
                _openEventShareCardPicker(destination: 'community', community: community);
              },
            ),
          );
        },
        onStory: () {
          Navigator.of(sheetContext).pop();
          _openEventShareCardPicker(destination: 'story');
        },
        onNativeApps: () {
          Navigator.of(sheetContext).pop();
          EventSharePosterService.shareEventPoster(
            context: context,
            preview: _preview!,
            repository: Get.find<EventRepository>(),
            onShareSuccess: (_) {
              if (mounted) setState(() {});
            },
          );
        },
      ),
    );
  }
  void _openCommentSheet() {
    Get.to(() => EventCommentsScreen(
      eventId: widget.event.id,
      eventName: widget.event.name,
    ));
  }

  void _openRatingSheet() {
    if (_preview != null && !_preview!.canRate) return;
    Get.to(() => EventRatingScreen(event: widget.event));
  }

  void _toggleActivity(String activityId) {
    if (!_isEventAdded) return;
    setState(() {
      _joinedActivities[activityId] = !(_joinedActivities[activityId] ?? false);
    });
  }

  @override
  void dispose() {
    _heartsAnimationController.dispose();
    _eventUpdateSubscription?.cancel();
    Get.find<EventRepository>().unsubscribeFromEventUpdates(widget.event.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Gestion de l'accès restreint si can_view_public_preview est faux
    if (_preview != null && !_preview!.canViewPublicPreview) {
      return _RestrictedPreviewView(
        preview: _preview!,
        eventId: widget.event.id,
      );
    }

    final preview = _preview;
    final event = preview?.event ?? widget.event;
    final ranking = preview?.ranking ?? const EventRankingInfo();
    final creator = preview?.creator;
    final currentUserId = Get.find<AppController>().authUser.value?.id;
    final role = (preview?.viewerRole ?? event.userRole ?? '').toLowerCase();
    final canManageActivities = preview != null && (
      ['owner', 'creator', 'fondateur', 'cofounder', 'co_founder', 'co_createur', 'co_creator', 'managed', 'staff'].contains(role) ||
      (currentUserId != null && currentUserId.isNotEmpty && event.creatorId == currentUserId)
    );

    // Calculs réels pour Billet minimum & Budget total estimé
    final cheapestAmount = preview?.cheapestTicket != null
        ? preview!.cheapestTicket!.converted.amount
        : (event.isFree ? 0.0 : (event.price ?? 0.0));

    final cheapestSymbol = preview?.cheapestTicket != null
        ? preview!.cheapestTicket!.converted.symbol
        : (event.currency ?? 'FCFA');

    final activitiesTotal = preview?.activitiesLiees.fold<double>(
          0.0,
          (sum, act) => sum + act.converted.amount,
        ) ??
        0.0;

    final estimatedTotalBudget = cheapestAmount + activitiesTotal;
    final totalAdded = preview != null && preview.attendeeCount > 0 ? preview.attendeeCount : event.totalAddedCount;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  expandedHeight: 260,
                  pinned: true,
                  backgroundColor: colorScheme.surface,
                  iconTheme: IconThemeData(color: colorScheme.onSurface),
                  flexibleSpace: FlexibleSpaceBar(
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        event.coverImageUrl != null && event.coverImageUrl!.isNotEmpty
                            ? AppCachedImage(
                                imageUrl: event.coverImageUrl!,
                                fit: BoxFit.cover,
                                errorWidget: _fallbackCover(),
                              )
                            : _fallbackCover(),
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, colorScheme.surface.withValues(alpha: 0.8)],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    GestureDetector(
                      onTap: _openCommentSheet,
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.4),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: SvgPicture.asset(
                            'assets/svg_icons/chat-round-svgrepo-com.svg',
                            width: 20,
                            height: 20,
                            colorFilter: ColorFilter.mode(
                              colorScheme.onSurface,
                              BlendMode.srcIn,
                            ),
                          ),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _showReportSheet,
                      child: Container(
                        margin: const EdgeInsets.only(right: 16),
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.4),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.more_vert, color: colorScheme.onSurface, size: 22),
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
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _StatusChip(status: event.status),
                                  if (event.isOnline)
                                    _TagChip(label: 'En ligne', color: AppColors.blue)
                                  else
                                    _TagChip(label: 'Présentiel', color: AppColors.success),
                                  _TagChip(
                                    label: event.visibility.toString().split('.').last == 'communityOnly'
                                        ? 'Communauté'
                                        : event.visibility.toString().split('.').last,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  if (event.isRecurring)
                                    _TagChip(label: 'Annuel', color: const Color(0xFFEAB308)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            _TagChip(
                              label: '#${ranking.rang > 0 ? ranking.rang : (event.countryRank ?? 3)}',
                              icon: Icons.emoji_events_rounded,
                              color: const Color(0xFFEAB308),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              fit: FlexFit.loose,
                              child: Text(
                                event.name,
                                style: AppTextStyles.h2.copyWith(color: colorScheme.onSurface),
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
                          style: AppTextStyles.body.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),

                        if (event.description != null) ...[
                          AnimatedCrossFade(
                            firstChild: Text(event.description!,
                                style: AppTextStyles.bodyLarge.copyWith(color: colorScheme.onSurfaceVariant),
                                maxLines: 3, overflow: TextOverflow.ellipsis),
                            secondChild: Text(event.description!,
                                style: AppTextStyles.bodyLarge.copyWith(color: colorScheme.onSurfaceVariant)),
                            crossFadeState: _descriptionExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                            duration: const Duration(milliseconds: 200),
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _descriptionExpanded = !_descriptionExpanded),
                            child: Text(_descriptionExpanded ? 'Voir moins' : 'Voir plus',
                                style: AppTextStyles.link.copyWith(color: AppColors.primary, fontSize: 13)),
                          ),
                        ],
                        const SizedBox(height: 24),

                        // Date & Lieu
                        _InfoRow(
                          icon: Icons.calendar_today_outlined,
                          label: 'Date',
                          value: DateFormat('EEEE d MMMM yyyy').format(event.startsAt),
                        ),
                        _InfoRow(
                          icon: Icons.access_time,
                          label: 'Heure',
                          value: event.endsAt != null
                              ? '${event.timeString} – ${DateFormat('HH:mm').format(event.endsAt!)}'
                              : (event.timeString ?? 'Non précisé'),
                        ),
                        if (event.timezone != null)
                          _InfoRow(icon: Icons.public, label: 'Fuseau horaire', value: event.timezone!),
                        const SizedBox(height: 16),

                        if (event.isOnline && event.onlineUrl != null) ...[
                          _InfoRow(icon: Icons.videocam_outlined, label: 'Lien visio',
                              value: event.onlineUrl!, isLink: true),
                        ] else if (event.address != null) ...[
                          _InfoRow(icon: Icons.location_on_outlined, label: 'Adresse', value: event.address!),
                        ],
                        // Conditions d'accès configurées côté backend (event_restrictions).
                        if (preview != null && _hasAccessConditions(preview.restrictions)) ...[
                          _buildAccessConditions(preview.restrictions, colorScheme),
                          const SizedBox(height: 24),
                        ],

                        const SizedBox(height: 24),

                        // Bloc Tarification Réel: Prix billet minimum & Budget total estimé
                        Row(
                          children: [
                            if (event.isFree && (preview?.tickets.isEmpty ?? true))
                              Expanded(
                                child: _buildPriceBox(
                                  context,
                                  icon: Icons.money_off,
                                  color: AppColors.success,
                                  label: 'Entrée Gratuite',
                                  value: 'Gratuit',
                                ),
                              )
                            else ...[
                              Expanded(
                                child: InkWell(
                                  onTap: (preview?.tickets.isNotEmpty ?? false) ? _showTicketsSheet : null,
                                  child: _buildPriceBox(
                                    context,
                                    icon: Icons.confirmation_number_outlined,
                                    color: AppColors.primary,
                                    label: 'À partir de',
                                    value: cheapestAmount <= 0
                                        ? 'Gratuit'
                                        : NumberFormatter.formatPrice(cheapestAmount, cheapestSymbol),
                                    showArrow: preview?.tickets.isNotEmpty ?? false,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: InkWell(
                                  onTap: () {
                                    Get.toNamed(
                                      AppPages.eventBudget.replaceFirst(':id', event.id),
                                      arguments: {
                                        'tickets': preview?.tickets ?? [],
                                        'activities': preview?.activitiesLiees ?? [],
                                        'cheapestTicket': preview?.cheapestTicket,
                                      },
                                    );
                                  },
                                  child: _buildPriceBox(
                                    context,
                                    icon: Icons.account_balance_wallet_outlined,
                                    color: AppColors.primary,
                                    label: 'Budget total estimé',
                                    value: estimatedTotalBudget <= 0
                                        ? 'Gratuit'
                                        : NumberFormatter.formatPrice(estimatedTotalBudget, cheapestSymbol),
                                    isGradient: true,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Amis ayant ajouté l'événement
                        if (preview != null && preview.amisDansAgendaPhotos.isNotEmpty) ...[
                          Text(
                            'Tes connexions y vont',
                            style: AppTextStyles.h5.copyWith(color: colorScheme.onSurface),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  height: 36,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: preview.amisDansAgendaPhotos.take(5).map((photo) {
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
                                    }).toList(),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    '${preview.amisDansAgendaCount} ami${preview.amisDansAgendaCount > 1 ? 's' : ''} ont ajouté cet événement',
                                    style: AppTextStyles.body.copyWith(color: colorScheme.onSurfaceVariant),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],

                        // Activités Réelles de l'événement
                        if (preview != null && preview.activitiesLiees.isNotEmpty) ...[
                          Text('Activités', style: AppTextStyles.h5.copyWith(color: colorScheme.onSurface)),
                          const SizedBox(height: 12),
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: preview.activitiesLiees.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final act = preview.activitiesLiees[index];
                              final isFree = act.converted.amount <= 0;
                              final priceText = isFree
                                  ? 'Gratuit'
                                  : NumberFormatter.formatPrice(act.converted.amount, act.converted.symbol);

                              return Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  // Les visiteurs consultent uniquement la carte.
                                  // L'écran de gestion est réservé à l'équipe.
                                  onTap: canManageActivities
                                      ? () {
                                          Get.toNamed(
                                            AppPages.eventActivities.replaceFirst(':id', widget.event.id),
                                            arguments: {'activity': act, 'event': widget.event},
                                          );
                                        }
                                      : null,
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: colorScheme.surfaceContainerLow,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color: isFree
                                                ? AppColors.success.withValues(alpha: 0.12)
                                                : AppColors.primary.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Icon(
                                            Icons.local_activity_rounded,
                                            color: isFree ? AppColors.success : AppColors.primary,
                                            size: 22,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                act.name,
                                                style: GoogleFonts.spaceGrotesk(
                                                  color: colorScheme.onSurface,
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Activité de l\'événement',
                                                style: AppTextStyles.caption.copyWith(
                                                  color: colorScheme.onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: isFree
                                                    ? AppColors.success.withValues(alpha: 0.12)
                                                    : AppColors.primary.withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Text(
                                                priceText,
                                                style: GoogleFonts.spaceGrotesk(
                                                  color: isFree ? AppColors.success : AppColors.primary,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Icon(
                                              Icons.arrow_forward_ios_rounded,
                                              size: 14,
                                              color: colorScheme.onSurfaceVariant,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 20),
                        ],

                        const SizedBox(height: 120),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom Action Bar
          Container(
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
                  if (_preview == null || _preview!.canAddToCalendar) ...[
                    Row(
                      children: [
                        Expanded(
                          flex: _isEventAdded ? 5 : 1,
                          child: ElevatedButton.icon(
                            onPressed: _isCalendarLoading ? null : _handleCalendarAction,
                            icon: Icon(_isEventAdded ? Icons.check_rounded : Icons.calendar_today_rounded, size: 18),
                            label: Text(
                              _isEventAdded ? 'Ajouté à mon agenda' : 'Ajouter à mon agenda',
                              style: AppTextStyles.buttonSmall.copyWith(fontSize: 13, fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isEventAdded ? AppColors.success : colorScheme.surfaceContainerHighest,
                              foregroundColor: _isEventAdded ? AppColors.white : colorScheme.onSurface,
                              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                          ),
                        ),
                        if (_isEventAdded) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 5,
                            child: ElevatedButton.icon(
                              onPressed: () => Get.to(
                                () => EventItineraryScreen(event: widget.event),
                                transition: Transition.rightToLeft,
                              ),
                              icon: const Icon(Icons.route_rounded, size: 18),
                              label: const Text(
                                'Organiser mon parcours',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: AppColors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                  Row(
                    children: [
                      // 1. LIKE
                      Expanded(
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: (_isLikeLoading || (_preview != null && !_preview!.canLike)) ? null : _toggleLike,
                                icon: Icon(
                                  _isLiked ? Icons.favorite : Icons.favorite_border,
                                  size: 16,
                                  color: _isLiked ? AppColors.error : colorScheme.onSurface,
                                ),
                                label: Text(
                                  '${NumberFormatter.formatCount(_preview != null ? _likesCount : (preview?.likesCount ?? event.interestedCount))}',
                                  style: AppTextStyles.buttonSmall.copyWith(
                                    color: _isLiked ? AppColors.error : colorScheme.onSurface,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _isLiked ? AppColors.error : colorScheme.onSurface,
                                  side: BorderSide(
                                    color: _isLiked
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
                          onPressed: (_preview != null && _preview!.canRate)
                              ? _openRatingSheet
                              : null,
                          icon: Icon(Icons.star_outline_rounded, size: 16, color: colorScheme.onSurface),
                          label: Text(
                            'Noter',
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
                          onPressed: (_preview != null && !_preview!.canShare) ? null : _shareEvent,
                          icon: Icon(Icons.share_outlined, size: 16, color: colorScheme.onSurface),
                          label: Text(
                            '${NumberFormatter.formatCount(preview?.shareCount ?? event.shareCount)}',
                            style: AppTextStyles.buttonSmall.copyWith(color: colorScheme.onSurface),
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
          ),
        ],
      ),
    );
  }

  Widget _fallbackCover() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.surfaceContainerHighest,
      child: Center(child: Icon(Icons.event, size: 64, color: colorScheme.onSurfaceVariant)),
    );
  }

  Widget _buildPriceBox(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    bool showArrow = false,
    bool isGradient = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isGradient ? null : colorScheme.surfaceContainerLow,
        gradient: isGradient
            ? LinearGradient(
                colors: [color.withValues(alpha: 0.1), color.withValues(alpha: 0.05)],
              )
            : null,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isGradient ? color.withValues(alpha: 0.2) : colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: AppTextStyles.caption.copyWith(color: isGradient ? color : colorScheme.onSurfaceVariant, fontSize: 10)),
                Text(value, style: AppTextStyles.h4.copyWith(color: color, fontSize: 15)),
              ],
            ),
          ),
          if (showArrow) Icon(Icons.keyboard_arrow_down, color: colorScheme.outline, size: 18),
        ],
      ),
    );
  }
}

class _RestrictedPreviewView extends StatelessWidget {
  const _RestrictedPreviewView({
    required this.preview,
    required this.eventId,
  });

  final EventPreviewModel preview;
  final String eventId;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final event = preview.event;
    final message = preview.message ??
        'Cette prévisualisation publique n\'est pas disponible pour votre rôle actuel (${preview.viewerRole ?? "organisateur"}).';

    final isOwnerOrStaff = (preview.viewerRole == 'owner' ||
        preview.viewerRole == 'cofounder' ||
        preview.viewerRole == 'staff');

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
                    if (preview.viewerRole == 'staff') {
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

class _TagChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const _TagChip({required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final EventStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    String label = status.value;
    Color color = Colors.grey;

    if (status == EventStatus.published) {
      label = 'Actif';
      color = AppColors.success;
    } else if (status == EventStatus.draft) {
      label = 'En attente';
      color = Colors.amber[800]!;
    } else if (status == EventStatus.pendingDeletion) {
      label = 'Suppression';
      color = AppColors.error;
    } else if (status == EventStatus.cancelled) {
      label = 'Annulé';
      color = AppColors.error;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isLink;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.isLink = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTextStyles.caption.copyWith(color: colorScheme.onSurfaceVariant, fontSize: 10)),
              Text(
                value,
                style: AppTextStyles.body.copyWith(
                  color: isLink ? AppColors.primary : colorScheme.onSurface,
                  fontWeight: isLink ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
