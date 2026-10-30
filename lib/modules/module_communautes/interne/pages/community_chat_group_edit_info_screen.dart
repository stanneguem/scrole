import 'dart:io';

import 'package:flutter/material.dart';
import 'package:scrole/app/repository_global/r2_media_repository.dart';
import 'package:scrole/shared/widgets/app_cached_image.dart';
import 'package:scrole/shared/widgets/media_gallery_sheet.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CommunityChatGroupEditInfoScreen extends StatefulWidget {
  const CommunityChatGroupEditInfoScreen({
    super.key,
    required this.salonId,
    required this.initialData,
  });
  final String salonId;
  final Map<String, dynamic> initialData;

  @override
  State<CommunityChatGroupEditInfoScreen> createState() =>
      _CommunityChatGroupEditInfoScreenState();
}

class _CommunityChatGroupEditInfoScreenState
    extends State<CommunityChatGroupEditInfoScreen> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  XFile? _avatar;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialData['name']?.toString() ?? '');
    _description = TextEditingController(text: widget.initialData['description']?.toString() ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    if (_saving) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (galleryContext) => MediaGallerySheet(
        maxSelection: 1,
        allowMixedMedia: false,
        onSelected: (files) {
          if (files.isNotEmpty && mounted) {
            setState(() => _avatar = files.first);
          }
          Navigator.of(galleryContext).pop();
        },
      ),
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.length < 2 || name.length > 80) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(''community_chat_group_edit_name_invalid'.tr')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.rpc(
        'update_community_chat_group_settings',
        params: {
          'p_salon_id': widget.salonId,
          'p_name': name,
          'p_description': _description.text.trim(),
          'p_visibility': widget.initialData['visibility'] ?? 'public',
        },
      );
      String? avatarUrl = widget.initialData['avatar_url']?.toString();
      if (_avatar != null) {
        final uploaded = await R2MediaRepository().uploadFile(
          file: File(_avatar!.path),
          category: 'salon_avatar',
          mediaType: 'image',
          entityId: widget.salonId,
        );
        avatarUrl = uploaded.publicUrl;
        if (avatarUrl == null || avatarUrl.isEmpty || !uploaded.isPublic) {
          throw StateError('Impossible de récupérer l’URL publique Cloudflare R2.');
        }
        await Supabase.instance.client.rpc(
          'set_community_chat_group_avatar',
          params: {'p_salon_id': widget.salonId, 'p_avatar_url': avatarUrl},
        );

        // Supprimer l'ancien objet R2 seulement après confirmation que la
        // nouvelle URL est enregistrée sur le salon.
        final previousAvatarUrl =
            widget.initialData['avatar_url']?.toString().trim() ?? '';
        if (previousAvatarUrl.isNotEmpty &&
            previousAvatarUrl != avatarUrl) {
          try {
            await R2MediaRepository()
                .deleteReplacedPublicMedia(previousAvatarUrl);
          } catch (cleanupError) {
            debugPrint(
              '[SALON_AVATAR] Ancienne photo non supprimée de R2: $cleanupError',
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'community_chat_group_edit_avatar_cleanup_error'.tr,
                  ),
                ),
              );
            }
          }
        }
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('community_chat_group_edit_error'.trParams({'error': error.toString()}))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final avatarUrl = widget.initialData['avatar_url']?.toString();
    return Scaffold(
      appBar: AppBar(
        title: Text('community_chat_group_edit_title'.tr),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text('community_chat_group_edit_save'.tr),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Semantics(
              button: true,
              label: 'community_chat_group_edit_avatar_hint'.tr,
              child: GestureDetector(
              onTap: _saving ? null : _pickAvatar,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Container(
                    width: 116,
                    height: 116,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.surfaceContainerHighest,
                      border: Border.all(
                        color: colors.outlineVariant.withOpacity(.65),
                        width: 1,
                      ),
                    ),
                    child: ClipOval(
                      child: SizedBox.expand(
                        child: _avatar != null
                            ? Image.file(
                                File(_avatar!.path),
                                fit: BoxFit.cover,
                                width: 116,
                                height: 116,
                              )
                            : avatarUrl == null || avatarUrl.isEmpty
                                ? Icon(
                                    Icons.forum_outlined,
                                    size: 40,
                                    color: colors.onSurfaceVariant,
                                  )
                                : AppCachedImage(
                                    imageUrl: avatarUrl,
                                    fit: BoxFit.cover,
                                  ),
                      ),
                    ),
                  ),
                  CircleAvatar(
                    radius: 17,
                    backgroundColor: colors.primary,
                    child: Icon(Icons.camera_alt_outlined, size: 17, color: colors.onPrimary),
                  ),
                ],
              ),
            ),
            ),
          ),
          const SizedBox(height: 28),
          TextField(
            controller: _name,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'community_chat_group_edit_name'.tr,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _description,
            maxLength: 300,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'community_chat_group_edit_description'.tr,
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }
}
