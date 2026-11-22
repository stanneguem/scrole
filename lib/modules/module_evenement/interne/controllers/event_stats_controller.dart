import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../centre/models/event_statistics_model.dart';
import '../../centre/usecases/event_stats_use_case.dart';

class EventStatsController extends GetxController {
  final String eventId;
  final EventStatsUseCase _useCase;

  EventStatsController({
    required this.eventId,
    EventStatsUseCase? useCase,
  }) : _useCase = useCase ?? EventStatsUseCase();

  final Rxn<EventStatisticsModel> stats = Rxn<EventStatisticsModel>();
  final RxBool isLoading = true.obs;
  final RxBool isStale = false.obs;
  final RxnString errorMessage = RxnString();
  final RxMap<String, dynamic> budgetInsights = <String, dynamic>{}.obs;

  @override
  void onInit() {
    super.onInit();
    loadStatistics();
  }

  Future<void> loadStatistics({bool force = false}) async {
    isLoading.value = true;
    errorMessage.value = null;

    try {
      final result = await _useCase.execute(eventId, forceRefresh: force);
      stats.value = result;
      try {
        final rawBudget = await Supabase.instance.client.rpc(
          'get_event_budget_insights',
          params: {'p_event_id': eventId},
        );
        if (rawBudget is Map) {
          budgetInsights.assignAll(Map<String, dynamic>.from(rawBudget));
        }
      } catch (budgetError) {
        debugPrint('[EventStatsController] budget insights unavailable: $budgetError');
      }
      isStale.value = false;
    } catch (e) {
      debugPrint('[EventStatsController] loadStatistics error: $e');
      if (stats.value != null) {
        isStale.value = true;
      } else {
        errorMessage.value = 'Impossible de charger les statistiques de cet événement.';
      }
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> refreshStatistics() async {
    await loadStatistics(force: true);
  }
}
