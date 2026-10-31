import 'dart:async';
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
  final List<AssetEntity> _imageAssets = [];
  final List<AssetEntity> _videoAssets = [];
  final List<AssetEntity> _selectedAssets = [];
  bool _isLoadingImages = true;
  bool _isLoadingVideos = false;
  bool _isLoadingMoreImages = false;
  bool _isLoadingMoreVideos = false;
  bool _isRequestingAssets = false;
  bool _hasMoreImages = true;
  bool _hasMoreVideos = true;
  bool _videosLoaded = false;
  int _imagePage = 0;
  int _videoPage = 0;
  int _activeTab = 0;
  static const int _pageSize = 30;
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
  AssetPathEntity? _imagePath;
  AssetPathEntity? _videoPath;

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
        _isLoadingImages = true;
        _isLoadingVideos = false;
        _isLoadingMoreImages = false;
        _isLoadingMoreVideos = false;
        _hasMoreImages = true;
        _hasMoreVideos = true;
        _videosLoaded = false;
        _imagePage = 0;
        _videoPage = 0;
        _imageAssets.clear();
        _videoAssets.clear();
      });
    }

    try {
      final permissionWatch = Stopwatch()..start();
      final PermissionState ps = await PhotoManager.requestPermissionExtend()
          .timeout(_galleryOperationTimeout);
      debugPrint('[MEDIA_GALLERY] permission: ${permissionWatch.elapsedMilliseconds}ms state=$ps');
      if (!(ps.isAuth || ps == PermissionState.limited)) {
        if (mounted) setState(() => _isLoadingImages = false);
        return;
      }

      final imageAlbumsWatch = Stopwatch()..start();
      final imagePaths = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        onlyAll: true,
        filterOption: FilterOptionGroup(
          containsLivePhotos: false,
          orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
        ),
      ).timeout(_galleryOperationTimeout);
      debugPrint('[MEDIA_GALLERY] image albums: ${imageAlbumsWatch.elapsedMilliseconds}ms count=${imagePaths.length}');

      if (imagePaths.isNotEmpty) {
        _imagePath = imagePaths.first;
        final imageWatch = Stopwatch()..start();
        final images = await _imagePath!
            .getAssetListPaged(page: 0, size: _pageSize)
            .timeout(_galleryOperationTimeout);
        if (mounted) {
          setState(() {
            _imageAssets.addAll(images.where((asset) => asset.type == AssetType.image));
            _hasMoreImages = images.length == _pageSize;
            _isLoadingImages = false;
          });
        }
        debugPrint('[MEDIA_GALLERY] first images: count=${images.length} duration=${imageWatch.elapsedMilliseconds}ms');
      } else if (mounted) {
        setState(() => _isLoadingImages = false);
      }

      // Les images sont déjà affichées : la récupération des vidéos se fait en arrière-plan.
      if (widget.allowMixedMedia && mounted) unawaited(_loadInitialVideos());
      debugPrint('[MEDIA_GALLERY] images ready after ${totalWatch.elapsedMilliseconds}ms');
    } on Exception catch (e, stack) {
      debugPrint('[MEDIA_GALLERY] Initial image load failed after ${totalWatch.elapsedMilliseconds}ms: $e\n$stack');
      if (mounted) {
        setState(() => _isLoadingImages = false);
        Get.snackbar('Galerie indisponible', 'Le chargement des images a échoué. Réessaie.', snackPosition: SnackPosition.BOTTOM);
      }
    } finally {
      _isRequestingAssets = false;
    }
  }

  Future<void> _loadInitialVideos() async {
    if (_videosLoaded || _isLoadingVideos || !widget.allowMixedMedia) return;
    if (mounted) setState(() => _isLoadingVideos = true);
    final watch = Stopwatch()..start();
    try {
      final paths = await PhotoManager.getAssetPathList(
        type: RequestType.video,
        onlyAll: true,
        filterOption: FilterOptionGroup(
          orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
        ),
      ).timeout(_galleryOperationTimeout);
      if (paths.isNotEmpty) {
        _videoPath = paths.first;
        final videos = await _videoPath!
            .getAssetListPaged(page: 0, size: _pageSize)
            .timeout(_galleryOperationTimeout);
        if (mounted) {
          setState(() {
            _videoAssets.addAll(videos.where(_isSupportedAsset));
            _hasMoreVideos = videos.length == _pageSize;
            _videosLoaded = true;
            _isLoadingVideos = false;
          });
        }
        debugPrint('[MEDIA_GALLERY] first videos: count=${videos.length} duration=${watch.elapsedMilliseconds}ms');
      } else if (mounted) {
        setState(() {
          _videosLoaded = true;
          _isLoadingVideos = false;
          _hasMoreVideos = false;
        });
      }
    } on Exception catch (e, stack) {
      debugPrint('[MEDIA_GALLERY] Initial video load failed after ${watch.elapsedMilliseconds}ms: $e\n$stack');
      if (mounted) setState(() {
        _videosLoaded = true;
        _isLoadingVideos = false;
        _hasMoreVideos = false;
      });
    }
  }

  Future<void> _loadMoreAssets() async {
    final isImages = _activeTab == 0;
    final path = isImages ? _imagePath : _videoPath;
    final isLoadingMore = isImages ? _isLoadingMoreImages : _isLoadingMoreVideos;
    final hasMore = isImages ? _hasMoreImages : _hasMoreVideos;
    if (isLoadingMore || !hasMore || path == null) return;
    if (!isImages && !_videosLoaded) return;

    setState(() {
      if (isImages) {
        _isLoadingMoreImages = true;
      } else {
        _isLoadingMoreVideos = true;
      }
    });
    final watch = Stopwatch()..start();
    try {
      final nextPage = (isImages ? _imagePage : _videoPage) + 1;
      final entities = await path.getAssetListPaged(page: nextPage, size: _pageSize)
          .timeout(_galleryOperationTimeout);
      final supported = isImages
          ? entities.where((asset) => asset.type == AssetType.image).toList()
          : entities.where(_isSupportedAsset).toList();

      if (mounted) {
        setState(() {
          if (isImages) {
            _imagePage = nextPage;
            _imageAssets.addAll(supported);
            _hasMoreImages = entities.length == _pageSize;
            _isLoadingMoreImages = false;
          } else {
            _videoPage = nextPage;
            _videoAssets.addAll(supported);
            _hasMoreVideos = entities.length == _pageSize;
            _isLoadingMoreVideos = false;
          }
        });
      }
      debugPrint('[MEDIA_GALLERY] ${isImages ? "images" : "videos"} page=$nextPage fetched=${entities.length} supported=${supported.length} duration=${watch.elapsedMilliseconds}ms');
      if (supported.isEmpty && entities.length == _pageSize && mounted) {
        await _loadMoreAssets();
      }
    } on Exception catch (e, stack) {
      debugPrint('[MEDIA_GALLERY] Pagination failed: $e\n$stack');
      if (mounted) setState(() {
        if (isImages) {
          _isLoadingMoreImages = false;
          _hasMoreImages = false;
        } else {
          _isLoadingMoreVideos = false;
          _hasMoreVideos = false;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final assets = _activeTab == 0 ? _imageAssets : _videoAssets;
    final isLoading = _activeTab == 0 ? _isLoadingImages : _isLoadingVideos;
    final isLoadingMore = _activeTab == 0 ? _isLoadingMoreImages : _isLoadingMoreVideos;
    final hasMore = _activeTab == 0 ? _hasMoreImages : _hasMoreVideos;
    final videosPending = _activeTab == 1 && !_videosLoaded && !_isLoadingVideos;

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.6,
      maxChildSize: 1.0,
      expand: false,
      builder: (context, scrollController) {
        return Container(
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
                          style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 16),
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
              if (widget.allowMixedMedia)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Row(
                    children: [
                      Expanded(child: _galleryTab('Images', 0, _imageAssets.length, colorScheme)),
                      const SizedBox(width: 8),
                      Expanded(child: _galleryTab('Vidéos', 1, _videoAssets.length, colorScheme)),
                    ],
                  ),
                ),
              const Divider(height: 1),
              Expanded(
                child: isLoading || videosPending
                    ? const Center(child: CircularProgressIndicator())
                    : assets.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('gallery_empty'.tr),
                                const SizedBox(height: 16),
                                OutlinedButton(onPressed: _requestAssets, child: Text('gallery_refresh'.tr)),
                                TextButton(onPressed: PhotoManager.openSetting, child: Text('gallery_permissions'.tr)),
                              ],
                            ),
                          )
                        : NotificationListener<ScrollNotification>(
                            onNotification: (notification) {
                              if (notification.metrics.pixels >= notification.metrics.maxScrollExtent - 200) {
                                _loadMoreAssets();
                              }
                              return false;
                            },
                            child: GridView.builder(
                              key: PageStorageKey<String>('media-gallery-$_activeTab'),
                              controller: scrollController,
                              padding: const EdgeInsets.all(1),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 2,
                                mainAxisSpacing: 2,
                              ),
                              itemCount: assets.length + (hasMore || isLoadingMore ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index >= assets.length) {
                                  return const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(8),
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  );
                                }
                                final asset = assets[index];
                                return _AssetItem(
                                  asset: asset,
                                  isSelected: _selectedAssets.contains(asset),
                                  selectionIndex: _selectedAssets.indexOf(asset),
                                  onTap: () => _toggleSelection(asset),
                                );
                              },
                            ),
                          ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _galleryTab(String label, int index, int count, ColorScheme colorScheme) {
    final selected = _activeTab == index;
    return Material(
      color: selected ? colorScheme.primary.withOpacity(0.12) : colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          setState(() => _activeTab = index);
          if (index == 1 && !_videosLoaded && !_isLoadingVideos) {
            unawaited(_loadInitialVideos());
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
          child: Center(
            child: Text(
              '$label ($count)',
              style: TextStyle(
                color: selected ? colorScheme.primary : colorScheme.onSurface,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
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
