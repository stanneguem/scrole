import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:scrole/shared/models/chat_message.dart'
    as legacy;
import '../../centre/repositories/messaging_repository.dart';
import '../../centre/services/chat_media_cache.dart';

class DirectVoiceMessagePlayer extends StatefulWidget {
  final legacy.VoiceMessage voiceMessage;
  final String? audioPath;
  final String? messageId;
  final bool isMine;
  const DirectVoiceMessagePlayer({
    super.key,
    required this.voiceMessage,
    this.audioPath,
    this.messageId,
    this.isMine = false,
  });
  @override
  State<DirectVoiceMessagePlayer> createState() =>
      _DirectVoiceMessagePlayerState();
}

class _DirectVoiceMessagePlayerState extends State<DirectVoiceMessagePlayer> {
  AudioPlayer? _player;
  bool _loading = false;
  bool _initialized = false;
  String? _error;
  Future<void> _loadAndPlay() async {
    if (_loading) return;
    final path = widget.audioPath ?? widget.voiceMessage.url;
    if (path == null || path.isEmpty) return;
    setState(() => _loading = true);
    _error = null;
    try {
      String? playable;
      if (Get.isRegistered<MessagingRepository>()) {
        final result = await Get.find<MessagingRepository>().cacheMedia(widget.messageId ?? '', path);
        if (result.success && result.data != null && result.data!.isNotEmpty) {
          playable = result.data;
        }
      }
      playable ??= await ChatMediaCache.instance.resolveLocalPath(path);
      if (playable == null || playable.isEmpty) {
        throw Exception('Impossible de télécharger cet audio');
      }
      final player = _player ??= AudioPlayer();
      if (playable.startsWith('http://') || playable.startsWith('https://')) {
        await player.setUrl(playable);
      } else {
        await player.setFilePath(playable);
      }
      _initialized = true;
      if (mounted) setState(() => _loading = false);
      await player.play();
    } catch (e) {
      debugPrint('[DirectVoiceMessagePlayer] load failed: $e');
      if (mounted)
        setState(() {
          _loading = false;
          _error = 'Impossible de télécharger cet audio';
        });
    }
  }

  Future<void> _togglePlay() async {
    if (!_initialized) {
      await _loadAndPlay();
      return;
    }
    final p = _player;
    if (p == null) return;
    if (p.playing)
      await p.pause();
    else {
      if (p.processingState == ProcessingState.completed)
        await p.seek(Duration.zero);
      await p.play();
    }
  }

