import 'package:get/get.dart';
import '../models/event_statistics_model.dart';
import '../repositories/event_repository.dart';

class EventStatsUseCase {
  final EventRepository _repository;

  EventStatsUseCase({EventRepository? repository})
      : _repository = repository ?? Get.find<EventRepository>();

  Future<EventStatisticsModel> execute(String eventId, {bool forceRefresh = false}) {
    return _repository.getEventStatistics(eventId, forceRefresh: forceRefresh);
  }
}
