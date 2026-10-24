class CommunityModel {
  final String id;
  final String name;
  final String slug;
  final String? description;
  final String? avatarUrl;
  final String? bannerUrl;
  final String visibility; // 'public' or 'prive'
  final String status; // 'confirmed' or 'pending' or 'error'
  final int memberCount;
  final int cachedAt;
  final int createdAt;

  const CommunityModel({
    required this.id,
    required this.name,
    required this.slug,
    this.description,
    this.avatarUrl,
    this.bannerUrl,
    required this.visibility,
    required this.status,
    this.memberCount = 1,
    required this.cachedAt,
    required this.createdAt,
  });

  factory CommunityModel.fromMap(Map<String, dynamic> map) {
    final rawId = map['id']?.toString() ?? '';
    final rawSlug = map['slug']?.toString();
    final slug = (rawSlug != null && rawSlug.trim().isNotEmpty) ? rawSlug.trim() : rawId;

    return CommunityModel(
      id: rawId,
      name: map['name']?.toString() ?? '',
      slug: slug,
      description: map['description']?.toString(),
      avatarUrl: map['avatar_url']?.toString() ?? map['photo_profile']?.toString() ?? map['imageUrl']?.toString(),
      bannerUrl: map['banner_url']?.toString() ?? map['photo_cover']?.toString(),
      visibility: map['visibility']?.toString() ?? 'public',
      status: map['status']?.toString() ?? 'confirmed',
      memberCount: (map['member_count'] as num?)?.toInt() ?? 1,
      cachedAt: (map['cached_at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      createdAt: (map['created_at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'slug': slug,
      'description': description,
      'avatar_url': avatarUrl,
      'banner_url': bannerUrl,
      'visibility': visibility,
      'status': status,
      'member_count': memberCount,
      'cached_at': cachedAt,
      'created_at': createdAt,
    };
  }

  CommunityModel copyWith({
    String? id,
    String? name,
    String? slug,
    String? description,
    String? avatarUrl,
    String? bannerUrl,
    String? visibility,
    String? status,
    int? memberCount,
    int? cachedAt,
    int? createdAt,
  }) {
    return CommunityModel(
      id: id ?? this.id,
      name: name ?? this.name,
      slug: slug ?? this.slug,
      description: description ?? this.description,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bannerUrl: bannerUrl ?? this.bannerUrl,
      visibility: visibility ?? this.visibility,
      status: status ?? this.status,
      memberCount: memberCount ?? this.memberCount,
      cachedAt: cachedAt ?? this.cachedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class CommunityOpenResult {
  final String destination; // 'community', 'preview', 'unavailable'
  final String? membershipStatus; // 'active', 'pending', 'none', 'excluded'
  final String? requestStatus; // 'en_attente', 'approuve', 'refuse', 'none'
  final String joinAction; // 'join', 'request', 'none'
  final List<String> reasons;
  final String? id;
  final String? name;
  final String? slug;
  final String? description;
  final String? photoProfile;
  final String? photoCover;
  final String? visibility;
  final int? memberCount;

  const CommunityOpenResult({
    required this.destination,
    this.membershipStatus,
    this.requestStatus,
    this.joinAction = 'none',
    this.reasons = const [],
    this.id,
    this.name,
    this.slug,
    this.description,
    this.photoProfile,
    this.photoCover,
    this.visibility,
    this.memberCount,
  });

  factory CommunityOpenResult.fromJson(Map<String, dynamic> json) {
    final rawDestination = json['destination']?.toString().toLowerCase();
    String destination = 'unavailable';
    if (rawDestination == 'community') {
      destination = 'community';
    } else if (rawDestination == 'preview') {
      destination = 'preview';
    }

    final rawAction = json['join_action']?.toString().toLowerCase();
    String joinAction = 'none';
    if (rawAction == 'join') {
      joinAction = 'join';
    } else if (rawAction == 'request') {
      joinAction = 'request';
    }

    final rawReasons = json['reasons'] is List
        ? (json['reasons'] as List).map((e) => e.toString()).toList()
        : <String>[];

    final communityData = json['community'] is Map
        ? Map<String, dynamic>.from(json['community'] as Map)
        : json;

    return CommunityOpenResult(
      destination: destination,
      membershipStatus: json['membership_status']?.toString() ?? communityData['membership_status']?.toString(),
      requestStatus: json['request_status']?.toString() ?? communityData['request_status']?.toString(),
      joinAction: joinAction,
      reasons: rawReasons,
      id: communityData['id']?.toString() ?? json['id']?.toString(),
      name: communityData['name']?.toString() ?? communityData['title']?.toString() ?? json['name']?.toString() ?? json['title']?.toString(),
      slug: communityData['slug']?.toString() ?? json['slug']?.toString(),
      description: communityData['description']?.toString() ?? communityData['subtitle']?.toString() ?? json['description']?.toString() ?? json['subtitle']?.toString(),
      photoProfile: communityData['photo_profile']?.toString() ?? communityData['photo_url']?.toString() ?? json['photo_profile']?.toString() ?? json['photo_url']?.toString(),
      photoCover: communityData['photo_cover']?.toString() ?? json['photo_cover']?.toString(),
      visibility: communityData['visibility']?.toString() ?? json['visibility']?.toString(),
      memberCount: (communityData['member_count'] as num?)?.toInt() ?? (json['member_count'] as num?)?.toInt(),
    );
  }

  bool get isMember => destination == 'community' || membershipStatus == 'active';
  bool get isPending => membershipStatus == 'pending' || requestStatus == 'en_attente' || reasons.contains('REQUEST_PENDING');
}
