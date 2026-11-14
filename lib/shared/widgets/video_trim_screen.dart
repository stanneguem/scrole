import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_trimmer/video_trimmer.dart';
import '../../app/theme/app_colors.dart';

class VideoTrimScreen extends StatefulWidget {
  final File videoFile;
  final Duration maxDuration;

  const VideoTrimScreen({super.key, required this.videoFile, this.maxDuration = const Duration(seconds: 30)});

  @override
  State<VideoTrimScreen> createState() => _VideoTrimScreenState();
}

class _VideoTrimScreenState extends State<VideoTrimScreen> {
  final Trimmer _trimmer = Trimmer();
  double _startValue = 0.0;
  double _endValue = 100.0;
  bool _isPlaying = false;
  bool _progressVisibility = false;
  bool _isLoadingVideo = true;
  bool _loadFailed = false;
  Duration _videoDuration = Duration.zero;
  double _selectedStartMs = 0;
  double _selectedEndMs = 0;
  List<File> _timelineFrames = [];

  @override
  void initState() {
    super.initState();
    _loadVideo();
  }

  Future<void> _loadVideo() async {
    try {
      await _trimmer.loadVideo(videoFile: widget.videoFile);
      final videoDuration =
          _trimmer.videoPlayerController?.value.duration ?? Duration.zero;
      final durationMs = videoDuration.inMilliseconds.toDouble();
      final initialSelectionMs = durationMs
          .clamp(1, widget.maxDuration.inMilliseconds.toDouble())
          .toDouble();
      if (mounted) {
        setState(() {
          _videoDuration = videoDuration;
          _selectedStartMs = 0;
          _selectedEndMs = initialSelectionMs;
          // video_trimmer v5 reports and accepts trim positions in ms.
          _startValue = 0;
          _endValue = initialSelectionMs;
          _isLoadingVideo = false;
        });
      }
      await _generateTimelineFrames(durationMs);
    } catch (e, stack) {
      debugPrint('[VideoTrimScreen] load error: $e\\n$stack');
      if (mounted) {
        setState(() {
          _isLoadingVideo = false;
          _loadFailed = true;
        });
      }
    }
  }

  @override
  void dispose() {
    // Le Trimmer possède un VideoPlayerController natif : le libérer à la
    // fermeture de l'écran évite de conserver le décodeur en mémoire.
    _trimmer.dispose();
    super.dispose();
  }

  Future<void> _saveVideo() async {
    setState(() {
      _progressVisibility = true;
    });

    try {
      await _trimmer.saveTrimmedVideo(
        startValue: _startValue,
        endValue: _endValue,
        onSave: (outputPath) {
          if (mounted) {
            setState(() {
              _progressVisibility = false;
            });
          }
          if (outputPath != null && outputPath.trim().isNotEmpty && File(outputPath).existsSync()) {
            debugPrint('[VideoTrimScreen] TRIM_SUCCESS outputPath=$outputPath');
            Get.back(result: File(outputPath));
          } else {
            debugPrint('[VideoTrimScreen] TRIM_FAILED reason=empty_output_path');
            Get.back<File?>(result: null);
          }
        },
      );
    } catch (e) {
      debugPrint('[VideoTrimScreen] save error: $e');
      if (mounted) {
        setState(() {
          _progressVisibility = false;
        });
      }
      // Ne jamais renvoyer la vidéo originale quand le découpage a échoué :
      // elle pourrait dépasser la limite et faire annuler toute la publication.
      Get.back<File?>(result: null);
    }
  }

