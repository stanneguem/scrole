import 'package:flutter/material.dart';
import 'package:scrole/modules/module_communautes/interne/pages/community_chat_group_edit_info_screen.dart';
import 'package:scrole/modules/module_communautes/interne/pages/community_chat_group_members_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CommunityChatGroupManagementScreen extends StatefulWidget {
  const CommunityChatGroupManagementScreen({
    super.key,
    required this.salonId,
    required this.groupName,
  });
  final String salonId;
  final String groupName;

  @override
  State<CommunityChatGroupManagementScreen> createState() =>
      _CommunityChatGroupManagementScreenState();
}

class _CommunityChatGroupManagementScreenState
    extends State<CommunityChatGroupManagementScreen> {
  Map<String, dynamic> _data = {};
  bool _loading = true;
  bool _saving = false;

  bool get _isOwner => _data['my_role'] == 'owner';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await Supabase.instance.client.rpc(
        'get_community_chat_group_settings',
        params: {'p_salon_id': widget.salonId},
      );
      if (!mounted) return;
      setState(() {
        _data = Map<String, dynamic>.from(result as Map);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible de charger la gestion : $error')),
      );
    }
  }

  Future<void> _setVisibility(String visibility) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.rpc(
        'update_community_chat_group_settings',
        params: {
          'p_salon_id': widget.salonId,
          'p_name': _data['name'],
          'p_description': _data['description'] ?? '',
          'p_visibility': visibility,
        },
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Visibilité mise à jour.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossible de modifier la visibilité : $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Éliminer la discussion ?'),
        content: const Text(
          'Cette action supprimera définitivement la discussion, ses messages et ses membres. Elle est irréversible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Éliminer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await Supabase.instance.client.rpc('delete_community_chat_group',
          params: {'p_salon_id': widget.salonId});
      if (mounted) Navigator.of(context).pop('deleted');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossible de supprimer la discussion : $error')),
        );
      }
    }
  }

  Widget _section(ColorScheme colors, List<Widget> children) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: colors.surfaceContainerHighest.withOpacity(.28),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: colors.outline.withOpacity(.08)),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(children: children),
  );

  Widget _tile({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    Color? color,
  }) => ListTile(
    leading: Icon(icon, color: color),
    title: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
    subtitle: subtitle == null ? null : Text(subtitle),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final visibility = (_data['visibility'] ?? 'public').toString();
    if (_loading) {
      return Scaffold(appBar: AppBar(title: const Text('Gestion de la discussion')),
        body: const Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Gestion de la discussion')),
      body: ListView(
        padding: const EdgeInsets.only(top: 14, bottom: 32),
        children: [
          _section(colors, [
            _tile(
              icon: Icons.edit_outlined,
              title: 'Modifier les informations',
              subtitle: 'Nom, description et photo de la discussion',
              onTap: () async {
                final changed = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => CommunityChatGroupEditInfoScreen(
                      salonId: widget.salonId,
                      initialData: _data,
                    ),
                  ),
                );
                if (changed == true) _load();
              },
            ),
            _tile(
              icon: Icons.people_alt_outlined,
              title: 'Gérer les membres',
              subtitle: '${_data['member_count'] ?? 0} membre(s)',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => CommunityChatGroupMembersScreen(
                  salonId: widget.salonId,
                  groupName: widget.groupName,
                ),
              )),
            ),
          ]),
          const SizedBox(height: 16),
          _section(colors, [
            ListTile(
              leading: const Icon(Icons.lock_outline_rounded),
              title: const Text('Type de discussion',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Définir qui peut trouver et rejoindre ce groupe'),
              trailing: DropdownButton<String>(
                value: visibility == 'private' ? 'private' : 'public',
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: 'public', child: Text('Publique')),
                  DropdownMenuItem(value: 'private', child: Text('Privée')),
                ],
                onChanged: _saving ? null : (value) {
                  if (value != null) _setVisibility(value);
                },
              ),
            ),
            if (_isOwner)
              _tile(
                icon: Icons.delete_forever_outlined,
                title: 'Éliminer la discussion',
                subtitle: 'Supprimer définitivement le groupe et son contenu',
                color: colors.error,
                onTap: _delete,
              ),
          ]),
        ],
      ),
    );
  }
}
