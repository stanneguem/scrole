import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../service_global/supabse_service.dart';
import 'r2_media_repository.dart';

class StorageRepository {
  final SupabaseClient _client = Get.find<SupabaseService>().client;
  final R2MediaRepository _r2MediaRepository = R2MediaRepository();

  /// Upload un fichier vers un bucket Supabase
  Future<String> uploadFile({
    required String bucket,
    required String path,
    required File file,
  }) async {
    try {
      await _client.storage.from(bucket).upload(
        path,
        file,
        fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
      );

      final String publicUrl = _client.storage.from(bucket).getPublicUrl(path);
      return publicUrl;
    } catch (e) {
      throw Exception('Erreur lors de l\'upload: $e');
    }
  }

  /// Supprime des fichiers du storage
  Future<void> deleteFiles(String bucket, List<String> paths) async {
    if (paths.isEmpty) return;
    try {
      await _client.storage.from(bucket).remove(paths);
    } catch (e) {
      debugPrint('[Warning] Erreur lors de la suppression des anciens fichiers: $e');
    }
  }

  /// Supprime un fichier à partir de son URL publique.
  /// Utilisé pour compenser un upload déjà réussi lorsqu'une étape suivante échoue.
  Future<void> deletePublicFile({
    required String bucket,
    required String publicUrl,
  }) async {
    try {
      final marker = '/storage/v1/object/public/$bucket/';
      final markerIndex = publicUrl.indexOf(marker);

      if (markerIndex == -1) {
        debugPrint('[Warning] URL Storage invalide, suppression ignorée: $publicUrl');
        return;
      }

      final path = publicUrl.substring(markerIndex + marker.length);
      if (path.isEmpty) return;

      await deleteFiles(bucket, [path]);
    } catch (e) {
      debugPrint('[Warning] Erreur compensation Storage: $e');
    }
  }

  /// Nettoie un dossier en ne gardant que les fichiers qui ne commencent pas par un préfixe 
  /// ou en supprimant les anciens fichiers selon un pattern.
  Future<void> _cleanOldFiles({
    required String bucket,
    required String directoryPath,
    required String prefix,
    required String currentFileName,
  }) async {
    try {
      final List<FileObject> files = await _client.storage.from(bucket).list(path: directoryPath);
      
      final List<String> toDelete = files
          .where((f) => f.name.startsWith(prefix) && f.name != currentFileName)
          .map((f) => '$directoryPath/${f.name}')
          .toList();

      if (toDelete.isNotEmpty) {
        await deleteFiles(bucket, toDelete);
        debugPrint('[Storage] Nettoyage : ${toDelete.length} fichier(s) supprimé(s) dans $directoryPath');
      }
    } catch (e) {
      debugPrint('[Warning] Erreur nettoyage storage: $e');
    }
  }

  /// Upload une photo de profil utilisateur
  /// Structure : profiles/{userId}/avatar_{timestamp}.jpg
  Future<void> deleteProfileAvatar(String publicUrl) =>
      _r2MediaRepository.deleteProfileAvatar(publicUrl);

  Future<String> uploadProfilePicture(String userId, File file) async {
    final traceId = DateTime.now().millisecondsSinceEpoch.toString();
    debugPrint('[STORAGE_AVATAR][$traceId] START userId=$userId path=${file.path}');
    final currentUser = _client.auth.currentUser;
    debugPrint('[STORAGE_AVATAR][$traceId] authUserId=${currentUser?.id ?? 'null'} sessionPresent=${_client.auth.currentSession != null}');
    if (currentUser == null || currentUser.id != userId) {
      debugPrint('[STORAGE_AVATAR][$traceId] DENIED: session absente ou userId différent');
      throw Exception('Vous ne pouvez téléverser que votre propre photo de profil.');
    }
    final sizeBytes = await file.length();
    debugPrint('[STORAGE_AVATAR][$traceId] fileSizeBytes=$sizeBytes extension=${file.path.split('.').last}');
    try {
      debugPrint('[STORAGE_AVATAR][$traceId] STEP: R2MediaRepository.uploadFile category=profile_avatar');
      final uploaded = await _r2MediaRepository.uploadFile(
        file: file,
        category: 'profile_avatar',
        mediaType: 'image',
        entityId: userId,
      );
      final url = uploaded.publicUrl;
      if (url == null || url.isEmpty || !uploaded.isPublic) {
        throw StateError('Cloudflare R2 n’a pas retourné une URL publique pour la photo de profil.');
      }
      debugPrint('[STORAGE_AVATAR][$traceId] SUCCESS objectKey=${uploaded.objectKey} bytes=${uploaded.sizeBytes} contentType=${uploaded.contentType}');
      return url;
    } catch (e, stack) {
      debugPrint('[STORAGE_AVATAR][$traceId] FAILURE type=${e.runtimeType} error=$e');
      debugPrint('[STORAGE_AVATAR][$traceId] STACK_TRACE\n$stack');
      rethrow;
    }
  }

