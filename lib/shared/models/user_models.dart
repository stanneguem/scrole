import 'package:get/get.dart';

class AppPreferences {
  final String language;
  final String theme;
  final bool notificationsEnabled;
  final bool notifPush;
  final bool notifMessages;
  final bool notifEvenements;
  final bool notifCommunautes;
  final bool notifSocial;
  final bool autoPlayVideos;

  AppPreferences({
    required this.language,
    required this.theme,
    required this.notificationsEnabled,
    this.notifPush = true,
    this.notifMessages = true,
    this.notifEvenements = true,
    this.notifCommunautes = true,
    this.notifSocial = true,
    this.autoPlayVideos = true,
  });

  factory AppPreferences.fromJson(Map<String, dynamic> json) => AppPreferences(
    language: json['language']?.toString() ?? _getDeviceLanguage(),
    theme: json['theme']?.toString() ?? 'system',
    notificationsEnabled: json['notifications_enabled'] as bool? ?? true,
    notifPush: json['notif_push'] as bool? ?? true,
    notifMessages: json['notif_messages'] as bool? ?? true,
    notifEvenements: json['notif_evenements'] as bool? ?? true,
    notifCommunautes: json['notif_communautes'] as bool? ?? true,
    notifSocial: json['notif_social'] as bool? ?? true,
    autoPlayVideos: json['auto_play_videos'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    'language': language,
    'theme': theme,
    'notifications_enabled': notificationsEnabled,
    'notif_push': notifPush,
    'notif_messages': notifMessages,
    'notif_evenements': notifEvenements,
    'notif_communautes': notifCommunautes,
    'notif_social': notifSocial,
    'auto_play_videos': autoPlayVideos,
  };

  factory AppPreferences.defaultValues() => AppPreferences(
    language: _getDeviceLanguage(),
    theme: 'system',
    notificationsEnabled: true,
    autoPlayVideos: true,
  );

  static String _getDeviceLanguage() => Get.deviceLocale?.languageCode ?? 'fr';
}

class AppPrivacy {
  final String profileVisibility;
  final bool showOnlineStatus;
  final String allowMessagesFrom;
  final bool afficherPays;
  final bool afficherVille;
  final bool afficherDerniereConnexion;
  final String eventItineraryVisibility;

  AppPrivacy({required this.profileVisibility, required this.showOnlineStatus, required this.allowMessagesFrom, required this.afficherPays, required this.afficherVille, required this.afficherDerniereConnexion, this.eventItineraryVisibility = 'only_me'});

  factory AppPrivacy.fromJson(Map<String, dynamic> json) => AppPrivacy(
    profileVisibility: json['profile_visibility'] ?? 'public',
    showOnlineStatus: json['show_online_status'] ?? true,
    allowMessagesFrom: json['allow_messages_from'] ?? 'everyone',
    afficherPays: json['afficher_pays'] ?? true,
    afficherVille: json['afficher_ville'] ?? true,
    afficherDerniereConnexion: json['afficher_derniere_connexion'] ?? true,
    eventItineraryVisibility: json['event_itinerary_visibility'] ?? 'only_me',
  );

  Map<String, dynamic> toJson() => {'profile_visibility': profileVisibility, 'show_online_status': showOnlineStatus, 'allow_messages_from': allowMessagesFrom, 'afficher_pays': afficherPays, 'afficher_ville': afficherVille, 'afficher_derniere_connexion': afficherDerniereConnexion, 'event_itinerary_visibility': eventItineraryVisibility};

  AppPrivacy copyWith({
    String? profileVisibility,
    bool? showOnlineStatus,
    String? allowMessagesFrom,
    bool? afficherPays,
    bool? afficherVille,
    bool? afficherDerniereConnexion,
    String? eventItineraryVisibility,
  }) => AppPrivacy(
    profileVisibility: profileVisibility ?? this.profileVisibility,
    showOnlineStatus: showOnlineStatus ?? this.showOnlineStatus,
    allowMessagesFrom: allowMessagesFrom ?? this.allowMessagesFrom,
    afficherPays: afficherPays ?? this.afficherPays,
    afficherVille: afficherVille ?? this.afficherVille,
    afficherDerniereConnexion: afficherDerniereConnexion ?? this.afficherDerniereConnexion,
    eventItineraryVisibility: eventItineraryVisibility ?? this.eventItineraryVisibility,
  );

