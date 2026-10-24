import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme/text_styles.dart';

class ScroleImageEditorScreen extends StatefulWidget {
  const ScroleImageEditorScreen({super.key, required this.file});

  final File file;

  @override
  State<ScroleImageEditorScreen> createState() => _ScroleImageEditorScreenState();
}

class _ScroleImageEditorScreenState extends State<ScroleImageEditorScreen> {
  late File _file;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _file = widget.file;
  }

  Future<void> _crop() async {
    setState(() => _isProcessing = true);
    try {
      final result = await ImageCropper().cropImage(
        sourcePath: _file.path,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Modifier la photo',
            toolbarColor: const Color(0xFFEB5E28),
            statusBarColor: Colors.black,
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: const Color(0xFFEB5E28),
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
            hideBottomControls: false,
          ),
          IOSUiSettings(
            title: 'Modifier la photo',
            doneButtonTitle: 'Valider',
            cancelButtonTitle: 'Annuler',
          ),
        ],
      );
      if (result != null && mounted) {
        setState(() => _file = File(result.path));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _validate() => Get.back(result: XFile(_file.path));

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: Text('Modifier la photo', style: AppTextStyles.h5),
        leading: IconButton(
          onPressed: _isProcessing ? null : Get.back,
          icon: const Icon(Icons.close_rounded),
        ),
        actions: [
          TextButton(
            onPressed: _isProcessing ? null : _validate,
            child: Text('Valider', style: AppTextStyles.buttonSmall.copyWith(color: colors.primary)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4,
                child: Image.file(_file, fit: BoxFit.contain),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isProcessing ? null : _crop,
                      icon: const Icon(Icons.crop_rounded),
                      label: const Text('Recadrer / ajuster'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filled(
                    onPressed: _isProcessing ? null : _validate,
                    icon: const Icon(Icons.check_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
