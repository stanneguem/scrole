import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';
import 'package:scrole/modules/module_principale/externe/repositories/stories_repository.dart';
import 'package:scrole/modules/module_principale/centre/models/community_post.dart';
import '../../../../app_controller.dart';
import '../../../../app/repository_global/storage_repository.dart';
import '../../../../app/repository_global/r2_media_repository.dart';

class StoryItem {
  final String id;
  final String kind; // 'text' | 'image' | 'video'
  final String? content;
  final String? imageUrl;
  final String? background;
  final String audience;
  final DateTime createdAt;
  final DateTime expiresAt;
  bool viewed;
  int viewersCount;
  int commentsCount;
  final dynamic poll;
  bool isPending;
  int likesCount;
  int sharesCount;
  bool isLiked;
  final CommunityPost? sharedPost;
  final String? sharedPostId;
  final bool sharedPostCanOpenOriginal;

  StoryItem({
    required this.id,
    required this.kind,
    this.content,
    this.imageUrl,
    this.background,
    this.audience = 'public',
    required this.createdAt,
    required this.expiresAt,
    this.viewed = false,
    this.viewersCount = 0,
    this.commentsCount = 0,
    this.poll,
    this.isPending = false,
    this.likesCount = 0,
    this.sharesCount = 0,
    this.isLiked = false,
    this.sharedPost,
    this.sharedPostId,
    this.sharedPostCanOpenOriginal = true,
  });

  String? get mediaUrl => imageUrl;

  factory StoryItem.fromMap(Map<String, dynamic> map) {
    CommunityPost? shared;
    if (map['shared_post'] is Map) {
      final spMap = Map<String, dynamic>.from(map['shared_post']);
      if (spMap['available'] != false) {
        shared = CommunityPost.fromMap(spMap);
      } else {
        shared = CommunityPost(
          id: spMap['id']?.toString() ?? '',
          authorName: '',
          authorId: '',
          timeAgo: '',
          content: '',
        );
      }
    }

    return StoryItem(
      id: map['id']?.toString() ?? '',
      kind: map['kind']?.toString() ?? 'text',
      content: map['content']?.toString(),
      imageUrl: map['image_url']?.toString() ?? map['media_url']?.toString(),
      background: map['background']?.toString(),
      audience: map['audience']?.toString() ?? 'public',
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now() : DateTime.now(),
      expiresAt: map['expires_at'] != null ? DateTime.tryParse(map['expires_at'].toString()) ?? DateTime.now().add(const Duration(hours: 24)) : DateTime.now().add(const Duration(hours: 24)),
      viewed: map['viewed'] == true || map['viewed'] == 1,
      viewersCount: (map['viewers_count'] ?? map['views_count'] as num?)?.toInt() ?? 0,
      commentsCount: (map['comments_count'] ?? map['comment_count'] ?? map['shared_post']?['comment_count'] as num?)?.toInt() ?? 0,
      poll: map['poll'],
      likesCount: (map['likes_count'] as num?)?.toInt() ?? 0,
      sharesCount: (map['shares_count'] as num?)?.toInt() ?? 0,
      isLiked: map['is_liked'] == true ||
               map['is_liked'] == 1 ||
               map['is_liked']?.toString() == 'true' ||
               map['user_liked'] == true ||
               map['user_liked'] == 1 ||
               map['user_liked']?.toString() == 'true' ||
               map['viewer_has_liked'] == true ||
               map['viewer_has_liked'] == 1 ||
               map['viewer_has_liked']?.toString() == 'true' ||
               map['is_liked_by_me'] == true ||
               map['is_liked_by_me'] == 1 ||
               map['is_like'] == true ||
               map['liked'] == true ||
               map['liked'] == 1,
      sharedPost: shared,
      sharedPostId: map['shared_post_id']?.toString(),
      sharedPostCanOpenOriginal: map['shared_post_can_open_original'] == true,
    );
  }
}

class StoryAuthor {
  final String userId;
  final String username;
  final String firstName;
  final String lastName;
  final String? photoUrl;
  final bool isCertified;

  const StoryAuthor({
    required this.userId,
    required this.username,
    required this.firstName,
    required this.lastName,
    this.photoUrl,
    this.isCertified = false,
  });

  factory StoryAuthor.fromMap(Map<String, dynamic> map) {
    return StoryAuthor(
      userId: map['user_id']?.toString() ?? map['id']?.toString() ?? '',
      username: map['username']?.toString() ?? '',
      firstName: map['first_name']?.toString() ?? '',
      lastName: map['last_name']?.toString() ?? '',
      photoUrl: map['photo_url']?.toString() ?? map['avatar_url']?.toString(),
      isCertified: map['is_certified'] == true || map['is_certified'] == 1,
    );
  }

