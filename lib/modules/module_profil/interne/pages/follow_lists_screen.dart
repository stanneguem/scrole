import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/routes/app_pages.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/widgets/user_certified_badge.dart';
import '../../../module_discussion_direct/externe/repositories/social_repository.dart';
import '../../../module_discussion_direct/centre/services/follow_error_mapper.dart';

class FollowListsScreen extends StatelessWidget {
  const FollowListsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final args = Get.arguments is Map ? Map<String, dynamic>.from(Get.arguments as Map) : <String, dynamic>{};
    final userId = args['userId']?.toString();
    final initialTab = (args['initialTab'] as num?)?.toInt() ?? 0;
    return DefaultTabController(
      length: 3,
      initialIndex: initialTab.clamp(0, 2).toInt(),
      child: Scaffold(
        appBar: AppBar(
          title: Text('follow_lists_title'.tr),
          bottom: TabBar(
            tabs: [
              Tab(text: 'follow_tab_followers'.tr),
              Tab(text: 'follow_tab_following'.tr),
              Tab(text: 'follow_tab_friends'.tr),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _FollowListTab(kind: 'followers', userId: userId),
            _FollowListTab(kind: 'following', userId: userId),
            _FollowListTab(kind: 'friends', userId: userId),
          ],
        ),
      ),
    );
  }
}

class _FollowListTab extends StatefulWidget {
  const _FollowListTab({required this.kind, this.userId});
  final String kind;
  final String? userId;

  @override
  State<_FollowListTab> createState() => _FollowListTabState();
}