  /// Upload une photo de couverture utilisateur vers Cloudflare R2.
  Future<String> uploadProfileCover(String userId, File file) async {
    final currentUser = _client.auth.currentUser;
    if (currentUser == null || currentUser.id != userId) {
      throw Exception('Vous ne pouvez téléverser que votre propre couverture de profil.');
    }
    final uploaded = await _r2MediaRepository.uploadFile(
      file: file,
      category: 'profile_cover',
      mediaType: 'image',
      entityId: userId,
    );
    final url = uploaded.publicUrl;
    if (url == null || url.isEmpty || !uploaded.isPublic) {
      throw StateError('Cloudflare R2 n’a pas retourné une URL publique pour la couverture du profil.');
    }
    return url;
  }

  /// Upload une photo de profil de communauté vers Cloudflare R2.
  Future<String> uploadCommunityAvatar(File file, {required String communityId}) async {
    final uploaded = await _r2MediaRepository.uploadFile(
      file: file,
      category: 'community_avatar',
      mediaType: 'image',
      entityId: communityId,
    );
    final url = uploaded.publicUrl;
    if (url == null || url.isEmpty || !uploaded.isPublic) {
      throw StateError('Cloudflare R2 n’a pas retourné une URL publique pour l’avatar de communauté.');
    }
    return url;
  }

  /// Upload une couverture de communauté vers Cloudflare R2.
  Future<String> uploadCommunityBanner(File file, {required String communityId}) async {
    final uploaded = await _r2MediaRepository.uploadFile(
      file: file,
      category: 'community_cover',
      mediaType: 'image',
      entityId: communityId,
    );
    final url = uploaded.publicUrl;
    if (url == null || url.isEmpty || !uploaded.isPublic) {
      throw StateError('Cloudflare R2 n’a pas retourné une URL publique pour la couverture de communauté.');
    }
    return url;
  }

  /// Upload un média de publication de communauté (ne nettoie pas les autres fichiers du dossier).
  /// Structure : communities/{communityId}/posts/post_{timestamp}_{random}.jpg
  Future<String> uploadCommunityPostMedia(File file, {required String communityId}) async {
    final extension = file.path.split('.').last.toLowerCase();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomSuffix = DateTime.now().microsecond;
    final fileName = 'post_${timestamp}_$randomSuffix.$extension';
    final dirPath = 'communities/$communityId/posts';
    final path = '$dirPath/$fileName';
    
    final url = await uploadFile(bucket: 'community-media', path: path, file: file);
    return url;
  }

  /// Upload une capture d'écran pour un rapport de bug
  /// Structure : bug_reports/{userId}/{timestamp}.jpg
  Future<String> uploadBugReportScreenshot(String userId, File file) async {
    final extension = file.path.split('.').last;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = '$timestamp.$extension';
    final path = 'bug_reports/$userId/$fileName';
    
    return await uploadFile(bucket: 'bug-reports', path: path, file: file);
  }

  /// Upload un fichier vidéo de publication vers le bucket community-videos
  Future<String> uploadCommunityPostVideo(File file, {required String communityId, required String userId}) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = '$timestamp.mp4';
    final path = '$userId/$communityId/$fileName';
    return await uploadFile(bucket: 'community-videos', path: path, file: file);
  }
}
