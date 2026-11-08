import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../centre/models/event_preview_model.dart';

/// Story-first event share artwork. The visual adapts to the app's current theme.
class EventSharePosterWidget extends StatelessWidget {
  final EventPreviewModel preview;
  final bool isAttending;
  final String? profilePhotoUrl;
  final Brightness brightness;

  const EventSharePosterWidget({
    super.key,
    required this.preview,
    required this.isAttending,
    required this.profilePhotoUrl,
    required this.brightness,
  });

  @override
  Widget build(BuildContext context) {
    final event = preview.event;
    final dark = brightness == Brightness.dark;
    final background = dark ? const Color(0xFF10131D) : const Color(0xFFF5F2EC);
    final foreground = dark ? const Color(0xFFF9FAFB) : const Color(0xFF171923);
    final muted = dark ? const Color(0xFFCFD2DC) : const Color(0xFF555968);
    final accent = const Color(0xFF8067F2);
    final start = event.startsAt.toLocal();
    final end = event.endsAt?.toLocal();
    final locale = Intl.getCurrentLocale();
    final date = DateFormat('EEE d MMM', locale).format(start);
    final time = DateFormat('HH:mm', locale).format(start);
    final dateLabel = end == null
        ? '$date · $time'
        : '$date · $time — ${DateFormat('EEE d MMM · HH:mm', locale).format(end)}';
    final place = event.locationDisplay.trim();

    Widget heroImage() {
      final imageUrl = isAttending ? (profilePhotoUrl ?? '').trim() : (event.coverImageUrl ?? '').trim();
      if (imageUrl.isEmpty) {
        return Container(
          color: dark ? const Color(0xFF28253D) : const Color(0xFFE6E0F3),
          alignment: Alignment.center,
          child: Icon(
            isAttending ? Icons.person_rounded : Icons.event_rounded,
            size: 120,
            color: accent.withValues(alpha: .8),
          ),
        );
      }
      return Image.network(
        imageUrl,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          color: dark ? const Color(0xFF28253D) : const Color(0xFFE6E0F3),
          alignment: Alignment.center,
          child: Icon(
            isAttending ? Icons.person_rounded : Icons.event_rounded,
            size: 120,
            color: accent.withValues(alpha: .8),
          ),
        ),
      );
    }

    return Container(
      width: 540,
      height: 960,
      color: background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 640,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(42)),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  heroImage(),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: .36),
                          Colors.transparent,
                          Colors.black.withValues(alpha: .78),
                        ],
                        stops: const [0, .38, 1],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 34,
                    right: 34,
                    top: 48,
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: .32),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: Colors.white.withValues(alpha: .22)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SvgPicture.asset(
                                'assets/svg_icons/logo.svg',
                                width: 25,
                                height: 25,
                                colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                              ),
                              const SizedBox(width: 9),
                              Text(
                                'SCROLE',
                                style: GoogleFonts.spaceGrotesk(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 2.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        if (isAttending)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
                            decoration: BoxDecoration(
                              color: accent,
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Text(
                              'event_share_attending_badge'.tr.toUpperCase(),
                              style: GoogleFonts.spaceGrotesk(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: .8,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 38,
                    right: 38,
                    bottom: 42,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isAttending
                              ? 'event_share_attending_intro'.tr
                              : 'event_share_discovery_intro'.tr,
                          style: GoogleFonts.spaceGrotesk(
                            color: Colors.white.withValues(alpha: .92),
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            letterSpacing: .3,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          event.name,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.spaceGrotesk(
                            color: Colors.white,
                            fontSize: 43,
                            height: 1.04,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 38,
            right: 38,
            bottom: 50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.calendar_month_rounded, color: accent, size: 25),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Text(
                        dateLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.spaceGrotesk(
                          color: foreground,
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                if (place.isNotEmpty) ...[
                  const SizedBox(height: 19),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.location_on_rounded, color: accent, size: 25),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Text(
                          place,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.spaceGrotesk(
                            color: muted,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 27),
                Container(
                  height: 2,
                  width: 66,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 17),
                Text(
                  'event_share_footer'.tr,
                  style: GoogleFonts.spaceGrotesk(
                    color: muted.withValues(alpha: .85),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: .3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
