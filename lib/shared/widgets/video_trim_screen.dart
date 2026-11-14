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

  @override
  void initState() {
    super.initState();
    _loadVideo();
  }

  Future<void> _loadVideo() async {
    try {
      await _trimmer.loadVideo(videoFile: widget.videoFile);
      if (mounted) setState(() => _isLoadingVideo = false);
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
            onPressed: _progressVisibility ? null : _saveVideo,
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
                  Center(
                    child: TrimViewer(
                      trimmer: _trimmer,
                      viewerHeight: 50.0,
                      viewerWidth: MediaQuery.of(context).size.width,
                      type: ViewerType.fixed,
                      maxVideoLength: widget.maxDuration,
                      onChangeStart: (value) => _startValue = value,
                      onChangeEnd: (value) => _endValue = value,
                      onChangePlaybackState: (value) {
                        if (mounted) setState(() => _isPlaying = value);
                      },
                    ),
                  ),
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
