import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../centre/models/event_model.dart';
import '../../../../shared/widgets/entity_certified_badge.dart';

class UserPassScreen extends StatelessWidget {
  final EventModel event;
  const UserPassScreen({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final userId = Supabase.instance.client.auth.currentUser?.id ?? 'guest';
    final colors = Theme.of(context).colorScheme;
    
    // Le payload contient l'ID utilisateur et l'ID de l'événement
    // Dans une version sécurisée, ceci serait signé par une Edge Function
    final qrData = 'scrole_pass:user=$userId:event=${event.id}:ts=${DateTime.now().millisecondsSinceEpoch}';

    return Scaffold(
      backgroundColor: AppColors.primary,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(color: Colors.white),
      ),
      body: Column(
        children: [
          const SizedBox(height: 20),
          Text(
            'user_pass_title'.tr,
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  event.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              EntityCertifiedBadge(
                entityType: 'event',
                entityId: event.id,
                size: 18,
              ),
            ],
          ),
          const Spacer(),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 40),
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                QrImageView(
                  data: qrData,
                  version: QrVersions.auto,
                  size: 250.0,
                  foregroundColor: Colors.black,
                ),
                const SizedBox(height: 20),
                Text(
                  'user_pass_hint'.tr,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodySmall.copyWith(color: Colors.black54),
                ),
              ],
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(30.0),
            child: Column(
              children: [
                Text(
                  Supabase.instance.client.auth.currentUser?.email ?? '',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'user_pass_verified_identity'.tr,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
