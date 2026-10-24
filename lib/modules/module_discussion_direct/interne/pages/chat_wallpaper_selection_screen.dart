import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../../../../shared/widgets/media_gallery_sheet.dart';

class ChatWallpaperSelectionScreen extends StatefulWidget {
  const ChatWallpaperSelectionScreen({
    super.key,
    required this.initialWallpaper,
    required this.userName,
    required this.userColor,
    this.userAvatar,
    required this.onApply,
  });

  final String initialWallpaper;
  final String userName;
  final Color userColor;
  final String? userAvatar;
  final ValueChanged<String> onApply;

  @override
  State<ChatWallpaperSelectionScreen> createState() =>
      _ChatWallpaperSelectionScreenState();
}

class _ChatWallpaperSelectionScreenState
    extends State<ChatWallpaperSelectionScreen> {
  late String _selectedKey;
  String? _customPath;

  final List<Map<String, dynamic>> _presetWallpapers = [
    {'id': 'none', 'labelKey': 'wallpaper_none', 'path': null},
    {'id': 'fond1', 'labelKey': 'wallpaper_fond', 'number': '1', 'path': 'assets/message_fond/messsage_fond1.png'},
    {'id': 'fond2', 'labelKey': 'wallpaper_fond', 'number': '2', 'path': 'assets/message_fond/messsage_fond2.png'},
    {'id': 'fond3', 'labelKey': 'wallpaper_fond', 'number': '3', 'path': 'assets/message_fond/messsage_fond3.png'},
  ];

  @override
  void initState() {
    super.initState();
    _selectedKey = widget.initialWallpaper;
    if (_selectedKey.startsWith('custom:')) {
      _customPath = _selectedKey.substring(7);
      if (!File(_customPath!).existsSync()) {
        _customPath = null;
        _selectedKey = 'none';
      }
    }
  }

  /// Sauvegarde sécurisée dans le bac à sable (Sandbox) de l'application.
  /// Supprime le ou les anciens fichiers pour forcer un chemin unique réactif.
  Future<String> _saveCustomWallpaperToSandbox(String sourcePath) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final targetDir = Directory('${docsDir.path}/chat_wallpapers');
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final id = widget.userName.hashCode.abs().toString();

    // 1. Nettoyer les anciens fonds d'écran personnalisés pour cette conversation
    try {
      final list = targetDir.listSync();
      for (final entity in list) {
        if (entity is File && entity.path.contains('wallpaper_$id')) {
          await entity.delete();
        }
      }
    } catch (_) {}

    // 2. Générer un nom de fichier unique avec timestamp pour garantir que le chemin change
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final targetPath = '${targetDir.path}/wallpaper_${id}_$timestamp.jpg';

    // 3. Copier la nouvelle image sélectionnée dans le bac à sable
    final newFile = File(sourcePath);
    final savedFile = await newFile.copy(targetPath);
    return savedFile.path;
  }

  void _openInternalGallery() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MediaGallerySheet(
        maxSelection: 1,
        onSelected: (files) async {
          if (files.isNotEmpty) {
            final xfile = files.first;
            final savedPath = await _saveCustomWallpaperToSandbox(xfile.path);
            if (mounted) {
              setState(() {
                _customPath = savedPath;
                _selectedKey = 'custom:$savedPath';
              });
            }
          }
        },
      ),
    );
  }

  Widget _buildPreviewImage() {
    if (_selectedKey == 'none') {
      return Container(color: Theme.of(context).colorScheme.surface);
    }

    if (_selectedKey.startsWith('custom:')) {
      final path = _selectedKey.substring(7);
      final file = File(path);
      if (file.existsSync()) {
        return Image.file(
          file,
          key: ValueKey(path),
          fit: BoxFit.cover,
        );
      }
      return Container(color: Theme.of(context).colorScheme.surface);
    }

    final preset = _presetWallpapers.firstWhereOrNull((w) => w['id'] == _selectedKey);
    final path = preset?['path'] as String?;
    if (path != null) {
      return Image.asset(path, fit: BoxFit.cover);
    }

    return Container(color: Theme.of(context).colorScheme.surface);
  }

  bool get _hasActiveWallpaper => _selectedKey != 'none';

  @override
  Widget build(BuildContext context) {
    final isDark = Get.isDarkMode;
    final colors = Theme.of(context).colorScheme;
    final hasWallpaper = _hasActiveWallpaper;

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: Text(
          'wallpaper_selection_title'.tr,
          style: AppTextStyles.h4.copyWith(
            color: colors.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: () {
                widget.onApply(_selectedKey);
                Get.back();
                Get.snackbar(
                  'chats_title'.tr,
                  'wallpaper_applied_success'.tr,
                  snackPosition: SnackPosition.BOTTOM,
                  margin: const EdgeInsets.all(12),
                  duration: const Duration(seconds: 2),
                );
              },
              child: Text(
                'wallpaper_apply'.tr,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 1. Zone de Prévisualisation dynamique (Simulateur de discussion)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: colors.outline.withValues(alpha: .2),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .08),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      // Arrière-plan de la prévisualisation
                      Positioned.fill(
                        child: _buildPreviewImage(),
                      ),

                      // Calque sombre
                      if (hasWallpaper)
                        Positioned.fill(
                          child: Container(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.60 : 0.45,
                            ),
                          ),
                        ),

                      // Contenu factice (En-tête, Bulles de conversation, Barre de saisie)
                      Column(
                        children: [
                          // Mini App Bar
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            color: colors.surface.withValues(alpha: hasWallpaper ? 0.85 : 1.0),
                            child: Row(
                              children: [
                                ClipOval(
                                  child: SizedBox(
                                    width: 32,
                                    height: 32,
                                    child: widget.userAvatar != null && widget.userAvatar!.isNotEmpty
                                        ? AppCachedImage(imageUrl: widget.userAvatar!, fit: BoxFit.cover)
                                        : Container(
                                            color: widget.userColor.withValues(alpha: .2),
                                            alignment: Alignment.center,
                                            child: Text(
                                              widget.userName.isEmpty ? '?' : widget.userName[0].toUpperCase(),
                                              style: TextStyle(color: widget.userColor, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  widget.userName,
                                  style: AppTextStyles.h6.copyWith(
                                    fontSize: 15,
                                    color: colors.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Simulation de bulles de message
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Message reçu (Autre utilisateur)
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      margin: const EdgeInsets.only(bottom: 12),
                                      constraints: const BoxConstraints(maxWidth: 240),
                                      decoration: BoxDecoration(
                                        color: hasWallpaper
                                            ? Colors.black.withValues(alpha: 0.5)
                                            : colors.surfaceContainerHighest,
                                        borderRadius: const BorderRadius.only(
                                          topLeft: Radius.circular(16),
                                          topRight: Radius.circular(16),
                                          bottomRight: Radius.circular(16),
                                          bottomLeft: Radius.circular(4),
                                        ),
                                      ),
                                      child: Text(
                                        'wallpaper_preview_sample_other'.tr,
                                        style: TextStyle(
                                          color: hasWallpaper ? Colors.white : colors.onSurface,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ),

                                  // Message envoyé (Moi)
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      constraints: const BoxConstraints(maxWidth: 240),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary,
                                        borderRadius: const BorderRadius.only(
                                          topLeft: Radius.circular(16),
                                          topRight: Radius.circular(16),
                                          bottomLeft: Radius.circular(16),
                                          bottomRight: Radius.circular(4),
                                        ),
                                      ),
                                      child: Text(
                                        'wallpaper_preview_sample_me'.tr,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Mini barre de saisie
                          Container(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                            color: Colors.transparent,
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: (hasWallpaper ? Colors.white : colors.onSurface).withValues(alpha: .15),
                                  ),
                                  child: Icon(Icons.add, size: 18, color: hasWallpaper ? Colors.white : colors.onSurface),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Container(
                                    height: 38,
                                    padding: const EdgeInsets.symmetric(horizontal: 14),
                                    decoration: BoxDecoration(
                                      color: hasWallpaper
                                          ? Colors.black.withValues(alpha: .4)
                                          : colors.surfaceContainerHighest.withValues(alpha: .3),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      'chats_message_hint'.tr,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: hasWallpaper ? Colors.white60 : colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: (hasWallpaper ? Colors.white : colors.onSurface).withValues(alpha: .15),
                                  ),
                                  child: Icon(Icons.mic_none, size: 18, color: hasWallpaper ? Colors.white : colors.onSurface),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 2. Carrousel de choix des fonds d'écran
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              color: colors.surface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    child: Text(
                      'wallpaper_selection_title'.tr,
                      style: AppTextStyles.labelLarge.copyWith(
                        color: colors.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 110,
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      scrollDirection: Axis.horizontal,
                      children: [
                        // Option 0: Aucun
                        _buildWallpaperCard(
                          id: 'none',
                          label: 'wallpaper_none'.tr,
                          content: Container(
                            color: colors.surfaceContainerHighest,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.block_rounded, color: colors.onSurfaceVariant, size: 24),
                                const SizedBox(height: 4),
                                Text('wallpaper_none'.tr, style: AppTextStyles.bodySmall.copyWith(fontSize: 11, color: colors.onSurfaceVariant)),
                              ],
                            ),
                          ),
                          isSelected: _selectedKey == 'none',
                          onTap: () => setState(() => _selectedKey = 'none'),
                        ),
                        const SizedBox(width: 12),

                        // Option 1: Galerie Interne (Bouton d'importation / photo personnalisée)
                        _buildWallpaperCard(
                          id: 'gallery',
                          label: _customPath != null ? 'wallpaper_custom'.tr : 'wallpaper_gallery'.tr,
                          content: _customPath != null && File(_customPath!).existsSync()
                              ? Image.file(
                                  File(_customPath!),
                                  key: ValueKey(_customPath!),
                                  fit: BoxFit.cover,
                                )
                              : Container(
                                  color: colors.surfaceContainerHighest,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.photo_library_outlined, color: AppColors.primary, size: 24),
                                      const SizedBox(height: 4),
                                      Text('wallpaper_gallery'.tr, style: AppTextStyles.bodySmall.copyWith(fontSize: 11, color: colors.onSurfaceVariant)),
                                    ],
                                  ),
                                ),
                          isSelected: _selectedKey.startsWith('custom:'),
                          onTap: () {
                            if (_customPath != null && File(_customPath!).existsSync()) {
                              setState(() => _selectedKey = 'custom:$_customPath');
                            }
                            _openInternalGallery();
                          },
                        ),
                        const SizedBox(width: 12),

                        // Options Présélectionnées (Fond 1, Fond 2, Fond 3)
                        ..._presetWallpapers.where((w) => w['id'] != 'none').map((w) {
                          final id = w['id'] as String;
                          final path = w['path'] as String;
                          final label = 'wallpaper_fond'.trParams({'number': w['number'] as String});
                          final isSelected = (_selectedKey == id);

                          return Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: _buildWallpaperCard(
                              id: id,
                              label: label,
                              content: Image.asset(path, fit: BoxFit.cover),
                              isSelected: isSelected,
                              onTap: () => setState(() => _selectedKey = id),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWallpaperCard({
    required String id,
    required String label,
    required Widget content,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final colors = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 82,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.primary : colors.outline.withValues(alpha: .2),
            width: isSelected ? 3 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Stack(
            fit: StackFit.expand,
            children: [
              content,
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  color: Colors.black54,
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              if (isSelected)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
