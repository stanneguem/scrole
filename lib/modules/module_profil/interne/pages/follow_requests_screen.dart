import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../module_discussion_direct/externe/repositories/social_repository.dart';
import '../../../module_discussion_direct/centre/services/follow_error_mapper.dart';

class FollowRequestsScreen extends StatefulWidget {
  const FollowRequestsScreen({super.key});

  @override
  State<FollowRequestsScreen> createState() => _FollowRequestsScreenState();
}

class _FollowRequestsScreenState extends State<FollowRequestsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('follow_requests_title'.tr),
      bottom: TabBar(
        controller: _tabs,
        tabs: [Tab(text: 'follow_requests_received'.tr), Tab(text: 'follow_requests_sent'.tr)],
      ),
    ),
    body: TabBarView(
      controller: _tabs,
      children: const [_FollowRequestsTab(direction: 'received'), _FollowRequestsTab(direction: 'sent')],
    ),
  );
}

class _FollowRequestsTab extends StatefulWidget {
  const _FollowRequestsTab({required this.direction});
  final String direction;

  @override
  State<_FollowRequestsTab> createState() => _FollowRequestsTabState();
}

class _FollowRequestsTabState extends State<_FollowRequestsTab> {
  final SocialRepository _repository = SocialRepository();
  final List<Map<String, dynamic>> _items = [];
  final ScrollController _scroll = ScrollController();
  bool _loading = false;
  bool _hasMore = true;
  int _offset = 0;
  String? _error;
  RealtimeChannel? _relationshipChannel;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
    _subscribeToRelationshipChanges();
    _scroll.addListener(_onScroll);
  }

  void _subscribeToRelationshipChanges() {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) return;
    try {
      _relationshipChannel = Supabase.instance.client
          .channel('user:$uid', opts: const RealtimeChannelConfig(private: true))
          .onBroadcast(
            event: 'relationship_changed',
            callback: (payload) {
              debugPrint('[FOLLOW] relationship_changed requests payload=$payload');
              if (mounted) _load(reset: true);
            },
          )
          ..subscribe();
    } catch (e, stack) {
      debugPrint('[FOLLOW] requests relationship_changed subscription exception=$e\\n$stack');
    }
  }

  void _onScroll() {
    if (_scroll.hasClients &&
        _scroll.position.pixels >= _scroll.position.maxScrollExtent - 220 &&
        !_loading &&
        _hasMore) {
      _load();
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    if (reset) {
      _offset = 0;
      _hasMore = true;
      _items.clear();
    }
    if (!_hasMore) return;
    setState(() { _loading = true; _error = null; });
    try {
      final response = await _repository.getMyFollowRequests(direction: widget.direction, limit: 30, offset: _offset);
      final raw = response['items'];
      final page = raw is List ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _items.addAll(page);
        _offset += page.length;
        _hasMore = response['has_more'] == true && page.isNotEmpty;
      });
    } catch (e, stack) {
      debugPrint('[FOLLOW] get_my_follow_requests direction=${widget.direction} exception=$e\\n$stack');
      if (mounted) setState(() => _error = FollowErrorMapper.keyFor(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _respond(Map<String, dynamic> item, bool accepted) async {
    final user = item['user'] is Map ? Map<String, dynamic>.from(item['user'] as Map) : <String, dynamic>{};
    final userId = (user['user_id'] ?? user['id'] ?? '').toString();
    final requestId = (item['request_id'] ?? '').toString();
    if (userId.isEmpty || requestId.isEmpty) return;
    try {
      await _repository.respondFollowRequest(requestId, accepted, targetUserId: userId);
      await _load(reset: true);
    } catch (e, stack) {
      debugPrint('[FOLLOW] respond_follow_request request=$requestId exception=$e\\n$stack');
      if (mounted) Get.snackbar('error_title'.tr, FollowErrorMapper.keyFor(e).tr);
    }
  }

  Future<void> _cancel(Map<String, dynamic> item) async {
    final user = item['user'] is Map ? Map<String, dynamic>.from(item['user'] as Map) : <String, dynamic>{};
    final userId = (user['user_id'] ?? user['id'] ?? '').toString();
    if (userId.isEmpty) return;
    try {
      await _repository.cancelFollowRequest(userId);
      await _load(reset: true);
    } catch (e, stack) {
      debugPrint('[FOLLOW] cancel_follow_request user=$userId exception=$e\\n$stack');
      if (mounted) Get.snackbar('error_title'.tr, 'follow_action_failed'.tr);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    final channel = _relationshipChannel;
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_error != null && _items.isEmpty && !_loading) {
      return Center(child: Text((_error ?? 'follow_action_impossible').tr));
    }
    if (_items.isEmpty && _loading) return const Center(child: CircularProgressIndicator());
    if (_items.isEmpty) return Center(child: Text('profile_contacts_empty'.tr));
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView.separated(
        controller: _scroll,
        padding: const EdgeInsets.all(12),
        itemCount: _items.length + (_loading ? 1 : 0),
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index >= _items.length) return const Center(child: CircularProgressIndicator());
          final item = _items[index];
          final user = item['user'] is Map ? Map<String, dynamic>.from(item['user'] as Map) : <String, dynamic>{};
          final first = (user['first_name'] ?? '').toString().trim();
          final last = (user['last_name'] ?? '').toString().trim();
          final fullName = '$first $last'.trim();
          final username = (user['pseudo'] ?? user['username'] ?? '').toString();
          final photo = user['photo_url']?.toString();
          final status = (item['status'] ?? 'pending').toString();
          final retryAt = item['next_retry_at']?.toString();
          return ListTile(
            leading: CircleAvatar(
              backgroundImage: photo != null && photo.isNotEmpty ? NetworkImage(photo) : null,
              child: photo == null || photo.isEmpty ? Text((fullName.isEmpty ? username : fullName).isNotEmpty ? (fullName.isEmpty ? username : fullName)[0].toUpperCase() : '?') : null,
            ),
            title: Text(fullName.isEmpty ? username : fullName, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(username.startsWith('@') ? username : '@$username'),
                if (widget.direction == 'sent' && status == 'rejected' && retryAt != null)
                  Text('follow_retry_at'.trParams({'date': retryAt}), style: TextStyle(color: scheme.error, fontSize: 12)),
              ],
            ),
            trailing: widget.direction == 'received'
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(onPressed: () => _respond(item, false), icon: Icon(Icons.close_rounded, color: scheme.error)),
                      IconButton(onPressed: () => _respond(item, true), icon: Icon(Icons.check_rounded, color: AppColors.success)),
                    ],
                  )
                : status == 'pending'
                    ? TextButton(onPressed: () => _cancel(item), child: Text('cancel'.tr))
                    : const SizedBox.shrink(),
          );
        },
      ),
    );
  }
}
