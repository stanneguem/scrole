import 'package:flutter/material.dart';
import 'community_post.dart';

class PostComment {
  final String id;
  final String authorName;
  final String authorId;
  final Color authorColor;
  final String? avatarUrl;
  final String timeAgo;
  final String content;
  final int likesCount;
  final PostReaction userReaction;
  final bool isCertified;
  final bool isOp;
  final int repliesCount;
  final List<PostComment> replies;

  const PostComment({
    required this.id,
    required this.authorName,
    required this.authorId,
    required this.authorColor,
    this.avatarUrl,
    required this.timeAgo,
    required this.content,
    this.likesCount = 0,
    this.userReaction = PostReaction.none,
    this.isCertified = false,
    this.isOp = false,
    this.repliesCount = 0,
    this.replies = const [],
  });

  PostComment copyWith({
    String? id,
    String? authorName,
    int? likesCount,
    PostReaction? userReaction,
    List<PostComment>? replies,
  }) {
    return PostComment(
      id: id ?? this.id,
      authorName: authorName ?? this.authorName,
      authorId: authorId,
      authorColor: authorColor,
      avatarUrl: avatarUrl,
      timeAgo: timeAgo,
      content: content,
      likesCount: likesCount ?? this.likesCount,
      userReaction: userReaction ?? this.userReaction,
      isCertified: isCertified,
      isOp: isOp,
      repliesCount: repliesCount,
      replies: replies ?? this.replies,
    );
  }
}
