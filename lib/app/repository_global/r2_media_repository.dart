import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

class R2UploadedMedia {
  const R2UploadedMedia({
    required this.objectKey,
    required this.publicUrl,
    required this.isPublic,
    required this.contentType,
    required this.sizeBytes,
  });

  final String objectKey;
  final String? publicUrl;
  final bool isPublic;
  final String contentType;
  final int sizeBytes;
}

/// Obtient une URL présignée via Supabase Edge Function puis envoie les octets
/// directement vers R2. Aucune clé R2 n'est embarquée dans l'application.
class R2MediaRepository {
  R2MediaRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const Map<String, String> _imageTypes = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'avif': 'image/avif',
    'gif': 'image/gif',
  };

  static const Map<String, String> _audioTypes = {
    'm4a': 'audio/mp4',
    'aac': 'audio/aac',
    'mp3': 'audio/mpeg',
    'ogg': 'audio/ogg',
    'wav': 'audio/wav',
    'webm': 'audio/webm',
  };

  static const Map<String, String> _videoTypes = {
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
  };

  /// Supprime uniquement un ancien objet public R2 appartenant au profil
  /// ou à la communauté après confirmation que la nouvelle URL est enregistrée.
  /// Les URL historiques Supabase Storage sont volontairement ignorées.
  Future<void> deleteReplacedPublicMedia(String previousUrl) async {
    final uri = Uri.tryParse(previousUrl.trim());
    if (uri == null || !uri.hasAuthority || !["http", "https"].contains(uri.scheme)) return;
    final pathSegments = uri.pathSegments.map(Uri.decodeComponent).toList();
    final rootIndex = pathSegments.indexWhere((part) => part == "profiles" || part == "communities");
    if (rootIndex < 0) return;
    final segments = pathSegments.sublist(rootIndex);
    final key = segments.join("/");
    final userId = _client.auth.currentUser?.id;
    final isOwnedProfileMedia = segments.length == 4 &&
        segments[0] == "profiles" &&
        segments[1] == userId &&
        ["avatar", "cover"].contains(segments[2]);
    final isCommunityMedia = segments.length == 4 &&
        segments[0] == "communities" &&
        ["avatar", "cover"].contains(segments[2]) &&
        segments[1].isNotEmpty;
    final isEventMedia = segments.length == 4 &&
        segments[0] == "events" &&
        segments[1].isNotEmpty &&
        segments[2] == userId;
    if (!isOwnedProfileMedia && !isCommunityMedia && !isEventMedia) {
      // Old Supabase Storage URLs and unrelated URLs are not R2 object keys.
      return;
    }
    final response = await _client.functions.invoke("r2-media-upload", body: {
      "action": "delete-owned-media",
      "object_key": key,
    });
    if (response.status < 200 || response.status >= 300 ||
        response.data is! Map || (response.data as Map)["deleted"] != true) {
      throw StateError("La suppression de l’ancien média R2 a échoué: ${response.data}");
    }
  }

  /// Compatibilité avec les appels existants : cette méthode ne supprime
  /// plus les URL Supabase historiques et accepte également les avatars R2.
  Future<void> deleteProfileAvatar(String publicUrl) =>
      deleteReplacedPublicMedia(publicUrl);

  /// Deletes uploaded R2 objects when post creation is cancelled.
  /// The Edge Function validates ownership and keeps any object already referenced by a post.
  Future<void> deleteFailedPostMedia({
    required List<String> objectKeys,
    String? communityId,
  }) async {
    final keys = objectKeys.map((key) => key.trim()).where((key) => key.isNotEmpty).toSet().toList();
    if (keys.isEmpty) return;
    final response = await _client.functions.invoke(
      'r2-media-upload',
      body: <String, dynamic>{
        'action': 'delete-failed-post-media',
        'object_keys': keys,
        if (communityId != null && communityId.isNotEmpty) 'community_id': communityId,
      },
    );
    if (response.status < 200 || response.status >= 300 ||
        response.data is! Map || (response.data as Map)['success'] != true) {
      throw StateError('Failed to clean up post media: ${response.data}');
    }
    debugPrint('[R2_UPLOAD] FAILED_POST_MEDIA_CLEANUP deleted=${(response.data as Map)['deleted_count']}');
  }

  Future<R2UploadedMedia> uploadFile({
    required File file,
    required String category,
    required String mediaType,
    String? entityId,
    String? communityId,
    Duration? videoDuration,
    String? mediaRole,
  }) async {
    final traceId = DateTime.now().millisecondsSinceEpoch.toString();
    debugPrint('[R2_UPLOAD][$traceId] START category=$category mediaType=$mediaType entityId=$entityId communityId=$communityId');
    final authUser = _client.auth.currentUser;
    debugPrint('[R2_UPLOAD][$traceId] authUserId=${authUser?.id ?? 'null'} sessionPresent=${_client.auth.currentSession != null}');
    if (authUser == null) {
      debugPrint('[R2_UPLOAD][$traceId] ABORT: utilisateur non connecté');
      throw const AuthException('Vous devez être connecté pour envoyer un média.');
    }

    final extension = p.extension(file.path).replaceFirst('.', '').toLowerCase();
    final isVideo = mediaType == 'video';
    final isAudio = mediaType == 'audio';
    final contentType = (isVideo ? _videoTypes : isAudio ? _audioTypes : _imageTypes)[extension];
    if (contentType == null) {
      debugPrint('[R2_UPLOAD][$traceId] ABORT: extension non prise en charge .$extension');
      throw ArgumentError('Format de média non pris en charge : .$extension');
    }

    final bytes = await file.readAsBytes();
    debugPrint('[R2_UPLOAD][$traceId] fileRead bytes=${bytes.length} extension=$extension contentType=$contentType');
    if (bytes.isEmpty) {
      debugPrint('[R2_UPLOAD][$traceId] ABORT: fichier vide');
      throw StateError('Le fichier sélectionné est vide.');
    }

    debugPrint('[R2_UPLOAD][$traceId] STEP 1: appel Edge Function r2-media-upload');
    final response = await _client.functions
        .invoke(
          'r2-media-upload',
          body: <String, dynamic>{
            'action': 'create-upload-url',
            'category': category,
            'media_type': mediaType,
            if (mediaRole != null) 'media_role': mediaRole,
            'content_type': contentType,
            'extension': extension,
            'size_bytes': bytes.length,
            if (entityId != null) 'entity_id': entityId,
            if (communityId != null) 'community_id': communityId,
            if (videoDuration != null)
              'duration_seconds': videoDuration.inMilliseconds / 1000,
          },
        )
        .timeout(const Duration(seconds: 30), onTimeout: () {
          throw TimeoutException('Délai dépassé lors de la préparation de l’envoi R2.');
        });

    debugPrint('[R2_UPLOAD][$traceId] Edge Function status=${response.status} dataType=${response.data.runtimeType}');
    if (response.status < 200 || response.status >= 300 || response.data is! Map) {
      final details = response.data is Map
          ? (response.data as Map)['error']?.toString()
          : null;
      debugPrint('[R2_UPLOAD][$traceId] EDGE_FUNCTION_FAILURE status=${response.status} details=${details ?? response.data}');
      throw StateError('Autorisation R2 refusée${details == null ? '' : ' : $details'}');
    }

    final data = Map<String, dynamic>.from(response.data as Map);
    debugPrint('[R2_UPLOAD][$traceId] Edge response fields=${data.keys.toList()} objectKey=${data['object_key']} expiresIn=${data['expires_in']}');
    final uploadUrl = data['upload_url'] as String?;
    final objectKey = data['object_key'] as String?;
    final publicUrl = data['public_url'] as String?;
    final isPublic = data['is_public'] == true;
    final privateKeyPrefixes = ['private/', 'stories/', 'messages/', 'salon-messages/', 'bug-reports/', 'comments/'];
    if (uploadUrl == null || objectKey == null || (isPublic && publicUrl == null) ||
        (!isPublic && !privateKeyPrefixes.any((prefix) => objectKey.startsWith(prefix)))) {
      debugPrint('[R2_UPLOAD][$traceId] ABORT: réponse incomplète uploadUrl=${uploadUrl != null} objectKey=${objectKey != null} publicUrl=${publicUrl != null} isPublic=$isPublic');
      throw StateError('Réponse R2 incomplète ou incohérente : URL ou clé manquante.');
    }

    // Ne jamais journaliser uploadUrl : cette URL contient une signature temporaire.
    final request = http.Request('PUT', Uri.parse(uploadUrl))
      ..headers['Content-Type'] = contentType
      ..bodyBytes = Uint8List.fromList(bytes);

    final client = http.Client();
    try {
      debugPrint('[R2_UPLOAD][$traceId] STEP 2: PUT vers R2 objectKey=$objectKey bytes=${bytes.length} contentType=$contentType');
      final streamed = await client
          .send(request)
          .timeout(const Duration(minutes: 3), onTimeout: () {
        throw TimeoutException('Le transfert vers R2 a dépassé 3 minutes.');
      });
      final uploadResponse = await http.Response.fromStream(streamed)
          .timeout(const Duration(seconds: 30), onTimeout: () {
        throw TimeoutException('Délai dépassé pendant la confirmation de l’envoi R2.');
      });
      debugPrint('[R2_UPLOAD][$traceId] R2 PUT status=${uploadResponse.statusCode} responseBytes=${uploadResponse.bodyBytes.length}');
      if (uploadResponse.statusCode < 200 || uploadResponse.statusCode >= 300) {
        final bodyPreview = uploadResponse.body.length > 500
            ? uploadResponse.body.substring(0, 500)
            : uploadResponse.body;
        // Extract only the provider error code for a useful diagnostic. Never
        // print uploadUrl: it contains a temporary signature credential.
        final codeMatch = RegExp(r'<Code>([^<]+)</Code>').firstMatch(bodyPreview);
        final providerCode = codeMatch?.group(1);
        debugPrint('[R2_UPLOAD][$traceId] R2_PUT_FAILURE status=${uploadResponse.statusCode} providerCode=${providerCode ?? 'unknown'} body=$bodyPreview');
        throw HttpException(
          'Échec du téléversement R2 (HTTP ${uploadResponse.statusCode}'
          '${providerCode == null ? '' : ', $providerCode'}).',
        );
      }
    } catch (e, stack) {
      debugPrint('[R2_UPLOAD][$traceId] PUT_EXCEPTION type=${e.runtimeType} error=$e');
      debugPrint('[R2_UPLOAD][$traceId] PUT_STACK_TRACE\\n$stack');
      // A reset/timeout can happen after R2 received the full PUT. Delete the
      // known key even when the client never got the successful response.
      if (category == 'post_media' && objectKey.isNotEmpty) {
        try {
          await deleteFailedPostMedia(objectKeys: [objectKey], communityId: communityId);
        } catch (cleanupError) {
          debugPrint('[R2_UPLOAD][$traceId] FAILED_PUT_CLEANUP_FAILED objectKey=$objectKey error=$cleanupError');
        }
      }
      rethrow;
    } finally {
      client.close();
      debugPrint('[R2_UPLOAD][$traceId] HTTP client closed');
    }

    debugPrint('[R2_UPLOAD][$traceId] SUCCESS objectKey=$objectKey bytes=${bytes.length}');
    return R2UploadedMedia(
      objectKey: objectKey,
      publicUrl: publicUrl,
      isPublic: isPublic,
      contentType: contentType,
      sizeBytes: bytes.length,
    );
  }
}
