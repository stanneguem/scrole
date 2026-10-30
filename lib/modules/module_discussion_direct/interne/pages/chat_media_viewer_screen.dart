import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:video_player/video_player.dart';

import '../../centre/services/chat_media_cache.dart';

/// Visualiseur dédié aux médias échangés en messagerie directe.
/// Aucun compteur ni action sociale du fil d'actualité n'est affiché.
class ChatMediaViewerScreen extends StatefulWidget {
  const ChatMediaViewerScreen({
    super.key,
    required this.mediaUrls,
    this.initialIndex = 0,
    this.mediaTypes = const [],
  });

  final List<String> mediaUrls;
  final int initialIndex;
  /// "image" or "video" for each URL. Missing entries default to image.
  final List<String> mediaTypes;

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

  bool _isVideo(int index) =>
      index < widget.mediaTypes.length && widget.mediaTypes[index] == 'video';

  String _fileName(String url) {
    final uri = Uri.tryParse(url);
    var ext = p.extension(uri?.path ?? url);
    if (ext.isEmpty) ext = _isVideo(_currentIndex) ? '.mp4' : '.jpg';
    return 'scrole_${_isVideo(_currentIndex) ? 'video' : 'image'}_${DateTime.now().millisecondsSinceEpoch}$ext';
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
      final kind = _isVideo(_currentIndex) ? 'vidéo' : 'image';
      Get.snackbar(
        ok ? '${kind[0].toUpperCase()}${kind.substring(1)} enregistrée' : 'Enregistrement impossible',
        ok ? 'Le média a été enregistré dans la galerie de votre appareil.'
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
    await Share.shareXFiles([XFile(path)], text: 'Média partagé depuis Scrole');
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
                child: _isVideo(index)
                    ? _ChatMediaVideo(url: urls[index])
                    : InteractiveViewer(
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
              title: Text(_isVideo(_currentIndex)
                  ? 'Enregistrer la vidéo'
                  : 'Enregistrer dans la galerie'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _saveToGallery();
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: Text(_isVideo(_currentIndex) ? 'Partager la vidéo' : 'Partager l’image'),
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


/// Lecteur plein écran utilisé par le visualiseur des médias de discussion.
class _ChatMediaVideo extends StatefulWidget {
  const _ChatMediaVideo({required this.url});
  final String url;

  @override
  State<_ChatMediaVideo> createState() => _ChatMediaVideoState();
}

class _ChatMediaVideoState extends State<_ChatMediaVideo> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final localPath = await ChatMediaCache.instance.resolveLocalPath(widget.url);
      final controller = localPath != null && await File(localPath).exists()
          ? VideoPlayerController.file(File(localPath))
          : VideoPlayerController.networkUrl(Uri.parse(widget.url));
      _controller = controller;
      await controller.initialize();
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_failed) {
      return const Center(child: Icon(Icons.videocam_off_outlined, color: Colors.white70, size: 56));
    }
    if (!_ready || controller == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    return Center(
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(controller),
            IconButton.filledTonal(
              iconSize: 38,
              onPressed: () => setState(() {
                controller.value.isPlaying ? controller.pause() : controller.play();
              }),
              icon: Icon(controller.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 8,
              child: VideoProgressIndicator(
                controller,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: Colors.white,
                  bufferedColor: Colors.white38,
                  backgroundColor: Colors.white24,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
