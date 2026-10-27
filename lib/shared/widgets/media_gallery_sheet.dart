import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import '../constants/post_media_limits.dart';

import '../../app/theme/text_styles.dart';

class MediaGallerySheet extends StatefulWidget {
  const MediaGallerySheet({
    super.key,
    required this.onSelected,
    this.maxSelection = maxPostPhotos,
    this.allowMixedMedia = true,
  });

  final Function(List<XFile>) onSelected;
  final int maxSelection;
  final bool allowMixedMedia;

  @override
  State<MediaGallerySheet> createState() => _MediaGallerySheetState();
}

class _MediaGallerySheetState extends State<MediaGallerySheet> {
  final List<AssetEntity> _allAssets = [];
  final List<AssetEntity> _selectedAssets = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _isRequestingAssets = false;
  bool _hasMore = true;
  int _currentPage = 0;
  // Charger moins d'éléments au premier affichage limite le coût de MediaStore
  // et de génération des miniatures sur les appareils contenant beaucoup de photos.
  static const int _pageSize = 30;
  static const int _maxInitialPages = 3;
  static const Duration _galleryOperationTimeout = Duration(seconds: 20);
  
  bool _isOpeningMedia = false;
  static const Set<String> _videoExtensions = {'mp4', 'mov', 'm4v'};
  bool _isSupportedAsset(AssetEntity asset) {
    if (asset.type == AssetType.image) return true;
    if (asset.type != AssetType.video) return false;
    final title = asset.title ?? '';
    final extension = p.extension(title).replaceFirst('.', '').toLowerCase();
    return _videoExtensions.contains(extension);
  }
  AssetPathEntity? _currentPath;

  @override
  void initState() {
    super.initState();
    _requestAssets();
  }

  Future<void> _requestAssets() async {
    if (_isRequestingAssets) return;
    _isRequestingAssets = true;
    final totalWatch = Stopwatch()..start();
    if (mounted) {
      setState(() {
        _isLoading = true;
        _isLoadingMore = false;
        _hasMore = true;
        _currentPage = 0;
        _allAssets.clear();
      });
    }

    try {
      final permissionWatch = Stopwatch()..start();
      final PermissionState ps = await PhotoManager.requestPermissionExtend()
          .timeout(_galleryOperationTimeout);
      debugPrint('[MEDIA_GALLERY] permission: ${permissionWatch.elapsedMilliseconds}ms state=$ps');

      if (!(ps.isAuth || ps == PermissionState.limited)) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final albumsWatch = Stopwatch()..start();
      final paths = await PhotoManager.getAssetPathList(
        type: widget.allowMixedMedia ? RequestType.common : RequestType.image,
        onlyAll: true,
        filterOption: FilterOptionGroup(
          containsLivePhotos: false,
          orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
        ),
      ).timeout(_galleryOperationTimeout);
      debugPrint('[MEDIA_GALLERY] albums: ${albumsWatch.elapsedMilliseconds}ms count=${paths.length}');

      if (paths.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      _currentPath = paths.first;
      // Il peut y avoir une page composée uniquement de formats vidéo non pris
      // en charge. Avancer quelques pages évite d'afficher une galerie vide bloquée.
      var pageCount = 0;
      var exhausted = false;
      while (pageCount < _maxInitialPages && _allAssets.isEmpty && !exhausted) {
        final pageWatch = Stopwatch()..start();
        final entities = await _currentPath!
            .getAssetListPaged(page: _currentPage, size: _pageSize)
            .timeout(_galleryOperationTimeout);
        pageCount++;
        _allAssets.addAll(entities.where(_isSupportedAsset));
        exhausted = entities.length < _pageSize;
        _hasMore = !exhausted;
        debugPrint(
          '[MEDIA_GALLERY] page=$_currentPage fetched=${entities.length} '
          'supported=${entities.where(_isSupportedAsset).length} '
          'duration=${pageWatch.elapsedMilliseconds}ms',
        );
        if (!exhausted && _allAssets.isEmpty && pageCount < _maxInitialPages) {
          _currentPage++;
        } else {
          break;
        }
      }

      if (mounted) setState(() => _isLoading = false);
      debugPrint(
        '[MEDIA_GALLERY] initial load: ${totalWatch.elapsedMilliseconds}ms '
        'assets=${_allAssets.length} hasMore=$_hasMore',
      );
    } on Exception catch (e, stack) {
      debugPrint('[MEDIA_GALLERY] Initial load failed after ${totalWatch.elapsedMilliseconds}ms: $e\n$stack');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasMore = false;
        });
        Get.snackbar(
          'Galerie indisponible',
          'Le chargement des médias a pris trop de temps ou a échoué. Réessaie.',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } finally {
      _isRequestingAssets = false;
    }
  }

