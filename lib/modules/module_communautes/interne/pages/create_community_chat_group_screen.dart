import 'dart:math' as math;
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:scrole/app/repository_global/r2_media_repository.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Écran dédié à la création d'une discussion textuelle de communauté.
class CreateCommunityChatGroupScreen extends StatefulWidget {
  final String communityId;

  const CreateCommunityChatGroupScreen({
    super.key,
    required this.communityId,
  });

  @override
  State<CreateCommunityChatGroupScreen> createState() =>
      _CreateCommunityChatGroupScreenState();
}

class _CreateCommunityChatGroupScreenState
    extends State<CreateCommunityChatGroupScreen> {
  final _client = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _visibility = 'public';
  bool _saving = false;
  XFile? _selectedCover;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  String _newUuid() {
    final random = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }

  Future<void> _pickCover() async {
    if (_saving) return;
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
      maxWidth: 1200,
    );
    if (image != null && mounted) setState(() => _selectedCover = image);
  }

  Future<void> _create() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    if (_client.auth.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('chat_groups_access_error'.tr)),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final salonId = _newUuid();
      await _client.rpc('create_community_chat_group', params: {
        'p_id': salonId,
        'p_community_id': widget.communityId,
        'p_name': _nameController.text.trim(),
        'p_description': _descriptionController.text.trim(),
        'p_visibility': _visibility,
      });
      if (_selectedCover != null) {
        final uploaded = await R2MediaRepository().uploadFile(
          file: File(_selectedCover!.path),
          category: 'salon_avatar',
          mediaType: 'image',
          entityId: salonId,
        );
        final publicUrl = uploaded.publicUrl;
        if (publicUrl == null || publicUrl.isEmpty || !uploaded.isPublic) {
          throw StateError('L’image du salon n’a pas reçu d’URL publique R2.');
        }
        await _client.rpc('set_community_chat_group_avatar', params: {
          'p_salon_id': salonId,
          'p_avatar_url': publicUrl,
        });
      }
      if (mounted) Navigator.of(context).pop(true);
    } on PostgrestException catch (error) {
      if (!mounted) return;
      final message = error.message.toLowerCase().contains('action non autorisée')
          ? 'chat_groups_create_error'.tr
          : '${'chat_groups_create_error'.tr} : ${error.message}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${'chat_groups_create_error'.tr} : $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('chat_groups_create_title'.tr)),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              Center(
                child: GestureDetector(
                  onTap: _saving ? null : _pickCover,
                  child: Stack(alignment: Alignment.bottomRight, children: [
                    CircleAvatar(
                      radius: 48,
                      backgroundColor: colors.primaryContainer,
                      backgroundImage: _selectedCover == null ? null : FileImage(File(_selectedCover!.path)),
                      child: _selectedCover == null
                          ? Icon(Icons.forum_rounded, size: 42, color: colors.onPrimaryContainer)
                          : null,
                    ),
                    CircleAvatar(
                      radius: 17,
                      backgroundColor: colors.primary,
                      child: Icon(Icons.camera_alt_rounded, size: 17, color: colors.onPrimary),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              Text('chat_groups_cover_hint'.tr, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 14),
              Text(
                'chat_groups_empty_help'.tr,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 28),
              TextFormField(
                controller: _nameController,
                maxLength: 80,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'chat_groups_name'.tr,
                  hintText: 'chat_groups_name'.tr,
                  prefixIcon: const Icon(Icons.forum_outlined),
                  border: const OutlineInputBorder(),
                ),
                validator: (value) => value == null || value.trim().length < 2
                    ? 'chat_groups_name_invalid'.tr
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                maxLength: 300,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'chat_groups_description'.tr,
                  hintText: 'chat_groups_description'.tr,
                  prefixIcon: const Icon(Icons.notes_rounded),
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'chat_groups_title'.tr,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Card(
                clipBehavior: Clip.antiAlias,
                child: RadioListTile<String>(
                  value: 'public',
                  groupValue: _visibility,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _visibility = value!),
                  secondary: const Icon(Icons.public_rounded),
                  title: Text('chat_groups_public'.tr),
                  subtitle: Text('chat_groups_public_help'.tr),
                ),
              ),
              Card(
                clipBehavior: Clip.antiAlias,
                child: RadioListTile<String>(
                  value: 'private',
                  groupValue: _visibility,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _visibility = value!),
                  secondary: const Icon(Icons.lock_outline_rounded),
                  title: Text('chat_groups_private'.tr),
                  subtitle: Text('chat_groups_private_help'.tr),
                ),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: _saving ? null : _create,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_comment_outlined),
                label: Text(
                  _saving
                      ? 'chat_groups_request_pending'.tr
                      : 'chat_groups_create_action'.tr,
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
