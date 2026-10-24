import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:scrole/app/theme/text_styles.dart';
import 'package:scrole/shared/widgets/media_gallery_sheet.dart';
import '../controllers/community/community_controller.dart';

class CreateCommunityScreen extends StatefulWidget {
  const CreateCommunityScreen({super.key});

  @override
  State<CreateCommunityScreen> createState() => _CreateCommunityScreenState();
}

class _CreateCommunityScreenState extends State<CreateCommunityScreen> {
  final CommunityController _controller = Get.put(CommunityController());

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _slugController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  File? _avatarFile;
  File? _bannerFile;
  String _visibility = 'public'; // 'public' or 'prive'
  bool _isCreating = false;
  String? _errorMessage;
  bool _isSlugManuallyEdited = false;

  @override
  void dispose() {
    _nameController.dispose();
    _slugController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  String _normalizeSlug(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[àáâãäå]'), 'a')
        .replaceAll(RegExp(r'[èéêë]'), 'e')
        .replaceAll(RegExp(r'[ìíîï]'), 'i')
        .replaceAll(RegExp(r'[òóôõö]'), 'o')
        .replaceAll(RegExp(r'[ùúûü]'), 'u')
        .replaceAll('ç', 'c')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-+'), '-');
  }

  void _onNameChanged(String val) {
    if (!_isSlugManuallyEdited) {
      _slugController.text = _normalizeSlug(val);
    }
    setState(() => _errorMessage = null);
  }

  Future<void> _pickAvatar() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MediaGallerySheet(
        maxSelection: 1,
        onSelected: (files) {
          if (files.isNotEmpty) {
            setState(() {
              _avatarFile = File(files.first.path);
            });
          }
        },
      ),
    );
  }

  Future<void> _pickBanner() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MediaGallerySheet(
        maxSelection: 1,
        onSelected: (files) {
          if (files.isNotEmpty) {
            setState(() {
              _bannerFile = File(files.first.path);
            });
          }
        },
      ),
    );
  }

  bool get _isValid {
    return _nameController.text.trim().isNotEmpty &&
        _slugController.text.trim().isNotEmpty &&
        _descriptionController.text.trim().isNotEmpty &&
        (_visibility == 'public' || _visibility == 'prive');
  }

  Future<void> _createCommunity() async {
    if (!_isValid || _isCreating) return;

    if (_nameController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'community_name_required'.tr);
      return;
    }
    if (_slugController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'community_slug_required'.tr);
      return;
    }
    if (_descriptionController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'community_description_required'.tr);
      return;
    }

    setState(() {
      _isCreating = true;
      _errorMessage = null;
    });

    try {
      final success = await _controller.createCommunity(
        name: _nameController.text.trim(),
        slug: _slugController.text.trim(),
        description: _descriptionController.text.trim(),
        visibility: _visibility,
        avatarFile: _avatarFile,
        bannerFile: _bannerFile,
      );

      if (mounted) {
        setState(() => _isCreating = false);
        if (success) {
          Get.back();
          Get.snackbar(
            'create_community_title'.tr,
            'community_success_created'.trParams({'name': _nameController.text.trim()}),
            backgroundColor: Colors.black87,
            colorText: Colors.white,
            snackPosition: SnackPosition.BOTTOM,
          );
        } else {
          setState(() => _errorMessage = 'community_create_generic_error'.tr);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCreating = false;
          _errorMessage = e.toString().tr;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        centerTitle: false,
        title: Text('create_community_title'.tr),
        titleTextStyle: AppTextStyles.h5.copyWith(color: colorScheme.onSurface, fontWeight: FontWeight.bold),
        leading: IconButton(
          onPressed: () => Get.back(),
          icon: const Icon(Icons.close_rounded, size: 28),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: TextButton(
              onPressed: _isValid && !_isCreating ? _createCommunity : null,
              style: TextButton.styleFrom(
                foregroundColor: _isValid ? colorScheme.primary : colorScheme.outline,
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: _isCreating
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(
                      'community_create_action'.tr,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: _isValid ? colorScheme.primary : colorScheme.outline.withValues(alpha: 0.6),
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: Colors.red),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red, fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // --- Cover & Avatar Photos ---
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  GestureDetector(
                    onTap: _pickBanner,
                    child: Container(
                      height: 140,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                        image: _bannerFile != null
                            ? DecorationImage(image: FileImage(_bannerFile!), fit: BoxFit.cover)
                            : null,
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                      ),
                      child: _bannerFile == null
                          ? Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.add_photo_alternate_rounded, color: colorScheme.onSurfaceVariant),
                                  const SizedBox(width: 8),
                                  Text(
                                    'community_banner_label'.tr,
                                    style: TextStyle(color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            )
                          : null,
                    ),
                  ),
                  Positioned(
                    bottom: -35,
                    child: GestureDetector(
                      onTap: _pickAvatar,
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          Container(
                            width: 84,
                            height: 84,
                            decoration: BoxDecoration(
                              color: colorScheme.surface,
                              shape: BoxShape.circle,
                              border: Border.all(color: colorScheme.primary, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: _avatarFile != null
                                ? Image.file(_avatarFile!, fit: BoxFit.cover)
                                : Icon(Icons.groups_rounded, color: colorScheme.primary, size: 36),
                          ),
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: colorScheme.surface, width: 2),
                            ),
                            child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 50),

              // --- Community Name ---
              Text(
                'community_name_label'.tr,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                onChanged: _onNameChanged,
                style: TextStyle(color: colorScheme.onSurface, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'community_name_hint'.tr,
                  hintStyle: TextStyle(color: colorScheme.outline.withValues(alpha: 0.5)),
                  prefixIcon: Icon(Icons.badge_outlined, color: colorScheme.onSurfaceVariant),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                ),
              ),
              const SizedBox(height: 20),

              // --- Slug ---
              Text(
                'community_slug_label'.tr,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _slugController,
                onChanged: (_) {
                  setState(() => _isSlugManuallyEdited = true);
                },
                style: TextStyle(color: colorScheme.onSurface, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'community_slug_hint'.tr,
                  hintStyle: TextStyle(color: colorScheme.outline.withValues(alpha: 0.5)),
                  prefixIcon: Icon(Icons.link_rounded, color: colorScheme.onSurfaceVariant),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                ),
              ),
              const SizedBox(height: 20),

              // --- Description ---
              Text(
                'community_description_label'.tr,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _descriptionController,
                maxLines: 4,
                onChanged: (_) => setState(() {}),
                style: TextStyle(color: colorScheme.onSurface, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'community_description_hint'.tr,
                  hintStyle: TextStyle(color: colorScheme.outline.withValues(alpha: 0.5)),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
              const SizedBox(height: 20),

              // --- Visibility Dropdown ---
              Text(
                'community_visibility_label'.tr,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _visibility,
                isExpanded: true,
                dropdownColor: colorScheme.surfaceContainerHigh,
                style: TextStyle(color: colorScheme.onSurface, fontSize: 15),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
                  prefixIcon: Icon(
                    _visibility == 'prive' ? Icons.lock_outline_rounded : Icons.public_rounded,
                    color: colorScheme.primary,
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'public',
                    child: Text('community_visibility_public'.tr, overflow: TextOverflow.ellipsis),
                  ),
                  DropdownMenuItem(
                    value: 'prive',
                    child: Text('community_visibility_private'.tr, overflow: TextOverflow.ellipsis),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _visibility = val);
                  }
                },
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  _visibility == 'prive' ? 'community_visibility_private_hint'.tr : 'community_visibility_public_hint'.tr,
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
