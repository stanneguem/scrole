import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../app/theme/app_colors.dart';
import '../controllers/direct_conversation_controller.dart';

class DirectVoiceRecorderPanel extends StatelessWidget {
  const DirectVoiceRecorderPanel({super.key, required this.controller});

  final DirectConversationController controller;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Obx(() {
      final state = controller.recordingState.value;
      if (state == RecordingState.idle) return const SizedBox.shrink();

      final reviewing = state == RecordingState.reviewing;
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          child: GestureDetector(
            onHorizontalDragUpdate: reviewing
                ? null
                : controller.onRecordingDragUpdate,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: colors.outline.withValues(alpha: .12),
                ),
                boxShadow: [
                  BoxShadow(
                    color: colors.shadow.withValues(alpha: .14),
                    blurRadius: 18,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _WaveformHeader(
                    controller: controller,
                    reviewing: reviewing,
                  ),
                  const SizedBox(height: 10),
                  _Controls(
                    controller: controller,
                    colors: colors,
                    reviewing: reviewing,
                  ),
                  if (!reviewing) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Glissez vers la gauche pour annuler',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.onSurfaceVariant.withValues(alpha: .7),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _WaveformHeader extends StatefulWidget {
  const _WaveformHeader({required this.controller, required this.reviewing});

  final DirectConversationController controller;
  final bool reviewing;

  @override
  State<_WaveformHeader> createState() => _WaveformHeaderState();
}

class _WaveformHeaderState extends State<_WaveformHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (!widget.reviewing) _animation.repeat();
  }

  @override
  void didUpdateWidget(covariant _WaveformHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reviewing) {
      _animation.stop();
    } else if (!_animation.isAnimating) {
      _animation.repeat();
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        Row(
          children: [
            Icon(
              widget.reviewing
                  ? Icons.graphic_eq_rounded
                  : Icons.mic_rounded,
              size: 18,
              color: AppColors.primary,
            ),
            const SizedBox(width: 8),
            Text(
              widget.reviewing ? 'Aperçu du message vocal' : 'Enregistrement vocal',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: colors.onSurface,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${widget.controller.recordingDuration.value}s',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 82,
          width: double.infinity,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ColoredBox(
              color: colors.surface.withValues(alpha: .5),
              child: AnimatedBuilder(
                animation: _animation,
                builder: (_, __) => CustomPaint(
                  painter: _RecordingWaveformPainter(
                    progress: _animation.value,
                    active: AppColors.primary,
                    inactive: colors.onSurfaceVariant.withValues(alpha: .22),
                    animated: !widget.reviewing,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.controller,
    required this.colors,
    required this.reviewing,
  });

  final DirectConversationController controller;
  final ColorScheme colors;
  final bool reviewing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ControlButton(
          icon: Icons.close_rounded,
          onTap: controller.cancelRecording,
          color: colors.onSurfaceVariant,
        ),
        const Spacer(),
        if (reviewing)
          Obx(
            () => _MainRecordButton(
              icon: controller.isPlayingReview.value
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              onTap: controller.playReview,
            ),
          )
        else
          _MainRecordButton(
            icon: Icons.mic_rounded,
            onTap: controller.stopRecording,
          ),
        const Spacer(),
        if (reviewing)
          _ControlButton(
            icon: Icons.send_rounded,
            onTap: controller.sendVoiceMessage,
            color: AppColors.primary,
          )
        else
          _ControlButton(
            icon: Icons.stop_rounded,
            onTap: controller.stopRecording,
            color: colors.onSurfaceVariant,
          ),
      ],
    );
  }
}

class _MainRecordButton extends StatelessWidget {
  const _MainRecordButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      elevation: 4,
      shadowColor: AppColors.primary.withValues(alpha: .28),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          width: 74,
          height: 58,
          child: Icon(icon, color: Colors.white, size: 25),
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({required this.icon, required this.onTap, required this.color});

  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: .08),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(icon, color: color, size: 23),
        ),
      ),
    );
  }
}

class _RecordingWaveformPainter extends CustomPainter {
  const _RecordingWaveformPainter({
    required this.progress,
    required this.active,
    required this.inactive,
    required this.animated,
  });

  final double progress;
  final Color active;
  final Color inactive;
  final bool animated;

  static const List<double> _heights = [
    .18, .28, .45, .7, .38, .62, .3, .52, .76, .4, .66, .25,
    .5, .32, .72, .46, .22, .58, .8, .35, .64, .42, .25, .55,
    .74, .34, .62, .45, .2, .5, .7, .3, .56, .78, .38, .62,
    .28, .48, .68, .34, .58, .76, .4, .24, .52, .72, .36, .6,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final spacing = size.width / _heights.length;
    final barWidth = math.max(2.0, spacing * .34);
    final activeUntil = animated
        ? (progress * _heights.length).floor()
        : _heights.length;

    for (var i = 0; i < _heights.length; i++) {
      final wave = animated
          ? (math.sin((progress * math.pi * 2) + i * .55) + 1) * .12
          : 0;
      final h = math.min(1.0, _heights[i] + wave);
      final barHeight = math.max(5.0, h * size.height * .72);
      final x = spacing * i + (spacing - barWidth) / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x + barWidth / 2, centerY),
          width: barWidth,
          height: barHeight,
        ),
        const Radius.circular(3),
      );
      canvas.drawRRect(
        rect,
        Paint()..color = i <= activeUntil ? active : inactive,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RecordingWaveformPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.active != active ||
      oldDelegate.inactive != inactive ||
      oldDelegate.animated != animated;
}
