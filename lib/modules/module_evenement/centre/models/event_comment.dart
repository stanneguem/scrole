/// Modèle d'auteur pour les commentaires d'événements Scrole.
class CommentAuthor {
  final String userId;
  final String username;
  final String? firstName;
  final String? lastName;
  final String? photoUrl;

  const CommentAuthor({
    required this.userId,
    required this.username,
    this.firstName,
    this.lastName,
    this.photoUrl,
  });

  String get displayName {
    final full = '${firstName ?? ''} ${lastName ?? ''}'.trim();
    if (full.isNotEmpty) return full;
    if (username.isNotEmpty) return username;
    return 'Membre Scrole';
  }

  factory CommentAuthor.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const CommentAuthor(userId: '', username: 'Membre Scrole');
    }
    return CommentAuthor(
      userId: (json['user_id'] ?? json['id'] ?? '').toString(),
      username: (json['username'] ?? json['user_name'] ?? 'Membre Scrole').toString(),
      firstName: json['first_name']?.toString(),
      lastName: json['last_name']?.toString(),
      photoUrl: (json['photo_url'] ?? json['avatar_url'])?.toString(),
    );
  }
}

/// Modèle pour les commentaires et réponses d'un événement Scrole.
class EventComment {
  final String id;
  final String eventId;
  final String userId;
  final String content;
  final String? parentCommentId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final CommentAuthor author;
  final String? eventRole; // "founder", "co_founder", "staff", or null
  final int likesCount;
  final bool isLikedByMe;
  final int repliesCount;
  final List<EventComment> replies;

  final bool areRepliesLoaded;
  final bool isLoadingReplies;
  final bool hasMoreReplies;

  const EventComment({
    required this.id,
    required this.eventId,
    required this.userId,
    required this.content,
    this.parentCommentId,
    required this.createdAt,
    this.updatedAt,
    required this.author,
    this.eventRole,
    this.likesCount = 0,
    this.isLikedByMe = false,
    this.repliesCount = 0,
    this.replies = const [],
    this.areRepliesLoaded = false,
    this.isLoadingReplies = false,
    this.hasMoreReplies = false,
  });

  bool get isLiked => isLikedByMe;

  factory EventComment.fromJson(Map<String, dynamic> json) {
    List<EventComment> repliesList = [];
    if (json['replies'] is List) {
      repliesList = (json['replies'] as List)
          .whereType<Map>()
          .map((m) => EventComment.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    }

    CommentAuthor authorObj;
    if (json['author'] is Map) {
      authorObj = CommentAuthor.fromJson(Map<String, dynamic>.from(json['author'] as Map));
    } else {
      authorObj = CommentAuthor(
        userId: (json['user_id'] ?? json['author_id'] ?? '').toString(),
        username: (json['username'] ?? json['author_name'] ?? 'Membre Scrole').toString(),
        photoUrl: (json['photo_url'] ?? json['avatar_url'])?.toString(),
      );
    }

    final rawRole = json['event_role']?.toString();
    final validRole = (rawRole == 'founder' || rawRole == 'co_founder' || rawRole == 'staff')
        ? rawRole
        : null;

    return EventComment(
      id: (json['id'] ?? '').toString(),
      eventId: (json['event_id'] ?? json['evenement_id'] ?? '').toString(),
      userId: (json['user_id'] ?? json['author_id'] ?? authorObj.userId).toString(),
      content: (json['content'] ?? json['commentaire'] ?? '').toString(),
      parentCommentId: json['parent_comment_id']?.toString() ?? json['parent_id']?.toString(),
      createdAt: json['created_at'] != null
          ? (DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now())
          : DateTime.now(),
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'].toString()) : null,
      author: authorObj,
      eventRole: validRole,
      likesCount: (json['likes_count'] as num?)?.toInt() ?? 0,
      isLikedByMe: (json['is_liked'] ?? json['is_liked_by_me']) == true,
      repliesCount: (json['replies_count'] as num?)?.toInt() ?? repliesList.length,
      replies: repliesList,
      areRepliesLoaded: repliesList.isNotEmpty,
    );
  }

  EventComment copyWith({
    String? content,
    String? eventRole,
    int? likesCount,
    bool? isLikedByMe,
    int? repliesCount,
    List<EventComment>? replies,
    bool? areRepliesLoaded,
    bool? isLoadingReplies,
    bool? hasMoreReplies,
  }) {
    return EventComment(
      id: id,
      eventId: eventId,
      userId: userId,
      content: content ?? this.content,
      parentCommentId: parentCommentId,
      createdAt: createdAt,
      updatedAt: updatedAt,
      author: author,
      eventRole: eventRole ?? this.eventRole,
      likesCount: likesCount ?? this.likesCount,
      isLikedByMe: isLikedByMe ?? this.isLikedByMe,
      repliesCount: repliesCount ?? this.repliesCount,
      replies: replies ?? this.replies,
      areRepliesLoaded: areRepliesLoaded ?? this.areRepliesLoaded,
      isLoadingReplies: isLoadingReplies ?? this.isLoadingReplies,
      hasMoreReplies: hasMoreReplies ?? this.hasMoreReplies,
    );
  }
}
