import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../../centre/services/chat_media_cache.dart';

/// Visualiseur dédié aux médias échangés en messagerie directe.
/// Aucun compteur ni action sociale du fil d'actualité n'est affiché.
class ChatMediaViewerScreen extends StatefulWidget {
  const ChatMediaViewerScreen({
    super.key,
    required this.mediaUrls,
    this.initialIndex = 0,
  });

  final List<String> mediaUrls;
  final int initialIndex;

  @override
  State<ChatMediaViewerScreen> createState() => _ChatMediaViewerScreenState();
}

class _ChatMediaViewerScreenState extends State<ChatMediaViewerScreen> {
  late final PageController _pageController;
  late int _currentIndex;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(
      0,
      widget.mediaUrls.isEmpty ? 0 : widget.mediaUrls.length - 1,
    );
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String _fileName(String url) {
    final uri = Uri.tryParse(url);
    final ext = p.extension(uri?.path ?? url);
    return 'scrole_image_${DateTime.now().millisecondsSinceEpoch}${ext.isEmpty ? '.jpg' : ext}';
  }

  Future<String?> _localFile(String url) async {
    if (ChatMediaCache.isFilesystemPath(url)) {
      final path = url.startsWith('file://') ? Uri.parse(url).toFilePath() : url;
      if (await File(path).exists()) return path;
    }

    final cached = await ChatMediaCache.instance.resolveLocalPath(url);
    if (cached != null && await File(cached).exists()) return cached;

    // Fallback for public/accessible URLs if the chat cache could not resolve it.
    if (ChatMediaCache.isHttpUrl(url)) {
      try {
        final file = await DefaultCacheManager().getSingleFile(url);
        return file.path;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Future<void> _saveToGallery() async {
    if (_saving || widget.mediaUrls.isEmpty) return;
    setState(() => _saving = true);
    try {
      final url = widget.mediaUrls[_currentIndex];
      final localPath = await _localFile(url);
      if (localPath == null) {
        Get.snackbar('Téléchargement impossible', 'Cette image ne peut pas être récupérée pour le moment.',
            snackPosition: SnackPosition.BOTTOM);
        return;
      }

      final ok = await ChatMediaCache.instance.saveToGallery(
        sourcePath: localPath,
        fileName: _fileName(url),
      );
      if (!mounted) return;
      Get.snackbar(
        ok ? 'Image enregistrée' : 'Enregistrement impossible',
        ok ? 'L’image a été enregistrée dans la galerie de votre appareil.'
            : 'Vérifiez les autorisations d’accès aux photos puis réessayez.',
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (_) {
      if (mounted) {
        Get.snackbar('Erreur', 'Impossible d’enregistrer cette image.',
            snackPosition: SnackPosition.BOTTOM);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _shareImage() async {
    if (widget.mediaUrls.isEmpty) return;
    final path = await _localFile(widget.mediaUrls[_currentIndex]);
    if (path == null) {
      Get.snackbar('Partage impossible', 'Cette image est momentanément indisponible.',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    await Share.shareXFiles([XFile(path)], text: 'Image partagée depuis Scrole');
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.mediaUrls;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: urls.length,
              onPageChanged: (index) => setState(() => _currentIndex = index),
              itemBuilder: (context, index) => Center(
                child: InteractiveViewer(
                  minScale: 0.7,
                  maxScale: 4,
                  child: SizedBox.expand(
                    child: _ChatMediaImage(url: urls[index]),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 4,
              left: 8,
              right: 8,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _CircleAction(
                    icon: Icons.close_rounded,
                    tooltip: 'Fermer',
                    onTap: () => Get.back(),
                  ),
                  if (urls.length > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_currentIndex + 1} / ${urls.length}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                  _CircleAction(
                    icon: Icons.more_vert_rounded,
                    tooltip: 'Options de l’image',
                    onTap: _showActions,
                  ),
                ],
              ),
            ),
            if (_saving)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x55000000),
                  child: Center(child: CircularProgressIndicator(color: Colors.white)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showActions() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.download_for_offline_outlined),
              title: const Text('Enregistrer dans la galerie'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _saveToGallery();
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Partager l’image'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _shareImage();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.black54,
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onTap,
          icon: Icon(icon, color: Colors.white),
        ),
      );
}

class _ChatMediaImage extends StatelessWidget {
  const _ChatMediaImage({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: ChatMediaCache.instance.resolveLocalPath(url),
      builder: (context, snapshot) {
        final path = snapshot.data;
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }
        if (path != null && File(path).existsSync()) {
          return Image.file(
            File(path),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const _UnavailableImage(),
          );
        }
        if (ChatMediaCache.isHttpUrl(url)) {
          return Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const _UnavailableImage(),
          );
        }
        return const _UnavailableImage();
      },
    );
  }
}

class _UnavailableImage extends StatelessWidget {
  const _UnavailableImage();

  @override
  Widget build(BuildContext context) => const Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: Colors.white70,
          size: 56,
        ),
      );
}
