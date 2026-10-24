import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:scrole/app/repository_global/storage_repository.dart';
import 'package:scrole/app/service_global/media_service.dart';
import 'package:scrole/app/service_global/centre_interrets_service.dart';
import 'package:scrole/shared/models/interest_model.dart';
import 'package:scrole/app_controller.dart';
import 'package:scrole/modules/module_principale/centre/models/community_post.dart';
import 'package:scrole/modules/module_principale/interne/enums/community_role_enum.dart';
import 'package:scrole/shared/models/post_media.dart';
import '../../../module_discussion_direct/externe/repositories/social_repository.dart';

class ProfileController extends GetxController {
  late final AppController _appController;
  late final MediaService _mediaService;
  late final StorageRepository _storageRepository;
  late final InterestService _interestService;

  // ============================================
  // USER DATA (dérivées du profil d'AppController)
  // ============================================

  final RxString userId = ''.obs;
  final RxString username = ''.obs;
  final RxString nom = ''.obs;
  final RxString prenom = ''.obs;
  final RxString fullName = ''.obs;
  final RxString email = ''.obs;
  final RxString avatarUrl = ''.obs;
  final RxString coverUrl = ''.obs;
  final RxString bio = ''.obs;
  final RxString country = ''.obs;
  final RxString city = ''.obs;
  final RxString gender = ''.obs;
  final RxInt ageValue = 0.obs;
  final Rx<DateTime?> birthDate = Rxn<DateTime>();
  final Rx<DateTime?> usernameUpdatedAt = Rxn<DateTime>();
  final Rx<DateTime?> genderUpdatedAt = Rxn<DateTime>();
  final Rx<DateTime?> locationUpdatedAt = Rxn<DateTime>();
  final Rx<DateTime?> birthDateUpdatedAt = Rxn<DateTime>();
  final RxString accountStatus = ''.obs;
  final RxString createdAt = ''.obs;
  final RxString lastSignInAt = ''.obs;
  final RxBool isVerified = false.obs;
  final RxString certificationLevel = 'none'.obs;
  final RxBool isLoading = false.obs;
  final RxInt followersCount = 0.obs;
  final RxInt followingCount = 0.obs;
  final RxInt friendsCount = 0.obs;
  final RxInt postsCount = 0.obs;
  final RxInt totalLikesReceived = 0.obs;
  final RxInt totalDislikesReceived = 0.obs;
  final RxInt eventsAttendedCount = 0.obs;
  final RxInt eventsOrganizedCount = 0.obs;
  final RxInt interactionsCount = 0.obs;
  final RxDouble reputation = 0.0.obs;

  final RxList<Interest> userInterests = <Interest>[].obs;

  // ============================================
  // TABS & POSTS / EVENTS
  // ============================================

  final RxInt selectedTab = 0.obs;
  final RxList<CommunityPost> userPosts = <CommunityPost>[].obs;
  final RxList<dynamic> userEvents = <dynamic>[].obs;
  final RxList<CommunityPost> savedPosts = <CommunityPost>[].obs;
  final RxSet<int> loadingProfileTabs = <int>{}.obs;
  final RxSet<int> loadedProfileTabs = <int>{}.obs;
  final RxMap<int, String> profileTabErrors = <int, String>{}.obs;

  // ============================================
  // COVER & PROFILE IMAGE
  // ============================================

  final RxString coverImageUrl = ''.obs;
  final RxString profileImageUrl = ''.obs;
  final RxBool isUploadingCover = false.obs;
  final RxBool isUploadingProfileImage = false.obs;

  Worker? _profileWorker;
  RealtimeChannel? _relationshipChannel;

