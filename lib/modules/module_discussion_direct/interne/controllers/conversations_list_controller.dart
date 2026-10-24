import 'dart:async';
import 'package:get/get.dart';
import 'package:scrole/modules/module_discussion_direct/centre/models/conversation_model.dart';
import 'package:scrole/modules/module_discussion_direct/centre/models/message_model.dart';
import 'package:scrole/modules/module_discussion_direct/centre/models/conversation.dart';
import 'package:scrole/modules/module_discussion_direct/centre/repositories/messaging_repository.dart';

class ConversationsListController extends GetxController {
  ConversationsListController(this._repository);
  final MessagingRepository _repository;
  final RxString searchQuery = ''.obs;
  final RxList<ConversationModel> conversations = <ConversationModel>[].obs;
  final RxBool isLoading = true.obs;
  StreamSubscription<List<Conversation>>? _subscription;

  List<ConversationModel> get filteredConversations {
    final query = searchQuery.value.trim().toLowerCase();
    final source = query.isEmpty
        ? conversations.toList()
        : conversations.where((c) => (c.name ?? '').toLowerCase().contains(query)).toList();
    source.sort((a, b) {
      final aAt = a.lastMessage?.createdAt ?? a.updatedAt;
      final bAt = b.lastMessage?.createdAt ?? b.updatedAt;
      final byActivity = bAt.compareTo(aAt);
      if (byActivity != 0) return byActivity;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return source.toList(growable: false);
  }

  List<ConversationModel> get pinnedConversations => filteredConversations.where((c) => c.isPinned).toList(growable: false);
  List<ConversationModel> get unpinnedConversations => filteredConversations.where((c) => !c.isPinned).toList(growable: false);
  bool get isEmpty => conversations.isEmpty && !isLoading.value;

  @override
  void onInit() {
    super.onInit();
    _subscription = _repository.watchConversationsList().listen((items) {
      conversations.assignAll(items.map(_toModel));
      conversations.refresh();
      isLoading.value = false;
    }, onError: (_) => isLoading.value = false);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final result = await _repository.syncConversations();
    if (!result.success && conversations.isEmpty) isLoading.value = false;
  }

  Future<void> refreshConversations() async {
    final result = await _repository.syncConversations();
    if (!result.success) Get.snackbar('Discussions', result.message ?? 'Impossible de synchroniser les discussions.');
  }

  void onSearchChanged(String value) => searchQuery.value = value;

  Future<void> togglePin(String conversationId) async {
    final result = await _repository.toggleConversationPinned(conversationId);
    if (!result.success) {
      Get.snackbar('Discussions', result.message ?? 'Impossible de modifier l’épingle.');
    }
  }

  ConversationModel _toModel(Conversation c) => ConversationModel(
    id: c.id, name: c.name, avatarUrl: c.avatarUrl, participantIds: c.participantIds,
    lastMessage: c.lastMessagePreview == null ? null : MessageModel.fromMessage(c.lastMessagePreview!),
    updatedAt: c.updatedAt, unreadCount: c.unreadCount, isGroup: c.isGroup, isPinned: c.isPinned,
  );

  @override
  void onClose() { _subscription?.cancel(); super.onClose(); }
}
