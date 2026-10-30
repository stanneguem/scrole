import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:scrole/app/repository_global/r2_media_repository.dart';
import 'package:scrole/shared/widgets/app_cached_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CommunityChatGroupSettingsScreen extends StatefulWidget {
  const CommunityChatGroupSettingsScreen({
    super.key,
    required this.salonId,
    required this.initialName,
    required this.communityName,
    this.initialAvatarUrl,
  });

  final String salonId;
  final String initialName;
  final String communityName;
  final String? initialAvatarUrl;

  @override
  State<CommunityChatGroupSettingsScreen> createState() =>
      _CommunityChatGroupSettingsScreenState();
}

class _CommunityChatGroupSettingsScreenState
    extends State<CommunityChatGroupSettingsScreen> {
  final _client = Supabase.instance.client;
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  Map<String, dynamic> _settings = {};
  List<Map<String, dynamic>> _members = [];
  String _visibility = 'public';
  String? _avatarUrl;
  XFile? _newAvatar;
  bool _loading = true;
  bool _saving = false;

  bool get _isAdmin => _settings['is_salon_admin'] == true;
  bool get _isOwner => _settings['my_role'] == 'owner';

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.initialName;
    _avatarUrl = widget.initialAvatarUrl;
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final raw = await _client.rpc('get_community_chat_group_settings',
          params: {'p_salon_id': widget.salonId});
      final data = Map<String, dynamic>.from(raw as Map);
      final members = (data['members'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _settings = data;
        _members = members;
        _nameController.text = (data['name'] ?? widget.initialName).toString();
        _descriptionController.text = (data['description'] ?? '').toString();
        _visibility = (data['visibility'] ?? 'public').toString();
        _avatarUrl = data['avatar_url']?.toString();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('Impossible de charger les paramètres du groupe : $e', error: true);
    }
  }

  void _message(String value, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _pickAvatar() async {
    if (!_isAdmin || _saving) return;
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
      maxWidth: 1200,
    );
    if (image != null && mounted) setState(() => _newAvatar = image);
  }

  Future<void> _save() async {
    if (!_isAdmin || _saving) return;
    final name = _nameController.text.trim();
    if (name.length < 2 || name.length > 80) {
      _message('Le nom doit contenir entre 2 et 80 caractères.', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await _client.rpc('update_community_chat_group_settings', params: {
        'p_salon_id': widget.salonId,
        'p_name': name,
        'p_description': _descriptionController.text.trim(),
        'p_visibility': _visibility,
      });
      if (_newAvatar != null) {
        final uploaded = await R2MediaRepository().uploadFile(
          file: File(_newAvatar!.path),
          category: 'salon_avatar',
          mediaType: 'image',
          entityId: widget.salonId,
        );
        final url = uploaded.publicUrl;
        if (url == null || url.isEmpty || !uploaded.isPublic) {
          throw StateError('Impossible de récupérer l’URL publique R2 de cette image.');
        }
        await _client.rpc('set_community_chat_group_avatar', params: {
          'p_salon_id': widget.salonId,
          'p_avatar_url': url,
        });
        _avatarUrl = url;
        _newAvatar = null;
      }
      await _load();
      _message('Paramètres du groupe enregistrés.');
      if (mounted) Navigator.of(context).pop({
        'name': name,
        'avatar_url': _avatarUrl,
      });
    } catch (e) {
      _message('Impossible d’enregistrer les paramètres : $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changeMemberRole(Map<String, dynamic> member, String role) async {
    final userId = member['user_id']?.toString();
    if (!_isOwner || userId == null) return;
    try {
      await _client.rpc('set_community_chat_group_member_role', params: {
        'p_salon_id': widget.salonId,
        'p_user_id': userId,
        'p_role': role,
      });
      await _load();
      _message('Rôle du membre mis à jour.');
    } catch (e) {
      _message('Impossible de modifier ce rôle : $e', error: true);
    }
  }

  Future<void> _removeMember(Map<String, dynamic> member) async {
    final userId = member['user_id']?.toString();
    if (userId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Retirer ce membre ?'),
        content: Text('Voulez-vous retirer ${member['display_name'] ?? 'ce membre'} de la discussion ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('cancel'.tr)),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Retirer')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _client.rpc('remove_community_chat_group_member', params: {
        'p_salon_id': widget.salonId,
        'p_user_id': userId,
      });
      await _load();
      _message('Membre retiré de la discussion.');
    } catch (e) {
      _message('Impossible de retirer ce membre : $e', error: true);
    }
  }

  Future<void> _leave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Quitter la discussion ?'),
        content: const Text('Tu ne recevras plus les nouveaux messages de ce groupe. Tu pourras le rejoindre à nouveau si ses règles le permettent.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('cancel'.tr)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(dialogContext).colorScheme.error),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Quitter'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _client.rpc('leave_community_chat_group', params: {
        'p_salon_id': widget.salonId,
      });
      if (mounted) Navigator.of(context).pop('left');
    } catch (e) {
      _message('Impossible de quitter cette discussion : $e', error: true);
    }
  }

  Future<void> _deleteGroup() async {
    if (!_isOwner) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer le groupe ?'),
        content: const Text('Cette action supprimera définitivement le groupe et ses messages pour tous ses membres.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('cancel'.tr)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(dialogContext).colorScheme.error),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _client.rpc('delete_community_chat_group', params: {
        'p_salon_id': widget.salonId,
      });
      if (mounted) Navigator.of(context).pop('deleted');
    } catch (e) {
      _message('Impossible de supprimer le groupe : $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _buildHeader(colors),
                    const SizedBox(height: 12),
                    _buildIdentity(colors),
                    const SizedBox(height: 24),
                    if (_isAdmin) ...[
                      _section(colors, children: [
                        _fieldTile(
                          icon: Icons.edit_outlined,
                          title: 'Nom du groupe',
                          child: TextField(
                            controller: _nameController,
                            maxLength: 80,
                            decoration: const InputDecoration(
                              hintText: 'Nom de la discussion',
                              border: InputBorder.none,
                              counterText: '',
                            ),
                          ),
                        ),
                        _fieldTile(
                          icon: Icons.notes_rounded,
                          title: 'Description',
                          child: TextField(
                            controller: _descriptionController,
                            maxLength: 300,
                            minLines: 1,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              hintText: 'Description du groupe',
                              border: InputBorder.none,
                              counterText: '',
                            ),
                          ),
                        ),
                        _visibilityTile(colors),
                        ListTile(
                          leading: const Icon(Icons.save_outlined),
                          title: const Text('Enregistrer les modifications'),
                          trailing: _saving
                              ? const SizedBox(width: 20, height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.chevron_right_rounded),
                          onTap: _saving ? null : _save,
                        ),
                      ]),
                      const SizedBox(height: 16),
                      _section(colors, children: [
                        ListTile(
                          leading: const Icon(Icons.people_alt_outlined),
                          title: const Text('Membres du groupe'),
                          subtitle: Text('${_members.length} membre(s)'),
                        ),
                        for (final member in _members) _memberTile(member, colors),
                      ]),
                      const SizedBox(height: 16),
                    ],
                    _section(colors, children: [
                      ListTile(
                        leading: Icon(Icons.logout_rounded, color: colors.error),
                        title: Text('Quitter la discussion',
                          style: TextStyle(color: colors.error, fontWeight: FontWeight.w600)),
                        onTap: _leave,
                      ),
                    ]),
                    if (_isOwner) ...[
                      const SizedBox(height: 16),
                      _section(colors, children: [
                        ListTile(
                          leading: Icon(Icons.delete_forever_outlined, color: colors.error),
                          title: Text('Supprimer le groupe',
                            style: TextStyle(color: colors.error, fontWeight: FontWeight.w600)),
                          onTap: _deleteGroup,
                        ),
                      ]),
                    ],
                    const SizedBox(height: 32),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme colors) => SizedBox(
    height: 185,
    child: Stack(clipBehavior: Clip.none, children: [
      Container(
        height: 140,
        width: double.infinity,
        color: colors.primaryContainer,
        alignment: Alignment.center,
        child: Icon(Icons.forum_rounded, size: 54, color: colors.onPrimaryContainer.withOpacity(.55)),
      ),
      Positioned(top: 12, left: 16, child: _headerButton(
        icon: Icons.arrow_back_ios_new_rounded,
        onTap: () => Navigator.of(context).pop(),
      )),
      Positioned(bottom: 0, left: 20, child: GestureDetector(
        onTap: _isAdmin ? _pickAvatar : null,
        child: Stack(alignment: Alignment.bottomRight, children: [
          Container(
            width: 90, height: 90,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: colors.surface, width: 5),
              color: colors.primaryContainer,
            ),
            child: ClipOval(
              child: _newAvatar != null
                  ? Image.file(File(_newAvatar!.path), fit: BoxFit.cover)
                  : (_avatarUrl == null || _avatarUrl!.isEmpty
                      ? Icon(Icons.forum_rounded, size: 34, color: colors.onPrimaryContainer)
                      : AppCachedImage(imageUrl: _avatarUrl!, fit: BoxFit.cover)),
            ),
          ),
          if (_isAdmin) CircleAvatar(
            radius: 15,
            backgroundColor: colors.primary,
            child: Icon(Icons.camera_alt_rounded, size: 15, color: colors.onPrimary),
          ),
        ]),
      )),
    ]),
  );

  Widget _headerButton({required IconData icon, required VoidCallback onTap}) =>
      Material(
        color: Colors.black.withOpacity(.42),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(width: 38, height: 38,
            child: Icon(icon, color: Colors.white, size: 20)),
        ),
      );

  Widget _buildIdentity(ColorScheme colors) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(_nameController.text,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      Text(widget.communityName,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
      if ((_settings['description'] ?? '').toString().isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(_settings['description'].toString(),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
      ],
      const SizedBox(height: 8),
      Text('${_members.length} membre(s) • ${_visibility == 'private' ? 'Privé' : 'Public'}',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
    ]),
  );

  Widget _section(ColorScheme colors, {required List<Widget> children}) =>
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withOpacity(.28),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.outline.withOpacity(.08)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      );

  Widget _fieldTile({required IconData icon, required String title, required Widget child}) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
          Padding(padding: const EdgeInsets.only(left: 32, top: 4), child: child),
        ]),
      );

  Widget _visibilityTile(ColorScheme colors) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(children: [
      Icon(Icons.lock_outline_rounded, color: colors.onSurfaceVariant, size: 20),
      const SizedBox(width: 12),
      const Expanded(child: Text('Visibilité')),
      DropdownButton<String>(
        value: _visibility,
        underline: const SizedBox.shrink(),
        items: const [
          DropdownMenuItem(value: 'public', child: Text('Public')),
          DropdownMenuItem(value: 'private', child: Text('Privé')),
        ],
        onChanged: (value) => value == null ? null : setState(() => _visibility = value),
      ),
    ]),
  );

  Widget _memberTile(Map<String, dynamic> member, ColorScheme colors) {
    final role = (member['role'] ?? 'member').toString();
    final isSelf = member['user_id']?.toString() == _client.auth.currentUser?.id;
    final canRemove = _isOwner || (_settings['my_role'] == 'moderator' && role == 'member');
    return ListTile(
      leading: CircleAvatar(
        backgroundImage: (member['photo_url']?.toString().isNotEmpty ?? false)
            ? NetworkImage(member['photo_url'].toString()) : null,
        child: member['photo_url'] == null
            ? const Icon(Icons.person_outline_rounded) : null,
      ),
      title: Text((member['display_name'] ?? 'Membre').toString()),
      subtitle: Text(role == 'owner' ? 'Propriétaire du groupe'
          : role == 'moderator' ? 'Modérateur du groupe' : 'Membre'),
      trailing: (role != 'owner' && !isSelf)
          ? PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'moderator' || value == 'member') {
                  _changeMemberRole(member, value);
                } else if (value == 'remove') {
                  _removeMember(member);
                }
              },
              itemBuilder: (_) => [
                if (_isOwner && role == 'member')
                  const PopupMenuItem(value: 'moderator', child: Text('Nommer modérateur')),
                if (_isOwner && role == 'moderator')
                  const PopupMenuItem(value: 'member', child: Text('Retirer les droits admin')),
                if (canRemove)
                  const PopupMenuItem(value: 'remove', child: Text('Retirer du groupe')),
              ],
            )
          : null,
    );
  }
}