  String get displayName => '$firstName $lastName'.trim().isEmpty ? username : '$firstName $lastName'.trim();
}

class EventStoryGroup {
  final StoryAuthor author;
  final String relation; // 'own' | 'friend' | 'follow' | 'other'
  bool hasUnseen;
  final DateTime latestAt;
  final int storiesCount;
  final List<StoryItem> stories;

  EventStoryGroup({
    required this.author,
    required this.relation,
    required this.hasUnseen,
    required this.latestAt,
    required this.storiesCount,
    required this.stories,
  });

  String get eventName => author.displayName;
  String? get eventLogoUrl => author.photoUrl;

  factory EventStoryGroup.fromMap(Map<String, dynamic> map) {
    final authorMap = map['author'] is Map ? Map<String, dynamic>.from(map['author']) : <String, dynamic>{};
    final storiesList = map['stories'] is List ? (map['stories'] as List).map((s) => StoryItem.fromMap(Map<String, dynamic>.from(s))).toList() : <StoryItem>[];
    
    final now = DateTime.now();
    final validStories = storiesList.where((s) => s.expiresAt.isAfter(now)).toList();

    return EventStoryGroup(
      author: StoryAuthor.fromMap(authorMap),
      relation: map['relation']?.toString() ?? 'other',
      hasUnseen: map['has_unseen'] == true || map['has_unseen'] == 1 || validStories.any((s) => !s.viewed),
      latestAt: map['latest_at'] != null ? DateTime.tryParse(map['latest_at'].toString()) ?? DateTime.now() : DateTime.now(),
      storiesCount: validStories.length,
      stories: validStories,
    );
  }
}

class StoriesController extends GetxController {
  final StoriesRepository _repo = StoriesRepository();
  final StorageRepository _storageRepo = StorageRepository();
  final R2MediaRepository _r2MediaRepo = R2MediaRepository();

  final Rxn<EventStoryGroup> ownGroup = Rxn<EventStoryGroup>();
  final RxList<EventStoryGroup> followingGroups = <EventStoryGroup>[].obs;
  final RxList<EventStoryGroup> suggestedGroups = <EventStoryGroup>[].obs;
  final RxBool isLoading = false.obs;
  final RxBool isPublishingStory = false.obs;

  List<EventStoryGroup> get storyGroups => [
        if (ownGroup.value != null) ownGroup.value!,
        ...followingGroups,
        ...suggestedGroups,
      ];

  @override
  void onInit() {
    super.onInit();
    fetchStories();
  }

  Future<void> fetchStories() async {
    isLoading.value = true;
    try {
      debugPrint('[STORY] [Controller] Fetching stories tray');
      final data = await _repo.getStoriesTray();
      
      if (data['own'] != null) {
        ownGroup.value = EventStoryGroup.fromMap(Map<String, dynamic>.from(data['own']));
      } else {
        ownGroup.value = null;
      }

      if (data['following'] is List) {
        followingGroups.value = (data['following'] as List)
            .map((g) => EventStoryGroup.fromMap(Map<String, dynamic>.from(g)))
            .where((g) => g.stories.isNotEmpty)
            .toList();
      }

      if (data['suggested'] is List) {
        suggestedGroups.value = (data['suggested'] as List)
            .map((g) => EventStoryGroup.fromMap(Map<String, dynamic>.from(g)))
            .where((g) => g.stories.isNotEmpty)
            .toList();
      }
      debugPrint('[STORY] [Controller] Stories tray fetched successfully.');
    } catch (e, st) {
      debugPrint('[STORY] [Controller] Error fetching stories: $e\n$st');
    } finally {
      isLoading.value = false;
    }
  }

  void markAsViewed(String userId) {
    if (ownGroup.value?.author.userId == userId) {
      ownGroup.value?.hasUnseen = false;
      ownGroup.refresh();
    }
    final fIdx = followingGroups.indexWhere((g) => g.author.userId == userId);
    if (fIdx != -1) {
      followingGroups[fIdx].hasUnseen = false;
      followingGroups.refresh();
    }
    final sIdx = suggestedGroups.indexWhere((g) => g.author.userId == userId);
    if (sIdx != -1) {
      suggestedGroups[sIdx].hasUnseen = false;
      suggestedGroups.refresh();
    }
  }

  void refreshGroupViewedState(EventStoryGroup group) {
    group.hasUnseen = group.stories.any((story) => !story.viewed);
    if (ownGroup.value?.author.userId == group.author.userId) {
      ownGroup.refresh();
      return;
    }
    if (followingGroups.any((item) => item.author.userId == group.author.userId)) {
      followingGroups.refresh();
      return;
    }
    if (suggestedGroups.any((item) => item.author.userId == group.author.userId)) {
      suggestedGroups.refresh();
    }
  }

