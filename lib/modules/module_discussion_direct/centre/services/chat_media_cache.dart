import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;

class ChatMediaCache {
  ChatMediaCache._();
  static final ChatMediaCache instance = ChatMediaCache._();
  String? get _userId => Supabase.instance.client.auth.currentUser?.id;

  Future<Directory?> _directory() async {
    final uid = _userId;
    if (uid == null || uid.isEmpty) return null;
    final root = await getApplicationSupportDirectory();
    final directory = Directory(p.join(root.path, 'chat_media', uid));
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  static bool isHttpUrl(String value) =>
      value.startsWith('http://') || value.startsWith('https://');

  /// True for real device paths (`/data/...`, `file://...`), not Storage keys.
  static bool isFilesystemPath(String value) {
    if (value.startsWith('file://')) return true;
    if (value.startsWith('/')) return true;
    return false;
  }

  /// Supabase object key stored in `media_urls`, e.g. `{uid}/chat/media/file.jpg`.
  static bool isStorageKey(String value) =>
      value.isNotEmpty && !isHttpUrl(value) && !isFilesystemPath(value);

  static bool _isR2ObjectKey(String value) =>
      value.startsWith('messages/') || value.startsWith('stories/') ||
      value.startsWith('private/') || value.startsWith('bug-reports/');

  String _fileName(String remoteUrl) {
    final sourcePath = isHttpUrl(remoteUrl)
        ? (Uri.tryParse(remoteUrl)?.path ?? remoteUrl)
        : remoteUrl;
    final extension = p.extension(sourcePath.split('?').first);
    return '${sha256.convert(remoteUrl.codeUnits)}${extension.isEmpty ? '.bin' : extension}';
  }

  Future<String?> localPathFor(String remoteUrl) async {
    if (remoteUrl.isEmpty) return null;
    final directory = await _directory();
    if (directory == null) return null;
    final file = File(p.join(directory.path, _fileName(remoteUrl)));
    return await file.exists() ? file.path : null;
  }

  Future<String?> cacheBytes(String remoteUrl, Uint8List bytes) async {
    final directory = await _directory();
    if (directory == null) return null;
    final file = File(p.join(directory.path, _fileName(remoteUrl)));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<String?> saveLocalToSandbox(String storagePath, String localSourcePath) async {
    if (storagePath.isEmpty || localSourcePath.isEmpty) return null;
    final sourceFile = File(localSourcePath);
    if (!await sourceFile.exists()) return null;
    final directory = await _directory();
    if (directory == null) return null;
    final targetFile = File(p.join(directory.path, _fileName(storagePath)));
    await sourceFile.copy(targetFile.path);
    return targetFile.path;
  }

  Future<bool> _requestGalleryPermission() async {
    if (Platform.isAndroid) {
      final status = await Permission.photos.request();
      if (status.isGranted || status.isLimited) return true;
      final storage = await Permission.storage.request();
      return storage.isGranted;
    }
    if (Platform.isIOS) {
      final status = await Permission.photosAddOnly.request();
      return status.isGranted || status.isLimited;
    }
    return true;
  }

  Future<bool> saveToGallery({required String sourcePath, required String fileName}) async {
    final source = File(sourcePath);
    if (!await source.exists()) return false;
    if (!await _requestGalleryPermission()) return false;

    final result = await SaverGallery.saveFile(
      filePath: source.path,
      fileName: fileName,
      androidRelativePath: 'Pictures/Scrole',
      skipIfExists: true,
    );
    return result.isSuccess;
  }

  /// Returns a path that is safe to pass to [Image.file] / [AudioPlayer.setFilePath].
  Future<String?> resolveLocalPath(String ref) async {
    if (ref.isEmpty) return null;

    if (isFilesystemPath(ref)) {
      final file = File(ref.startsWith('file://') ? Uri.parse(ref).toFilePath() : ref);
      if (await file.exists()) return file.path;
      return null;
    }

    return cacheRemote(ref);
  }

  Future<String?> cacheRemote(String remoteUrl) async {
    if (remoteUrl.isEmpty || isFilesystemPath(remoteUrl)) return null;
    final existing = await localPathFor(remoteUrl);
    if (existing != null) return existing;

    try {
      final client = Supabase.instance.client;
      String downloadUrl;
      if (isHttpUrl(remoteUrl) && !remoteUrl.contains('/storage/v1/object/')) {
        downloadUrl = remoteUrl;
      } else if (_isR2ObjectKey(remoteUrl)) {
        final response = await client.functions.invoke(
          'r2-media-upload',
          body: {'action': 'create-download-url', 'object_key': remoteUrl},
        );
        if (response.status < 200 || response.status >= 300 || response.data is! Map) return null;
        final data = Map<String, dynamic>.from(response.data as Map);
        final resolved = data['url'] as String?;
        if (resolved == null || resolved.isEmpty) return null;
        downloadUrl = resolved;
      } else if (isHttpUrl(remoteUrl)) {
        downloadUrl = remoteUrl;
      } else {
        // Legacy Supabase Storage key support for old messages only.
        downloadUrl = await client.storage.from('chat-media').createSignedUrl(remoteUrl, 120);
      }
      final response = await http.get(Uri.parse(downloadUrl));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      return cacheBytes(remoteUrl, response.bodyBytes);
    } catch (_) {
      return null;
    }
  }

  String _storagePathFromPublicUrl(String url) {
    const markers = [
      '/storage/v1/object/public/chat-media/',
      '/storage/v1/object/sign/chat-media/',
      '/storage/v1/object/authenticated/chat-media/',
    ];
    for (final marker in markers) {
      final index = url.indexOf(marker);
      if (index != -1) {
        final raw = url.substring(index + marker.length).split('?').first;
        return Uri.decodeFull(raw);
      }
    }
    throw const FormatException('Invalid chat media URL');
  }

  Future<void> removeLocal(String remoteUrl) async {
    final path = await localPathFor(remoteUrl);
    if (path == null) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  /// Nettoie les fichiers médias vieux de plus de [days] jours.
  Future<void> purgeOldFiles({int days = 30}) async {
    final dir = await _directory();
    if (dir == null || !await dir.exists()) return;

    final now = DateTime.now();
    final threshold = now.subtract(Duration(days: days));
    int count = 0;

    try {
      final List<FileSystemEntity> entities = await dir.list().toList();
      for (final entity in entities) {
        if (entity is File) {
          final stats = await entity.stat();
          if (stats.changed.isBefore(threshold)) {
            await entity.delete();
            count++;
          }
        }
      }
      if (count > 0) {
        debugPrint('[ChatMediaCache] Purge : $count fichiers supprimés (> $days jours)');
      }
    } catch (e) {
      debugPrint('[ChatMediaCache] Erreur lors de la purge : $e');
    }
  }
}