  Future<void> _loadMoreAssets() async {
    if (_isLoading || _isLoadingMore || !_hasMore || _currentPath == null) return;

    setState(() => _isLoadingMore = true);
    final watch = Stopwatch()..start();
    try {
      final nextPage = _currentPage + 1;
      final entities = await _currentPath!
          .getAssetListPaged(page: nextPage, size: _pageSize)
          .timeout(_galleryOperationTimeout);
      final supported = entities.where(_isSupportedAsset).toList();

      if (mounted) {
        setState(() {
          _currentPage = nextPage;
          _allAssets.addAll(supported);
          _hasMore = entities.length == _pageSize;
          _isLoadingMore = false;
        });
      }
      debugPrint(
        '[MEDIA_GALLERY] next page=$nextPage fetched=${entities.length} '
        'supported=${supported.length} duration=${watch.elapsedMilliseconds}ms',
      );

      // Si cette page ne contient aucun média affichable, continuer la pagination
      // pour éviter que l'indicateur reste visible sans nouvelles vignettes.
      if (supported.isEmpty && entities.length == _pageSize && mounted) {
        await _loadMoreAssets();
      }
    } on Exception catch (e, stack) {
      debugPrint('[MEDIA_GALLERY] Loading more failed after ${watch.elapsedMilliseconds}ms: $e\n$stack');
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
          _hasMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.6,
      maxChildSize: 1.0,
      expand: false,
      builder: (context, scrollController) {
        return NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification scrollInfo) {
            if (scrollInfo.metrics.pixels >= scrollInfo.metrics.maxScrollExtent - 200) {
              _loadMoreAssets();
            }
            return false;
          },
          child: Container(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Galerie (${_selectedAssets.length}/${widget.maxSelection})', style: AppTextStyles.h5),
                      if (_selectedAssets.isNotEmpty)
                        TextButton(
                          onPressed: _isOpeningMedia ? null : _confirmSelection,
                          child: Text(
                            'Confirmer (${_selectedAssets.length})',
                            style: TextStyle(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        )
                      else
                        IconButton(
                          onPressed: _isOpeningMedia ? null : () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _allAssets.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('gallery_empty'.tr),
                                  const SizedBox(height: 16),
                                  OutlinedButton(
                                    onPressed: _requestAssets,
                                    child: Text('gallery_refresh'.tr),
                                  ),
                                  TextButton(
                                    onPressed: PhotoManager.openSetting,
                                    child: Text('gallery_permissions'.tr),
                                  ),
                                ],
                              ),
                            )
                          : GridView.builder(
                              controller: scrollController,
                              padding: const EdgeInsets.all(1),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 2,
                                mainAxisSpacing: 2,
                              ),
                              itemCount: _allAssets.length + (_hasMore ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index >= _allAssets.length) {
                                  return const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(8.0),
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  );
                                }

                                final asset = _allAssets[index];
                                final isSelected = _selectedAssets.contains(asset);
                                final selectionIndex = _selectedAssets.indexOf(asset);

                                return _AssetItem(
                                  asset: asset,
                                  isSelected: isSelected,
                                  selectionIndex: selectionIndex,
                                  onTap: () => _toggleSelection(asset),
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _toggleSelection(AssetEntity asset) {
    setState(() {
      if (_selectedAssets.contains(asset)) {
        _selectedAssets.remove(asset);
      } else {
        if (_selectedAssets.length < widget.maxSelection) {
          _selectedAssets.add(asset);
        } else {
          Get.snackbar(
            'Limite atteinte',
            'Vous ne pouvez sélectionner que ${widget.maxSelection} médias compatibles.',
            snackPosition: SnackPosition.BOTTOM,
          );
        }
      }
    });
  }

  Future<void> _confirmSelection() async {
    if (_selectedAssets.isEmpty) return;
    final expectedCount = _selectedAssets.length;
    setState(() => _isOpeningMedia = true);

    try {
      final List<XFile> xFiles = [];
      for (final asset in _selectedAssets) {
        final file = await asset.file;
        if (file == null || !await file.exists()) {
          throw StateError('Un des fichiers sélectionnés est inaccessible.');
        }
        xFiles.add(XFile(file.path));
      }

      debugPrint('[MEDIA_GALLERY] Selection resolved: selected=$expectedCount resolved=${xFiles.length}');
      if (xFiles.length != expectedCount) {
        throw StateError('Sélection incomplète : $expectedCount médias choisis, ${xFiles.length} accessibles.');
      }
      // Le callback propriétaire ferme la feuille en renvoyant les fichiers.
      // Un second pop fermerait aussi l'écran de création/édition de profil.
      widget.onSelected(xFiles);
    } catch (error, stack) {
      debugPrint('[MEDIA_GALLERY] Selection failed: $error\n$stack');
      if (mounted) {
        Get.snackbar(
          'Sélection incomplète',
          'Certains médias ne sont pas accessibles. Rien n’a été ajouté : réessaie avec d’autres fichiers.',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } finally {
      if (mounted) setState(() => _isOpeningMedia = false);
    }
  }
}

class _AssetItem extends StatelessWidget {
  const _AssetItem({
    required this.asset,
    required this.onTap,
    this.isSelected = false,
    this.selectionIndex = -1,
  });

  final AssetEntity asset;
  final VoidCallback onTap;
  final bool isSelected;
  final int selectionIndex;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AssetEntityImage(
            asset,
            isOriginal: false,
            thumbnailSize: const ThumbnailSize.square(200),
            fit: BoxFit.cover,
          ),
          if (asset.type == AssetType.video)
            Positioned(
              left: 5,
              bottom: 5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.72),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.play_arrow_rounded, color: Colors.white, size: 13),
                    SizedBox(width: 2),
                    Text(
                      'Vidéo',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (isSelected)
            Container(
              color: Colors.black26,
              child: Center(
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Center(
                    child: Text(
                      '${selectionIndex + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
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
