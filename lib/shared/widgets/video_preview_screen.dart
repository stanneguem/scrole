import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:video_player/video_player.dart';

import 'video_trim_screen.dart';

/// Lecteur dédié aux vidéos sélectionnées dans le compositeur de publication.
/// Les opérations d'édition sont regroupées ici afin de ne pas garder un
/// décodeur vidéo actif dans la grille du compositeur.
class VideoPreviewScreen extends StatefulWidget {
  final File videoFile;
  final Duration maxDuration;

  const VideoPreviewScreen({
    super.key,
    required this.videoFile,
    this.maxDuration = const Duration(seconds: 29),
  });

  @override
  State<VideoPreviewScreen> createState() => _VideoPreviewScreenState();
}

class _VideoPreviewScreenState extends State<VideoPreviewScreen> {
  late File _videoFile;
  VideoPlayerController? _controller;
  bool _isInitializing = true;
  bool _hasError = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _videoFile = widget.videoFile;
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    final previous = _controller;
    _controller = null;
    if (previous != null) {
      await previous.dispose();
    }
    if (!mounted) return;

    setState(() {
      _isInitializing = true;
      _hasError = false;
    });

    try {
      final controller = VideoPlayerController.file(_videoFile);
      _controller = controller;
      await controller.initialize();
      await controller.setLooping(false);
      if (!mounted || !identical(_controller, controller)) {
        await controller.dispose();
        return;
      }
      setState(() => _isInitializing = false);
    } catch (error, stack) {
      debugPrint('[VideoPreviewScreen] player initialization failed: $error\\n$stack');
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _hasError = true;
        });
      }
    }
  }

  Future<void> _trimVideo() async {
    if (_isInitializing || _hasError) return;
    final wasPlaying = _controller?.value.isPlaying ?? false;
    if (wasPlaying) await _controller?.pause();

    final trimmed = await Get.to<File>(() => VideoTrimScreen(
          videoFile: _videoFile,
          maxDuration: widget.maxDuration,
        ));
    if (trimmed == null || !mounted) {
      if (wasPlaying) await _controller?.play();
      return;
    }

    _videoFile = trimmed;
    _hasChanges = true;
    await _initializePlayer();
  }

  void _close() {
    Get.back<File?>(result: _hasChanges ? _videoFile : null);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Aperçu de la vidéo'),
        actions: [
          IconButton(
            tooltip: 'Options vidéo',
            onPressed: _isInitializing || _hasError ? null : _trimVideo,
            icon: const Icon(Icons.tune_rounded),
          ),
          PopupMenuButton<String>(
            iconColor: Colors.white,
            onSelected: (value) {
              if (value == 'trim') _trimVideo();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'trim',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.content_cut_rounded),
                  title: Text('Découper la vidéo'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: _isInitializing
                    ? const CircularProgressIndicator(color: Colors.white)
                    : _hasError || controller == null || !controller.value.isInitialized
                        ? const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Impossible de lire cette vidéo sur cet appareil.',
                              style: TextStyle(color: Colors.white70),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : AspectRatio(
                            aspectRatio: controller.value.aspectRatio > 0
                                ? controller.value.aspectRatio
                                : 9 / 16,
                            child: VideoPlayer(controller),
                          ),
              ),
            ),
            if (!_isInitializing && !_hasError && controller != null && controller.value.isInitialized)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                child: Column(
                  children: [
                    VideoProgressIndicator(
                      controller,
                      allowScrubbing: true,
                      colors: const VideoProgressColors(
                        playedColor: Colors.white,
                        bufferedColor: Colors.white38,
                        backgroundColor: Colors.white24,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          _formatDuration(controller.value.position),
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        const Spacer(),
                        IconButton.filled(
                          onPressed: () async {
                            if (controller.value.isPlaying) {
                              await controller.pause();
                            } else {
                              if (controller.value.position >= controller.value.duration) {
                                await controller.seekTo(Duration.zero);
                              }
                              await controller.play();
                            }
                            if (mounted) setState(() {});
                          },
                          icon: Icon(
                            controller.value.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _formatDuration(controller.value.duration),
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _trimVideo,
                        icon: const Icon(Icons.content_cut_rounded),
                        label: const Text('Découper / modifier la durée'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white54),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
