import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:get/get.dart';

import '../../shared/widgets/media_gallery_sheet.dart';

class MediaService extends GetxService {
  final ImagePicker _picker = ImagePicker();

  Future<XFile?> _pickGalleryImage() async {
    final context = Get.context;
    if (context == null) return _picker.pickImage(source: ImageSource.gallery);

    return ScroleBottomSheetGallery.pick(context);
  }

  Future<File?> pickImage({ImageSource source = ImageSource.gallery}) async {
    final XFile? pickedFile = source == ImageSource.gallery
        ? await _pickGalleryImage()
        : await _picker.pickImage(source: source);
    if (pickedFile == null) return null;
    return File(pickedFile.path);
  }

  Future<File?> cropImage(File imageFile, {bool circle = false}) async {
    final croppedFile = await ImageCropper().cropImage(
      sourcePath: imageFile.path,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Redimensionner',
          toolbarColor: const Color(0xFFEB5E28),
          statusBarColor: Colors.black,
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: const Color(0xFFEB5E28),
          initAspectRatio: circle ? CropAspectRatioPreset.square : CropAspectRatioPreset.original,
          lockAspectRatio: circle,
        ),
        IOSUiSettings(
          title: 'Redimensionner',
          doneButtonTitle: 'Terminer',
          cancelButtonTitle: 'Annuler',
        ),
      ],
    );
    if (croppedFile == null) return null;
    return File(croppedFile.path);
  }

  Future<File?> compressImage(File file, {int quality = 80}) async {
    final tempDir = await getTemporaryDirectory();
    final targetPath = p.join(tempDir.path, "${DateTime.now().millisecondsSinceEpoch}.jpg");
    final result = await FlutterImageCompress.compressAndGetFile(file.absolute.path, targetPath, quality: quality);
    if (result == null) return null;
    return File(result.path);
  }

  Future<File?> pickProfileImage({ImageSource source = ImageSource.gallery}) async {
    final picked = await pickImage(source: source);
    if (picked == null) return null;
    final cropped = await cropImage(picked, circle: true);
    if (cropped == null) return null;
    return await compressImage(cropped);
  }

  Future<File?> pickCoverImage({ImageSource source = ImageSource.gallery}) async {
    final picked = await pickImage(source: ImageSource.gallery);
    if (picked == null) return null;
    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Recadrer la couverture',
          toolbarColor: const Color(0xFFEB5E28),
          statusBarColor: Colors.black,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.ratio16x9,
          lockAspectRatio: true,
        ),
        IOSUiSettings(title: 'Recadrer', aspectRatioLockEnabled: true),
      ],
    );
    if (cropped == null) return null;
    return await compressImage(File(cropped.path));
  }
}

/// Adapter permettant au MediaService d'utiliser la galerie interne sans
/// exposer sa mécanique aux contrôleurs.
class ScroleBottomSheetGallery {
  static Future<XFile?> pick(BuildContext context) async {
    final result = await showModalBottomSheet<List<XFile>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => MediaGallerySheet(
        maxSelection: 1,
        onSelected: (files) => Navigator.of(context).pop(files),
      ),
    );

    if (result != null && result.isNotEmpty) {
      return result.first;
    }
    return null;
  }
}
