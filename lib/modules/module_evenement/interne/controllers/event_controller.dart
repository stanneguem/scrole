import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:scrole/app/utils/boot_timing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../enums/event_enum.dart';
import '../../centre/models/event_model.dart';
import '../../centre/repositories/event_repository.dart';
import '../../../module_authentification/centre/services/auth_service.dart';
import '../widgets/event_filter.dart';

enum EventSuggestionsStatus {
  initial,
  loading,
  successWithData,
  successEmpty,
  error,
}

enum EventCalendarStatus {
  initial,
  loading,
  successWithData,
  successEmpty,
  error,
}

class EventController extends GetxController with WidgetsBindingObserver {
  final EventRepository _repository;
  final AuthService _authService = Get.isRegistered<AuthService>()
      ? Get.find<AuthService>()
      : AuthService();

  EventController({EventRepository? repository}) 
    : _repository = repository ?? Get.find<EventRepository>();

  final RxList<EventModel> events = <EventModel>[].obs;
  final RxList<EventModel> suggestedEvents = <EventModel>[].obs;
  final RxList<EventModel> calendarEvents = <EventModel>[].obs;
  final RxList<EventModel> managedEvents = <EventModel>[].obs;
  final RxList<EventModel> staffEvents = <EventModel>[].obs;

  final Rx<EventSortFilter> currentSortFilter = EventSortFilter.popularite.obs;
  final Rx<EventSuggestionsStatus> suggestionsStatus = EventSuggestionsStatus.initial.obs;
  final RxString suggestionsErrorMessage = ''.obs;

  final Rx<EventCalendarStatus> calendarStatus = EventCalendarStatus.initial.obs;
  final RxString calendarErrorMessage = ''.obs;

  final RxBool isLoading = false.obs;
  final RxBool isLoadingSuggestions = false.obs;
  final RxBool isLoadingCalendar = false.obs;
  final RxBool isLoadingMyEvents = false.obs;

  // Checkpoint pour le préchargement du calendrier
  DateTime? _lastMonthLoaded;
  int _nbMonthsInCache = 0;
  DateTime? _lastRefresh;

  StreamSubscription? _localDbSubscription;
  StreamSubscription? _localEventUpdateSubscription;

  @override
  void onInit() {
    bootLog('EventController.onInit start');
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    
    _lastRefresh = DateTime.now();
    ever(_authService.currentUser, (_) {
      _resetStateAndReload();
    });

    unawaited(bootMeasureAsync('EventController.fetchSuggestedEvents', () => fetchSuggestedEvents()));
    _initUserEventsRealtime();

    _localEventUpdateSubscription = _repository.onEventUpdated.listen((updatedEvent) {
      _updateEventInLists(updatedEvent);
    });

    _localDbSubscription = _repository.eventChanges.listen((_) {
    });
    bootLog('EventController.onInit end');
  }

  @override
  void onReady() {
    bootLog('EventController.onReady start');
    super.onReady();
    Future.delayed(const Duration(milliseconds: 300), () {
      unawaited(bootMeasureAsync('EventController.fetchCalendarEvents', () => fetchCalendarEvents(DateTime.now())));
      unawaited(bootMeasureAsync('EventController.fetchEvents', () => fetchEvents()));
      unawaited(bootMeasureAsync('EventController.fetchMyEvents', () => fetchMyEvents()));
    });
    bootLog('EventController.onReady end');
  }

  void _resetStateAndReload() {
    suggestedEvents.clear();
    calendarEvents.clear();
    managedEvents.clear();
    staffEvents.clear();
    events.clear();
    suggestionsStatus.value = EventSuggestionsStatus.initial;
    calendarStatus.value = EventCalendarStatus.initial;
    fetchSuggestedEvents(force: true);
    fetchCalendarEvents(DateTime.now(), force: true);
    fetchMyEvents();
  }

