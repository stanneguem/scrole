import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../../centre/models/staff_model.dart';
import '../../centre/models/co_creator_model.dart';
import '../../centre/models/activity_model.dart';
import '../../centre/models/event_model.dart';
import '../../centre/repositories/event_repository.dart';
import '../../../../modules/module_authentification/centre/services/auth_service.dart';
import '../../../../modules/module_discussion_direct/externe/repositories/social_repository.dart';
import '../../../../modules/module_discussion_direct/interne/controllers/contacts_controller.dart';

class StaffController extends GetxController {
  final String eventId;
  final EventRepository _repository;

  StaffController({
    required this.eventId,
    EventRepository? repository,
  }) : _repository = repository ?? Get.find<EventRepository>();

  final SocialRepository _socialRepository = SocialRepository();

  final RxList<StaffMemberModel> staffMembers = <StaffMemberModel>[].obs;
  final RxList<CoCreatorModel> coCreators = <CoCreatorModel>[].obs;
  final RxList<EventActivityModel> eventActivities = <EventActivityModel>[].obs;
  final RxList<ContactModel> friends = <ContactModel>[].obs;

  final RxString eventCreatorId = ''.obs;
  final Rx<EventModel?> eventModel = Rx<EventModel?>(null);

  final RxBool isLoadingStaff = false.obs;
  final RxBool isLoadingCoCreators = false.obs;
  final RxBool isLoadingFriends = false.obs;

  String get currentUserId => Get.find<AuthService>().userId ?? '';

  bool get isCurrentUserFounder =>
      currentUserId.isNotEmpty && eventCreatorId.value.isNotEmpty && eventCreatorId.value == currentUserId;

  bool get isCurrentUserCoFounder =>
      currentUserId.isNotEmpty && acceptedCoCreators.any((c) => c.userId == currentUserId);

  @override
  void onInit() {
    super.onInit();
    loadEventDetails();
    loadStaff();
    loadCoCreators();
    loadEventActivities();
    loadFriends();
  }

  Future<void> loadEventDetails() async {
    try {
      final args = Get.arguments;
      if (args is EventModel) {
        eventModel.value = args;
        eventCreatorId.value = args.creatorId;
      } else {
        final ev = await _repository.getEventById(eventId);
        eventModel.value = ev;
        eventCreatorId.value = ev.creatorId;
      }
    } catch (e) {
      debugPrint('[StaffController] loadEventDetails error: $e');
    }
  }

  Future<void> loadStaff() async {
    isLoadingStaff.value = true;
    try {
      final results = await _repository.getEventStaff(eventId);
      staffMembers.assignAll(results);
    } catch (e) {
      debugPrint('[Error] StaffController.loadStaff: $e');
    } finally {
      isLoadingStaff.value = false;
    }
  }

  Future<void> loadCoCreators() async {
    isLoadingCoCreators.value = true;
    try {
      final results = await _repository.getEventCoCreators(eventId);
      coCreators.assignAll(results);
    } catch (e) {
      Get.log('[Error] StaffController.loadCoCreators: $e');
    } finally {
      isLoadingCoCreators.value = false;
    }
  }

  Future<void> loadEventActivities() async {
    try {
      final activities = await _repository.getEventActivities(eventId);
      eventActivities.assignAll(activities);
    } catch (e) {
      Get.log('[Error] StaffController.loadEventActivities: $e');
    }
  }

  Future<void> loadFriends() async {
    isLoadingFriends.value = true;
    try {
      final list = await _socialRepository.getAcceptedConnections();
      friends.assignAll(list.map((json) {
        final first = (json['first_name'] as String? ?? '').trim();
        final last = (json['last_name'] as String? ?? '').trim();
        final username = (json['username'] as String? ?? '').trim();
        final name = '$first $last'.trim();
        return ContactModel(
          id: json['user_id'] as String,
          name: name.isEmpty ? username : name,
          username: username,
          avatarUrl: json['photo_url'] as String?,
        );
      }).toList());
    } catch (e) {
      Get.log('[Error] StaffController.loadFriends: $e');
    } finally {
      isLoadingFriends.value = false;
    }
  }

  Future<void> inviteStaff(String userId, {List<String> activityIds = const []}) async {
    final friend = friends.firstWhereOrNull((f) => f.id == userId);
    final tempMember = StaffMemberModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      userId: userId,
      name: friend?.name ?? 'Utilisateur',
      username: friend?.username,
      avatarUrl: friend?.avatarUrl,
      status: StaffStatus.pending,
      invitedAt: DateTime.now(),
    );

    final existingIdx = staffMembers.indexWhere((m) => m.userId == userId);
    if (existingIdx == -1) {
      staffMembers.add(tempMember);
    }

