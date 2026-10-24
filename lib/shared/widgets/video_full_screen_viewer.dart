import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:video_player/video_player.dart';
import '../../app/theme/app_colors.dart';

class VideoFullScreenViewer extends StatefulWidget {
  final File? videoFile;
  final String? videoUrl;

  const VideoFullScreenViewer({super.key, this.videoFile, this.videoUrl});

  @override
  State<VideoFullScreenViewer> createState() => _VideoFullScreenViewerState();
}

class _VideoFullScreenViewerState extends State<VideoFullScreenViewer> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _controlsVisible = true;
  bool _showCenterIcon = false;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  Future<void> _initController() async {
    if (widget.videoUrl != null && widget.videoUrl!.isNotEmpty) {
      final isHttp = widget.videoUrl!.startsWith('http://') || widget.videoUrl!.startsWith('https://');
      if (isHttp) {
        _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl!));
      } else {
        final absolute = widget.videoUrl!.startsWith('file://') ? Uri.parse(widget.videoUrl!).toFilePath() : widget.videoUrl!;
        _controller = VideoPlayerController.file(File(absolute));
      }
    } else if (widget.videoFile != null) {
      _controller = VideoPlayerController.file(widget.videoFile!);
    } else {
      return;
    }

    try {
      await _controller.initialize();
      _duration = _controller.value.duration;
      _controller.addListener(_playerListener);
      setState(() => _isInitialized = true);
      _controller.play();
      setState(() => _isPlaying = true);
      _startHideTimer();
    } catch (e) {
      debugPrint('[VideoFullScreenViewer] init error: $e');
    }
  }

  void _playerListener() {
    if (!mounted) return;
    setState(() {
      _position = _controller.value.position;
      _isPlaying = _controller.value.isPlaying;
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller.removeListener(_playerListener);
    _controller.dispose();
    super.dispose();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (_isPlaying) {
      _hideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && _isPlaying) {
          setState(() => _controlsVisible = false);
        }
      });
    }
  }

  void _showControls() {
    setState(() => _controlsVisible = true);
    _startHideTimer();
  }

  void _togglePlay() {
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
        _hideTimer?.cancel();
        _controlsVisible = true;
      } else {
        _controller.play();
        _startHideTimer();
      }
      _showCenterIcon = true;
    });
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _showCenterIcon = false);
    });
  }

  Future<void> _seekTo(Duration target) async {
    _showControls();
    final wasPlaying = _controller.value.isPlaying;
    if (wasPlaying) {
      await _controller.pause();
    }
    final clamped = target > _duration ? _duration : (target < Duration.zero ? Duration.zero : target);
    await _controller.seekTo(clamped);
    if (wasPlaying) {
      await _controller.play();
      _startHideTimer();
    }
  }

  void _seekForward10s() {
    final target = _position + const Duration(seconds: 10);
    _seekTo(target);
  }

  void _seekBackward10s() {
    final target = _position - const Duration(seconds: 10);
    _seekTo(target);
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      final hours = d.inHours.toString().padLeft(2, '0');
      final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
      final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
      return '$hours:$minutes:$seconds';
    }
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Video Player occupying max space
          Center(
            child: _isInitialized
                ? SizedBox.expand(
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                        width: _controller.value.size.width > 0 ? _controller.value.size.width : 16.0,
                        height: _controller.value.size.height > 0 ? _controller.value.size.height : 9.0,
                        child: VideoPlayer(_controller),
                      ),
                    ),
                  )
                : const CircularProgressIndicator(color: AppColors.primary),
          ),

          // 3 Touch Zones (Left, Center, Right)
          if (_isInitialized)
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () {
                      _showControls();
                      _seekBackward10s();
                    },
                    child: const SizedBox.expand(),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () {
                      if (!_controlsVisible) {
                        _showControls();
                      } else {
                        _togglePlay();
                      }
                    },
                    child: Center(
                      child: AnimatedOpacity(
                        opacity: _controlsVisible && (!_isPlaying || _showCenterIcon) ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 48,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () {
                      _showControls();
                      _seekForward10s();
                    },
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ),

          // Top bar with close button (auto-hideable)
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 10,
            child: AnimatedOpacity(
              opacity: _controlsVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: IconButton(
                  onPressed: () => Get.back(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white, size: 30),
                ),
              ),
            ),
          ),

          // Bottom Timeline & Duration (auto-hideable, translucent, no thumb)
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 16,
            left: 16,
            right: 16,
            child: AnimatedOpacity(
              opacity: _controlsVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4.0, left: 2.0),
                        child: Text(
                          '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2.5,
                          thumbShape: SliderComponentShape.noThumb,
                          overlayShape: SliderComponentShape.noOverlay,
                          activeTrackColor: AppColors.primary,
                          inactiveTrackColor: Colors.white24,
                        ),
                        child: Slider(
                          value: _position.inMilliseconds.toDouble(),
                          min: 0.0,
                          max: _duration.inMilliseconds.toDouble() > 0 ? _duration.inMilliseconds.toDouble() : 1.0,
                          onChanged: (value) {
                            _seekTo(Duration(milliseconds: value.toInt()));
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
