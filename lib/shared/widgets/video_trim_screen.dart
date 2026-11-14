import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
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

  Widget _buildVisibleTimeline() {
    final totalMs = _videoDuration.inMilliseconds.toDouble();
    final maxSelectionMs = widget.maxDuration.inMilliseconds.toDouble();
    if (totalMs <= 0) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('ZONE DE DÉCOUPAGE',
                  style: TextStyle(color: Colors.white70, fontSize: 11,
                      fontWeight: FontWeight.w700, letterSpacing: 1)),
              Text('MAX ${widget.maxDuration.inSeconds} s',
                  style: const TextStyle(color: AppColors.primary,
                      fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.primary, width: 1.5),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Row(
                    children: List.generate(12, (index) => Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          color: index.isEven
                              ? Colors.white12 : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    )),
                  ),
                ),
                Positioned.fill(
                  child: Center(
                    child: Text(
                      '${_formatTime(_selectedStartMs)}  —  ${_formatTime(_selectedEndMs)}',
                      style: const TextStyle(color: Colors.white,
                          fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          RangeSlider(
            min: 0,
            max: totalMs,
            divisions: totalMs >= 1000 ? totalMs.floor().clamp(1, 10000) : null,
            values: RangeValues(
              _selectedStartMs.clamp(0, totalMs),
              _selectedEndMs.clamp(0, totalMs),
            ),
            onChanged: (range) {
              var start = range.start;
              var end = range.end;
              if (end - start > maxSelectionMs) {
                if (start != _selectedStartMs) {
                  start = end - maxSelectionMs;
                } else {
                  end = start + maxSelectionMs;
                }
              }
              if (end - start < 500 && totalMs >= 500) {
                end = (start + 500).clamp(0, totalMs);
                start = (end - 500).clamp(0, totalMs);
              }
              setState(() {
                _selectedStartMs = start;
                _selectedEndMs = end;
                _startValue = start;
                _endValue = end;
              });
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatTime(_selectedStartMs),
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
              Text('${_formatTime(_selectedEndMs)} / ${_formatTime(totalMs)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
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
        title: Text(
          'Découper la vidéo (max ${widget.maxDuration.inSeconds} s)',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, fontSize: 16),
        ),
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
                          : VideoViewer(trimmer: _trimmer),
                ),
                if (!_isLoadingVideo && !_loadFailed) ...[
                  _buildVisibleTimeline(),
                  TextButton(
                    child: _isPlaying
                        ? const Icon(Icons.pause, size: 60.0, color: Colors.white)
                        : const Icon(Icons.play_arrow, size: 60.0, color: Colors.white),
                    onPressed: () async {
                      try {
                        final playbackState = await _trimmer.videoPlaybackControl(
                          startValue: _startValue,
                          endValue: _endValue,
                        );
                        if (mounted) setState(() => _isPlaying = playbackState);
                      } catch (e) {
                        debugPrint('[VideoTrimScreen] playback error: $e');
                      }
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
