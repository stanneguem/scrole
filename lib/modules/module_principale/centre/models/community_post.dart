import 'package:flutter/material.dart';
import 'package:scrole/shared/models/post_media.dart';
import 'package:scrole/modules/module_principale/interne/enums/community_role_enum.dart';

enum PostReaction { like, dislike, none }

class CommunityPostAuthor {
  final String userId;
  final String username;
  final String? photoUrl;
  final bool isCertified;

  const CommunityPostAuthor({
    required this.userId,
    required this.username,
    this.photoUrl,
    this.isCertified = false,
  });

  String get displayName => username.isNotEmpty ? username : 'Utilisateur';

  factory CommunityPostAuthor.fromMap(Map<String, dynamic> map) {
    return CommunityPostAuthor(
      userId: map['user_id']?.toString() ?? map['id']?.toString() ?? '',
      username: map['username']?.toString() ?? '',
      photoUrl: map['photo_url']?.toString() ?? map['avatar_url']?.toString(),
      isCertified: map['is_certified'] == true || map['is_certified'] == 1 || map['is_verified'] == true || map['is_verified'] == 1,
    );
  }
}

class CommunityPostMention {
  final String userId;
  final String username;
  final String? photoUrl;
  final bool isCertified;

  const CommunityPostMention({
    required this.userId,
    required this.username,
    this.photoUrl,
    this.isCertified = false,
  });
}

class HashtagModel {
  final String name;
  const HashtagModel({required this.name});
}

class CommunityPost {
  final String id;
  final String authorName;
  final String authorId;
  final Color authorColor;
  final CommunityRole authorRole;
  final CommunityPostAuthor? authorObj;
  final String timeAgo;
  final String content;
  final List<PostMedia> media;
  final List<HashtagModel> hashtags;
  final List<CommunityPostMention>? mentionedUsers;
  final List<CommunityPostMention>? influencerReactions;
  final dynamic poll;
  final int likeCount;
  final int dislikeCount;
  final int commentCount;
  final int shareCount;
  final int viewCount;
  final bool viewerHasShared;
  final String? sharedPostId;
  final CommunityPost? sharedPost;
  final bool sharingEnabled;
  final bool communitySharingEnabled;
  final bool canOpenOriginal;
  final bool commentsEnabled;
  final bool reactionsEnabled;
  final String audience;
  final PostReaction userReaction;
  final bool isPublishing;
  final String? eventId;
  final String? eventName;
  final String? eventLogoUrl;
  final String? eventCity;
  final String? communityId;
  final String? communityName;
  final String? communityLogoUrl;
  final bool isSuggested;
  final String? reasonSubtitle;

  const CommunityPost({
    required this.id,
    required this.authorName,
    required this.authorId,
    this.authorColor = Colors.blue,
    this.authorRole = CommunityRole.member,
    this.authorObj,
    required this.timeAgo,
    required this.content,
    this.media = const [],
    this.hashtags = const [],
    this.mentionedUsers,
    this.influencerReactions,
    this.poll,
    this.likeCount = 0,
    this.dislikeCount = 0,
    this.commentCount = 0,
    this.shareCount = 0,
    this.viewCount = 0,
    this.viewerHasShared = false,
    this.sharedPostId,
    this.sharedPost,
    this.sharingEnabled = true,
    this.communitySharingEnabled = true,
    this.canOpenOriginal = true,
    this.commentsEnabled = true,
    this.reactionsEnabled = true,
    this.audience = 'public',
    this.userReaction = PostReaction.none,
    this.isPublishing = false,
    this.eventId,
    this.eventName,
    this.eventLogoUrl,
    this.eventCity,
    this.communityId,
    this.communityName,
    this.communityLogoUrl,
    this.isSuggested = false,
    this.reasonSubtitle,
  });

  int get sharesCount => shareCount;
  int get viewsCount => viewCount;
  bool get canRepost => sharingEnabled && communitySharingEnabled;

