import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CommunityAdminChatGroupsScreen extends StatefulWidget {
  const CommunityAdminChatGroupsScreen({super.key, required this.communityId, required this.communityName});
  final String communityId;
  final String communityName;
  @override
  State<CommunityAdminChatGroupsScreen> createState() => _CommunityAdminChatGroupsScreenState();
}

class _CommunityAdminChatGroupsScreenState extends State<CommunityAdminChatGroupsScreen> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _groups = [];
  bool _loading = true;
  final Set<String> _deleting = {};

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final rows = await _db.rpc('list_community_admin_salons', params: {'p_community_id': widget.communityId});
      if (!mounted) return;
      setState(() {
        _groups = (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('community_admin_salons_load_error'.tr, true);
    }
  }

  void _toast(String value, [bool error = false]) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(value),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _delete(Map<String, dynamic> group) async {
    final id = group['id']?.toString() ?? '';
    if (id.isEmpty || _deleting.contains(id)) return;
    final name = (group['name'] ?? '').toString();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.delete_forever_outlined, color: Theme.of(ctx).colorScheme.error),
        title: Text('community_admin_salon_delete_title'.tr),
        content: Text('community_admin_salon_delete_body'.trParams({'name': name})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('cancel'.tr)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('delete'.tr),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting.add(id));
    try {
      await _db.rpc('delete_community_chat_group', params: {'p_salon_id': id});
      if (!mounted) return;
      setState(() { _groups.removeWhere((e) => e['id']?.toString() == id); _deleting.remove(id); });
      _toast('community_admin_salon_deleted'.tr);
    } catch (_) {
      if (!mounted) return;
      setState(() => _deleting.remove(id));
      _toast('community_admin_salon_delete_error'.tr, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('community_admin_salons_title'.tr),
        Text(widget.communityName, style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
      ])),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _groups.isEmpty
                  ? ListView(children: [
                      const SizedBox(height: 120),
                      Icon(Icons.forum_outlined, size: 52, color: colors.onSurfaceVariant),
                      const SizedBox(height: 14),
                      Center(child: Text('community_admin_salons_empty'.tr)),
                    ])
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _groups.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final group = _groups[index];
                        final id = group['id'].toString();
                        final avatar = group['avatar_url']?.toString() ?? '';
                        final isPrivate = group['visibility'] == 'private';
                        return Material(
                          color: colors.surfaceContainerHighest.withOpacity(.4),
                          borderRadius: BorderRadius.circular(18),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            leading: CircleAvatar(
                              backgroundColor: colors.primaryContainer,
                              backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
                              child: avatar.isEmpty ? Icon(isPrivate ? Icons.lock_outline : Icons.forum_outlined) : null,
                            ),
                            title: Text((group['name'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text('community_admin_salon_meta'.trParams({
                              'count': (group['member_count'] ?? 0).toString(),
                              'visibility': isPrivate ? 'chat_groups_private'.tr : 'chat_groups_public'.tr,
                            })),
                            trailing: IconButton(
                              tooltip: 'delete'.tr,
                              onPressed: _deleting.contains(id) ? null : () => _delete(group),
                              icon: _deleting.contains(id)
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                  : Icon(Icons.delete_outline_rounded, color: colors.error),
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
