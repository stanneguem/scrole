import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:scrole/modules/module_communautes/interne/pages/community_chat_group_edit_info_screen.dart';
import 'package:scrole/modules/module_communautes/interne/pages/community_chat_group_members_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'community_chat_group_access_rules_screen.dart';
import 'community_chat_group_join_requests_screen.dart';
import 'community_chat_group_message_permissions_screen.dart';
import 'community_chat_group_visibility_screen.dart';

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
  final _db = Supabase.instance.client;

  Map<String, dynamic> _data = {};
  int _pending = 0;
  bool _loading = true;
  bool _saving = false;
  bool _deleting = false;

  bool get _owner => _data['my_role'] == 'owner';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await _db.rpc(
        'get_community_chat_group_settings',
        params: {'p_salon_id': widget.salonId},
      );
      final data = Map<String, dynamic>.from(raw as Map);
      final requests = await _db.rpc(
        'get_community_chat_group_requests',
        params: {'p_salon_id': widget.salonId},
      );

      if (!mounted) return;
      setState(() {
        _data = data;
        _pending = (requests as List).length;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('community_chat_management_load_error'.trParams({
        'error': e.toString(),
      }));
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _visibility(String value) async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      await _db.rpc(
        'update_community_chat_group_settings',
        params: {
          'p_salon_id': widget.salonId,
          'p_name': _data['name'],
          'p_description': _data['description'] ?? '',
          'p_visibility': value,
        },
      );
      await _load();
      _toast('community_chat_management_visibility_updated'.tr);
    } catch (e) {
      _toast('community_chat_management_visibility_error'.trParams({
        'error': e.toString(),
      }));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _requests() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CommunityChatGroupJoinRequestsScreen(
          salonId: widget.salonId,
          groupName: widget.groupName,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _delete() async {
    if (_deleting) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final colors = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          icon: Icon(
            Icons.delete_forever_outlined,
            color: colors.error,
            size: 30,
          ),
          title: Text('community_chat_delete_title'.tr),
          content: Text('community_chat_delete_body'.tr),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text('community_chat_delete_cancel'.tr),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: colors.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text('community_chat_delete_confirm'.tr),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await _db.rpc(
        'delete_community_chat_group',
        params: {'p_salon_id': widget.salonId},
      );
      if (mounted) Navigator.of(context).pop('deleted');
    } catch (e) {
      _toast('community_chat_delete_error'.trParams({
        'error': e.toString(),
      }));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  // The section itself is a Material surface. Keeping the background and
  // ListTile ink on the same Material avoids the DecoratedBox/ink assertion.
  Widget _section(ColorScheme colors, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: colors.surfaceContainerHighest.withOpacity(.28),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: colors.outline.withOpacity(.08),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      ),
    );
  }

  Widget _tile(
    ColorScheme colors,
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap, {
    Color? color,
    String? trailing,
  }) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 17,
        vertical: 7,
      ),
      leading: Icon(icon, color: color ?? colors.onSurfaceVariant),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
      subtitle: Text(subtitle),
      trailing: trailing == null
          ? Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant)
          : Text(
              trailing,
              style: TextStyle(
                color: colors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
      onTap: _saving || _deleting ? null : onTap,
      ),
    );
  }

  Future<void> _editInfo() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CommunityChatGroupEditInfoScreen(
          salonId: widget.salonId,
          initialData: _data,
        ),
      ),
    );
    if (changed == true && mounted) await _load();
  }

  Future<void> _members() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CommunityChatGroupMembersScreen(
          salonId: widget.salonId,
          groupName: widget.groupName,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _visibilityScreen() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CommunityChatGroupVisibilityScreen(
          salonId: widget.salonId,
          initialData: _data,
        ),
      ),
    );
    if (changed == true && mounted) await _load();
  }

  Future<void> _messagePermissions() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CommunityChatGroupMessagePermissionsScreen(
          salonId: widget.salonId,
        ),
      ),
    );
    if (changed == true && mounted) await _load();
  }

  Future<void> _accessRules() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CommunityChatGroupAccessRulesScreen(
          salonId: widget.salonId,
          initialData: _data,
        ),
      ),
    );
    if (changed == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: Text('community_chat_management_title'.tr),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final visibility = (_data['visibility'] ?? 'public').toString();

    return Scaffold(
      appBar: AppBar(
        title: Text('community_chat_management_title'.tr),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 14, bottom: 32),
        children: [
          _section(colors, [
            _tile(
              colors,
              Icons.edit_outlined,
              'community_chat_management_edit_info'.tr,
              'community_chat_management_edit_info_desc'.tr,
              _editInfo,
            ),
            _tile(
              colors,
              Icons.people_alt_outlined,
              'community_chat_management_members'.tr,
              'community_chat_management_members_desc'.tr,
              _members,
            ),
            _tile(
              colors,
              Icons.person_add_alt_1_outlined,
              'community_chat_management_join_requests'.tr,
              'community_chat_management_join_requests_desc'.tr,
              _requests,
              trailing: _pending == 0 ? '' : _pending.toString(),
            ),
          ]),
          const SizedBox(height: 16),
          _section(colors, [
            _tile(
              colors,
              Icons.lock_outline_rounded,
              'community_chat_management_visibility'.tr,
              'community_chat_management_visibility_desc'.tr,
              _visibilityScreen,
              trailing: visibility == 'private'
                  ? 'community_chat_management_private'.tr
                  : 'community_chat_management_public'.tr,
            ),
            _tile(
              colors,
              Icons.chat_bubble_outline_rounded,
              'community_chat_management_message_permissions'.tr,
              'community_message_permissions_screen_intro'.tr,
              _messagePermissions,
              trailing: '',
            ),
            _tile(
              colors,
              Icons.admin_panel_settings_outlined,
              'community_chat_management_access_rules'.tr,
              'community_chat_management_access_rules_desc'.tr,
              _accessRules,
            ),
          ]),
          const SizedBox(height: 16),
          if (_owner)
            _section(colors, [
              _tile(
                colors,
                Icons.delete_forever_outlined,
                'community_chat_management_delete'.tr,
                'community_chat_management_delete_desc'.tr,
                _delete,
                color: colors.error,
                trailing: _deleting ? '…' : '',
              ),
            ]),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Text(
              _owner
                  ? 'community_chat_management_owner_note'.tr
                  : 'community_chat_management_admin_note'.tr,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