  @override
  void onInit() {
    super.onInit();
    _appController = Get.find<AppController>();
    _mediaService = Get.find<MediaService>();
    _interestService = Get.find<InterestService>();
    _storageRepository = StorageRepository();
    
    unawaited(_applyProfileOrDefaults(_appController.profile.value));
    _profileWorker = ever(_appController.profile, (data) {
      unawaited(_applyProfileOrDefaults(data));
      unawaited(_loadFollowStats());
      unawaited(_loadProfileTab(selectedTab.value, forceRefresh: true));
    });
    unawaited(_loadFollowStats());
    _subscribeToRelationshipChanges();

    unawaited(_loadProfileTab(0));

  }


  Future<void> selectProfileTab(int index) async {
    selectedTab.value = index;
    await _loadProfileTab(index);
  }

  Future<void> _loadProfileTab(int index, {bool forceRefresh = false}) async {
    final uid = userId.value;
    if (uid.isEmpty || loadingProfileTabs.contains(index)) return;
    if (!forceRefresh && loadedProfileTabs.contains(index)) return;

    loadingProfileTabs.add(index);
    profileTabErrors.remove(index);
    try {
      final tab = switch (index) {
        0 => 'posts',
        1 => 'events',
        2 => 'liked',
        _ => throw ArgumentError.value(index, 'index', 'Onglet de profil invalide'),
      };
      final response = await Supabase.instance.client.rpc(
        'get_external_profile_tab',
        params: {
          'p_user_id': uid,
          'p_tab': tab,
          'p_limit': 24,
          'p_offset': 0,
        },
      );
      final rows = response is List
          ? response.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList()
          : <Map<String, dynamic>>[];

      if (index == 0) {
        // Sur le profil personnel, afficher toutes les publications de l'utilisateur,
        // y compris celles publiées dans ses communautés.
        userPosts.assignAll(rows.map(CommunityPost.fromMap));
      } else if (index == 2) {
        savedPosts.assignAll(rows.map(CommunityPost.fromMap));
      } else {
        userEvents.assignAll(rows);
      }
      loadedProfileTabs.add(index);
    } catch (e, stack) {
      debugPrint('[ProfileController] _loadProfileTab($index) failed: $e\\n$stack');
      profileTabErrors[index] = 'Impossible de charger ce contenu. Réessaie.';
    } finally {
      loadingProfileTabs.remove(index);
    }
  }

  Future<void> refreshProfileTab(int index) => _loadProfileTab(index, forceRefresh: true);

