import 'package:flutter/material.dart';

class PostMedia {
  final String type;
  final String storage;
  final String url;
  final String? thumbnailUrl;
  final Color color;

  const PostMedia({
    this.type = 'photo',
    this.storage = 'supabase',
    required this.url,
    this.thumbnailUrl,
    this.color = Colors.grey,
  });

  bool get isVideo => type.toLowerCase().contains('video');

  factory PostMedia.fromJson(Map<String, dynamic> json) {
    final rawType = (json['type'] ?? json['media_type'] ?? json['mime_type'] ?? 'photo').toString().toLowerCase();
    final type = rawType.contains('video') ? 'video' : (rawType.contains('gif') ? 'gif' : 'photo');
    return PostMedia(
      type: type,
      storage: json['storage']?.toString() ?? 'supabase',
      url: (json['url'] ?? json['media_url'] ?? json['original_url'] ?? json['video_url'] ?? '').toString(),
      thumbnailUrl: (json['thumbnail_url'] ?? json['thumbnail'] ?? json['video_thumbnail_url'])?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'storage': storage,
        'url': url,
        if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
      };
}