    try {
      await _repository.inviteStaff(eventId, userId, activityIds: activityIds);
      Get.snackbar('Invitation envoyée', 'L\'invitation a été envoyée avec succès.', snackPosition: SnackPosition.BOTTOM);
      await loadStaff();
    } catch (e) {
      if (existingIdx == -1) {
        staffMembers.removeWhere((m) => m.userId == userId && m.id == tempMember.id);
      }
      Get.snackbar('Erreur', 'Impossible d\'envoyer l\'invitation : $e', snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> removeStaff(String userId) async {
    final memberToRemove = staffMembers.firstWhereOrNull((m) => m.userId == userId);
    staffMembers.removeWhere((m) => m.userId == userId);

    try {
      await _repository.removeStaff(eventId, userId);
      Get.snackbar('Membre retiré', 'Le membre a été retiré du staff de l\'événement.', snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      if (memberToRemove != null) {
        staffMembers.add(memberToRemove);
      }
      Get.snackbar('Erreur', 'Impossible de retirer le membre du staff : $e', snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> updateStaffActivities({
    required String staffId,
    required List<String> activityIds,
    required List<String> activityNames,
  }) async {
    final idx = staffMembers.indexWhere((m) => m.id == staffId || m.userId == staffId);
    StaffMemberModel? original;
    if (idx != -1) {
      original = staffMembers[idx];
      staffMembers[idx] = original.copyWith(
        assignedActivityIds: activityIds,
        assignedActivityNames: activityNames,
      );
    }

    try {
      await _repository.setEventStaffActivities(
        eventStaffId: staffId,
        activityIds: activityIds,
      );
      Get.snackbar('Activités enregistrées', 'Les activités du membre ont été enregistrées avec succès.', snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      debugPrint('[StaffController] updateStaffActivities error: $e');
      if (idx != -1 && original != null) {
        staffMembers[idx] = original;
      }
      final errStr = e.toString();
      if (errStr.contains('P0001') || errStr.contains('pas liée à cet événement')) {
        Get.snackbar(
          'Attribution impossible',
          'Une ou plusieurs activités sélectionnées ne sont plus associées à cet événement. Veuillez d\'abord les ajouter à l\'événement.',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 4),
        );
      } else {
        Get.snackbar('Erreur', 'Impossible de sauvegarder l\'attribution : $e', snackPosition: SnackPosition.BOTTOM);
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> fetchStaffStats(String staffId) async {
    try {
      return await _repository.getEventStaffStats(staffId);
    } catch (e) {
      debugPrint('[StaffController] fetchStaffStats error: $e');
      rethrow;
    }
  }

  Future<void> promoteStaffToCoCreator(String userId) async {
    final staffMember = staffMembers.firstWhereOrNull((m) => m.userId == userId || m.id == userId);
    if (staffMember == null) return;

    staffMembers.removeWhere((m) => m.userId == userId || m.id == userId);

    try {
      await _repository.promoteEventStaffToCoCreator(eventId: eventId, userId: userId);
      Get.snackbar(
        'Membre promu',
        '${staffMember.name} est désormais co-fondateur de cet événement.',
        snackPosition: SnackPosition.BOTTOM,
      );
      await loadStaff();
      await loadCoCreators();
    } catch (e) {
      debugPrint('[StaffController] promoteStaffToCoCreator error: $e');
      if (!staffMembers.any((m) => m.userId == userId || m.id == userId)) {
        staffMembers.add(staffMember);
      }
      Get.snackbar(
        'Erreur de promotion',
        'Impossible de promouvoir ce membre : $e',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  Future<void> inviteCoCreator(String userId) async {
    try {
      await _repository.inviteCoCreatorOptimistic(eventId, userId);
      Get.snackbar('Co-créateur', 'Invitation envoyée !', snackPosition: SnackPosition.BOTTOM);
      loadCoCreators();
    } catch (e) {
      Get.snackbar('Erreur', e.toString(), snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> removeCoCreator(String userId) async {
    try {
      await _repository.removeCoCreator(eventId, userId);
      coCreators.removeWhere((c) => c.userId == userId);
      Get.snackbar('Co-fondateur', 'Le rôle de co-fondateur a été révoqué.', snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('Erreur', e.toString(), snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> leaveCoCreatorRole() async {
    if (currentUserId.isEmpty) return;
    try {
      await _repository.removeCoCreator(eventId, currentUserId);
      coCreators.removeWhere((c) => c.userId == currentUserId);
      Get.snackbar('Co-fondateur', 'Vous avez quitté votre rôle de co-fondateur.', snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('Erreur', e.toString(), snackPosition: SnackPosition.BOTTOM);
    }
  }

  List<StaffMemberModel> get acceptedStaff =>
      staffMembers.where((m) => m.status == StaffStatus.accepted).toList();

  List<StaffMemberModel> get pendingStaff =>
      staffMembers.where((m) => m.status == StaffStatus.pending).toList();

  List<StaffMemberModel> get rejectedStaff =>
      staffMembers.where((m) => m.status == StaffStatus.rejected).toList();

  List<CoCreatorModel> get acceptedCoCreators =>
      coCreators.where((c) => c.status == CoCreatorStatus.accepted).toList();

  List<CoCreatorModel> get pendingCoCreators =>
      coCreators.where((c) => c.status == CoCreatorStatus.pending).toList();
}