  factory AppPrivacy.defaultValues() => AppPrivacy(profileVisibility: 'public', showOnlineStatus: true, allowMessagesFrom: 'everyone', afficherPays: true, afficherVille: true, afficherDerniereConnexion: true, eventItineraryVisibility: 'only_me');
}

class DeviceInfos {
  final String? id;
  final String? userId;
  final String? deviceToken;
  final String? platform;
  final String? osVersion;
  final String? appVersion;
  final DateTime? lastSeenAt;
  final String? deviceBrand;
  final String? deviceModel;
  final String? detectedCountryId;
  final String? detectedCountry;
  final String? pushProvider;
  final bool? pushEnabled;
  final DateTime? tokenUpdatedAt;
  final bool? isCurrentDevice;

  DeviceInfos({this.id, this.userId, this.deviceToken, this.platform, this.osVersion, this.appVersion, this.lastSeenAt, this.deviceBrand, this.deviceModel, this.detectedCountryId, this.detectedCountry, this.pushProvider, this.pushEnabled, this.tokenUpdatedAt, this.isCurrentDevice});

  factory DeviceInfos.fromJson(Map<String, dynamic> json) => DeviceInfos(
    id: json['id']?.toString(),
    userId: json['user_id']?.toString(),
    deviceToken: json['device_token']?.toString(),
    platform: json['platform']?.toString(),
    osVersion: json['os_version']?.toString(),
    appVersion: json['app_version']?.toString(),
    lastSeenAt: _parseDateTime(json['last_seen_at']),
    deviceBrand: json['device_brand']?.toString(),
    deviceModel: json['device_model']?.toString(),
    detectedCountryId: json['detected_country_id']?.toString(),
    detectedCountry: json['detected_country']?.toString(),
    pushProvider: json['push_provider']?.toString(),
    pushEnabled: json['push_enabled'] as bool?,
    tokenUpdatedAt: _parseDateTime(json['token_updated_at']),
    isCurrentDevice: json['is_current_device'] as bool?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'device_token': deviceToken,
    'platform': platform,
    'os_version': osVersion,
    'app_version': appVersion,
    'last_seen_at': lastSeenAt?.toIso8601String(),
    'device_brand': deviceBrand,
    'device_model': deviceModel,
    'detected_country_id': detectedCountryId,
    'detected_country': detectedCountry,
    'push_provider': pushProvider,
    'push_enabled': pushEnabled,
    'token_updated_at': tokenUpdatedAt?.toIso8601String(),
    'is_current_device': isCurrentDevice,
  };

  static DateTime? _parseDateTime(dynamic value) => value == null ? null : DateTime.tryParse(value.toString());
}

class UserSessionData {
  final Map<String, dynamic> profile;
  final AppPreferences preferences;
  final AppPrivacy privacy;
  final DeviceInfos? device;
  final int syncCursor;

  UserSessionData({required this.profile, required this.preferences, required this.privacy, this.device, required this.syncCursor});

  factory UserSessionData.fromJson(Map<String, dynamic> json) => UserSessionData(
    profile: Map<String, dynamic>.from(json['profile'] ?? {}),
    preferences: AppPreferences.fromJson(json['preferences'] ?? {}),
    privacy: AppPrivacy.fromJson(json['privacy'] ?? {}),
    device: json['device'] != null ? DeviceInfos.fromJson(json['device']) : null,
    syncCursor: json['sync_cursor'] ?? 0,
  );

  Map<String, dynamic> toJson() => {'profile': profile, 'preferences': preferences.toJson(), 'privacy': privacy.toJson(), 'device': device?.toJson(), 'sync_cursor': syncCursor};
}
