import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:scrole/app/theme/app_colors.dart';
import 'package:scrole/shared/utils/number_formatter.dart';
import 'package:scrole/shared/widgets/app_cached_image.dart';
import 'package:scrole/shared/widgets/entity_certified_badge.dart';
import '../../centre/models/event_preview_model.dart';

/// Widget d'affiche promotionnelle événementielle (Format 9:16 Réseaux Sociaux).
class EventSharePosterWidget extends StatelessWidget {
  final EventPreviewModel preview;

  const EventSharePosterWidget({
    super.key,
    required this.preview,
  });

  @override
  Widget build(BuildContext context) {
    final event = preview.event;
    final cheapest = preview.cheapestTicket;
    final isFree = (cheapest == null || cheapest.converted.amount <= 0) && event.isFree;

    final priceText = isFree
        ? 'Gratuit'
        : (cheapest != null
            ? 'À partir de ${NumberFormatter.formatPrice(cheapest.converted.amount, cheapest.converted.symbol)}'
            : (event.isFree ? 'Gratuit' : event.priceDisplay));

    final dateStr = _formatFrenchDate(event.startsAt, event.endsAt);

    return Container(
      width: 540,
      height: 960,
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF0F172A), // Slate 900
            Color(0xFF1E1B4B), // Indigo 950
            Color(0xFF0F172A),
          ],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── HEADER: PARTICIPE À ───
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
                ),
                child: Text(
                  'PARTICIPE À L\'ÉVÉNEMENT',
                  style: GoogleFonts.spaceGrotesk(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              // Logo Scrole
              Row(
                children: [
                  SvgPicture.asset(
                    'assets/svg_icons/logo.svg',
                    width: 24,
                    height: 24,
                    colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Scrole',
                    style: GoogleFonts.spaceGrotesk(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ─── TITRE ÉVÉNEMENT ───
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  event.name,
                  style: GoogleFonts.spaceGrotesk(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              EntityCertifiedBadge(entityType: 'event', entityId: event.id, size: 24),
            ],
          ),

          const SizedBox(height: 20),

          // ─── VISUEL / COUVERTURE ───
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(26),
                ),
                child: event.coverImageUrl != null && event.coverImageUrl!.isNotEmpty
                    ? AppCachedImage(
                        imageUrl: event.coverImageUrl!,
                        fit: BoxFit.cover,
                      )
                    : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.event, size: 64, color: Colors.white.withValues(alpha: 0.3)),
                            const SizedBox(height: 12),
                            Text(
                              'Scrole Événement',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 16),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ─── CARTES INFO: DATE, LIEU, PRIX ───
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B).withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Column(
              children: [
                _PosterInfoRow(
                  icon: Icons.calendar_month_rounded,
                  iconColor: const Color(0xFF38BDF8),
                  text: dateStr,
                ),
                const Divider(height: 20, color: Colors.white12),
                _PosterInfoRow(
                  icon: Icons.location_on_rounded,
                  iconColor: const Color(0xFFF43F5E),
                  text: event.locationDisplay,
                ),
                const Divider(height: 20, color: Colors.white12),
                _PosterInfoRow(
                  icon: Icons.confirmation_number_rounded,
                  iconColor: const Color(0xFF10B981),
                  text: priceText,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ─── FOOTER BRANDING ───
          Center(
            child: Text(
              'Retrouve cet événement et d\'autres sur l\'application Scrole',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  String _formatFrenchDate(DateTime startsAt, DateTime? endsAt) {
    try {
      final startLocal = startsAt.toLocal();
      final dateStr = DateFormat('EEEE d MMMM yyyy', 'fr_FR').format(startLocal);
      final timeStr = DateFormat('HH:mm').format(startLocal);
      final capitalizedDate = dateStr.isNotEmpty ? dateStr[0].toUpperCase() + dateStr.substring(1) : dateStr;
      return '$capitalizedDate à $timeStr';
    } catch (_) {
      return DateFormat('dd/MM/yyyy HH:mm').format(startsAt);
    }
  }
}

class _PosterInfoRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String text;

  const _PosterInfoRow({
    required this.icon,
    required this.iconColor,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
