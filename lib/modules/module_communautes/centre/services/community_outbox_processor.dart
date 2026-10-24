import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:video_compress/video_compress.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/local_storage/structured/app_cache_database.dart';
import '../../../module_authentification/centre/services/auth_service.dart';
import '../../externe/repositories/community_repository.dart';
import '../../interne/controllers/community/community_feed_controller.dart';
import '../../../module_principale/interne/controllers/home_feed_controller.dart';
import '../../../../app/repository_global/r2_media_repository.dart';
import '../../../../shared/constants/post_media_limits.dart';
import '../persistence/community_local_dao.dart';

class CommunityOutboxProcessor extends GetxService {
  final CommunityRepository _repository = CommunityRepository();
  final AuthService _authService = Get.find<AuthService>();
  late final CommunityLocalDao _dao = CommunityLocalDao(Get.find<AppDatabase>());

  final RxBool isProcessing = false.obs;
  bool _isProcessingPosts = false;
  static const int _maxPostAttempts = 5;
  Timer? _pollingTimer;

  @override
  void onInit() {
    super.onInit();
    debugPrint('[CREATE_COMMUNITY] [Outbox] CommunityOutboxProcessor onInit triggered');
    _pollingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      debugPrint('[CREATE_COMMUNITY] [Outbox] Timer tick triggered processPendingOperations & processPendingPosts');
      processPendingOperations();
      processPendingPosts();
    });
    unawaited(processPendingOperations());
    unawaited(processPendingPosts());
  }

  @override
  void onClose() {
    _pollingTimer?.cancel();
    super.onClose();
  }

  Future<void> processPendingOperations() async {
    final currentUserId = _authService.userId;
    debugPrint('[CREATE_COMMUNITY] [Outbox] processPendingOperations started. currentUserId=$currentUserId, isProcessing=${isProcessing.value}');
    if (currentUserId == null || isProcessing.value) {
      debugPrint('[CREATE_COMMUNITY] [Outbox] Skipped processing: userId=$currentUserId, isProcessing=${isProcessing.value}');
      return;
    }

    isProcessing.value = true;
    try {
      final pendingList = await _dao.getPendingOutboxOperations(currentUserId);
      debugPrint('[CREATE_COMMUNITY] [Outbox] Found ${pendingList.length} pending operations for userId=$currentUserId');
      for (final item in pendingList) {
        final id = (item['id'] as num).toInt();
        final operationId = item['operation_id'].toString();
        final userId = item['user_id'].toString();
        final communityId = item['community_id']?.toString() ?? '';
        final operationType = item['operation_type'].toString();
        final attempts = (item['attempt_count'] as num).toInt();
        final payload = Map<String, dynamic>.from(jsonDecode(item['payload'].toString()));
        final createdAtStr = item['created_at']?.toString();

        debugPrint('[CREATE_COMMUNITY] [Outbox] Inspecting item id=$id, operationId=$operationId, type=$operationType, communityId=$communityId, attempts=$attempts');

        if (userId != currentUserId) {
          debugPrint('[CREATE_COMMUNITY] [Outbox] Skipping item: userId $userId != currentUserId $currentUserId');
          continue;
        }

        // 2-Minute Pending Creation Expiration check in Outbox handler
        if (operationType == 'create_community' && createdAtStr != null) {
          final createdAtTime = DateTime.tryParse(createdAtStr) ?? DateTime.fromMillisecondsSinceEpoch(0);
          final age = DateTime.now().difference(createdAtTime);
          debugPrint('[CREATE_COMMUNITY] [Outbox] Item $operationId age: ${age.inSeconds}s');
          if (age.inMinutes >= 2) {
            debugPrint('[CREATE_COMMUNITY] [Outbox] Outbox operation $operationId refused: pending creation expired (>2m)');
            await _dao.markOutboxOperationFailed(id: id, lastError: 'Pending creation expired (>2m)');
            if (communityId.isNotEmpty) {
              await _dao.deleteCommunity(communityId);
            }
            Get.snackbar(
              'error'.tr,
              'community_creation_expired_msg'.tr,
              snackPosition: SnackPosition.BOTTOM,
            );
            continue;
          }
        }

        try {
          debugPrint('[CREATE_COMMUNITY] [Outbox] Executing operationId=$operationId type=$operationType communityId=$communityId');

          if (operationType == 'create_community') {
            final name = payload['name']?.toString() ?? '';
            final slug = payload['slug']?.toString() ?? '';
            final description = payload['description']?.toString() ?? '';
            final visibility = payload['visibility']?.toString() ?? 'public';
            final requireManualApproval = payload['require_manual_approval'] == true || visibility == 'prive';

            // Créer d’abord la communauté : l’Edge Function R2 vérifie que
            // l’entité existe et que l’utilisateur en est propriétaire.
            await _repository.createCommunityRpc(
              p_id: communityId,
              p_name: name,
              p_slug: slug,
              p_description: description,
              p_visibility: visibility,
              p_require_manual_approval: requireManualApproval,
            );

            final r2 = R2MediaRepository();
            final avatarLocalPath = payload['avatar_local_path']?.toString() ??
                payload['avatar_url']?.toString() ?? payload['photo_profile']?.toString();
            final bannerLocalPath = payload['banner_local_path']?.toString() ??
                payload['banner_url']?.toString() ?? payload['photo_cover']?.toString();
            String? photoProfile;
            String? photoCover;

            if (avatarLocalPath != null && avatarLocalPath.isNotEmpty) {
              if (avatarLocalPath.startsWith('http://') || avatarLocalPath.startsWith('https://')) {
                photoProfile = avatarLocalPath;
              } else {
                final file = File(avatarLocalPath);
                if (!await file.exists()) {
                  throw FileSystemException('Le fichier de photo de profil de la communauté est introuvable.', avatarLocalPath);
                }
                final uploaded = await r2.uploadFile(
                  file: file,
                  category: 'community_avatar',
                  mediaType: 'image',
                  entityId: communityId,
                );
                photoProfile = uploaded.publicUrl;
                if (photoProfile == null || photoProfile.isEmpty || !uploaded.isPublic) {
                  throw StateError('R2 n’a pas retourné d’URL publique pour la photo de la communauté.');
                }
                debugPrint('[CREATE_COMMUNITY] R2 avatar uploaded key=${uploaded.objectKey}');
              }
            }

            if (bannerLocalPath != null && bannerLocalPath.isNotEmpty) {
              if (bannerLocalPath.startsWith('http://') || bannerLocalPath.startsWith('https://')) {
                photoCover = bannerLocalPath;
              } else {
                final file = File(bannerLocalPath);
                if (!await file.exists()) {
                  throw FileSystemException('Le fichier de couverture de la communauté est introuvable.', bannerLocalPath);
                }
                final uploaded = await r2.uploadFile(
                  file: file,
                  category: 'community_cover',
                  mediaType: 'image',
                  entityId: communityId,
                );
                photoCover = uploaded.publicUrl;
                if (photoCover == null || photoCover.isEmpty || !uploaded.isPublic) {
                  throw StateError('R2 n’a pas retourné d’URL publique pour la couverture de la communauté.');
                }
                debugPrint('[CREATE_COMMUNITY] R2 cover uploaded key=${uploaded.objectKey}');
              }
            }

            if (photoProfile != null || photoCover != null) {
              await _repository.updateCommunityInfo(
                p_id: communityId,
                p_name: name,
                p_description: description,
                p_photo_profile: photoProfile,
                p_photo_cover: photoCover,
              );
            }
          }

          debugPrint('[CREATE_COMMUNITY] [Outbox] Operation $operationId completed successfully. Marking confirmed.');
          await _dao.updateCommunityStatus(communityId, 'confirmed');
          await _dao.markOutboxOperationCompleted(id);
        } catch (e, stackTrace) {
          final errStr = e.toString();
          debugPrint('[CREATE_COMMUNITY] [Outbox] Operation $operationId failed with error: $errStr');
          debugPrint('[CREATE_COMMUNITY] [Outbox] StackTrace: $stackTrace');

          if (_isTerminalError(e)) {
            debugPrint('[CREATE_COMMUNITY] [Outbox] Terminal error detected for operation $operationId. Marking failed.');
            await _dao.markOutboxOperationFailed(id: id, lastError: errStr);
            await _dao.updateCommunityStatus(communityId, 'error');
          } else {
            final nextAttempt = attempts + 1;
            final retryDelay = _calculateBackoffDelay(nextAttempt);
            final nextRetryAt = DateTime.now().add(retryDelay).millisecondsSinceEpoch;
            debugPrint('[CREATE_COMMUNITY] [Outbox] Transient error for operation $operationId. Scheduling retry attempt $nextAttempt at $nextRetryAt');

            await _dao.markOutboxOperationRetry(
              id: id,
              attemptCount: nextAttempt,
              nextRetryAt: nextRetryAt,
              lastError: errStr,
            );
          }
        }
      }
    } catch (e, st) {
      debugPrint('[CREATE_COMMUNITY] [Outbox] Unexpected error in processPendingOperations: $e\n$st');
    } finally {
      isProcessing.value = false;
      debugPrint('[CREATE_COMMUNITY] [Outbox] processPendingOperations finished.');
    }
  }

  Future<void> _persistUploadedMedia(
    dynamic db,
    int rowId,
    Map<String, dynamic> payload,
    List<Map<String, dynamic>> uploadedMedia,
    String operationId,
    String postKind,
  ) async {
    payload['p_uploaded_media'] = List<Map<String, dynamic>>.from(uploadedMedia);
    await db.update(
      'post_outbox',
      {'payload': jsonEncode(payload), 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [rowId],
    );
    debugPrint('[POST_CREATE][$postKind] MEDIA_PROGRESS_SAVED operationId=$operationId uploaded=${uploadedMedia.length}');
  }
  bool _isDefinitiveUploadError(dynamic error) {
    final str = error.toString().toLowerCase();
    return str.contains('413') ||
        str.contains('payload too large') ||
        str.contains('invalid') ||
        str.contains('unsupported') ||
        str.contains('bad request') ||
        str.contains('400');
  }

  bool _isTerminalError(dynamic error) {
    final str = error.toString().toLowerCase();
    return _isDefinitiveUploadError(error) ||
        str.contains('permission denied') ||
        str.contains('not found') ||
        str.contains('already used') ||
        str.contains('exists') ||
        str.contains('23505') ||
        str.contains('409') ||
        str.contains('422');
  }

  Duration _calculateBackoffDelay(int attempt) {
    switch (attempt) {
      case 1:
        return const Duration(seconds: 5);
      case 2:
        return const Duration(seconds: 15);
      case 3:
        return const Duration(seconds: 30);
      default:
        return const Duration(minutes: 1);
    }
  }

  void _refreshVisibleFeed(String communityId) {
    try {
      if (communityId.isNotEmpty) {
        if (Get.isRegistered<CommunityFeedController>(tag: communityId)) {
          unawaited(Get.find<CommunityFeedController>(tag: communityId).fetchCommunityFeed(isRefresh: true));
        }
      } else if (Get.isRegistered<HomeFeedController>()) {
        unawaited(Get.find<HomeFeedController>().fetchFeed(refresh: true));
      }
    } catch (e) {
      debugPrint('[POST_CREATE] FEED_REFRESH_AFTER_OUTBOX_FAILED communityId=$communityId error=$e');
    }
  }

  Future<void> processPendingPosts() async {
    final currentUserId = _authService.userId;
    debugPrint('[POST_CREATE] PROCESS_START userId=$currentUserId alreadyProcessing=$_isProcessingPosts');
    if (currentUserId == null || _isProcessingPosts) {
      debugPrint('[POST_CREATE] PROCESS_SKIPPED userId=$currentUserId alreadyProcessing=$_isProcessingPosts');
      return;
    }
    _isProcessingPosts = true;

    try {
      final db = await Get.find<AppDatabase>().database;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final pendingList = await db.query(
        'post_outbox',
        where: 'user_id = ? AND status = "pending" AND next_retry_at <= ?',
        whereArgs: [currentUserId, nowMs],
        orderBy: 'created_at ASC',
      );

      debugPrint('[POST_CREATE] OUTBOX_SCAN userId=$currentUserId pendingCount=${pendingList.length} nowMs=$nowMs');
      for (final item in pendingList) {
        final id = (item['id'] as num).toInt();
        final operationId = item['operation_id'].toString();
        final communityId = item['community_id']?.toString();
        final attempts = (item['attempt_count'] as num).toInt();
        final payload = Map<String, dynamic>.from(jsonDecode(item['payload'].toString()));

        final postKind = communityId == null || communityId.isEmpty ? 'feed' : 'community';
        final rawLocalMediaForGuard = payload['p_local_media'];
        final localMediaCountForGuard = rawLocalMediaForGuard is List ? rawLocalMediaForGuard.length : 0;
        final cachedMediaForGuard = payload['p_uploaded_media'];
        final cachedMediaCountForGuard = cachedMediaForGuard is List
            ? cachedMediaForGuard.where((media) => media is Map && media['url'] != null).length
            : 0;
        final payloadVersion = payload['p_outbox_version'];
        // Legacy rows can contain stale media selections from earlier composer attempts.
        // Never upload them automatically unless every media item already has a cached upload.
        if (payloadVersion != 2 && cachedMediaCountForGuard != localMediaCountForGuard) {
          debugPrint('[POST_CREATE][$postKind] LEGACY_OUTBOX_QUARANTINED operationId=$operationId localMediaCount=$localMediaCountForGuard cachedMediaCount=$cachedMediaCountForGuard reason=unversioned_payload_would_upload_media');
          await db.update(
            'post_outbox',
            {
              'status': 'failed',
              'next_retry_at': 0,
              'updated_at': DateTime.now().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [id],
          );
          continue;
        }
        if (localMediaCountForGuard > maxPostMedia) {
          debugPrint('[POST_CREATE][$postKind] INVALID_OUTBOX_QUARANTINED operationId=$operationId mediaCount=$localMediaCountForGuard limit=$maxPostMedia');
          await db.update(
            'post_outbox',
            {
              'status': 'failed',
              'next_retry_at': 0,
              'updated_at': DateTime.now().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [id],
          );
          continue;
        }
        debugPrint('[POST_CREATE][$postKind] OUTBOX_ITEM_START operationId=$operationId communityId=$communityId attempts=$attempts payloadKeys=${payload.keys.toList()}');

        try {
          final rawLocalMedia = List<dynamic>.from(payload['p_local_media'] ?? []);
          final localMediaItems = rawLocalMedia.map((item) => item is Map ? Map<String, dynamic>.from(item) : <String, dynamic>{'path': item.toString(), 'type': 'photo'}).toList();
          List<Map<String, dynamic>> uploadedMedia = [];
          final cachedUploadedMedia = payload['p_uploaded_media'];
          final cachedMediaList = cachedUploadedMedia is List ? cachedUploadedMedia : <dynamic>[];
          final reusableCount = cachedMediaList.length <= localMediaItems.length ? cachedMediaList.length : 0;
          if (reusableCount > 0) {
            uploadedMedia = cachedMediaList.take(reusableCount).where((media) => media is Map && media['url'] != null).map((media) => Map<String, dynamic>.from(media as Map)).toList();
            debugPrint('[POST_CREATE][$postKind] MEDIA_REUSE operationId=$operationId count=${uploadedMedia.length}/${localMediaItems.length} reason=previous_upload_progress');
          }

          final supabaseClient = Supabase.instance.client;
          final r2MediaRepository = R2MediaRepository(client: supabaseClient);
          if (uploadedMedia.length < localMediaItems.length) {
          debugPrint('[POST_CREATE][$postKind] MEDIA_PREPARE_START operationId=$operationId count=${localMediaItems.length} types=${localMediaItems.map((m) => m['type'] ?? 'photo').toList()}');
          for (int i = uploadedMedia.length; i < localMediaItems.length; i++) {
            final mediaStartedAt = DateTime.now();
            var localPath = (localMediaItems[i]['upload_path'] ?? localMediaItems[i]['path']).toString();
            final originalPath = localMediaItems[i]['path'].toString();
            final mediaType = (localMediaItems[i]['type'] ?? 'photo').toString();
            debugPrint('[POST_CREATE][$postKind] MEDIA_START operationId=$operationId index=${i + 1}/${localMediaItems.length} type=$mediaType remote=${localPath.startsWith('http://') || localPath.startsWith('https://')} exists=${localPath.startsWith('http') ? 'n/a' : File(localPath).existsSync()}');
            if (mediaType == 'video' &&
                !localPath.startsWith('http://') &&
                !localPath.startsWith('https://') &&
                localMediaItems[i]['upload_path'] == null) {
              final originalFile = File(originalPath);
              if (!await originalFile.exists()) {
                throw FileSystemException('La vidéo sélectionnée n’existe plus sur le stockage local.', originalPath);
              }
              final originalBytes = await originalFile.length();
              final appDir = await getApplicationDocumentsDirectory();
              final postId = (payload['p_id'] ?? operationId).toString();
              final originalExtension = p.extension(originalPath).toLowerCase();
              final safeExtension = RegExp(r'^\.(mp4|mov|m4v|3gp|mkv|webm)$').hasMatch(originalExtension)
                  ? originalExtension
                  : '.mp4';
              final safeSourcePath = p.join(appDir.path, 'posts', postId, 'source_video_$i$safeExtension');
              await Directory(p.dirname(safeSourcePath)).create(recursive: true);

              // Trimmers can return paths containing ':' and ',' in their
              // filenames. Copy to a stable internal path before native
              // transcoding; Android's URI data source can misread such paths.
              var uploadVideoPath = safeSourcePath;
              final safeSource = File(safeSourcePath);
              if (p.normalize(originalPath) != p.normalize(safeSourcePath) ||
                  !await safeSource.exists() ||
                  await safeSource.length() != originalBytes) {
                await originalFile.copy(safeSourcePath);
              }
              if (!await safeSource.exists() || await safeSource.length() != originalBytes) {
                throw StateError('Impossible de préparer la vidéo dans le stockage interne.');
              }
              debugPrint('[POST_CREATE][$postKind] VIDEO_COMPRESS_START operationId=$operationId index=${i + 1} originalBytes=$originalBytes safeSourcePath=$safeSourcePath');
              final compressionStartedAt = DateTime.now();
              try {
                final compressedInfo = await VideoCompress.compressVideo(
                  safeSourcePath,
                  quality: VideoQuality.MediumQuality,
                  deleteOrigin: false,
                  includeAudio: true,
                ).timeout(const Duration(minutes: 5), onTimeout: () {
                  throw TimeoutException('La compression vidéo a dépassé 5 minutes.');
                });
                final compressedFile = compressedInfo?.file;
                if (compressedFile != null &&
                    await compressedFile.exists() &&
                    await compressedFile.length() > 0) {
                  final compressedBytes = await compressedFile.length();
                  uploadVideoPath = compressedFile.path;
                  localMediaItems[i]['upload_path'] = uploadVideoPath;
                  localMediaItems[i]['original_size_bytes'] = originalBytes;
                  localMediaItems[i]['upload_size_bytes'] = compressedBytes;
                  debugPrint('[POST_CREATE][$postKind] VIDEO_COMPRESS_SUCCESS operationId=$operationId index=${i + 1} originalBytes=$originalBytes compressedBytes=$compressedBytes elapsedMs=${DateTime.now().difference(compressionStartedAt).inMilliseconds}');
                } else {
                  // Compression is an optimization, not a publication
                  // prerequisite. Keep publishing with the internal original.
                  debugPrint('[POST_CREATE][$postKind] VIDEO_COMPRESS_FALLBACK_ORIGINAL operationId=$operationId index=${i + 1} reason=no_valid_compressed_file');
                }
              } catch (compressionError) {
                debugPrint('[POST_CREATE][$postKind] VIDEO_COMPRESS_FALLBACK_ORIGINAL operationId=$operationId index=${i + 1} error=$compressionError');
              }
              if (localMediaItems[i]['upload_path'] == null) {
                localMediaItems[i]['upload_path'] = safeSourcePath;
                localMediaItems[i]['original_size_bytes'] = originalBytes;
                localMediaItems[i]['upload_size_bytes'] = originalBytes;
              }
              payload['p_local_media'] = localMediaItems;
              await db.update(
                'post_outbox',
                {'payload': jsonEncode(payload), 'updated_at': DateTime.now().toIso8601String()},
                where: 'id = ?',
                whereArgs: [id],
              );
              localPath = uploadVideoPath == safeSourcePath
                  ? safeSourcePath
                  : uploadVideoPath;
            }
            if (mediaType == 'photo' &&
                !localPath.startsWith('http://') &&
                !localPath.startsWith('https://') &&
                localMediaItems[i]['upload_path'] == null) {
              final originalFile = File(originalPath);
              if (!await originalFile.exists()) {
                throw FileSystemException('La photo sélectionnée n’existe plus sur le stockage local.', originalPath);
              }
              final originalBytes = await originalFile.length();
              final appDir = await getApplicationDocumentsDirectory();
              final postId = (payload['p_id'] ?? operationId).toString();
              final compressedPath = p.join(appDir.path, 'posts', postId, 'upload_photo_$i.jpg');
              await Directory(p.dirname(compressedPath)).create(recursive: true);
              debugPrint('[POST_CREATE][$postKind] IMAGE_COMPRESS_START operationId=$operationId index=${i + 1} originalBytes=$originalBytes');
              final compressionStartedAt = DateTime.now();
              final compressed = await FlutterImageCompress.compressAndGetFile(
                originalFile.absolute.path,
                compressedPath,
                minWidth: 1280,
                minHeight: 1280,
                quality: 80,
                format: CompressFormat.jpeg,
              ).timeout(const Duration(minutes: 2), onTimeout: () {
                throw TimeoutException('La compression photo a dépassé 2 minutes.');
              });
              if (compressed == null || !await File(compressed.path).exists()) {
                throw StateError('La compression photo n’a pas produit de fichier exploitable.');
              }
              final compressedBytes = await File(compressed.path).length();
              if (compressedBytes <= 0) throw StateError('La photo compressée est vide.');
              localMediaItems[i]['upload_path'] = compressed.path;
              localMediaItems[i]['original_size_bytes'] = originalBytes;
              localMediaItems[i]['upload_size_bytes'] = compressedBytes;
              payload['p_local_media'] = localMediaItems;
              await db.update(
                'post_outbox',
                {'payload': jsonEncode(payload), 'updated_at': DateTime.now().toIso8601String()},
                where: 'id = ?',
                whereArgs: [id],
              );
              localPath = compressed.path;
              debugPrint('[POST_CREATE][$postKind] IMAGE_COMPRESS_SUCCESS operationId=$operationId index=${i + 1} originalBytes=$originalBytes compressedBytes=$compressedBytes elapsedMs=${DateTime.now().difference(compressionStartedAt).inMilliseconds}');
            }
            if (localPath.startsWith('http://') || localPath.startsWith('https://')) {
              if (mediaType == 'video') {
                throw Exception('Une vidéo locale ne peut pas être une URL distante non vérifiée.');
              }
              uploadedMedia.add({'type': 'photo', 'storage': 'supabase', 'url': localPath}); // legacy queued remote URL; new local uploads always go to R2
              await _persistUploadedMedia(db, id, payload, uploadedMedia, operationId, postKind);
            } else {
              final file = File(localPath);
              if (file.existsSync()) {
                if (mediaType == 'video') {
                  final videoDurationMs = (await VideoCompress.getMediaInfo(localPath))?.duration ?? 0;
                  debugPrint('[POST_CREATE][$postKind] VIDEO_DURATION_CHECK operationId=$operationId index=${i + 1} durationMs=${videoDurationMs.round()} durationSeconds=${(videoDurationMs / 1000).toStringAsFixed(3)}');
                  if (videoDurationMs > const Duration(seconds: 30).inMilliseconds) {
                    throw StateError('Cette vidéo dépasse 30 secondes. Sélectionne-la à nouveau et découpe-la à 29 secondes maximum avant de publier.');
                  }
                  final uploaded = await r2MediaRepository.uploadFile(
                    file: file, category: 'post_media', mediaType: 'video',
                    communityId: communityId,
                    videoDuration: Duration(milliseconds: videoDurationMs.round()),
                  );
                  final videoMedia = <String, dynamic>{
                    'type': 'video', 'storage': 'r2',
                    'url': uploaded.publicUrl ?? uploaded.objectKey,
                    'object_key': uploaded.objectKey, 'is_public': uploaded.isPublic,
                    'mime_type': uploaded.contentType, 'size_bytes': uploaded.sizeBytes,
                    'duration_seconds': videoDurationMs / 1000,
                  };
                  // Persister la clé vidéo tout de suite : si la génération ou
                  // l'upload de la miniature échoue, la compensation pourra la supprimer.
                  uploadedMedia.add(videoMedia);
                  await _persistUploadedMedia(db, id, payload, uploadedMedia, operationId, postKind);

                  // Génère une image fixe depuis la vidéo compressée pour le fil.
                  final appDir = await getApplicationDocumentsDirectory();
                  final postId = (payload['p_id'] ?? operationId).toString();
                  final thumbnailPath = p.join(appDir.path, 'posts', postId, 'thumbnail_$i.jpg');
                  await Directory(p.dirname(thumbnailPath)).create(recursive: true);
                  File? generatedThumbnail;
                  for (final framePosition in <int>[1000, 0]) {
                    try {
                      final candidate = await VideoCompress.getFileThumbnail(
                        localPath,
                        quality: 78,
                        position: framePosition,
                      ).timeout(const Duration(seconds: 30));
                      if (await candidate.exists() && await candidate.length() > 0) {
                        generatedThumbnail = candidate;
                        break;
                      }
                    } catch (thumbnailError) {
                      debugPrint('[POST_CREATE][$postKind] THUMBNAIL_FRAME_FAILED operationId=$operationId index=$i position=$framePosition error=$thumbnailError');
                    }
                  }
                  if (generatedThumbnail == null) {
                    throw StateError('Impossible de générer la miniature de la vidéo.');
                  }
                  final thumbnailFile = await generatedThumbnail.copy(thumbnailPath);
                  if (!await thumbnailFile.exists() || await thumbnailFile.length() == 0) {
                    throw StateError('La miniature vidéo générée est vide.');
                  }
                  final uploadedThumbnail = await r2MediaRepository.uploadFile(
                    file: thumbnailFile,
                    category: 'post_media',
                    mediaType: 'image',
                    communityId: communityId,
                    mediaRole: 'video_thumbnail',
                  );
                  final thumbnailUrl = uploadedThumbnail.publicUrl ?? uploadedThumbnail.objectKey;
                  if (thumbnailUrl.trim().isEmpty) {
                    throw StateError('R2 n’a retourné ni URL ni clé pour la miniature vidéo.');
                  }
                  debugPrint('[POST_CREATE][$postKind] THUMBNAIL_UPLOAD_SUCCESS operationId=$operationId index=$i key=${uploadedThumbnail.objectKey} public=${uploadedThumbnail.isPublic} urlAvailable=${uploadedThumbnail.publicUrl != null} bytes=${uploadedThumbnail.sizeBytes}');
                  videoMedia['thumbnail_url'] = thumbnailUrl;
                  videoMedia['thumbnail_storage'] = 'r2';
                  videoMedia['thumbnail_object_key'] = uploadedThumbnail.objectKey;
                  await _persistUploadedMedia(db, id, payload, uploadedMedia, operationId, postKind);
                  debugPrint('[POST_CREATE][$postKind] MEDIA_SUCCESS operationId=$operationId index=${i + 1}/${localMediaItems.length} type=video key=${uploaded.objectKey} elapsedMs=${DateTime.now().difference(mediaStartedAt).inMilliseconds}');
                } else {
                  final uploaded = await r2MediaRepository.uploadFile(
                    file: file, category: 'post_media', mediaType: 'photo', communityId: communityId,
                  );
                  uploadedMedia.add({
                    'type': 'photo', 'storage': 'r2',
                    'url': uploaded.publicUrl ?? uploaded.objectKey,
                    'object_key': uploaded.objectKey, 'is_public': uploaded.isPublic,
                    'mime_type': uploaded.contentType, 'size_bytes': uploaded.sizeBytes,
                  });
                  debugPrint('[POST_CREATE][$postKind] MEDIA_SUCCESS operationId=$operationId index=${i + 1}/${localMediaItems.length} type=photo key=${uploaded.objectKey} elapsedMs=${DateTime.now().difference(mediaStartedAt).inMilliseconds}');
                  await _persistUploadedMedia(db, id, payload, uploadedMedia, operationId, postKind);
                }
              } else {
                throw FileSystemException('Le média sélectionné n’existe plus sur le stockage local.', localPath);
              }
            }
          }
          // Reprise idempotente : si l'application s'est arrêtée après l'upload
          // de la vidéo mais avant celui de sa miniature, compléter le média mis en cache.
          for (int mediaIndex = 0; mediaIndex < uploadedMedia.length && mediaIndex < localMediaItems.length; mediaIndex++) {
            final media = uploadedMedia[mediaIndex];
            if (media['type']?.toString() != 'video' ||
                (media['thumbnail_url']?.toString().trim().isNotEmpty ?? false)) {
              continue;
            }
            var sourcePath = (localMediaItems[mediaIndex]['upload_path'] ??
                localMediaItems[mediaIndex]['path'] ?? '').toString();
            if (sourcePath.startsWith('http://') || sourcePath.startsWith('https://') ||
                !await File(sourcePath).exists()) {
              sourcePath = (localMediaItems[mediaIndex]['path'] ?? '').toString();
            }
            if (sourcePath.isEmpty || !await File(sourcePath).exists()) {
              throw FileSystemException('Vidéo locale indisponible pour régénérer sa miniature.', sourcePath);
            }
            final appDir = await getApplicationDocumentsDirectory();
            final postId = (payload['p_id'] ?? operationId).toString();
            final thumbnailPath = p.join(appDir.path, 'posts', postId, 'thumbnail_$mediaIndex.jpg');
            await Directory(p.dirname(thumbnailPath)).create(recursive: true);
            File? generatedThumbnail;
            for (final framePosition in <int>[1000, 0]) {
              try {
                final candidate = await VideoCompress.getFileThumbnail(
                  sourcePath, quality: 78, position: framePosition,
                ).timeout(const Duration(seconds: 30));
                if (await candidate.exists() && await candidate.length() > 0) {
                  generatedThumbnail = candidate;
                  break;
                }
              } catch (error) {
                debugPrint('[POST_CREATE][$postKind] THUMBNAIL_RECOVERY_FAILED operationId=$operationId index=$mediaIndex position=$framePosition error=$error');
              }
            }
            if (generatedThumbnail == null) {
              throw StateError('Impossible de régénérer la miniature de la vidéo.');
            }
            final file = await generatedThumbnail.copy(thumbnailPath);
            if (!await file.exists() || await file.length() == 0) {
              throw StateError('La miniature vidéo régénérée est vide.');
            }
            final uploadedThumbnail = await r2MediaRepository.uploadFile(
              file: file, category: 'post_media', mediaType: 'image',
              communityId: communityId, mediaRole: 'video_thumbnail',
            );
            final thumbnailUrl = uploadedThumbnail.publicUrl ?? uploadedThumbnail.objectKey;
            if (thumbnailUrl.trim().isEmpty) {
              throw StateError('R2 n’a retourné ni URL ni clé pour la miniature vidéo.');
            }
            debugPrint('[POST_CREATE][$postKind] THUMBNAIL_RECOVERY_UPLOAD_SUCCESS operationId=$operationId index=$mediaIndex key=${uploadedThumbnail.objectKey} public=${uploadedThumbnail.isPublic} urlAvailable=${uploadedThumbnail.publicUrl != null} bytes=${uploadedThumbnail.sizeBytes}');
            media['thumbnail_url'] = thumbnailUrl;
            media['thumbnail_storage'] = 'r2';
            media['thumbnail_object_key'] = uploadedThumbnail.objectKey;
            await _persistUploadedMedia(db, id, payload, uploadedMedia, operationId, postKind);
          }
          if (uploadedMedia.length != localMediaItems.length) {
            throw StateError('Téléversement incomplet : ${uploadedMedia.length}/${localMediaItems.length} médias ont été préparés.');
          }
          debugPrint('[POST_CREATE][$postKind] MEDIA_CACHE_READY operationId=$operationId count=${uploadedMedia.length}');
          }

          final pId = payload['p_id']?.toString() ?? operationId;
          final content = payload['p_content']?.toString() ?? '';
          final audience = payload['p_audience']?.toString() ?? 'public';
          final hashtags = List<String>.from(payload['p_hashtags'] ?? []);
          final mentions = List<String>.from(payload['p_mentions'] ?? []);
          final commentsEnabled = payload['p_comments_enabled'] == true;
          final sharingEnabled = payload['p_sharing_enabled'] == true;
          final reactionsEnabled = payload['p_reactions_enabled'] == true;
          final poll = payload['p_poll'] is Map ? Map<String, dynamic>.from(payload['p_poll']) : null;
          final allowPromotion = payload['p_allow_promotion'] ?? true;

          debugPrint('[POST_CREATE][$postKind] RPC_START operationId=$operationId postId=$pId communityId=$communityId audience=$audience contentLength=${content.length} mediaCount=${uploadedMedia.length} hashtagCount=${hashtags.length} mentionCount=${mentions.length} pollPresent=${poll != null}');
          final rpcStartedAt = DateTime.now();

          await _repository.createPostRpc(
            p_id: pId,
            p_content: content,
            p_community_id: communityId,
            p_audience: audience,
            p_media: uploadedMedia,
            p_hashtags: hashtags,
            p_mentions: mentions,
            p_comments_enabled: commentsEnabled,
            p_sharing_enabled: sharingEnabled,
            p_reactions_enabled: reactionsEnabled,
            p_poll: poll,
            p_allow_promotion: allowPromotion,
          );

          debugPrint('[POST_CREATE][$postKind] RPC_SUCCESS operationId=$operationId postId=$pId elapsedMs=${DateTime.now().difference(rpcStartedAt).inMilliseconds}');
          debugPrint('[POST_CREATE][$postKind] OUTBOX_COMPLETE operationId=$operationId postId=$pId');
          await db.delete('post_outbox', where: 'id = ?', whereArgs: [id]);
          _refreshVisibleFeed(communityId ?? '');
        } catch (e, st) {
          final errStr = e.toString();
          debugPrint('[POST_CREATE][$postKind] CANCELLED operationId=$operationId communityId=$communityId attempt=${attempts + 1} error=$errStr\\n$st');

          // A failed attempt is final: never put this post back into the retry queue.
          // Clean any R2 objects uploaded before this attempt failed.
          final cachedUploaded = payload['p_uploaded_media'];
          final objectKeys = <String>[];
          if (cachedUploaded is List) {
            for (final media in cachedUploaded) {
              if (media is Map && media['storage']?.toString().toLowerCase() == 'r2') {
                final key = media['object_key']?.toString().trim() ?? '';
                if (key.isNotEmpty) objectKeys.add(key);
                final thumbnailKey = media['thumbnail_object_key']?.toString().trim() ?? '';
                if (thumbnailKey.isNotEmpty) objectKeys.add(thumbnailKey);
              }
            }
          }
          try {
            await R2MediaRepository(client: Supabase.instance.client).deleteFailedPostMedia(
              objectKeys: objectKeys,
              communityId: communityId,
            );
          } catch (cleanupError, cleanupStack) {
            debugPrint('[POST_CREATE][$postKind] MEDIA_CLEANUP_FAILED operationId=$operationId keys=${objectKeys.length} error=$cleanupError\\n$cleanupStack');
          }

          // Remove the local queued post and permanently stop retries.
          await db.delete('post_outbox', where: 'id = ?', whereArgs: [id]);
          debugPrint('[POST_CREATE][$postKind] OUTBOX_CANCELLED_AND_REMOVED operationId=$operationId');
          _refreshVisibleFeed(communityId ?? '');
          try {
            Get.snackbar(
              'error'.tr,
              'La publication a échoué et a été annulée.',
              snackPosition: SnackPosition.BOTTOM,
            );
          } catch (_) {}
        }
      }
    } catch (e, st) {
      debugPrint('[POST_CREATE] PROCESS_FATAL error=$e\n$st');
    } finally {
      _isProcessingPosts = false;
      debugPrint('[POST_CREATE] PROCESS_FINISHED userId=$currentUserId');
    }
  }
}
