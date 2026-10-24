import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../../../app/local_storage/structured/app_cache_database.dart';

class MediaLocalCache {
  MediaLocalCache(this._database);

  final AppDatabase _database;

  Future<String?> resolve({
    required String userId,
    required String messageId,
    required String remoteUrl,
  }) async {
    if (remoteUrl.isEmpty || !remoteUrl.startsWith('http')) return null;
    final db = await _database.database;
    final rows = await db.query(
      'direct_chat_media_cache',
      columns: ['local_path', 'downloaded'],
      where: 'user_id=? AND message_id=? AND remote_ref=?',
      whereArgs: [userId, messageId, remoteUrl],
      limit: 1,
    );
    if (rows.isEmpty || rows.first['downloaded'] != 1) return null;
    final path = rows.first['local_path']?.toString();
    if (path == null || path.isEmpty) return null;
    if (await File(path).exists()) return path;

    await db.delete(
      'direct_chat_media_cache',
      where: 'user_id=? AND message_id=? AND remote_ref=?',
      whereArgs: [userId, messageId, remoteUrl],
    );
    return null;
  }

  Future<String> download({
    required String userId,
    required String messageId,
    required String remoteUrl,
  }) async {
    final existing = await resolve(
      userId: userId,
      messageId: messageId,
      remoteUrl: remoteUrl,
    );
    if (existing != null) return existing;

    final response = await http.get(Uri.parse(remoteUrl));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('media_download_failed_${response.statusCode}');
    }

    final root = await getApplicationSupportDirectory();
    final directory = Directory(p.join(root.path, 'scrole_media', userId, messageId));
    await directory.create(recursive: true);

    final digest = sha256.convert(response.bodyBytes).toString();
    final extension = _extension(remoteUrl, response.headers['content-type']);
    final target = File(p.join(directory.path, '$digest$extension'));
    final temporary = File('${target.path}.part');
    await temporary.writeAsBytes(response.bodyBytes, flush: true);
    await temporary.rename(target.path);

    final db = await _database.database;
    await db.insert(
      'direct_chat_media_cache',
      {
        'user_id': userId,
        'message_id': messageId,
        'remote_ref': remoteUrl,
        'local_path': target.path,
        'downloaded': 1,
        'sha256': digest,
        'downloaded_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return target.path;
  }

  Future<void> deleteMessageMedia(String userId, String messageId) async {
    final db = await _database.database;
    final rows = await db.query(
      'direct_chat_media_cache',
      columns: ['local_path'],
      where: 'user_id=? AND message_id=?',
      whereArgs: [userId, messageId],
    );
    for (final row in rows) {
      final path = row['local_path']?.toString();
      if (path != null && path.isNotEmpty) {
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
    }
    await db.delete(
      'direct_chat_media_cache',
      where: 'user_id=? AND message_id=?',
      whereArgs: [userId, messageId],
    );
  }

  String _extension(String url, String? contentType) {
    final raw = p.extension(Uri.tryParse(url)?.path ?? '').toLowerCase();
    if (raw.length >= 2 && raw.length <= 6) return raw;
    return switch ((contentType ?? '').split(';').first.toLowerCase()) {
      'image/jpeg' => '.jpg',
      'image/png' => '.png',
      'image/webp' => '.webp',
      'image/gif' => '.gif',
      'video/mp4' => '.mp4',
      'video/webm' => '.webm',
      'audio/mpeg' => '.mp3',
      'audio/mp4' => '.m4a',
      'audio/aac' => '.aac',
      'audio/wav' => '.wav',
      _ => '.bin',
    };
  }
}