  factory CommunityPost.fromMap(Map<String, dynamic> map) {
    final authorMap = map['author'] is Map ? Map<String, dynamic>.from(map['author']) : <String, dynamic>{};
    final authorObj = authorMap.isNotEmpty ? CommunityPostAuthor.fromMap(authorMap) : null;
    final authorName = authorObj != null ? authorObj.displayName : (map['author_name']?.toString() ?? 'Utilisateur');

    PostReaction reaction = PostReaction.none;
    final vr = map['viewer_reaction']?.toString().toLowerCase();
    if (vr == 'like') reaction = PostReaction.like;
    if (vr == 'dislike') reaction = PostReaction.dislike;

    List<PostMedia> mediaList = [];
    if (map['media'] is List) {
      mediaList = (map['media'] as List).map((m) {
        if (m is Map) return PostMedia.fromJson(Map<String, dynamic>.from(m));
        if (m is String) return PostMedia(type: 'photo', url: m);
        return null;
      }).whereType<PostMedia>().where((m) => m.url.trim().isNotEmpty).toList();
    }
    if (mediaList.isEmpty && map['photos'] is List) {
      mediaList = (map['photos'] as List)
          .map((p) => PostMedia(type: 'photo', url: p.toString()))
          .where((m) => m.url.trim().isNotEmpty)
          .toList();
    }
    if (mediaList.isEmpty) {
      final photo = (map['photo'] ?? '').toString();
      if (photo.isNotEmpty) mediaList.add(PostMedia(type: 'photo', url: photo));
    }
    final videoUrl = (map['video_url'] ?? '').toString();
    if (videoUrl.isNotEmpty && !mediaList.any((m) => m.isVideo && m.url == videoUrl)) {
      mediaList.add(PostMedia(
        type: 'video',
        url: videoUrl,
        thumbnailUrl: (map['video_thumbnail_url'] ?? '').toString().isEmpty
            ? null
            : (map['video_thumbnail_url']).toString(),
      ));
    }
    if (map['videos'] is List) {
      for (final entry in map['videos'] as List) {
        late final PostMedia item;
        if (entry is Map) {
          final parsed = PostMedia.fromJson(Map<String, dynamic>.from(entry));
          if (parsed.url.isEmpty) continue;
          item = parsed.isVideo
              ? parsed
              : PostMedia(type: 'video', storage: parsed.storage, url: parsed.url, thumbnailUrl: parsed.thumbnailUrl);
        } else if (entry is String && entry.isNotEmpty) {
          item = PostMedia(type: 'video', url: entry);
        } else {
          continue;
        }
        if (!mediaList.any((existing) => existing.url == item.url)) {
          mediaList.add(item);
        }
      }
    }

    final rawHashtags = map['hashtags'] ?? map['post_hashtags'] ?? map['tags'];
    final parsedHashtags = rawHashtags is List
        ? rawHashtags.map((entry) {
            if (entry is Map) {
              final name = (entry['name'] ?? entry['hashtag'] ?? entry['normalized_name'] ?? '').toString().trim();
              return name.isEmpty ? null : HashtagModel(name: name.replaceFirst(RegExp(r'^#+'), ''));
            }
            final name = entry.toString().trim();
            return name.isEmpty ? null : HashtagModel(name: name.replaceFirst(RegExp(r'^#+'), ''));
          }).whereType<HashtagModel>().toList()
        : <HashtagModel>[];

    final rawMentions = map['mentions'] ?? map['mentioned_users'] ?? map['mentionedUsers'];
    final parsedMentions = rawMentions is List
        ? rawMentions.map((entry) {
            if (entry is! Map) return null;
            final row = Map<String, dynamic>.from(entry);
            final userId = (row['user_id'] ?? row['id'] ?? row['profile_id'] ?? '').toString();
            final profile = row['user_profiles'] is Map
                ? Map<String, dynamic>.from(row['user_profiles'] as Map)
                : <String, dynamic>{};
            final username = (row['username'] ?? profile['username'] ?? '').toString();
            if (userId.isEmpty) return null;
            return CommunityPostMention(
              userId: userId,
              username: username,
              photoUrl: (row['photo_url'] ?? profile['photo_url'])?.toString(),
              isCertified: row['is_certified'] == true || row['is_certified'] == 1 ||
                  row['is_verified'] == true || row['is_verified'] == 1 ||
                  profile['is_certified'] == true || profile['is_certified'] == 1 ||
                  profile['is_verified'] == true || profile['is_verified'] == 1,
            );
          }).whereType<CommunityPostMention>().toList()
        : <CommunityPostMention>[];

    CommunityPost? shared;
    if (map['shared_post'] is Map) {
      final spMap = Map<String, dynamic>.from(map['shared_post']);
      if (spMap['available'] != false) {
        shared = CommunityPost.fromMap(spMap);
      }
    }

    return CommunityPost(
      id: map['id']?.toString() ?? '',
      authorName: authorName,
      authorId: authorObj?.userId ?? map['author_id']?.toString() ?? '',
      authorObj: authorObj,
      timeAgo: map['created_at']?.toString() ?? '',
      content: map['content']?.toString() ?? '',
      media: mediaList,
      hashtags: parsedHashtags,
      mentionedUsers: parsedMentions,
      poll: map['poll'] ?? map['poll_state'] ?? map['community_poll'],
      likeCount: (map['likes_count'] as num?)?.toInt() ?? 0,
      dislikeCount: (map['dislikes_count'] as num?)?.toInt() ?? 0,
      commentCount: (map['comments_count'] as num?)?.toInt() ?? 0,
      shareCount: (map['shares_count'] as num?)?.toInt() ?? 0,
      viewCount: (map['views_count'] as num?)?.toInt() ?? 0,
      viewerHasShared: map['viewer_has_shared'] == true || map['viewer_has_shared'] == 1,
      sharedPostId: map['shared_post_id']?.toString(),
      sharedPost: shared,
      sharingEnabled: map['sharing_enabled'] != false,
      communitySharingEnabled: map['community'] is Map
          ? (map['community']['allow_post_sharing'] != false)
          : true,
      canOpenOriginal: map['shared_post_can_open_original'] != false && map['can_open_original'] != false,
      commentsEnabled: map['comments_enabled'] != false,
      reactionsEnabled: map['reactions_enabled'] != false,
      audience: map['audience']?.toString() ?? 'public',
      userReaction: reaction,
      communityId: map['community_id']?.toString(),
      communityName: map['community'] is Map ? map['community']['name']?.toString() : map['community_name']?.toString(),
      communityLogoUrl: map['community'] is Map ? map['community']['photo_profile']?.toString() : map['community_logo_url']?.toString(),
      isSuggested: map['is_suggested'] == true || map['is_suggested'] == 1,
      reasonSubtitle: map['reason_subtitle']?.toString(),
    );
  }

