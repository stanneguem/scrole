import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../centre/models/event_comment.dart';
import '../../centre/repositories/event_repository.dart';

enum EventCommentsState { initial, loading, loaded, empty, error }

class EventCommentsController extends GetxController {
  final EventRepository _repository = Get.find<EventRepository>();

  final RxList<EventComment> comments = <EventComment>[].obs;
  final Rx<EventCommentsState> state = EventCommentsState.initial.obs;
  final RxBool isSending = false.obs;
  final RxBool hasMoreComments = true.obs;
  final RxBool isLoadingMoreComments = false.obs;
  final RxString errorMessage = ''.obs;
  final Rx<EventComment?> replyingToComment = Rx<EventComment?>(null);
  final RxSet<String> likingCommentIds = <String>{}.obs;
  final RxBool isInMyCalendar = false.obs;

  final TextEditingController commentTextController = TextEditingController();
  final FocusNode commentFocusNode = FocusNode();

  String? _currentEventId;

  void init(String eventId) {
    _currentEventId = eventId;
    fetchComments(eventId);
    checkCalendarStatus(eventId);
    _repository.subscribeToEventCommentsRealtime(eventId, () {
      refreshCommentsQuietly(eventId);
    });
  }

  Future<void> checkCalendarStatus(String eventId) async {
    try {
      final preview = await _repository.getEventPreview(eventId);
      isInMyCalendar.value = preview.isInMyCalendar;
    } catch (e) {
      debugPrint('[EventCommentsController] checkCalendarStatus error: $e');
    }
  }

  Future<void> addToCalendar(String eventId) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        await _repository.addEventToCalendarOptimistic(eventId, userId);
        isInMyCalendar.value = true;
        Get.snackbar('Succès', 'Événement ajouté à votre agenda !', snackPosition: SnackPosition.BOTTOM);
      }
    } catch (e) {
      Get.snackbar('Erreur', 'Impossible d\'ajouter l\'événement.', snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> fetchComments(String eventId) async {
    state.value = EventCommentsState.loading;
    errorMessage.value = '';

    try {
      final list = await _repository.getEventComments(eventId: eventId, limit: 20);
      comments.value = list;
      hasMoreComments.value = list.length >= 20;

      if (list.isEmpty) {
        state.value = EventCommentsState.empty;
      } else {
        state.value = EventCommentsState.loaded;
      }
    } catch (e) {
      debugPrint('[EventCommentsController] fetchComments error: $e');
      errorMessage.value = 'Impossible de charger les commentaires.';
      state.value = EventCommentsState.error;
    }
  }

  Future<void> loadMoreComments(String eventId) async {
    if (!hasMoreComments.value || isLoadingMoreComments.value || comments.isEmpty) return;

    isLoadingMoreComments.value = true;
    final lastCreatedAt = comments.last.createdAt;

    try {
      final nextList = await _repository.getEventComments(
        eventId: eventId,
        limit: 20,
        beforeCreatedAt: lastCreatedAt,
      );

      final newItems = nextList.where((c) => !comments.any((existing) => existing.id == c.id)).toList();
      comments.addAll(newItems);
      hasMoreComments.value = nextList.length >= 20;
    } catch (e) {
      debugPrint('[EventCommentsController] loadMoreComments error: $e');
    } finally {
      isLoadingMoreComments.value = false;
    }
  }

  Future<void> refreshCommentsQuietly(String eventId) async {
    try {
      final list = await _repository.getEventComments(eventId: eventId, limit: 20);
      final Map<String, List<EventComment>> loadedRepliesMap = {};
      final Map<String, bool> loadedFlags = {};
      final Map<String, bool> hasMoreFlags = {};

      for (final existing in comments) {
        if (existing.areRepliesLoaded) {
          loadedRepliesMap[existing.id] = existing.replies;
          loadedFlags[existing.id] = true;
          hasMoreFlags[existing.id] = existing.hasMoreReplies;
        }
      }

      final updatedList = list.map((c) {
        if (loadedRepliesMap.containsKey(c.id)) {
          return c.copyWith(
            replies: loadedRepliesMap[c.id],
            areRepliesLoaded: true,
            hasMoreReplies: hasMoreFlags[c.id] ?? false,
          );
        }
        return c;
      }).toList();

      comments.value = updatedList;
      hasMoreComments.value = list.length >= 20;
    } catch (e) {
      debugPrint('[EventCommentsController] refreshCommentsQuietly error: $e');
    }
  }

  void startReplyTo(EventComment comment) {
    replyingToComment.value = comment;
    commentFocusNode.requestFocus();
  }

  void setReplyTo(EventComment comment) => startReplyTo(comment);

  Future<void> loadCommentReplies(EventComment comment) async {}
  Future<void> loadMoreCommentReplies(EventComment comment) async {}

  void cancelReply() {
    replyingToComment.value = null;
  }

  Future<void> sendComment(String eventId) async {
    final text = commentTextController.text.trim();
    if (text.isEmpty || isSending.value) return;

    isSending.value = true;
    try {
      final parentComment = replyingToComment.value;
      if (parentComment == null) {
        await _repository.createEventComment(eventId: eventId, content: text);
      } else {
        await _repository.createEventComment(
          eventId: eventId,
          content: text,
          parentCommentId: parentComment.id,
        );
      }
      commentTextController.clear();
      replyingToComment.value = null;
      await refreshCommentsQuietly(eventId);
    } catch (e) {
      debugPrint('[EventCommentsController] sendComment error: $e');
      Get.snackbar('Erreur', 'Impossible d\'envoyer le commentaire.', snackPosition: SnackPosition.BOTTOM);
    } finally {
      isSending.value = false;
    }
  }

  Future<void> toggleCommentLike(dynamic commentOrId, {bool? isMainComment, String? parentCommentId}) async {
    final commentId = commentOrId is EventComment ? commentOrId.id : commentOrId.toString();
    final eventId = _currentEventId;
    if (eventId == null) return;

    if (likingCommentIds.contains(commentId)) return;
    likingCommentIds.add(commentId);

    try {
      final rootComment = comments.firstWhereOrNull((c) => c.id == commentId || (parentCommentId != null && c.id == parentCommentId));
      if (rootComment == null) return;

      if (parentCommentId == null) {
        if (rootComment.isLikedByMe) {
          await _repository.unlikeEventComment(commentId);
        } else {
          await _repository.likeEventComment(commentId);
        }
      }
      await refreshCommentsQuietly(eventId);
    } catch (e) {
      debugPrint('[EventCommentsController] toggleCommentLike error: $e');
    } finally {
      likingCommentIds.remove(commentId);
    }
  }

  @override
  void onClose() {
    if (_currentEventId != null) {
      _repository.unsubscribeFromEventCommentsRealtime(_currentEventId!);
    }
    commentTextController.dispose();
    commentFocusNode.dispose();
    super.onClose();
  }
}
