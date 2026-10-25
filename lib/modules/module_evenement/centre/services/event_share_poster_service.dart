import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../models/event_preview_model.dart';
import '../repositories/event_repository.dart';
import '../../interne/widgets/event_share_poster_widget.dart';

class EventSharePosterService {
  EventSharePosterService._();

  static bool _isGenerating = false;

  static Future<void> shareEventPoster({
    required BuildContext context,
    required EventPreviewModel preview,
    required EventRepository repository,
    Function(int newShareCount)? onShareSuccess,
  }) async {
    if (_isGenerating) return;
    if (!preview.canShare) {
      debugPrint('[EventSharePosterService] User not authorized to share this event.');
      return;
    }

    _isGenerating = true;

    // Afficher l'indicateur de génération
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Row(
              children: [
                const CircularProgressIndicator(color: AppColors.primary),
                const SizedBox(width: 20),
                Expanded(
                  child: Text(
                    'Génération de l\'affiche...',
                    style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    OverlayEntry? overlayEntry;
    try {
      final boundaryKey = GlobalKey();

      // Rendu hors écran de l'affiche via OverlayEntry
      overlayEntry = OverlayEntry(
        builder: (_) => Positioned(
          left: -9999,
          top: -9999,
          child: Material(
            color: Colors.transparent,
            child: RepaintBoundary(
              key: boundaryKey,
              child: EventSharePosterWidget(preview: preview),
            ),
          ),
        ),
      );

      Overlay.of(context).insert(overlayEntry);

      // Laisser le temps au moteur Flutter de disposer et peindre le widget hors écran
      await Future.delayed(const Duration(milliseconds: 400));

      final boundary = boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('RepaintBoundary context null');
      }

      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      overlayEntry.remove();
      overlayEntry = null;

      if (byteData == null) {
        throw Exception('ByteData PNG conversion failed');
      }

      final Uint8List pngBytes = byteData.buffer.asUint8List();

      // Écriture du fichier temporaire
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/event_poster_${preview.event.id}.png';
      final file = File(filePath);
      await file.writeAsBytes(pngBytes, flush: true);

      // Fermeture du dialogue de progression avant d'ouvrir la feuille de partage native
      if (context.mounted && Navigator.canPop(context)) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      // Ouverture du système de partage natif (WhatsApp, Instagram, etc.)
      final eventLink = 'https://scrole.fun/event/${Uri.encodeComponent(preview.event.id)}';
      final shareText = 'Participe à ${preview.event.name} avec Scrole !\n\n$eventLink';
      final result = await Share.shareXFiles(
        [XFile(file.path)],
        text: shareText,
        subject: preview.event.name,
      );

      // Une fois le partage déclenché, appel de la RPC share_event pour incrémenter le compteur
      if (result.status == ShareResultStatus.success || result.status == ShareResultStatus.dismissed) {
        final newCount = await repository.shareEvent(preview.event.id);
        if (newCount != null && onShareSuccess != null) {
          onShareSuccess(newCount);
        }
      }
    } catch (e, stack) {
      debugPrint('[EventSharePosterService] Error generating/sharing poster: $e');
      debugPrint('$stack');

      if (overlayEntry != null) {
        overlayEntry.remove();
        overlayEntry = null;
      }

      if (context.mounted && Navigator.canPop(context)) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Impossible de générer l\'affiche pour le moment. Veuillez réessayer.',
              style: AppTextStyles.bodySmall.copyWith(color: Colors.white),
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      _isGenerating = false;
    }
  }
}
