import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Carte partageable d'un commentaire, avec l'identité visuelle sobre de Scrole.
class CommentSharePoster extends StatelessWidget {
  final String authorName;
  final String username;
  final String content;

  const CommentSharePoster({
    super.key,
    required this.authorName,
    required this.username,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    const brandBlue = Color(0xFF3B82F6);
    final initials = authorName.trim().isEmpty
        ? 'S'
        : authorName.trim().split(RegExp(r'\\s+')).take(2).map((part) => part.isNotEmpty ? part[0].toUpperCase() : '').join();

    return AspectRatio(
      aspectRatio: 9 / 16,
      child: Container(
        color: const Color(0xFFF4F7FB),
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 30),
        child: Column(
          children: [
            const Spacer(),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFE6EAF0)),
                boxShadow: const [
                  BoxShadow(color: Color(0x140F172A), blurRadius: 24, offset: Offset(0, 10)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(colors: [Color(0xFF60A5FA), brandBlue]),
                        ),
                        child: Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(authorName.isEmpty ? 'Utilisateur Scrole' : authorName,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF172033))),
                            if (username.isNotEmpty)
                              Text('@$username', maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                          ],
                        ),
                      ),
                      const Icon(Icons.format_quote_rounded, color: brandBlue, size: 24),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(content, style: const TextStyle(fontSize: 17, height: 1.45, color: Color(0xFF172033))),
                  const SizedBox(height: 18),
                  const Divider(height: 1, color: Color(0xFFE9EDF3)),
                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      Icon(Icons.chat_bubble_outline_rounded, color: brandBlue, size: 16),
                      SizedBox(width: 7),
                      Text('Commentaire partagé sur Scrole',
                        style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
            ),
            const Spacer(),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.circle, size: 10, color: brandBlue),
                SizedBox(width: 7),
                Text('scrole', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: Color(0xFF172033))),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Les conversations qui nous rapprochent', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
          ],
        ),
      ),
    );
  }
}

class CommentSharePosterService {
  CommentSharePosterService._();

  static Future<File> generateImage({
    required String authorName,
    required String username,
    required String content,
    required BuildContext context,
  }) async {
    final key = GlobalKey();
    final overlay = Overlay.of(context, rootOverlay: true);
    final entry = OverlayEntry(
      builder: (_) => Positioned(
        left: -2000,
        top: 0,
        width: 420,
        child: Material(
          color: Colors.transparent,
          child: RepaintBoundary(
            key: key,
            child: CommentSharePoster(authorName: authorName, username: username, content: content),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('Impossible de préparer la carte du commentaire.');
      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final ByteData? bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) throw StateError('Impossible de générer l’image du commentaire.');
      final Directory directory = await getTemporaryDirectory();
      final file = File('${directory.path}/scrole_comment_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      return file;
    } finally {
      entry.remove();
    }
  }

  static Future<void> shareImage({
    required String authorName,
    required String username,
    required String content,
    required BuildContext context,
  }) async {
    final file = await generateImage(authorName: authorName, username: username, content: content, context: context);
    await Share.shareXFiles([XFile(file.path)], text: 'Commentaire partagé sur Scrole');
  }
}
