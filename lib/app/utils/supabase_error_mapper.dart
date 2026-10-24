import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../theme/text_styles.dart';

class AppError {
  final String title;
  final String message;
  final IconData icon;
  final bool isIdempotentSuccess;

  const AppError({
    required this.title,
    required this.message,
    this.icon = Icons.error_outline_rounded,
    this.isIdempotentSuccess = false,
  });
}

AppError mapSupabaseError(dynamic error) {
  final raw = error.toString().toLowerCase();

  // Network/DNS/offline failures must never expose raw technical exceptions.
  if (_isNetworkError(raw)) {
    return AppError(
      title: 'Pas de connexion Internet',
      message: 'Vérifie ta connexion Internet, puis réessaie. Tes données ne sont pas perdues.',
      icon: Icons.wifi_off_rounded,
    );
  }
  if (raw.contains('timeout') || raw.contains('timed out') || raw.contains('deadline exceeded')) {
    return AppError(
      title: 'Délai dépassé',
      message: 'Le serveur met trop de temps à répondre. Vérifie ta connexion et réessaie.',
      icon: Icons.hourglass_disabled_rounded,
    );
  }
  if (raw.contains('socketexception') ||
      raw.contains('failed host lookup') ||
      raw.contains('connection refused') ||
      raw.contains('connection reset') ||
      raw.contains('network is unreachable') ||
      raw.contains('no address associated with hostname') ||
      raw.contains('websocketchannel')) {
    return AppError(
      title: 'Connexion au serveur impossible',
      message: 'Scrole ne parvient pas à joindre le serveur. Vérifie Internet et réessaie.',
      icon: Icons.cloud_off_rounded,
    );
  }
  if (raw.contains('invalid login credentials') || raw.contains('invalid_credentials')) {
    return AppError(
      title: 'Identifiants incorrects',
      message: 'Les informations de connexion sont incorrectes. Vérifie-les et réessaie.',
      icon: Icons.lock_outline_rounded,
    );
  }
  if (raw.contains('email not confirmed') || raw.contains('email_not_confirmed')) {
    return AppError(
      title: 'Adresse e-mail non confirmée',
      message: 'Confirme ton adresse e-mail avant de te connecter.',
      icon: Icons.mark_email_unread_outlined,
    );
  }
  if (raw.contains('user already registered') || raw.contains('already registered')) {
    return AppError(
      title: 'Compte déjà existant',
      message: 'Un compte existe déjà avec ces informations. Essaie de te connecter.',
      icon: Icons.person_outline_rounded,
    );
  }
  if (raw.contains('jwt expired') || raw.contains('token is expired') || raw.contains('refresh_token_not_found')) {
    return AppError(
      title: 'Session expirée',
      message: 'Ta session a expiré. Reconnecte-toi pour continuer.',
      icon: Icons.lock_clock_outlined,
    );
  }
  if (raw.contains('permission denied') || raw.contains('row-level security') ||
      raw.contains('violates row-level security') || raw.contains('42501')) {
    return AppError(
      title: 'Action non autorisée',
      message: 'Tu n’as pas les autorisations nécessaires pour effectuer cette action.',
      icon: Icons.lock_outline_rounded,
    );
  }
  if (raw.contains('duplicate key') || raw.contains('23505') || raw.contains('already exists')) {
    return AppError(
      title: 'Élément déjà existant',
      message: 'Cette information existe déjà. Vérifie les données saisies.',
      icon: Icons.content_copy_rounded,
    );
  }
  if (raw.contains('foreign key') || raw.contains('23503')) {
    return AppError(
      title: 'Action impossible',
      message: 'Un élément nécessaire est introuvable ou n’est plus disponible. Actualise la page et réessaie.',
      icon: Icons.link_off_rounded,
    );
  }
  if (raw.contains('not-null constraint') || raw.contains('23502') ||
      raw.contains('check constraint') || raw.contains('23514') ||
      raw.contains('invalid input syntax') || raw.contains('22p02')) {
    return AppError(
      title: 'Données invalides',
      message: 'Certaines informations sont manquantes ou incorrectes. Vérifie les champs et réessaie.',
      icon: Icons.rule_rounded,
    );
  }
  if (raw.contains('too many requests') || raw.contains('429') || raw.contains('rate limit')) {
    return AppError(
      title: 'Trop de tentatives',
      message: 'Tu as effectué trop de demandes en peu de temps. Patiente un instant avant de réessayer.',
      icon: Icons.timer_rounded,
    );
  }
  if (raw.contains('500') || raw.contains('502') || raw.contains('503') ||
      raw.contains('504') || raw.contains('internal server error') ||
      raw.contains('service unavailable') || raw.contains('bad gateway')) {
    return AppError(
      title: 'Service temporairement indisponible',
      message: 'Le serveur rencontre un problème temporaire. Réessaie dans quelques instants.',
      icon: Icons.cloud_off_rounded,
    );
  }

  if (raw.contains('rate limit') || raw.contains('5 posts') || raw.contains('10 min')) {
    return AppError(title: 'Erreur', message: 'post_error_rate_limit'.tr, icon: Icons.timer_rounded);
  }
  if (raw.contains('video') || raw.contains('vidéo') || raw.contains('not supported')) {
    return AppError(title: 'Erreur', message: 'post_error_videos_not_supported'.tr, icon: Icons.videocam_off_rounded);
  }
  if (raw.contains('invalid photo') || raw.contains('photo invalide')) {
    return AppError(title: 'Erreur', message: 'post_error_invalid_photo'.tr, icon: Icons.broken_image_rounded);
  }
  if (raw.contains('max 4') || raw.contains('4 photos')) {
    return AppError(title: 'Erreur', message: 'post_error_max_photos'.tr, icon: Icons.photo_library_rounded);
  }
  if (raw.contains('text') || raw.contains('media') || raw.contains('required') || raw.contains('requis')) {
    return AppError(title: 'Erreur', message: 'post_error_text_media_required'.tr, icon: Icons.edit_note_rounded);
  }
  if (raw.contains('5000') || raw.contains('char') || raw.contains('caractère')) {
    return AppError(title: 'Erreur', message: 'post_error_max_chars'.tr, icon: Icons.text_fields_rounded);
  }
  if (raw.contains('audience') || raw.contains('invalid_audience')) {
    return AppError(title: 'Erreur', message: 'post_error_invalid_audience'.tr, icon: Icons.group_rounded);
  }
  if (raw.contains('account') || raw.contains('unavailable') || raw.contains('indisponible')) {
    return AppError(title: 'Erreur', message: 'post_error_account_unavailable'.tr, icon: Icons.person_off_rounded);
  }
  if (raw.contains('member') || raw.contains('membre')) {
    return AppError(title: 'Erreur', message: 'post_error_members_only'.tr, icon: Icons.lock_rounded);
  }
  if (raw.contains('comment') || raw.contains('reaction') || raw.contains('disabled') || raw.contains('désactivé')) {
    return AppError(title: 'Erreur', message: 'post_error_comments_reactions_disabled'.tr, icon: Icons.block_rounded);
  }
  if (raw.contains('poll') || raw.contains('sondage')) {
    return AppError(title: 'Erreur', message: 'post_error_poll'.tr, icon: Icons.poll_rounded);
  }

  if (raw.contains('pas enregistrée') ||
      raw.contains('non enregistré') ||
      raw.contains('pas enregistre') ||
      raw.contains('not_registered') ||
      raw.contains('not registered') ||
      raw.contains('pas inscrit') ||
      raw.contains('non inscrit')) {
    return AppError(
      title: 'checkin_not_registered_title'.tr,
      message: 'checkin_not_registered_msg'.tr,
      icon: Icons.person_off_rounded,
    );
  }

  if (raw.contains('vous ne pouvez pas scanner votre propre qr code')) {
    return const AppError(
      title: 'Ce QR code est le tien',
      message: 'Tu ne peux pas t\'ajouter toi-même. Demande à quelqu\'un d\'autre de scanner ton QR code, ou scanne le sien.',
      icon: Icons.qr_code_2_rounded,
    );
  }

  if (raw.contains('qr code introuvable')) {
    return const AppError(
      title: 'QR code introuvable',
      message: 'Ce code ne correspond à aucun QR Scrole valide. Réessaie en cadrant mieux le code.',
      icon: Icons.qr_code_scanner_rounded,
    );
  }

  if (raw.contains('ce qr code n\'est plus valide') || raw.contains('qr code expiré')) {
    return const AppError(
      title: 'QR code expiré',
      message: 'Ce QR code a déjà été utilisé le nombre de fois maximum. Demande un nouveau code à cette personne.',
      icon: Icons.history_rounded,
    );
  }

  if (raw.contains('déjà ami') || raw.contains('vous êtes déjà ami(e)')) {
    return const AppError(
      title: 'Déjà amis',
      message: 'Vous êtes déjà connectés avec cet utilisateur.',
      icon: Icons.check_circle_rounded,
      isIdempotentSuccess: true,
    );
  }

  if (raw.contains('une demande est déjà en attente')) {
    return const AppError(
      title: 'Demande déjà en attente',
      message: 'Une demande d\'ami a déjà été envoyée à cet utilisateur.',
      icon: Icons.hourglass_top_rounded,
      isIdempotentSuccess: true,
    );
  }

  if (raw.contains('vous devez attendre le')) {
    return const AppError(
      title: 'Délai d\'attente requis',
      message: 'Une demande précédente a été refusée. Veuillez patienter avant d\'envoyer une nouvelle demande.',
      icon: Icons.schedule_rounded,
    );
  }

  if (raw.contains('droit') || raw.contains('réservé') || raw.contains('privilège') || raw.contains('42501')) {
    return const AppError(
      title: 'Action non autorisée',
      message: 'Vous ne disposez pas des permissions requises pour réaliser cette action.',
      icon: Icons.lock_outline_rounded,
    );
  }

  if (raw.contains('en cours de suppression') || raw.contains('pending_deletion')) {
    if (raw.contains('annuler') || raw.contains('cancel')) {
      return const AppError(
        title: 'Activité en cours de suppression',
        message: 'Impossible d\'annuler cette demande de transfert : l\'activité est en cours de suppression. Annulez d\'abord la demande de suppression de l\'activité.',
        icon: Icons.warning_amber_rounded,
      );
    }
    return const AppError(
      title: 'Activité en cours de suppression',
      message: 'Cette activité est en cours de suppression. Contactez son propriétaire actuel afin qu\'il annule la demande de suppression. La suppression dispose de 30 jours avant sa suppression définitive.',
      icon: Icons.warning_amber_rounded,
    );
  }

  if (raw.contains('active') && (raw.contains('transfer') || raw.contains('transfert'))) {
    return const AppError(
      title: 'Transfert impossible',
      message: 'L\'activité doit être au statut "Active" pour pouvoir proposer un transfert de propriété.',
      icon: Icons.info_outline_rounded,
    );
  }

  // Unknown exceptions are logged by the caller in debug mode; never show
  // raw PostgreSQL, SQL, stack traces, hostnames or internal implementation.
  return AppError(
    title: 'Une erreur est survenue',
    message: 'Une erreur inattendue est survenue. Réessaie dans quelques instants. Si le problème persiste, contacte le support Scrole.',
    icon: Icons.error_outline_rounded,
  );
}

bool _isNetworkError(String raw) {
  return raw.contains('socketexception') ||
      raw.contains('failed host lookup') ||
      raw.contains('no address associated with hostname') ||
      raw.contains('network is unreachable') ||
      raw.contains('connection refused') ||
      raw.contains('connection reset') ||
      raw.contains('network request failed') ||
      raw.contains('websocketchannel') ||
      raw.contains('clientexception') ||
      raw.contains('xmlhttprequest error') ||
      raw.contains('failed to fetch') ||
      raw.contains('errno = 7') ||
      raw.contains('errno 7');
}

void showAppErrorDialog(BuildContext context, dynamic error) {
  final appError = mapSupabaseError(error);

  if (appError.isIdempotentSuccess) {
    Get.snackbar(
      appError.title,
      appError.message,
      backgroundColor: Colors.green,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(16),
      borderRadius: 12,
    );
    return;
  }

  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(appError.icon, color: AppColors.error, size: 36),
            ),
            const SizedBox(height: 16),
            Text(
              appError.title,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              appError.message,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size(double.infinity, 46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Compris', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    ),
  );
}