  Future<void> markStoriesViewed(List<String> storyIds) async {
    if (storyIds.isEmpty) return;
    try {
      debugPrint('[STORY] [Controller] Marking ${storyIds.length} stories as viewed');
      await _repo.markStoriesViewed(storyIds);
    } catch (e) {
      debugPrint('[STORY] [Controller] Error marking stories viewed: $e');
    }
  }

  Future<void> deleteStory(String storyId) async {
    try {
      debugPrint('[STORY] [Controller] Deleting story $storyId');
      await _repo.deleteStory(storyId);
      await fetchStories();
      Get.snackbar('Succès', 'Story supprimée', snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      debugPrint('[STORY] [Controller] Error deleting story: $e');
      Get.snackbar('Erreur', 'Impossible de supprimer la story', snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  Future<void> votePoll(String storyId, List<String> optionIds) async {
    try {
      debugPrint('[STORY] [Controller] Voting on poll for story $storyId');
      await _repo.voteStoryPoll(storyId, optionIds);
    } catch (e) {
      debugPrint('[STORY] [Controller] Error voting on poll: $e');
      Get.snackbar('Erreur', e.toString().replaceFirst('Exception: ', '').tr, snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  Future<void> createStory({
    required String kind,
    String? content,
    File? imageFile,
    List<File>? imageFiles,
    List<String>? mentions,
    String? background,
    String audience = 'public',
    Map<String, dynamic>? poll,
    bool allowReshare = false,
  }) async {
    final pId = const Uuid().v4();
    debugPrint('[STORY] [Controller] Creating story p_id=$pId, kind=$kind');

    final fileToUpload = imageFile ?? (imageFiles != null && imageFiles.isNotEmpty ? imageFiles.first : null);

    String? imageUrl;
    if ((kind == 'image' || kind == 'video') && fileToUpload != null) {
      try {
        if (kind == 'video') {
          final videoController = VideoPlayerController.file(fileToUpload);
          try {
            await videoController.initialize().timeout(const Duration(seconds: 30));
            final duration = videoController.value.duration;
            if (duration <= Duration.zero) {
              throw StateError('Impossible de déterminer la durée de la vidéo.');
            }
            debugPrint('[STORY] [Controller] Uploading story video to private Cloudflare R2 duration=${duration.inMilliseconds}ms');
            final uploaded = await _r2MediaRepo.uploadFile(
              file: fileToUpload,
              category: 'story_media',
              mediaType: 'video',
              videoDuration: duration,
            );
            imageUrl = uploaded.objectKey;
          } finally {
            await videoController.dispose();
          }
        } else {
        debugPrint('[STORY] [Controller] Compressing story image...');
        final appDir = await getApplicationDocumentsDirectory();
        final targetPath = p.join(appDir.path, 'stories', pId, 'story.jpg');
        await Directory(p.dirname(targetPath)).create(recursive: true);

        final compressedBytes = await FlutterImageCompress.compressAndGetFile(
          fileToUpload.absolute.path,
          targetPath,
          minWidth: 1080,
          quality: 80,
        );

        final finalFile = compressedBytes != null ? File(compressedBytes.path) : fileToUpload;
        debugPrint('[STORY] [Controller] Uploading story image to private Cloudflare R2');
        final uploaded = await _r2MediaRepo.uploadFile(
          file: finalFile,
          category: 'story_media',
          mediaType: 'image',
        );
        // Store the canonical private R2 object key. The media URL endpoint
        // checks story visibility before issuing a short-lived signed URL.
        imageUrl = uploaded.objectKey;
        debugPrint('[STORY] [Controller] Story image uploaded to R2 object key: $imageUrl');
        }
      } catch (e, st) {
        debugPrint('[STORY] [Controller] Story image compression/upload error: $e\n$st');
        Get.snackbar('Erreur', 'Échec de l\'upload du média de la story', snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
        return;
      }
    }

    try {
      await _repo.createStoryRpc(
        p_id: pId,
        p_kind: kind,
        p_content: content,
        p_image_url: imageUrl,
        p_background: background,
        p_audience: audience,
        p_poll: poll,
        p_allow_reshare: allowReshare,
      );

      await fetchStories();
      Get.snackbar('Succès', 'Story publiée avec succès !', snackPosition: SnackPosition.BOTTOM);
    } catch (e, st) {
      debugPrint('[STORY] [Controller] Error creating story RPC: $e\n$st');
      Get.snackbar('Erreur', e.toString().replaceFirst('Exception: ', '').tr, snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
    }
  }
}