  CommunityPost copyWith({
    PostReaction? userReaction,
    int? likeCount,
    int? dislikeCount,
    int? commentCount,
    int? shareCount,
    int? viewCount,
    bool? viewerHasShared,
    bool? isPublishing,
    String? audience,
    String? eventId,
    String? eventName,
    String? eventLogoUrl,
    String? eventCity,
    String? communityId,
    String? communityName,
    String? communityLogoUrl,
    bool? isSuggested,
    String? reasonSubtitle,
    List<CommunityPostMention>? mentionedUsers,
    List<CommunityPostMention>? influencerReactions,
    dynamic poll,
  }) {
    return CommunityPost(
      id: id,
      authorName: authorName,
      authorId: authorId,
      authorColor: authorColor,
      authorRole: authorRole,
      authorObj: authorObj,
      timeAgo: timeAgo,
      content: content,
      media: media,
      hashtags: hashtags,
      mentionedUsers: mentionedUsers ?? this.mentionedUsers,
      influencerReactions: influencerReactions ?? this.influencerReactions,
      poll: poll ?? this.poll,
      likeCount: likeCount ?? this.likeCount,
      dislikeCount: dislikeCount ?? this.dislikeCount,
      commentCount: commentCount ?? this.commentCount,
      shareCount: shareCount ?? this.shareCount,
      viewCount: viewCount ?? this.viewCount,
      viewerHasShared: viewerHasShared ?? this.viewerHasShared,
      sharedPostId: sharedPostId,
      sharedPost: sharedPost,
      sharingEnabled: sharingEnabled,
      communitySharingEnabled: communitySharingEnabled,
      canOpenOriginal: canOpenOriginal,
      commentsEnabled: commentsEnabled,
      reactionsEnabled: reactionsEnabled,
      audience: audience ?? this.audience,
      userReaction: userReaction ?? this.userReaction,
      isPublishing: isPublishing ?? this.isPublishing,
      eventId: eventId ?? this.eventId,
      eventName: eventName ?? this.eventName,
      eventLogoUrl: eventLogoUrl ?? this.eventLogoUrl,
      eventCity: eventCity ?? this.eventCity,
      communityId: communityId ?? this.communityId,
      communityName: communityName ?? this.communityName,
      communityLogoUrl: communityLogoUrl ?? this.communityLogoUrl,
      isSuggested: isSuggested ?? this.isSuggested,
      reasonSubtitle: reasonSubtitle ?? this.reasonSubtitle,
    );
  }
}
