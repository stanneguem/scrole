import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:scrole/shared/widgets/app_cached_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'community_chat_group_management_screen.dart';
import 'community_chat_group_members_screen.dart';

class CommunityChatGroupSettingsScreen extends StatefulWidget {
  const CommunityChatGroupSettingsScreen({super.key, required this.salonId, required this.initialName, required this.communityName, this.initialAvatarUrl});
  final String salonId;
  final String initialName;
  final String communityName;
  final String? initialAvatarUrl;
  @override
  State<CommunityChatGroupSettingsScreen> createState() => _CommunityChatGroupSettingsScreenState();
}

class _CommunityChatGroupSettingsScreenState extends State<CommunityChatGroupSettingsScreen> {
  final _client = Supabase.instance.client;
  Map<String, dynamic> _data = {};
  bool _loading = true, _saving = false, _notifications = true, _media = true, _expanded = false;
  bool get _isAdmin => _data['is_salon_admin'] == true;
  bool get _isOwner => _data['my_role'] == 'owner';
  String get _name => (_data['name'] ?? widget.initialName).toString();
  String get _description => (_data['description'] ?? '').toString();
  String? get _avatar {
    final value = _data['avatar_url']?.toString() ?? widget.initialAvatarUrl;
    return value == null || value.isEmpty ? null : value;
  }

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final raw = await _client.rpc('get_community_chat_group_settings', params: {'p_salon_id': widget.salonId});
      final data = Map<String, dynamic>.from(raw as Map);
      if (!mounted) return;
      setState(() {
        _data = data;
        _notifications = data['notifications_enabled'] != false;
        _media = data['media_visibility_enabled'] != false;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('community_chat_settings_load_error'.trParams({'error': e.toString()}));
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
  }

  String _formatCount(dynamic raw) {
    final n = (raw as num?)?.toDouble() ?? 0;
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(n % 1000000 == 0 ? 0 : 1).replaceAll('.', ',')} M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1).replaceAll('.', ',')} K';
    return n.toInt().toString();
  }

  Future<void> _preference({bool? notifications, bool? media}) async {
    if (_saving) return;
    final oldN = _notifications, oldM = _media;
    setState(() {
      _saving = true;
      if (notifications != null) _notifications = notifications;
      if (media != null) _media = media;
    });
    try {
      await _client.rpc('update_community_chat_group_preferences', params: {
        'p_salon_id': widget.salonId,
        'p_notifications_enabled': _notifications,
        'p_media_visibility_enabled': _media,
      });
    } catch (e) {
      if (mounted) {
        setState(() { _notifications = oldN; _media = oldM; });
        _toast('community_chat_settings_save_error'.trParams({'error': e.toString()}));
      }
    } finally { if (mounted) setState(() => _saving = false); }
  }

  Future<void> _members() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) =>
      CommunityChatGroupMembersScreen(salonId: widget.salonId, groupName: _name)));
    if (mounted) _load();
  }

  Future<void> _management() async {
    final result = await Navigator.of(context).push<dynamic>(MaterialPageRoute(builder: (_) =>
      CommunityChatGroupManagementScreen(salonId: widget.salonId, groupName: _name)));
    if (!mounted) return;
    if (result == 'deleted') { Navigator.of(context).pop('deleted'); return; }
    _load();
  }

  Future<void> _leave() async {
    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('community_chat_settings_leave_title'.tr),
      content: const Text('community_chat_settings_leave_body'.tr),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('cancel'.tr)),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
          onPressed: () => Navigator.pop(ctx, true), child: Text('community_chat_settings_leave_confirm'.tr)),
      ],
    ));
    if (yes != true) return;
    try {
      await _client.rpc('leave_community_chat_group', params: {'p_salon_id': widget.salonId});
      if (mounted) Navigator.of(context).pop('left');
    } catch (e) { _toast('community_chat_settings_leave_error'.trParams({'error': e.toString()})); }
  }

  Widget _section(ColorScheme c, List<Widget> children) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    child: Material(
      color: c.surfaceContainerHighest.withOpacity(.28),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: c.outline.withOpacity(.08)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    ),
  );

  Widget _action(ColorScheme c, IconData icon, String title, VoidCallback tap, {String? subtitle, bool danger = false}) =>
    Material(color: Colors.transparent, child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 17, vertical: 4),
      leading: Icon(icon, size: 21, color: danger ? c.error : c.onSurfaceVariant),
      title: Text(title, style: TextStyle(color: danger ? c.error : c.onSurface, fontWeight: FontWeight.w600)),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: Icon(Icons.chevron_right_rounded, color: c.onSurfaceVariant.withOpacity(.65)), onTap: tap));

  Widget _switch(ColorScheme c, IconData icon, String title, String subtitle, bool value, ValueChanged<bool> changed) =>
    Material(color: Colors.transparent, child: ListTile(
      contentPadding: const EdgeInsets.fromLTRB(17, 3, 12, 3),
      leading: Icon(icon, size: 21, color: c.onSurfaceVariant),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      trailing: Switch.adaptive(value: value, onChanged: _saving ? null : changed, activeColor: const Color(0xFFF0642C))));

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    if (_loading) return Scaffold(backgroundColor: c.surface, body: const Center(child: CircularProgressIndicator()));
    return Scaffold(backgroundColor: c.surface, body: SafeArea(child: RefreshIndicator(
      onRefresh: _load, child: ListView(padding: EdgeInsets.zero, children: [
        _header(c),
        const SizedBox(height: 12),
        _identity(c),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Text(
            'community_chat_settings_personal_note'.tr,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant),
          ),
        ),
        _section(c, [
          _switch(c, Icons.notifications_none_rounded, 'community_chat_settings_notifications'.tr,
            'community_chat_settings_notifications_desc'.tr, _notifications,
            (v) => _preference(notifications: v)),
          _switch(c, Icons.photo_library_outlined, 'community_chat_settings_media'.tr,
            'community_chat_settings_media_desc'.tr, _media,
            (v) => _preference(media: v)),
        ]),
        const SizedBox(height: 16),
        if (_isAdmin) ...[
          _section(c, [_action(c, Icons.settings_outlined, 'community_chat_settings_management'.tr,
            _management, subtitle: 'community_chat_settings_management_desc'.tr)]),
          const SizedBox(height: 16),
        ],
        _section(c, [_action(c, Icons.logout_rounded, 'Quitter la discussion', _leave, danger: true)]),
        const SizedBox(height: 32),
      ]),
    )));
  }

  Widget _header(ColorScheme c) => SizedBox(height: 185, child: Stack(clipBehavior: Clip.none, children: [
    Container(height: 140, width: double.infinity, color: c.surfaceContainerHighest.withOpacity(.45)),
    Positioned(top: 12, left: 16, child: _headerButton(Icons.arrow_back_ios_new_rounded, () => Navigator.of(context).pop())),
    Positioned(bottom: 0, left: 20, child: Container(width: 90, height: 90,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.surface, width: 5), color: c.primaryContainer),
      child: ClipOval(child: _avatar == null
        ? Icon(Icons.forum_rounded, size: 34, color: c.onPrimaryContainer)
        : AppCachedImage(imageUrl: _avatar!, fit: BoxFit.cover)))),
  ]));

  Widget _headerButton(IconData icon, VoidCallback tap) => Material(
    color: Colors.black.withOpacity(.42), shape: const CircleBorder(),
    child: InkWell(onTap: tap, customBorder: const CircleBorder(),
      child: SizedBox(width: 38, height: 38, child: Icon(icon, color: Colors.white, size: 20))));

  Widget _identity(ColorScheme c) => Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_name, maxLines: 2, overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: c.onSurface, fontWeight: FontWeight.w800)),
        const SizedBox(height: 3),
        Text(widget.communityName, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant)),
        if (_description.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          LayoutBuilder(builder: (context, constraints) {
            final style = Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.onSurfaceVariant);
            final painter = TextPainter(
              text: TextSpan(text: _description, style: style),
              textDirection: Directionality.of(context),
              maxLines: 2,
            )..layout(maxWidth: constraints.maxWidth);
            final hasMore = painter.didExceedMaxLines;
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_description, maxLines: _expanded ? null : 2,
                overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                style: style),
              if (hasMore)
                GestureDetector(onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(padding: const EdgeInsets.only(top: 3),
                    child: Text(_expanded ? 'community_chat_settings_see_less'.tr : 'community_chat_settings_see_more'.tr,
                      style: TextStyle(color: c.primary, fontWeight: FontWeight.w600)))),
            ]);
          }),
        ],
      ])),
      const SizedBox(width: 12),
      Padding(padding: const EdgeInsets.only(top: 5), child: Column(children: [
        Material(color: c.surfaceContainerHighest.withOpacity(.65), borderRadius: BorderRadius.circular(13),
          child: InkWell(onTap: _members, borderRadius: BorderRadius.circular(13),
            child: SizedBox(width: 48, height: 46, child: Icon(Icons.person_outline_rounded, color: c.onSurface)))),
        const SizedBox(height: 5),
        Text(_formatCount(_data['member_count']), style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: c.onSurfaceVariant, fontWeight: FontWeight.w700)),
      ])),
    ]));
}