  Future<void> _seek(double value) async {
    final p = _player;
    if (p == null || !_initialized) return;
    final d = p.duration;
    if (d == null || d == Duration.zero) return;
    await p.seek(d * value.clamp(0.0, 1.0));
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = colors.brightness == Brightness.dark;
    final bubbleColor = widget.isMine
        ? colors.primary
        : (dark ? const Color(0xFF20262D) : const Color(0xFFF2F4F5));
    final secondary = widget.isMine
        ? colors.onPrimary.withOpacity(.62)
        : colors.onSurfaceVariant.withOpacity(.58);
    final wi = widget.isMine
        ? colors.onPrimary.withOpacity(.30)
        : colors.onSurface.withOpacity(.15);
    final wa = widget.isMine ? colors.onPrimary : colors.primary;
    return Align(
      alignment: widget.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(minWidth: 250, maxWidth: 330),
        padding: const EdgeInsets.fromLTRB(9, 9, 12, 8),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(19),
            topRight: const Radius.circular(19),
            bottomLeft: Radius.circular(widget.isMine ? 19 : 6),
            bottomRight: Radius.circular(widget.isMine ? 6 : 19),
          ),
        ),
        child: _error != null
            ? _errorView(colors)
            : _player == null
            ? _idle(colors, secondary, wi, wa)
            : _active(colors, secondary, wi, wa),
      ),
    );
  }

  Widget _errorView(ColorScheme colors) => Row(
    children: [
      Icon(Icons.cloud_off_rounded, color: colors.onSurfaceVariant),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          _error!,
          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
        ),
      ),
    ],
  );
  Widget _idle(ColorScheme c, Color s, Color wi, Color wa) => Row(
    children: [
      _button(c, loading: _loading, playing: false),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _wave(wa, wi, 0, false),
            const SizedBox(height: 4),
            Text(
              _displayDuration(),
              style: TextStyle(
                color: s,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ],
  );
  Widget _active(ColorScheme c, Color s, Color wi, Color wa) {
    final p = _player!;
    return StreamBuilder<PlayerState>(
      stream: p.playerStateStream,
      builder: (context, ss) {
        final st = ss.data;
        final playing = st?.playing ?? false;
        final processing = st?.processingState;
        final loading =
            _loading ||
            processing == ProcessingState.loading ||
            processing == ProcessingState.buffering;
        return StreamBuilder<Duration?>(
          stream: p.durationStream,
          builder: (context, ds) {
            final d = ds.data ?? Duration.zero;
            return StreamBuilder<Duration>(
              stream: p.positionStream,
              builder: (context, ps) {
                final pos = ps.data ?? Duration.zero;
                final progress = d.inMilliseconds > 0
                    ? (pos.inMilliseconds / d.inMilliseconds).clamp(0.0, 1.0)
                    : 0.0;
                return Row(
                  children: [
                    _button(
                      c,
                      loading: loading,
                      playing:
                          playing && processing != ProcessingState.completed,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapDown: (details) {
                              final width = context.size?.width ?? 1;
                              _seek(details.localPosition.dx / width);
                            },
                            child: _wave(wa, wi, progress, true),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _format(pos),
                                style: TextStyle(
                                  color: s,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                d == Duration.zero
                                    ? _displayDuration()
                                    : _format(d),
                                style: TextStyle(
                                  color: s,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _button(
    ColorScheme c, {
    required bool loading,
    required bool playing,
  }) => Material(
    color: c.surface,
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: loading ? null : _togglePlay,
      child: SizedBox(
        width: 39,
        height: 39,
        child: Center(
          child: loading
              ? SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.primary,
                  ),
                )
              : Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: c.primary,
                  size: 24,
                ),
        ),
      ),
    ),
  );
  Widget _wave(Color active, Color inactive, double progress, bool enabled) =>
      SizedBox(
        height: 31,
        width: double.infinity,
        child: CustomPaint(
          painter: _WavePainter(
            active: active,
            inactive: inactive,
            progress: enabled ? progress : 0,
          ),
        ),
      );
  String _displayDuration() {
    final raw = widget.voiceMessage.durationLabel.trim();
    if (raw.isEmpty) return '0:00';
    final seconds = int.tryParse(raw);
    if (seconds == null) return raw;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  String _format(Duration d) {
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }
}

class _WavePainter extends CustomPainter {
  final Color active;
  final Color inactive;
  final double progress;
  const _WavePainter({
    required this.active,
    required this.inactive,
    required this.progress,
  });
  static const heights = [
    .34,
    .58,
    .82,
    .50,
    .72,
    .96,
    .64,
    .42,
    .78,
    .58,
    .88,
    .48,
    .68,
    .92,
    .55,
    .76,
    .45,
    .70,
    .98,
    .62,
    .84,
    .50,
    .74,
    .90,
    .56,
    .40,
    .66,
    .86,
    .52,
    .76,
    .94,
    .60,
    .46,
    .72,
    .88,
    .54,
    .80,
    .44,
    .68,
    .92,
  ];
  @override
  void paint(Canvas canvas, Size size) {
    const gap = 2.1;
    final width = math.max(
      1.5,
      (size.width - gap * (heights.length - 1)) / heights.length,
    );
    final center = size.height / 2;
    final activeX = progress * size.width;
    final ip = Paint()
      ..color = inactive
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    final ap = Paint()
      ..color = active
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < heights.length; i++) {
      final x = i * (width + gap) + width / 2;
      final half = math.max(2.0, size.height * heights[i] * .48);
      canvas.drawLine(
        Offset(x, center - half),
        Offset(x, center + half),
        x <= activeX ? ap : ip,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) =>
      old.progress != progress ||
      old.active != active ||
      old.inactive != inactive;
}