class _FollowListTabState extends State<_FollowListTab> {
  final SocialRepository _repository = SocialRepository();
  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();
  Timer? _debounce;
  final List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  bool _hasMore = true;
  int _offset = 0;
  String? _error;
  RealtimeChannel? _relationshipChannel;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
    _scroll.addListener(_onScroll);
    _subscribeToRelationshipChanges();
  }

  @override
  void didUpdateWidget(covariant _FollowListTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind || oldWidget.userId != widget.userId) _load(reset: true);
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
              debugPrint('[FOLLOW] relationship_changed list=${widget.kind} payload=$payload');
              if (mounted) _load(reset: true);
            },
          )
          ..subscribe();
    } catch (e, stack) {
      debugPrint('[FOLLOW] list relationship_changed subscription exception=$e\\n$stack');
    }
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 220 && !_loading && _hasMore) {
      _load();
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _load(reset: true));
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    if (reset) {
      _offset = 0;
      _hasMore = true;
      _items.clear();
    }
    if (!_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _repository.getFollowList(
        widget.kind,
        userId: widget.userId,
        limit: 30,
        offset: _offset,
        query: _search.text.trim().isEmpty ? null : _search.text.trim(),
      );
      final raw = result['items'];
      final page = raw is List
          ? raw.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _items.addAll(page);
        _offset += page.length;
        _hasMore = result['has_more'] == true && page.isNotEmpty;
      });
    } catch (e, stack) {
      debugPrint('[FOLLOW] get_${widget.kind} exception=$e\\n$stack');
      if (mounted) setState(() => _error = FollowErrorMapper.keyFor(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _followAction(Map<String, dynamic> item) async {
    final id = (item['user_id'] ?? '').toString();
    if (id.isEmpty) return;
    try {
      if (item['request_sent'] == true) {
        await _repository.cancelFollowRequest(id);
      } else if (item['i_follow'] == true) {
        await _repository.unfollowUser(id);
      } else {
        await _repository.followUser(id);
      }
      await _load(reset: true);
    } catch (e, stack) {
      debugPrint('[FOLLOW] action user=$id exception=$e\\n$stack');
      if (mounted) Get.snackbar('error_title'.tr, FollowErrorMapper.keyFor(e).tr);
    }
  }

  Future<void> _menuAction(String action, Map<String, dynamic> item) async {
    final id = (item['user_id'] ?? '').toString();
    if (id.isEmpty) return;
    try {
      if (action == 'remove_follower') {
        await _repository.removeFollower(id);
      } else if (action == 'remove_friend') {
        await _repository.removeFriend(id);
      }
      await _load(reset: true);
    } catch (e, stack) {
      debugPrint('[FOLLOW] $action user=$id exception=$e\\n$stack');
      if (mounted) Get.snackbar('error_title'.tr, 'follow_action_failed'.tr);
    }
  }

  String _buttonLabel(Map<String, dynamic> item) {
    if (item['is_friend'] == true) return 'follow_state_friends'.tr;
    if (item['request_sent'] == true) return 'follow_state_requested'.tr;
    if (item['i_follow'] == true) return 'follow_state_following'.tr;
    if (item['follows_me'] == true) return 'follow_state_follow_back'.tr;
    return 'follow_state_follow'.tr;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
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
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text((_error ?? 'follow_action_impossible').tr),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: () => _load(reset: true), child: Text('retry'.tr)),
        ]),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _search,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'profile_contacts_search'.tr,
              prefixIcon: const Icon(Icons.search_rounded),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: _items.isEmpty && _loading
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
                  ? Center(child: Text('profile_contacts_empty'.tr))
                  : RefreshIndicator(
                      onRefresh: () => _load(reset: true),
                      child: ListView.separated(
                        controller: _scroll,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        itemCount: _items.length + (_loading ? 1 : 0),
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          if (index >= _items.length) return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          );
                          final item = _items[index];
                          final id = (item['user_id'] ?? '').toString();
                          final first = (item['first_name'] ?? '').toString().trim();
                          final last = (item['last_name'] ?? '').toString().trim();
                          final display = '$first $last'.trim();
                          final pseudo = (item['pseudo'] ?? item['username'] ?? '').toString();
                          final photo = item['photo_url']?.toString();
                          final certified = item['is_certified'] == true || item['is_certified'] == 1 || item['is_certified']?.toString().toLowerCase() == 'true';
                          final isCurrentUser = id.isNotEmpty && id == Supabase.instance.client.auth.currentUser?.id;
                          final isFollowing = item['i_follow'] == true;
                          final label = _buttonLabel(item);
                          return ListTile(
                            onTap: id.isEmpty || isCurrentUser
                                ? null
                                : () => Get.toNamed(AppPages.externalProfilePath(id)),
                            leading: CircleAvatar(
                              backgroundImage: photo != null && photo.isNotEmpty ? NetworkImage(photo) : null,
                              child: photo == null || photo.isEmpty
                                  ? Text((display.isNotEmpty ? display : pseudo).isNotEmpty ? (display.isNotEmpty ? display : pseudo)[0].toUpperCase() : '?')
                                  : null,
                            ),
                            title: Row(children: [
                              Flexible(child: Text(display.isEmpty ? pseudo : display, maxLines: 1, overflow: TextOverflow.ellipsis)),
                              if (certified) ...[
                                const SizedBox(width: 4),
                                UserCertifiedBadge(size: 16, showTooltip: true, userId: id),
                              ],
                            ]),
                            subtitle: Text(pseudo.startsWith('@') ? pseudo : '@$pseudo'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!isCurrentUser)
                                  TextButton(
                                    onPressed: id.isEmpty ? null : () => _followAction(item),
                                    child: Text(label, style: AppTextStyles.bodySmall.copyWith(
                                      color: isFollowing || item['is_friend'] == true ? scheme.primary : scheme.onSurface,
                                      fontWeight: FontWeight.w600,
                                    )),
                                  ),
                                if (widget.kind == 'followers' || widget.kind == 'friends')
                                  PopupMenuButton<String>(
                                    onSelected: (action) => _menuAction(action, item),
                                    itemBuilder: (_) => [
                                      if (widget.kind == 'followers')
                                        PopupMenuItem(value: 'remove_follower', child: Text('follow_remove_follower_action'.tr)),
                                      if (widget.kind == 'friends')
                                        PopupMenuItem(value: 'remove_friend', child: Text('follow_remove_friend_action'.tr)),
                                    ],
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}
