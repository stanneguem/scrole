import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/text_styles.dart';
import 'image_source_sheet.dart';

/// Bloc bannière + avatar façon Facebook : la bannière occupe toute la
/// largeur, l'avatar est un cercle positionné en bas, chevauchant
/// légèrement le bas de la bannière, détaché par un liseré de la couleur
/// de fond.
class CoverAvatarPicker extends StatelessWidget {
  const CoverAvatarPicker({
    super.key,
    required this.bannerImage,
    required this.avatarImage,
    required this.onBannerCamera,
    required this.onBannerGallery,
    required this.onBannerRemove,
    required this.onAvatarCamera,
    required this.onAvatarGallery,
    required this.onAvatarRemove,
    this.bannerHeight = 150,
    this.avatarDiameter = 96,
  });

  final File? bannerImage;
  final File? avatarImage;

  final VoidCallback onBannerCamera;
  final VoidCallback onBannerGallery;
  final VoidCallback onBannerRemove;

  final VoidCallback onAvatarCamera;
  final VoidCallback onAvatarGallery;
  final VoidCallback onAvatarRemove;

  final double bannerHeight;
  final double avatarDiameter;

  @override
  Widget build(BuildContext context) {
    // L'avatar chevauche la bannière de la moitié de son diamètre : on
    // réserve cet espace sous le Stack pour ne rien tronquer.
    final overlap = avatarDiameter / 2;

    return Padding(
      padding: EdgeInsets.only(bottom: overlap + 4),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // --- Bannière ---
          Container(
            height: bannerHeight,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: .05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
              image: bannerImage != null
                  ? DecorationImage(
                      image: FileImage(bannerImage!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: InkWell(
              onTap: () => showImageSourceSheet(
                context,
                onCamera: onBannerCamera,
                onGallery: onBannerGallery,
                onRemove: bannerImage != null ? onBannerRemove : null,
              ),
              borderRadius: BorderRadius.circular(16),
              child: bannerImage == null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.image_outlined,
                          color: AppColors.textSecondary,
                          size: 26,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'community_banner_hint'.tr,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    )
                  : Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: _EditBadge(
                          onTap: () => showImageSourceSheet(
                            context,
                            onCamera: onBannerCamera,
                            onGallery: onBannerGallery,
                            onRemove: onBannerRemove,
                          ),
                        ),
                      ),
                    ),
            ),
          ),

          // --- Avatar, chevauchant en bas à gauche de la bannière ---
          Positioned(
            left: 16,
            bottom: -overlap,
            child: InkWell(
              onTap: () => showImageSourceSheet(
                context,
                onCamera: onAvatarCamera,
                onGallery: onAvatarGallery,
                onRemove: avatarImage != null ? onAvatarRemove : null,
              ),
              borderRadius: BorderRadius.circular(avatarDiameter / 2 + 4),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  // Reprend la couleur de fond de la page pour détacher
                  // visuellement l'avatar de la bannière, comme sur FB.
                  color: AppColors.background,
                ),
                child: Container(
                  width: avatarDiameter,
                  height: avatarDiameter,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withValues(alpha: .08),
                    border: Border.all(color: AppColors.border),
                    image: avatarImage != null
                        ? DecorationImage(
                            image: FileImage(avatarImage!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: Stack(
                    children: [
                      if (avatarImage == null)
                        Center(
                          child: Icon(
                            Icons.person_outline,
                            color: AppColors.textSecondary,
                            size: avatarDiameter * 0.4,
                          ),
                        ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: _EditBadge(small: true, onTap: () {}),
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

class _EditBadge extends StatelessWidget {
  const _EditBadge({required this.onTap, this.small = false});

  final VoidCallback onTap;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final size = small ? 24.0 : 28.0;
    return IgnorePointer(
      // Purement visuel : le tap est géré par l'InkWell parent (bannière
      // ou avatar) pour garder une seule zone tappable cohérente.
      child: CircleAvatar(
        radius: size / 2,
        backgroundColor: Colors.black54,
        child: Icon(Icons.camera_alt, size: size * 0.5, color: Colors.white),
      ),
    );
  }
}