  void _initUserEventsRealtime() {
    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId != null && currentUserId.isNotEmpty) {
        _repository.subscribeToUserEventsRealtime(
          userId: currentUserId,
          onEventUpdated: (eventId) => handleRealtimeEventUpdate(eventId),
          onEventDeleted: (eventId) => handleRealtimeEventDelete(eventId),
        );
      }
    } catch (e) {
      debugPrint('[EventController] _initUserEventsRealtime error: $e');
    }
  }

  Future<void> handleRealtimeEventUpdate(String eventId) async {
    debugPrint('[Realtime] event received');
    debugPrint('[Realtime] type=event_updated');
    debugPrint('[Realtime] event_id=$eventId');
    debugPrint('[Sync] fetching event $eventId ...');

    try {
      final updatedEvent = await _repository.refreshSingleEvent(eventId);
      debugPrint('[Sync] event fetched');
      debugPrint('[Cache] event updated');
      debugPrint('[SQLite] event updated');

      final mIdx = managedEvents.indexWhere((e) => e.id == eventId);
      if (mIdx != -1) {
        managedEvents[mIdx] = updatedEvent;
      } else {
        managedEvents.insert(0, updatedEvent);
      }

      final sIdx = staffEvents.indexWhere((e) => e.id == eventId);
      if (sIdx != -1) {
        staffEvents[sIdx] = updatedEvent;
      }

      final evIdx = events.indexWhere((e) => e.id == eventId);
      if (evIdx != -1) {
        events[evIdx] = updatedEvent;
      }

      debugPrint('[Controller] event replaced');
      debugPrint('[UI] card refreshed');
    } catch (e) {
      if (e is EventNotFoundException ||
          e.toString().toLowerCase().contains('introuvable') ||
          e.toString().toLowerCase().contains('not_found')) {
        handleRealtimeEventDelete(eventId);
      } else {
        debugPrint('[EventController] handleRealtimeEventUpdate error: $e');
      }
    }
  }

  void handleRealtimeEventDelete(String eventId) {
    debugPrint('[Realtime] event received');
    debugPrint('[Realtime] type=event_deleted');
    debugPrint('[Realtime] event_id=$eventId');

    managedEvents.removeWhere((e) => e.id == eventId);
    staffEvents.removeWhere((e) => e.id == eventId);
    events.removeWhere((e) => e.id == eventId);
    suggestedEvents.removeWhere((e) => e.id == eventId);
    calendarEvents.removeWhere((e) => e.id == eventId);

    debugPrint('[SQLite] event purged');
    debugPrint('[Cache] event purged');
    debugPrint('[Controller] event removed');
    debugPrint('[UI] card refreshed');
  }

  void _updateEventInLists(EventModel updatedEvent) {
    final eventId = updatedEvent.id;
    debugPrint('[EventController] Live event update received: $eventId -> ${updatedEvent.name}');

    final mIdx = managedEvents.indexWhere((e) => e.id == eventId);
    if (mIdx != -1) {
      managedEvents[mIdx] = updatedEvent;
    } else {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (updatedEvent.creatorId == currentUserId ||
          updatedEvent.userRole == 'fondateur' ||
          updatedEvent.userRole == 'co_createur' ||
          updatedEvent.userRole == 'owner' ||
          updatedEvent.userRole == 'managed') {
        managedEvents.insert(0, updatedEvent);
      }
    }

    final sIdx = staffEvents.indexWhere((e) => e.id == eventId);
    if (sIdx != -1) {
      staffEvents[sIdx] = updatedEvent;
    }

    final evIdx = events.indexWhere((e) => e.id == eventId);
    if (evIdx != -1) {
      events[evIdx] = updatedEvent;
    }

    final sugIdx = suggestedEvents.indexWhere((e) => e.id == eventId);
    if (sugIdx != -1) {
      suggestedEvents[sugIdx] = updatedEvent;
    }

    final calIdx = calendarEvents.indexWhere((e) => e.id == eventId);
    if (calIdx != -1) {
      calendarEvents[calIdx] = updatedEvent;
    }

    debugPrint('[Controller] event replaced in all lists');
    debugPrint('[UI] card refreshed');
  }

  @override
  void onClose() {
    _localDbSubscription?.cancel();
    _localEventUpdateSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final now = DateTime.now();
      if (_lastRefresh == null || now.difference(_lastRefresh!) > const Duration(hours: 5)) {
        debugPrint('[Sync] Discovery cache expired (>5h), refreshing...');
        _lastRefresh = now;
        fetchSuggestedEvents();
        if (_lastMonthLoaded != null) {
          fetchCalendarEvents(_lastMonthLoaded!);
        }
      }
      fetchMyEvents(); // Toujours rafraîchir le contenu personnel
    }
  }

  Future<void> fetchEvents() async {
    isLoading.value = true;
    try {
      final list = await _repository.getEvents();
      events.assignAll(list);
    } catch (e) {
      debugPrint('[Error] EventController.fetchEvents: $e');
      loadMockEvents();
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> fetchSuggestedEvents({bool force = false}) async {
    if (isLoadingSuggestions.value && !force) return;

    if (suggestedEvents.isEmpty) {
      suggestionsStatus.value = EventSuggestionsStatus.loading;
    }

    isLoadingSuggestions.value = true;
    suggestionsErrorMessage.value = '';

    try {
      final list = await _repository.getSuggestedEvents(forceRefresh: force);
      suggestedEvents.assignAll(list);
      final activeList = list.where((e) => !e.isFinished).toList();
      if (activeList.isNotEmpty) {
        suggestionsStatus.value = EventSuggestionsStatus.successWithData;
      } else {
        suggestionsStatus.value = EventSuggestionsStatus.successEmpty;
      }
    } catch (e) {
      debugPrint('[Error] fetchSuggestedEvents: $e');
      if (suggestedEvents.isEmpty) {
        suggestionsErrorMessage.value = e.toString();
        suggestionsStatus.value = EventSuggestionsStatus.error;
      }
    } finally {
      isLoadingSuggestions.value = false;
    }
  }

  Future<void> fetchCalendarEvents(DateTime startMonth, {bool force = false}) async {
    if (isLoadingCalendar.value && !force) return;

    if (calendarEvents.isEmpty) {
      calendarStatus.value = EventCalendarStatus.loading;
    }

    isLoadingCalendar.value = true;
    calendarErrorMessage.value = '';

    try {
      final list = await _repository.getRelevantCalendarEvents(
        startMonth: startMonth,
        nbMonths: 3,
        forceRefresh: force,
      );
      
      if (force) {
        final Map<String, EventModel> map = { for (var e in list) e.id: e };
        calendarEvents.assignAll(map.values.toList());
      } else {
        // Fusion intelligente pour éviter les doublons
        final Map<String, EventModel> map = { for (var e in calendarEvents) e.id: e };
        for (var e in list) { map[e.id] = e; }
        calendarEvents.assignAll(map.values.toList());
      }
      
      _lastMonthLoaded = startMonth;
      _nbMonthsInCache = 6;

      if (calendarEvents.isNotEmpty) {
        calendarStatus.value = EventCalendarStatus.successWithData;
      } else {
        calendarStatus.value = EventCalendarStatus.successEmpty;
      }
    } catch (e) {
      debugPrint('[Error] fetchCalendarEvents: $e');
      if (calendarEvents.isEmpty) {
        calendarErrorMessage.value = e.toString();
        calendarStatus.value = EventCalendarStatus.error;
      }
    } finally {
      isLoadingCalendar.value = false;
    }
  }

  /// Appelé par l'UI quand l'utilisateur change de mois
  void onCalendarMonthChanged(DateTime newMonth) {
    if (_lastMonthLoaded == null) return;
    
    // Calculer l'écart en mois
    final delta = (newMonth.year - _lastMonthLoaded!.year) * 12 + (newMonth.month - _lastMonthLoaded!.month);
    
    // S'il ne reste plus que 1 mois de marge (sur les 4 chargés initialement), on en charge d'autres
    if (delta >= _nbMonthsInCache - 2) {
      debugPrint('[Sync] Calendar margin low, preloading next months...');
      final nextMonth = DateTime(newMonth.year, newMonth.month + 2);
      fetchCalendarEvents(nextMonth);
    }
  }

  Future<String?> addToCalendar(String eventId) async {
    final suggestedCommunityId = await _repository.addEventToCalendar(eventId);
    fetchMyEvents();
    return suggestedCommunityId;
  }

  Future<void> removeFromCalendar(String eventId) async {
    await _repository.removeEventFromCalendar(eventId);
    fetchMyEvents();
  }

  Future<void> refreshStaffEvents() async {
    try {
      final remoteStaff = await _repository.getStaffEvents();
      staffEvents.assignAll(remoteStaff);
      debugPrint('[EventController] refreshStaffEvents: ${remoteStaff.length} events loaded');
    } catch (e) {
      debugPrint('[Error] EventController.refreshStaffEvents: $e');
    }
  }

  Future<void> fetchMyEvents() async {
    isLoadingMyEvents.value = true;
    try {
      final localManaged = await _repository.getManagedEventsLocal();
      if (localManaged.isNotEmpty) {
        managedEvents.assignAll(localManaged);
      }
      final localStaff = await _repository.getStaffEvents();
      staffEvents.assignAll(localStaff);
    } catch (e) {
      debugPrint('[Error] EventController.fetchMyEvents local: $e');
    } finally {
      isLoadingMyEvents.value = false;
    }

    try {
      final remoteManaged = await _repository.syncManagedEventsRemote();
      if (remoteManaged.isNotEmpty) {
        managedEvents.assignAll(remoteManaged);
      }
      final remoteStaff = await _repository.getStaffEvents();
      staffEvents.assignAll(remoteStaff);
    } catch (e) {
      debugPrint('[Error] EventController.fetchMyEvents remote: $e');
    }
  }

  void purgeEventFromMemory(String eventId) {
    events.removeWhere((e) => e.id == eventId);
    managedEvents.removeWhere((e) => e.id == eventId);
    staffEvents.removeWhere((e) => e.id == eventId);
    suggestedEvents.removeWhere((e) => e.id == eventId);
    calendarEvents.removeWhere((e) => e.id == eventId);
    debugPrint('[EventCache] event removed from FastCache');
    debugPrint('[EventCache] preview removed eventId=$eventId');
    debugPrint('[EventState] selectedEventId cleared eventId=$eventId');
  }

  void loadMockEvents() {
    final base = DateTime(2026, 7, 1);
    events.assignAll([
      EventModel(
        id: '1', creatorId: 'u1', name: 'Kamer Otaku Festival', slug: 'kamer-otaku-fest',
        description: 'Le plus grand rassemblement otaku du Cameroun !',
        startsAt: base.add(const Duration(days: 0, hours: 10)),
        endsAt: base.add(const Duration(days: 0, hours: 18)),
        address: 'Yaoundé, Cameroun',
        isFree: false, price: 2000.0, currency: 'XAF',
        interestedCount: 0, goingCount: 0, checkedInCount: 0,
        createdAt: base, status: EventStatus.published,
        coverImageUrl: 'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcTMoBiS7ZeDpT4ThsVz3i3gcIba5iAhxFO17LnL20wSKd6LrLIz-GVcF3sw&s=10',
      ),
    ]);
  }

  void setSortFilter(EventSortFilter filter) => currentSortFilter.value = filter;

  List<EventModel> sortEventList(List<EventModel> list) {
    final sorted = List<EventModel>.from(list);
    switch (currentSortFilter.value) {
      case EventSortFilter.popularite:
        sorted.sort((a, b) => b.interestedCount.compareTo(a.interestedCount));
        break;
      case EventSortFilter.gratuit:
        sorted.sort((a, b) => (a.isFree ? 0 : 1).compareTo(b.isFree ? 0 : 1));
        break;
      case EventSortFilter.plusAjouts:
        sorted.sort((a, b) => b.goingCount.compareTo(a.goingCount));
        break;
      case EventSortFilter.plusSurs:
        sorted.sort((a, b) => b.goingCount.compareTo(a.goingCount));
        break;
      case EventSortFilter.proches:
        sorted.sort((a, b) => a.startsAt.compareTo(b.startsAt));
        break;
    }
    return sorted;
  }
}
