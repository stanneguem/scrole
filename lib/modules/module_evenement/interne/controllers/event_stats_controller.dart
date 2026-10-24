import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
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