  void _subscribeToRelationshipChanges() {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) return;
    try {
      _relationshipChannel = Supabase.instance.client
          .channel('user:$uid', opts: const RealtimeChannelConfig(private: true))
          .onBroadcast(
            event: 'relationship_changed',
            callback: (payload) {
              debugPrint('[FOLLOW] relationship_changed self stats payload=$payload');
              unawaited(_loadFollowStats());
            },
          )
          ..subscribe();
    } catch (e, stack) {
      debugPrint('[FOLLOW] self relationship_changed subscription exception=$e\\n$stack');
    }
  }

  Future<void> _loadFollowStats() async {
    if (userId.value.isEmpty) return;
    try {
      final stats = await SocialRepository().getFollowStats();
      followersCount.value = (stats['followers_count'] as num?)?.toInt() ?? 0;
      followingCount.value = (stats['following_count'] as num?)?.toInt() ?? 0;
      friendsCount.value = (stats['friends_count'] as num?)?.toInt() ?? 0;
    } catch (e, stack) {
      debugPrint('[FOLLOW] get_follow_stats self exception=$e\\n$stack');
    }
  }

  Future<void> _applyProfileOrDefaults(Map<String, dynamic>? data) async {
    if (data == null) {
      _setDefaultValues();
      return;
    }
    await _updateUserData(data);
  }

  /// Met à jour les données utilisateur.
  /// Gère à la fois un payload plat (ancien format) et le nouveau
  /// payload backend imbriqué `{ privacy: {...}, profile: {...} }`.
  Future<void> _updateUserData(Map<String, dynamic> data) async {
    certificationLevel.value = 'none';
    isVerified.value = false;
    try {
      final Map<String, dynamic> profileData =
      (data['profile'] is Map) ? Map<String, dynamic>.from(data['profile'] as Map) : data;

      userId.value = profileData['user_id']?.toString() ?? profileData['id']?.toString() ?? '';
      username.value = profileData['username']?.toString() ?? '';
      nom.value = profileData['last_name']?.toString() ?? profileData['nom']?.toString() ?? '';
      prenom.value = profileData['first_name']?.toString() ?? profileData['prenom']?.toString() ?? '';

      fullName.value = '${prenom.value} ${nom.value}'.trim();

      email.value = profileData['email']?.toString() ?? '';
      avatarUrl.value = profileData['photo_url']?.toString() ?? '';
      coverUrl.value = profileData['cover_url']?.toString() ?? '';
      bio.value = profileData['bio']?.toString() ?? '';

      // Gestion intelligente et stable des noms de pays/villes
      final nextCountry = _extractName(profileData['countries'] ?? profileData['pays']);
      if (nextCountry != null) {
        country.value = nextCountry;
      } else if (profileData['country_id'] != null && 
                 !country.value.contains('-') && 
                 country.value.isNotEmpty) {
        // On a déjà un nom en clair et on reçoit un ID (probablement via Realtime brute)
        // On ne fait rien pour éviter d'écraser le nom par l'ID technique.
      } else {
        country.value = profileData['country_id']?.toString() ?? '';
      }

      final nextCity = _extractName(profileData['cities'] ?? profileData['ville']);
      if (nextCity != null) {
        city.value = nextCity;
      } else if (profileData['city_id'] != null && 
                 !city.value.contains('-') && 
                 city.value.isNotEmpty) {
        // Idem pour la ville
      } else {
        city.value = profileData['city_id']?.toString() ?? '';
      }

      gender.value = profileData['gender']?.toString() ?? profileData['genre']?.toString() ?? '';
      
      accountStatus.value = profileData['account_status']?.toString() ?? 'active';

      // Date de création du compte : priorité absolue au 'created_at' de Supabase Auth (auth.users)
      final authCreatedAt = _appController.authUser.value?.createdAt;
      createdAt.value = authCreatedAt ?? 
          profileData['account_created_at']?.toString() ??
          profileData['created_at']?.toString() ??
          '';

      lastSignInAt.value = profileData['last_sign_in_at']?.toString() ?? '';

      coverImageUrl.value = profileData['cover_url']?.toString() ?? '';
      profileImageUrl.value = profileData['photo_url']?.toString() ?? '';

      if (profileData['age'] != null) {
        ageValue.value = int.tryParse(profileData['age'].toString()) ?? 0;
      }

      if (profileData['birth_date'] != null || profileData['date_de_naissance'] != null) {
        try {
          final birthStr = (profileData['birth_date'] ?? profileData['date_de_naissance']).toString();
          birthDate.value = DateTime.parse(birthStr);
        } catch (e) {
          debugPrint('Erreur parse date naissance: $e');
        }
      }

      // Mappage des dates de verrouillage
      usernameUpdatedAt.value = _parseDate(profileData['username_updated_at']);
      genderUpdatedAt.value = _parseDate(profileData['gender_updated_at']);
      locationUpdatedAt.value = _parseDate(profileData['location_updated_at']);
      birthDateUpdatedAt.value = _parseDate(profileData['birth_date_updated_at']);

      var activeCertificationLevel = 'none';
      var activeSubscriptionLevel = 'none';
      final now = DateTime.now().toUtc();

      if (profileData['account_status'] == 'active' && userId.value.isNotEmpty) {
        try {
          final client = Supabase.instance.client;
          final certifications = await client
              .from('user_certifications')
              .select('issued_at, expires_at, certification_type_id')
              .eq('user_id', userId.value)
              .eq('status', 'active');

          final activeTypeIds = <String>{};
          for (final raw in certifications as List) {
            final row = Map<String, dynamic>.from(raw as Map);
            final issuedAt = DateTime.tryParse((row['issued_at'] ?? '').toString())?.toUtc();
            final expiresAt = DateTime.tryParse((row['expires_at'] ?? '').toString())?.toUtc();
            final isCurrent = issuedAt != null &&
                !issuedAt.isAfter(now) &&
                (expiresAt == null || !expiresAt.isBefore(now));
            final typeId = row['certification_type_id']?.toString();
            if (isCurrent && typeId != null && typeId.isNotEmpty) {
              activeTypeIds.add(typeId);
            }
          }

          if (activeTypeIds.isNotEmpty) {
            final types = await client
                .from('certification_type')
                .select('id, code')
                .inFilter('id', activeTypeIds.toList());
            for (final raw in types as List) {
              final row = Map<String, dynamic>.from(raw as Map);
              final code = (row['code'] ?? '').toString().toLowerCase();
              if (code == 'premium' ||
                  (code == 'pro' && activeCertificationLevel != 'premium') ||
                  (code == 'basique' && activeCertificationLevel == 'none')) {
                activeCertificationLevel = code;
              }
            }
          }

          final subscriptions = await client
              .from('scrole_subscriptions')
              .select('plan_code, starts_at, ends_at')
              .eq('user_id', userId.value)
              .eq('status', 'active');

          for (final raw in subscriptions as List) {
            final row = Map<String, dynamic>.from(raw as Map);
            final startsAt = DateTime.tryParse((row['starts_at'] ?? '').toString())?.toUtc();
            final endsAt = DateTime.tryParse((row['ends_at'] ?? '').toString())?.toUtc();
            if ((startsAt != null && startsAt.isAfter(now)) ||
                (endsAt != null && endsAt.isBefore(now))) {
              continue;
            }
            final code = (row['plan_code'] ?? '').toString().toLowerCase();
            if (code == 'premium') {
              activeSubscriptionLevel = 'premium';
              break;
            }
            if (code == 'pro') activeSubscriptionLevel = 'pro';
          }
        } catch (e) {
          debugPrint('[ProfileController] certification level lookup failed: $e');
        }
      }

      final legacyVerified = profileData['is_verified'] == true;
      final isActiveAccount = profileData['account_status'] == 'active';
      if (activeSubscriptionLevel == 'premium' ||
          activeCertificationLevel == 'premium') {
        certificationLevel.value = 'premium';
      } else if (activeSubscriptionLevel == 'pro' ||
          activeCertificationLevel == 'pro') {
        certificationLevel.value = 'pro';
      } else if (activeCertificationLevel == 'basique' || legacyVerified) {
        certificationLevel.value = 'basique';
      } else {
        certificationLevel.value = 'none';
      }
      isVerified.value = isActiveAccount && certificationLevel.value != 'none';
      if (!isActiveAccount) certificationLevel.value = 'none';
      
      if (userId.value.isNotEmpty) {
        _loadUserInterests();
        unawaited(_loadEngagementStats());
      }
    } catch (e) {
      debugPrint('Erreur mise à jour données: $e');
    }
  }

  Future<void> _loadEngagementStats() async {
    final uid = userId.value;
    if (uid.isEmpty) return;
    try {
      final raw = await Supabase.instance.client.rpc(
        'get_profile_engagement_stats',
        params: {'p_user_id': uid},
      );
      if (raw is! Map) return;
      final stats = Map<String, dynamic>.from(raw);
      postsCount.value = (stats['posts_count'] as num?)?.toInt() ?? 0;
      totalLikesReceived.value = (stats['total_likes_received'] as num?)?.toInt() ?? 0;
      totalDislikesReceived.value = (stats['total_dislikes_received'] as num?)?.toInt() ?? 0;
      eventsAttendedCount.value = (stats['events_attended_count'] as num?)?.toInt() ?? 0;
      eventsOrganizedCount.value = (stats['events_organized_count'] as num?)?.toInt() ?? 0;
      interactionsCount.value = (stats['interactions_count'] as num?)?.toInt() ?? 0;
      try {
        final reputationRaw = await Supabase.instance.client.rpc(
          'get_user_reputation',
          params: {'p_user_id': uid, 'p_community_id': null},
        );
        if (reputationRaw is Map) {
          final reputationData = Map<String, dynamic>.from(reputationRaw);
          reputation.value = ((reputationData['score'] as num?)?.toDouble() ?? 0.0)
              .clamp(0.0, 5.0).toDouble();
        }
      } catch (e) {
        // Compatibility fallback until the reputation V2 migration is deployed.
        reputation.value = ((stats['reputation'] as num?)?.toDouble() ?? reputation.value)
            .clamp(0.0, 5.0).toDouble();
        debugPrint('[ProfileController] V2 reputation unavailable; legacy fallback used: $e');
      }
    } catch (e, stack) {
      debugPrint('[ProfileController] get_profile_engagement_stats failed: $e\\n$stack');
    }
  }

  DateTime? _parseDate(dynamic data) {
    if (data == null) return null;
    try {
      return DateTime.parse(data.toString());
    } catch (_) {
      return null;
    }
  }

  String? _extractName(dynamic data) {
    if (data == null) return null;
    if (data is String) return data;
    if (data is Map) return data['nom']?.toString() ?? data['name']?.toString();
    return null;
  }

  void _setDefaultValues() {
    username.value = 'profile_default_username'.tr;
    nom.value = '';
    prenom.value = '';
    fullName.value = '';
    bio.value = '';
    avatarUrl.value = '';
    coverUrl.value = '';
    profileImageUrl.value = '';
    coverImageUrl.value = '';
    country.value = '';
    city.value = '';
    gender.value = '';
    email.value = '';
    createdAt.value = '';
    lastSignInAt.value = '';
    ageValue.value = 0;
    isVerified.value = false;
    certificationLevel.value = 'none';
    accountStatus.value = 'active';
  }

  // ============================================
  // REFRESH
  // ============================================

  Future<void> refreshProfile() async {
    isLoading.value = true;
    await Future.wait([
      _appController.forceRefresh(),
      _loadUserInterests(),
      _loadFollowStats(),
      _loadEngagementStats(),
      _loadProfileTab(selectedTab.value, forceRefresh: true),
    ]);
    if (Get.isRegistered<ProfileController>()) {
      isLoading.value = false;
    }
  }

  Future<void> _loadUserInterests() async {
    if (userId.value.isEmpty) return;
    try {
      final allInterests = await _interestService.getInterests();
      final userIntIds = await _interestService.getUserInterestIds(userId.value);
      
      userInterests.assignAll(
        allInterests.where((i) => userIntIds.contains(i.id)).toList(),
      );
    } catch (e) {
      debugPrint('Erreur chargement intérêts: $e');
    }
  }

  // ============================================
  // UPDATE PROFILE
  // ============================================

  Future<bool> updateProfile(Map<String, dynamic> data, {bool showLoading = true, bool showFeedback = true}) async {
    if (showLoading) isLoading.value = true;
    try {
      final updated = await _appController.updateProfile(data);

      if (updated != null) {
        if (showFeedback) {
          Get.snackbar(
            'profile_success_title'.tr,
            'profile_success_update'.tr,
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.green,
            colorText: Colors.white,
          );
        }
        return true;
      }

      if (showFeedback) {
        Get.snackbar(
          'profile_error_title'.tr,
          'profile_error_update'.tr,
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
      return false;
    } finally {
      if (showLoading && Get.isRegistered<ProfileController>()) {
        isLoading.value = false;
      }
    }
  }

  // ============================================
  // COVER IMAGE
  // ============================================

  Future<void> pickCoverImage(ImageSource source) async {
    String? uploadedCoverUrl;
    bool profileCoverSaved = false;
    try {
      final File? picked = await _mediaService.pickCoverImage(source: source);
      if (picked == null) return;

      isUploadingCover.value = true;
      final previousCoverUrl = coverUrl.value.trim().isNotEmpty
          ? coverUrl.value.trim()
          : coverImageUrl.value.trim();
      final String uploadedUrl = await _storageRepository.uploadProfileCover(userId.value, picked);
      uploadedCoverUrl = uploadedUrl;

      final saved = await updateProfile(
        {'cover_url': uploadedUrl},
        showLoading: false,
        showFeedback: false,
      );
      if (!saved) throw StateError('Upload réussi mais enregistrement cover_url échoué.');
      profileCoverSaved = true;
      if (previousCoverUrl.isNotEmpty && previousCoverUrl != uploadedUrl) {
        try {
          await _storageRepository.deleteProfileAvatar(previousCoverUrl);
        } catch (deleteError) {
          debugPrint('[PROFILE_COVER] Ancienne couverture R2 conservée après échec de nettoyage: $deleteError');
        }
      }
    } catch (e) {
      if (uploadedCoverUrl != null && !profileCoverSaved) {
        try { await _storageRepository.deleteProfileAvatar(uploadedCoverUrl); } catch (cleanupError) {
          debugPrint('[PROFILE_COVER] Orphan R2 upload cleanup deferred: $cleanupError');
        }
      }
      Get.snackbar(
        'profile_error_title'.tr,
        'profile_error_cover'.tr,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: const Color(0xFF1E1E22),
        colorText: Colors.white,
      );
    } finally {
      isUploadingCover.value = false;
    }
  }

  // ============================================
  // PROFILE IMAGE
  // ============================================

  Future<void> pickProfileImage(ImageSource source) async {
    final traceId = DateTime.now().millisecondsSinceEpoch.toString();
    String? uploadedAvatarUrl;
    bool profileAvatarSaved = false;
    debugPrint('[PROFILE_AVATAR][$traceId] START source=$source userId=${userId.value}');
    try {
      debugPrint('[PROFILE_AVATAR][$traceId] STEP 1: sélection, recadrage et compression');
      final File? picked = await _mediaService.pickProfileImage(source: source);
      if (picked == null) {
        debugPrint('[PROFILE_AVATAR][$traceId] STOP: sélection annulée ou aucune image');
        return;
      }
      debugPrint('[PROFILE_AVATAR][$traceId] STEP 2: fichier prêt path=${picked.path}');
      try {
        debugPrint('[PROFILE_AVATAR][$traceId] fileSizeBytes=${await picked.length()}');
      } catch (e) {
        debugPrint('[PROFILE_AVATAR][$traceId] WARNING lecture taille: $e');
      }

      isUploadingProfileImage.value = true;
      final previousAvatarUrl = avatarUrl.value.trim().isNotEmpty
          ? avatarUrl.value.trim()
          : profileImageUrl.value.trim();
      debugPrint('[PROFILE_AVATAR][$traceId] STEP 3: upload via StorageRepository');
      final String uploadedUrl = await _storageRepository.uploadProfilePicture(userId.value, picked);
      uploadedAvatarUrl = uploadedUrl;
      debugPrint('[PROFILE_AVATAR][$traceId] STEP 4: upload terminé url=$uploadedUrl');

      debugPrint('[PROFILE_AVATAR][$traceId] STEP 5: sauvegarde photo_url');
      final saved = await updateProfile(
        {'photo_url': uploadedUrl},
        showLoading: false,
        showFeedback: false,
      );
      debugPrint('[PROFILE_AVATAR][$traceId] STEP 6: sauvegarde result=$saved');
      if (!saved) throw StateError('Upload réussi mais enregistrement photo_url échoué.');
      profileAvatarSaved = true;
      if (previousAvatarUrl.isNotEmpty && previousAvatarUrl != uploadedUrl) {
        try {
          await _storageRepository.deleteProfileAvatar(previousAvatarUrl);
          debugPrint('[PROFILE_AVATAR][$traceId] OLD_AVATAR_DELETED');
        } catch (deleteError) {
          debugPrint('[PROFILE_AVATAR][$traceId] OLD_AVATAR_DELETE_WARNING error=$deleteError');
        }
      }
      debugPrint('[PROFILE_AVATAR][$traceId] SUCCESS');
    } catch (e, stack) {
      if (uploadedAvatarUrl != null && !profileAvatarSaved) {
        try { await _storageRepository.deleteProfileAvatar(uploadedAvatarUrl); } catch (cleanupError) {
          debugPrint('[PROFILE_AVATAR][$traceId] ORPHAN_UPLOAD_CLEANUP_WARNING error=$cleanupError');
        }
      }
      debugPrint('[PROFILE_AVATAR][$traceId] FAILURE type=${e.runtimeType} error=$e');
      debugPrint('[PROFILE_AVATAR][$traceId] STACK_TRACE\n$stack');
      Get.snackbar(
        'profile_error_title'.tr,
        'profile_error_avatar'.tr,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: const Color(0xFF1E1E22),
        colorText: Colors.white,
      );
    } finally {
      isUploadingProfileImage.value = false;
      debugPrint('[PROFILE_AVATAR][$traceId] FINALLY upload flag reset');
    }
  }

  // ============================================
  // GETTERS D'AFFICHAGE
  // ============================================

  String get displayName => fullName.value.isEmpty ? username.value : fullName.value;

  String get initials {
    if (displayName.isEmpty) return '?';
    final parts = displayName.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return displayName.substring(0, 1).toUpperCase();
  }

  /// Âge calculé à partir de la date de naissance (repli si le
  /// backend ne fournit pas directement `age`).
  String get age {
    if (birthDate.value == null) return '';
    final years = DateTime.now().difference(birthDate.value!).inDays ~/ 365;
    return years.toString();
  }

  /// Âge à afficher : priorité au champ `age` du backend.
  String get displayAge {
    if (ageValue.value > 0) return ageValue.value.toString();
    if (birthDate.value != null) return age;
    return '';
  }

  String get displayBio => bio.value.isEmpty ? 'profile_bio_empty'.tr : bio.value;

  String get displayCountry => country.value.isEmpty ? 'profile_not_specified'.tr : country.value;

  String get displayCity => city.value.isEmpty ? 'profile_not_specified'.tr : city.value;

  String get displayEmail => email.value.isEmpty ? 'profile_not_specified'.tr : email.value;

  String get displayGender {
    switch (gender.value.toLowerCase()) {
      case 'male':
      case 'homme':
        return 'profile_gender_male'.tr;
      case 'female':
      case 'femme':
        return 'profile_gender_female'.tr;
      case '':
        return 'profile_not_specified'.tr;
      default:
        return 'profile_gender_other'.tr;
    }
  }

  String _formatDate(String raw) {
    if (raw.isEmpty) return '';
    try {
      final date = DateTime.parse(raw).toLocal();
      return '${date.day.toString().padLeft(2, '0')}/'
          '${date.month.toString().padLeft(2, '0')}/'
          '${date.year}';
    } catch (_) {
      return '';
    }
  }

  String get formattedMemberSince {
    final formatted = _formatDate(createdAt.value);
    return formatted.isEmpty ? 'profile_not_specified'.tr : formatted;
  }

  String get formattedLastSignIn {
    final formatted = _formatDate(lastSignInAt.value);
    return formatted.isEmpty ? 'profile_not_specified'.tr : formatted;
  }

  @override
  void onClose() {
    _profileWorker?.dispose();
    final channel = _relationshipChannel;
    if (channel != null) {
      unawaited(Supabase.instance.client.removeChannel(channel));
    }
    super.onClose();
  }
}