  String _formatTime(double milliseconds) {
    final totalSeconds = (milliseconds / 1000).floor();
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _generateTimelineFrames(double durationMs) async {
    if (durationMs <= 0) return;
    final frames = <File>[];
    // Extraire les images une par une pour limiter la charge sur le décodeur Android.
    for (var i = 0; i < 7; i++) {
      if (!mounted) return;
      try {
        final position = ((durationMs - 1) * i / 6).round();
        final frame = await VideoCompress.getFileThumbnail(widget.videoFile.path, quality: 35, position: position).timeout(const Duration(seconds: 8));
        if (await frame.exists()) frames.add(frame);
      } catch (e) { debugPrint('[VideoTrimScreen] thumbnail $i failed: $e'); }
    }
    if (mounted && frames.isNotEmpty) setState(() => _timelineFrames = frames);
  }
  bool? _draggingStartHandle;

  void _togglePlayback() async {
    if (_isLoadingVideo || _loadFailed) return;
    try {
      final playbackState = await _trimmer.videoPlaybackControl(
        startValue: _startValue,
        endValue: _endValue,
      );
      if (mounted) setState(() => _isPlaying = playbackState);
    } catch (e) {
      debugPrint('[VideoTrimScreen] playback error: $e');
    }
  }

  Widget _buildVisibleTimeline() {
    final totalMs = _videoDuration.inMilliseconds.toDouble();
    final maxSelectionMs = widget.maxDuration.inMilliseconds.toDouble();
    if (totalMs <= 0) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      padding: const EdgeInsets.fromLTRB(12, 13, 12, 13),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'AJUSTER LA VIDÉO',
                style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1),
              ),
              Text(
                'MAX ${widget.maxDuration.inSeconds} s',
                style: const TextStyle(color: Color(0xFFFFC928), fontSize: 11, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 66,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final startFraction = (_selectedStartMs / totalMs).clamp(0.0, 1.0);
                final endFraction = (_selectedEndMs / totalMs).clamp(0.0, 1.0);
                final startX = width * startFraction;
                final endX = width * endFraction;

                void updateHandle(DragUpdateDetails details) {
                  final deltaMs = details.delta.dx / width * totalMs;
                  setState(() {
                    if (_draggingStartHandle == true) {
                      _selectedStartMs = (_selectedStartMs + deltaMs)
                          .clamp(0.0, _selectedEndMs - 500.0)
                          .toDouble();
                      if (_selectedEndMs - _selectedStartMs > maxSelectionMs) {
                        _selectedStartMs = _selectedEndMs - maxSelectionMs;
                      }
                    } else {
                      _selectedEndMs = (_selectedEndMs + deltaMs)
                          .clamp(_selectedStartMs + 500.0, totalMs)
                          .toDouble();
                      if (_selectedEndMs - _selectedStartMs > maxSelectionMs) {
                        _selectedEndMs = _selectedStartMs + maxSelectionMs;
                      }
                    }
                    _startValue = _selectedStartMs;
                    _endValue = _selectedEndMs;
                  });
                }

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (details) {
                    final x = details.localPosition.dx;
                    _draggingStartHandle = (x - startX).abs() <= (x - endX).abs();
                  },
                  onPanUpdate: updateHandle,
                  onPanEnd: (_) => _draggingStartHandle = null,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: _timelineFrames.isEmpty
                              ? Row(
                                  children: List.generate(
                                    12,
                                    (i) => Expanded(
                                      child: Container(
                                        margin: const EdgeInsets.symmetric(horizontal: 1),
                                        color: i.isEven ? const Color(0xFF5B5B5B) : const Color(0xFF343434),
                                        alignment: Alignment.center,
                                        child: const Icon(Icons.movie_outlined, color: Colors.white24, size: 16),
                                      ),
                                    ),
                                  ),
                                )
                              : Row(
                                  children: _timelineFrames
                                      .map((frame) => Expanded(child: Image.file(frame, fit: BoxFit.cover, gaplessPlayback: true)))
                                      .toList(),
                                ),
                        ),
                      ),
                      Positioned(
                        left: 0, top: 0, bottom: 0, width: startX,
                        child: IgnorePointer(child: Container(color: Colors.black.withValues(alpha: .62))),
                      ),
                      Positioned(
                        left: endX, top: 0, bottom: 0, width: width - endX,
                        child: IgnorePointer(child: Container(color: Colors.black.withValues(alpha: .62))),
                      ),
                      Positioned(
                        left: startX, top: 0, bottom: 0, width: (endX - startX).clamp(0.0, width),
                        child: IgnorePointer(
                          child: Container(decoration: BoxDecoration(border: Border.all(color: const Color(0xFFFFC928), width: 2))),
                        ),
                      ),
                      Positioned(
                        left: (startX - 7).clamp(0.0, width - 14), top: 0, bottom: 0, width: 14,
                        child: IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(color: const Color(0xFFFFC928), borderRadius: BorderRadius.circular(4)),
                            child: const Center(child: Icon(Icons.drag_indicator, size: 12, color: Colors.black87)),
                          ),
                        ),
                      ),
                      Positioned(
                        left: (endX - 7).clamp(0.0, width - 14), top: 0, bottom: 0, width: 14,
                        child: IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(color: const Color(0xFFFFC928), borderRadius: BorderRadius.circular(4)),
                            child: const Center(child: Icon(Icons.drag_indicator, size: 12, color: Colors.black87)),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: (_progressVisibility || _isLoadingVideo || _loadFailed) ? null : _saveVideo,
            child: _progressVisibility
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2))
                : const Text(
                    'Valider',
                    style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
          ),
        ],
      ),
      body: Builder(
        builder: (context) => Center(
          child: Container(
            padding: const EdgeInsets.only(bottom: 30.0),
            color: Colors.black,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.max,
              children: <Widget>[
                Visibility(
                  visible: _progressVisibility,
                  child: const LinearProgressIndicator(
                    backgroundColor: AppColors.primary,
                  ),
                ),
                Expanded(
                  child: _isLoadingVideo
                      ? const Center(child: CircularProgressIndicator(color: Colors.white))
                      : _loadFailed
                          ? const Center(
                              child: Text(
                                'Impossible de lire cette vidéo sur cet appareil.',
                                style: TextStyle(color: Colors.white70),
                                textAlign: TextAlign.center,
                              ),
                            )
                          : GestureDetector(\n                              behavior: HitTestBehavior.opaque,\n                              onTap: _togglePlayback,\n                              child: VideoViewer(trimmer: _trimmer),\n                            ),
                ),
                if (!_isLoadingVideo && !_loadFailed) ...[
                  _buildVisibleTimeline(),

                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
