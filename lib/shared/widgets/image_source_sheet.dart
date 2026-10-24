import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'scrole_bottom_sheet.dart';

Future<void> showImageSourceSheet(
  BuildContext context, {
  required VoidCallback onCamera,
  required VoidCallback onGallery,
  VoidCallback? onRemove,
}) async {
  if (onRemove == null) {
    // Directement ouvrir la galerie sans afficher de modal d'option
    onGallery();
    return;
  }

  // Si l'option de suppression est présente, n'afficher que Galerie et Supprimer (sans caméra)
  return ScroleBottomSheet.show<void>(
    context: context,
    showCancel: true,
    child: ScroleBottomSheetGroup(
      children: [
        ScroleBottomSheetAction(
          icon: Icons.photo_library_outlined,
          label: 'image_picker_choose_gallery'.tr,
          onTap: () {
            Navigator.of(context).pop();
            onGallery();
          },
        ),
        const ScroleBottomSheetDivider(),
        Builder(
          builder: (context) => ScroleBottomSheetAction(
            icon: Icons.delete_outline,
            label: 'image_picker_remove'.tr,
            color: Theme.of(context).colorScheme.error,
            onTap: () {
              Navigator.of(context).pop();
              onRemove();
            },
          ),
        ),
      ],
    ),
  );
}
