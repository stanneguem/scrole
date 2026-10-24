import 'package:get/get.dart';
import '../../centre/models/event_preview_model.dart';

class EventBudgetController extends GetxController {
  final List<EventPreviewTicket> tickets = <EventPreviewTicket>[];
  final List<EventPreviewActivity> activities = <EventPreviewActivity>[];

  final Rx<EventPreviewTicket?> selectedTicket = Rx<EventPreviewTicket?>(null);
  final RxList<String> selectedActivityIds = <String>[].obs;

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments;
    if (args is Map) {
      if (args['tickets'] is List) {
        tickets.clear();
        tickets.addAll((args['tickets'] as List).whereType<EventPreviewTicket>());
      }
      if (args['activities'] is List) {
        activities.clear();
        activities.addAll((args['activities'] as List).whereType<EventPreviewActivity>());
      }
      if (args['cheapestTicket'] is EventPreviewTicket) {
        selectedTicket.value = args['cheapestTicket'] as EventPreviewTicket;
      }
    }

    if (selectedTicket.value == null && tickets.isNotEmpty) {
      selectedTicket.value = tickets.first;
    }
  }

  void toggleActivity(String activityId) {
    if (selectedActivityIds.contains(activityId)) {
      selectedActivityIds.remove(activityId);
    } else {
      selectedActivityIds.add(activityId);
    }
  }

  double get totalBudget {
    double total = selectedTicket.value?.converted.amount ?? 0.0;
    for (final id in selectedActivityIds) {
      final act = activities.firstWhereOrNull((a) => a.activityId == id);
      if (act != null) {
        total += act.converted.amount;
      }
    }
    return total;
  }

  String get currency {
    if (selectedTicket.value != null) {
      return selectedTicket.value!.converted.symbol;
    }
    if (tickets.isNotEmpty) {
      return tickets.first.converted.symbol;
    }
    if (activities.isNotEmpty) {
      return activities.first.converted.symbol;
    }
    return 'FCFA';
  }
}
