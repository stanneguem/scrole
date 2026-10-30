import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';
import 'package:scrole/shared/widgets/video_trim_screen.dart';
import 'package:scrole/app/repository_global/r2_media_repository.dart';
import 'package:scrole/app/service_global/connectivity_service.dart';
import 'package:scrole/modules/module_communautes/centre/persistence/salon_chat_local_cache.dart';
import 'package:scrole/modules/module_discussion_direct/centre/services/chat_media_cache.dart';
import 'package:scrole/modules/module_discussion_direct/interne/pages/chat_media_viewer_screen.dart';
import 'package:scrole/modules/module_discussion_direct/interne/widgets/chat_cached_media.dart';
import 'package:scrole/app/service_global/notification_service.dart';
import 'package:scrole/modules/module_discussion_direct/interne/widgets/direct_voice_message_player.dart';
import 'package:scrole/shared/models/chat_message.dart' as legacy;
import 'package:scrole/shared/widgets/media_gallery_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:get/get.dart';
import 'create_community_chat_group_screen.dart';
import 'community_chat_group_settings_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Discussions textuelles d'une communauté : groupes publics/privés et demandes d'accès.
class CommunityChatGroupsScreen extends StatefulWidget {
  final String communityId;
  final String communityName;
  const CommunityChatGroupsScreen({super.key, required this.communityId, required this.communityName});

  @override
  State<CommunityChatGroupsScreen> createState() => _CommunityChatGroupsScreenState();
}

class _CommunityChatGroupsScreenState extends State<CommunityChatGroupsScreen> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _groups = [];
  bool _loading = true;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _client.rpc('list_community_chat_groups_with_preview', params: {'p_community_id': widget.communityId});
      final groups = (data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      // Les images de salon sont publiques sur R2 : l'URL est enregistrée en base.
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${'chat_groups_load_error'.tr} : $e')));
    }
  }

  Future<void> _createGroup() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateCommunityChatGroupScreen(
          communityId: widget.communityId,
        ),
      ),
    );
    if (created == true && mounted) {
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('chat_groups_created'.tr)),
      );
    }
  }

  String _newUuid() {
    // UUID v4 generated with a cryptographically secure random source.
    final secureRandom = math.Random.secure();
    final random = List<int>.generate(16, (_) => secureRandom.nextInt(256));
    random[6] = (random[6] & 0x0f) | 0x40;
    random[8] = (random[8] & 0x3f) | 0x80;
    final hex = random.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0,8)}-${hex.substring(8,12)}-${hex.substring(12,16)}-${hex.substring(16,20)}-${hex.substring(20,32)}';
  }

  Future<void> _openOrRequest(Map<String, dynamic> group) async {
    // Never trust the cached my_status returned by the list RPC: a removed
    // member can still have a stale row in the in-memory list.
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    final salonId = group['id'].toString();
    Map<String, dynamic>? membership;
    try {
      membership = await _client
          .from('community_salon_members')
          .select('user_id')
          .eq('salon_id', salonId)
          .eq('user_id', userId)
          .maybeSingle();
    } catch (e, st) {
      debugPrint('[CommunityChatGroups] Membership lookup failed; opening preview safely: $e');
      debugPrintStack(stackTrace: st);
      // Fail closed: a lookup error must never grant access to salon messages.
      membership = null;
    }
    if (!mounted) return;
    if (membership != null) {
      await _openConversation(group);
      return;
    }
    // Every non-member must see the preview, including public salons and
    // users whose old my_status value still says "member".
    final action = await showModalBottomSheet<String>(
      context: context, isScrollControlled: true, useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CommunityChatSalonPreviewSheet(
        group: group, communityName: widget.communityName,
        onJoin: () async {
          final result = await _client.rpc('request_community_chat_group_access', params: {'p_salon_id': group['id']});
          return result is Map ? (result['status'] ?? 'accepted').toString() : 'accepted';
        },
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'accepted') { await _openConversation(group); }
    else if (action == 'pending') {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('chat_groups_request_sent'.tr)));
      await _load();
    }
  }

  Future<void> _openConversation(Map<String, dynamic> group) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CommunityChatGroupConversation(
      salonId: group['id'].toString(), name: group['name']?.toString() ?? 'Discussion',
      communityName: widget.communityName, avatarUrl: group['avatar_url']?.toString(),
    )));
    await _load();
  }
  Future<void> _showRequests(Map<String, dynamic> group) async {
    try {
      final data = await _client.rpc('get_community_chat_group_requests', params: {'p_salon_id': group['id']});
      if (!mounted) return;
      final requests = (data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      await showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (sheetContext) => SafeArea(
        child: SizedBox(height: MediaQuery.of(context).size.height * .65, child: Column(children: [
          Padding(padding: EdgeInsets.all(16), child: Text('chat_groups_requests_title'.tr, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          Expanded(child: requests.isEmpty ? Center(child: Text('chat_groups_no_requests'.tr)) : ListView.builder(
            itemCount: requests.length,
            itemBuilder: (_, i) {
              final request = requests[i];
              final username = (request['username'] ?? 'Utilisateur').toString();
              return ListTile(
                leading: CircleAvatar(child: Text(username.isEmpty ? '?' : username[0].toUpperCase())),
                title: Text(username),
                subtitle: Text('chat_groups_requested_at'.trParams({'date': '${request['requested_at'] ?? ''}'})),
                trailing: Wrap(spacing: 4, children: [
                  IconButton(tooltip: 'chat_groups_reject'.tr, icon: const Icon(Icons.close, color: Colors.red), onPressed: () async { await _review(request['request_id'].toString(), 'rejected'); if (sheetContext.mounted) Navigator.pop(sheetContext); }),
                  IconButton(tooltip: 'chat_groups_accept'.tr, icon: const Icon(Icons.check, color: Colors.green), onPressed: () async { await _review(request['request_id'].toString(), 'accepted'); if (sheetContext.mounted) Navigator.pop(sheetContext); }),
                ]),
              );
            },
          )),
        ])),
      ));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Impossible de charger les demandes : $e')));
    }
  }

  Future<void> _review(String id, String decision) async {
    try {
      await _client.rpc('review_community_chat_group_request', params: {'p_request_id': id, 'p_decision': decision});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(decision == 'accepted' ? 'chat_groups_accepted'.tr : 'chat_groups_rejected'.tr)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${'chat_groups_action_error'.tr} : $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('chat_groups_title'.tr),
        Text(widget.communityName, style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
      ]), actions: [IconButton(onPressed: _creating ? null : _createGroup, tooltip: 'chat_groups_create_title'.tr, icon: const Icon(Icons.add_comment_outlined))]),
      body: _loading ? Center(child: CircularProgressIndicator()) : RefreshIndicator(
        onRefresh: _load,
        child: _groups.isEmpty ? ListView(children: [
          const SizedBox(height: 130), const Icon(Icons.forum_outlined, size: 58), const SizedBox(height: 16),
          Center(child: Text('chat_groups_empty'.tr)),
          Center(child: Padding(padding: const EdgeInsets.all(12), child: Text('chat_groups_empty_help'.tr, textAlign: TextAlign.center))),
        ]) : ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), itemCount: _groups.length,
          separatorBuilder: (_, __) => const SizedBox(height: 9),
          itemBuilder: (_, i) {
            final group = _groups[i];
            final isPrivate = group['visibility'] == 'private';
            final status = (group['my_status'] ?? 'none').toString();
            final canManage = group['can_manage'] == true;
            final isMember = status == 'member' || group['created_by'] == _client.auth.currentUser?.id;
            final pending = status == 'pending';
            final avatarUrl = group['avatar_url']?.toString();
            final messageType = group['last_message_type']?.toString() ?? '';
            final rawPreview = (group['last_message'] ?? '').toString().trim();
            final senderName = (group['last_message_sender_name'] ?? '').toString().trim();
            final previewContent = messageType == 'audio'
                ? 'chat_groups_audio_message'.tr
                : messageType == 'image'
                    ? 'chat_groups_pick_image'.tr
                    : messageType == 'video'
                        ? 'chat_groups_pick_video'.tr
                        : rawPreview;
            final preview = previewContent.isEmpty
                ? (group['description'] ?? '').toString()
                : senderName.isEmpty
                    ? previewContent
                    : '$senderName : $previewContent';
            final sentAt = DateTime.tryParse(group['last_message_at']?.toString() ?? '');
            final dateLabel = sentAt == null
                ? ''
                : (DateUtils.isSameDay(sentAt.toLocal(), DateTime.now())
                    ? '${sentAt.toLocal().hour.toString().padLeft(2, '0')}:${sentAt.toLocal().minute.toString().padLeft(2, '0')}'
                    : '${sentAt.toLocal().day.toString().padLeft(2, '0')}/${sentAt.toLocal().month.toString().padLeft(2, '0')}');
            final unreadCount = (group['unread_count'] as num?)?.toInt() ?? 0;
            final lastMessageFromMe = group['last_message_sender_id']?.toString() == _client.auth.currentUser?.id;
            final allRead = group['last_message_all_read'] == true;
            Widget statusIndicator;
            if (unreadCount > 0) {
              statusIndicator = Container(
                constraints: const BoxConstraints(minWidth: 19, minHeight: 19),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: const BoxDecoration(color: Color(0xFFD94B50), shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text(
                  unreadCount > 99 ? '99+' : '$unreadCount',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                ),
              );
            } else if (lastMessageFromMe) {
              statusIndicator = Icon(Icons.done_all_rounded, size: 17,
                color: allRead ? const Color(0xFF37C98A) : colors.onSurfaceVariant.withOpacity(.55));
            } else {
              statusIndicator = const SizedBox(width: 17, height: 17);
            }
            return Material(
              color: colors.surfaceContainerHighest.withOpacity(.42),
              borderRadius: BorderRadius.circular(22),
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: pending ? null : () => _openOrRequest(group),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 27,
                        backgroundColor: colors.primaryContainer,
                        backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                        child: avatarUrl == null || avatarUrl.isEmpty
                            ? Icon(isPrivate ? Icons.lock_outline : Icons.forum_outlined, color: colors.onPrimaryContainer)
                            : null,
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    (group['name'] ?? 'Discussion').toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                  ),
                                ),
                                if (dateLabel.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Text(dateLabel, style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant.withOpacity(.8))),
                                ],
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              pending ? 'chat_groups_request_pending'.tr : (preview.isEmpty ? (isPrivate ? 'chat_groups_private_label'.tr : 'chat_groups_public_label'.tr) : preview),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant.withOpacity(.85)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 9),
                      if (canManage && isPrivate && unreadCount == 0 && !lastMessageFromMe)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.group_add_outlined, size: 19),
                          tooltip: 'Gérer les demandes',
                          onPressed: () => _showRequests(group),
                        )
                      else
                        statusIndicator,
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class CommunityChatSalonPreviewSheet extends StatefulWidget {
  const CommunityChatSalonPreviewSheet({super.key, required this.group, required this.communityName, required this.onJoin});
  final Map<String, dynamic> group;
  final String communityName;
  final Future<String> Function() onJoin;
  @override State<CommunityChatSalonPreviewSheet> createState() => _CommunityChatSalonPreviewSheetState();
}

class _CommunityChatSalonPreviewSheetState extends State<CommunityChatSalonPreviewSheet> {
  bool _busy = false;
  bool _checkingEligibility = true;
  bool _eligible = false;
  bool _descriptionExpanded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkEligibility();
  }

  Future<void> _checkEligibility() async {
    try {
      final result = await Supabase.instance.client.rpc(
        'check_salon_eligibility',
        params: {'p_salon_id': widget.group['id'], 'p_user_id': Supabase.instance.client.auth.currentUser?.id},
      );
      if (!mounted) return;
      setState(() { _eligible = result == true; _checkingEligibility = false; });
    } catch (_) {
      if (!mounted) return;
      // Fail closed: never offer a join action when eligibility cannot be verified.
      setState(() { _eligible = false; _checkingEligibility = false; });
    }
  }
  Future<void> _join() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final status = (await widget.onJoin()).toLowerCase();
      if (!mounted) return;
      Navigator.of(context).pop(['accepted', 'member', 'joined'].contains(status) ? 'accepted' : 'pending');
    } catch (e) {
      if (mounted) setState(() { _busy = false; _error = e.toString().replaceFirst('Exception: ', ''); });
    }
  }
  @override Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final g = widget.group;
    final name = (g['name'] ?? 'Discussion').toString();
    final desc = (g['description'] ?? '').toString().trim();
    final avatar = (g['avatar_url'] ?? '').toString();
    final private = g['visibility'] == 'private';
    final count = (g['member_count'] as num?)?.toInt() ?? 0;
    final approval = private || g['requires_approval'] == true;
    final showJoinAction = !_checkingEligibility && _eligible;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .82),
      decoration: BoxDecoration(color: colors.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 10),
        Container(width: 38, height: 4, decoration: BoxDecoration(color: colors.onSurfaceVariant.withOpacity(.35), borderRadius: BorderRadius.circular(4))),
        Padding(padding: const EdgeInsets.fromLTRB(18, 8, 10, 10), child: Row(children: [
          Expanded(child: Text('chat_groups_salon_preview_title'.tr, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
          IconButton(onPressed: _busy ? null : () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
        ])),
        const Divider(height: 1),
        Flexible(child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 18, 20, 20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(radius: 27, backgroundColor: colors.primaryContainer,
                backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
                child: avatar.isEmpty ? Icon(private ? Icons.lock_outline : Icons.forum_outlined, color: colors.onPrimaryContainer) : null),
              const SizedBox(width: 12),
              Expanded(child: Text(name, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 5), Text(widget.communityName, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13)),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _SalonPreviewTag(icon: private ? Icons.lock_outline : Icons.public, label: private ? 'chat_groups_private_label'.tr : 'chat_groups_public_label'.tr),
              _SalonPreviewTag(icon: Icons.people_outline, label: 'chat_groups_preview_members'.trParams({'count': '$count'})),
              if (approval) _SalonPreviewTag(icon: Icons.verified_user_outlined, label: 'chat_groups_preview_approval'.tr),
            ]),
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('chat_groups_preview_about'.tr, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 7),
              LayoutBuilder(builder: (context, constraints) {
                final painter = TextPainter(
                  text: TextSpan(text: desc, style: TextStyle(height: 1.45, fontSize: 14, color: colors.onSurfaceVariant)),
                  textDirection: Directionality.of(context),
                  maxLines: 3,
                )..layout(maxWidth: constraints.maxWidth);
                final needsExpansion = painter.didExceedMaxLines;
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(desc, maxLines: _descriptionExpanded ? null : 3, overflow: _descriptionExpanded ? TextOverflow.visible : TextOverflow.ellipsis, style: TextStyle(height: 1.45, color: colors.onSurfaceVariant)),
                  if (needsExpansion) Align(alignment: Alignment.centerLeft, child: TextButton(
                    onPressed: () => setState(() => _descriptionExpanded = !_descriptionExpanded),
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    child: Text((_descriptionExpanded ? 'chat_groups_preview_see_less' : 'chat_groups_preview_see_more').tr),
                  )),
                ]);
              }),
            ],
            const SizedBox(height: 18),
            Container(padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: colors.surfaceContainerHighest.withOpacity(.5), borderRadius: BorderRadius.circular(14)), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.info_outline, color: colors.primary), const SizedBox(width: 9), Expanded(child: Text(approval ? 'chat_groups_preview_private_info'.tr : 'chat_groups_preview_public_info'.tr, style: TextStyle(fontSize: 12.5, height: 1.4, color: colors.onSurfaceVariant)))])),
            if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: TextStyle(color: colors.error, fontSize: 12))],
          ])),
        ]))),
        if (_checkingEligibility)
          const Padding(padding: EdgeInsets.fromLTRB(18, 12, 18, 20), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))))
        else if (showJoinAction)
          Padding(padding: const EdgeInsets.fromLTRB(18, 10, 18, 16), child: SizedBox(width: double.infinity, height: 50, child: FilledButton(onPressed: _busy ? null : _join, child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text((approval ? 'chat_groups_preview_request' : 'chat_groups_preview_join').tr, style: const TextStyle(fontWeight: FontWeight.w700)))))
        else
          Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 20), child: Container(width: double.infinity, padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: colors.errorContainer.withOpacity(.55), borderRadius: BorderRadius.circular(14)), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.lock_outline_rounded, color: colors.error), const SizedBox(width: 10), Expanded(child: Text('chat_groups_preview_not_eligible'.tr, style: TextStyle(color: colors.onErrorContainer, fontSize: 13, height: 1.4)))]))),
      ])),
    );
  }
}

class _SalonPreviewTag extends StatelessWidget {
  const _SalonPreviewTag({required this.icon, required this.label});
  final IconData icon; final String label;
  @override Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), decoration: BoxDecoration(color: c.secondaryContainer.withOpacity(.55), borderRadius: BorderRadius.circular(20)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 14, color: c.primary), const SizedBox(width: 5), Text(label, style: TextStyle(fontSize: 12, color: c.onSurface, fontWeight: FontWeight.w600))]));
  }
}
class CommunityChatGroupConversation extends StatefulWidget {
  final String salonId;
  final String? targetMessageId;
  final String name;
  final String communityName;
  final String? avatarUrl;
  const CommunityChatGroupConversation({super.key, required this.salonId, this.targetMessageId, required this.name, required this.communityName, this.avatarUrl});
  @override
  State<CommunityChatGroupConversation> createState() => _CommunityChatGroupConversationState();
}

class _CommunityChatGroupConversationState extends State<CommunityChatGroupConversation> {
  late String _conversationName;
  String? _conversationAvatarUrl;
  final _client = Supabase.instance.client;
  late final SalonChatLocalCache _localCache;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  bool _recording = false;
  bool _uploadingMedia = false;
  Map<String, dynamic>? _replyToMessage;
  bool _textMessagesAllowed = true;
  bool _audioMessagesAllowed = false;
  bool _imageMessagesAllowed = true;
  bool _videoMessagesAllowed = true;
  bool _autoDownloadIncomingMedia = false;
  final Set<String> _autoDownloadedMediaMessageIds = <String>{};
  final Set<String> _knownSalonMessageIds = <String>{};
  final Set<String> _readThroughInFlight = <String>{};
  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};
  bool _initialSalonMessagesLoaded = false;
  bool _initialScrollApplied = false;
  String? _initialAnchorMessageId;
  final AudioRecorder _recorder = AudioRecorder();
  DateTime? _recordingStartedAt;
  RealtimeChannel? _channel;
  StreamSubscription<bool>? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _conversationName = widget.name;
    _conversationAvatarUrl = widget.avatarUrl;
    _localCache = SalonChatLocalCache();
    _initialAnchorMessageId = widget.targetMessageId;
    NotificationService.instance.setActiveSalon(widget.salonId);
    _loadMessagePermissions();
    if (Get.isRegistered<ConnectivityService>()) {
      var wasConnected = Get.find<ConnectivityService>().isConnected.value;
      _connectivitySubscription = Get.find<ConnectivityService>().isConnected.listen((connected) {
        if (connected && !wasConnected) unawaited(_loadMessages());
        wasConnected = connected;
      });
    }
    unawaited(_loadLocalMessages());
    unawaited(_loadMessages());
    _channel = _client.channel('salon:${widget.salonId}', opts: const RealtimeChannelConfig(private: true))
      .onBroadcast(event: 'salon_message_sent', callback: (payload) {
        final id = payload['message_id']?.toString();
        if (id != null && id.isNotEmpty) {
          unawaited(_syncMessageDelta(id));
        } else {
          unawaited(_loadMessages());
        }
      })
      .onBroadcast(event: 'salon_message_edited', callback: (payload) {
        final id = payload['message_id']?.toString();
        if (id != null && id.isNotEmpty) unawaited(_syncMessageDelta(id));
      })
      .onBroadcast(event: 'salon_message_deleted', callback: (payload) {
        final id = payload['message_id']?.toString();
        if (id != null && id.isNotEmpty) unawaited(_syncMessageDelta(id));
      })
      .subscribe();
  }

  Future<void> _openGroupSettings() async {
    final result = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(
        builder: (_) => CommunityChatGroupSettingsScreen(
          salonId: widget.salonId,
          initialName: _conversationName,
          communityName: widget.communityName,
          initialAvatarUrl: _conversationAvatarUrl,
        ),
      ),
    );
    if (!mounted) return;
    await _loadMessagePermissions();
    if (result == 'left' || result == 'deleted') {
      Navigator.of(context).pop(true);
      return;
    }
    if (result is Map) {
      setState(() {
        _conversationName = (result['name'] ?? _conversationName).toString();
        _conversationAvatarUrl = result['avatar_url']?.toString();
      });
    }
  }

  Future<void> _showMessageActions(Map<String, dynamic> message, bool mine) async {
    final messageId = message['id']?.toString();
    if (messageId == null || messageId.isEmpty) return;
    final content = (message['content'] ?? '').toString();
    final type = (message['type'] ?? 'text').toString();
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            if (content.isNotEmpty && type != 'image' && type != 'video')
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: Text('chats_copy'.tr),
                onTap: () => Navigator.of(sheetContext).pop('copy'),
              ),
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: Text('chat_groups_reply'.tr),
              onTap: () => Navigator.of(sheetContext).pop('reply'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_sweep_outlined),
              title: const Text('Supprimer le message pour moi'),
              onTap: () => Navigator.of(sheetContext).pop('delete_me'),
            ),
            if (mine)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Supprimer le message pour tous',
                  style: TextStyle(color: Colors.red)),
                onTap: () => Navigator.of(sheetContext).pop('delete_all'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'reply') {
      setState(() => _replyToMessage = Map<String, dynamic>.from(message));
      return;
    }
    try {
      if (action == 'copy') {
        await Clipboard.setData(ClipboardData(text: content));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('chats_copied'.tr)),
        );
        return;
      }
      final deleteForAll = action == 'delete_all';
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(deleteForAll ? 'Supprimer pour tous ?' : 'Supprimer pour moi ?'),
          content: Text(deleteForAll
              ? 'Ce message sera supprimé pour tous les membres du salon.'
              : 'Ce message sera masqué uniquement dans ta conversation.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text('common_cancel'.tr),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text('Supprimer', style: TextStyle(color: Theme.of(dialogContext).colorScheme.error)),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      if (deleteForAll) {
        await _client.rpc('delete_salon_message', params: {'p_id': messageId});
        await _syncMessageDelta(messageId);
      } else {
        await _client.rpc('hide_salon_message_for_me', params: {'p_id': messageId});
        final userId = _client.auth.currentUser?.id;
        if (userId != null) {
          await _localCache.deleteMessage(
            userId: userId,
            salonId: widget.salonId,
            messageId: messageId,
          );
        }
        if (mounted) {
          setState(() => _messages.removeWhere((item) => item['id']?.toString() == messageId));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossible de supprimer ce message : $e')),
        );
      }
    }
  }

  Future<void> _loadMessagePermissions() async {
    try {
      final raw = await _client.rpc('get_community_chat_group_settings', params: {'p_salon_id': widget.salonId});
      final settings = Map<String, dynamic>.from(raw as Map);
      if (!mounted) return;
      setState(() {
        _textMessagesAllowed = settings['text_messages_allowed'] != false;
        _audioMessagesAllowed = settings['audio_messages_allowed'] == true;
        _imageMessagesAllowed = settings['image_messages_allowed'] != false;
        _videoMessagesAllowed = settings['video_messages_allowed'] != false;
        _autoDownloadIncomingMedia = settings['media_visibility_enabled'] != false;
      });
    } catch (e) {
      debugPrint('[SALON_PERMISSIONS] Could not load message permissions: $e');
    }
  }

  void _openSalonMediaViewer({
    required List<String> urls,
    required String type,
    int initialIndex = 0,
  }) {
    if (urls.isEmpty) return;
    Get.to(() => ChatMediaViewerScreen(
      mediaUrls: urls,
      initialIndex: initialIndex,
      mediaTypes: List<String>.filled(urls.length, type),
    ));
  }

  Future<void> _loadLocalMessages() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null || !mounted) return;
    try {
      final cached = await _localCache.readMessages(
        userId: userId,
        salonId: widget.salonId,
        limit: 300,
      );
      if (!mounted || cached.isEmpty) return;
      _initialSalonMessagesLoaded = true;
      final knownIds = cached.map((message) => message['id']?.toString() ?? '').toSet();
      final byId = <String, Map<String, dynamic>>{
        for (final message in cached)
          if (message['id'] != null) message['id'].toString(): message,
      };
      for (final message in _messages) {
        if (message['is_uploading'] != true && message['id'] != null) {
          byId[message['id'].toString()] = message;
        }
      }
      final merged = byId.values.toList()
        ..sort((a, b) => (DateTime.tryParse((a['sent_at'] ?? a['created_at'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(DateTime.tryParse((b['sent_at'] ?? b['created_at'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0)));
      final pending = _messages.where((message) => message['is_uploading'] == true).toList();
      setState(() {
        _messages = [...merged, ...pending];
        _knownSalonMessageIds.addAll(knownIds);
        _loading = false;
      });
    } catch (error) {
      debugPrint('[SALON_CACHE] Local snapshot read failed: $error');
    }
  }

  Future<List<Map<String, dynamic>>> _hydrateSalonMessages(List<dynamic> rawMessages) async {
    final messages = rawMessages
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .toList();
    final senderIds = messages.map((message) => message['sender_id']?.toString())
        .whereType<String>().where((id) => id.isNotEmpty).toSet().toList();
    if (senderIds.isNotEmpty) {
      try {
        final profiles = await _client.from('user_profiles')
            .select('user_id, username, first_name, last_name')
            .inFilter('user_id', senderIds);
        final namesById = <String, String>{};
        for (final rawProfile in profiles) {
          final profile = Map<String, dynamic>.from(rawProfile as Map);
          final fullName = [profile['first_name'], profile['last_name']]
              .where((part) => part != null && part.toString().trim().isNotEmpty)
              .map((part) => part.toString().trim()).join(' ');
          namesById[profile['user_id'].toString()] = fullName.isNotEmpty
              ? fullName
              : (profile['username'] ?? 'Membre').toString();
        }
        for (final message in messages) {
          final senderId = message['sender_id']?.toString();
          if (senderId != null) {
            message['sender_name'] = namesById[senderId] ??
                (senderId.length > 8 ? senderId.substring(0, 8) : senderId);
          }
        }
      } catch (error) {
        debugPrint('[SALON_CACHE] Sender names refresh failed: $error');
      }
    }
    return messages;
  }

  Future<void> _applyRemoteSalonMessages(List<dynamic> rawMessages) async {
    if (!mounted) return;
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    final hydrated = await _hydrateSalonMessages(rawMessages);
    if (!mounted) return;
    final newlyReceived = <Map<String, dynamic>>[];
    final byId = <String, Map<String, dynamic>>{
      for (final message in _messages)
        if (message['id'] != null) message['id'].toString(): message,
    };
    for (final message in hydrated) {
      final id = message['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      if (message['is_deleted'] == true) {
        byId.remove(id);
        await _localCache.deleteMessage(userId: userId, salonId: widget.salonId, messageId: id);
        continue;
      }
      if (_initialSalonMessagesLoaded && !_knownSalonMessageIds.contains(id)) {
        newlyReceived.add(message);
      }
      _knownSalonMessageIds.add(id);
      byId[id] = message;
    }
    final pending = _messages.where((message) => message['is_uploading'] == true).toList();
    final merged = byId.values.toList()
      ..sort((a, b) => (DateTime.tryParse((a['sent_at'] ?? a['created_at'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(DateTime.tryParse((b['sent_at'] ?? b['created_at'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0)));
    // Never persist expiring signed URLs in SQLite. Store stable R2 object keys;
    // ChatMediaCache resolves them locally first and requests a fresh URL only online.
    final cacheableMessages = hydrated.map((message) {
      final safe = Map<String, dynamic>.from(message)
        ..remove('media_signed_url')
        ..remove('media_signed_urls')
        ..remove('audio_signed_url');
      return safe;
    }).toList();
    await _localCache.upsertMessages(
      userId: userId,
      salonId: widget.salonId,
      messages: cacheableMessages,
    );
    // Advance only after message writes/deletions succeed: a crash can cause
    // harmless replay, never a cursor that skips data not yet persisted.
    for (final message in hydrated) {
      final id = message['id']?.toString() ?? '';
      final syncAt = DateTime.tryParse(
        (message['sync_updated_at'] ?? message['sent_at'] ?? message['created_at'] ?? '').toString(),
      );
      if (id.isNotEmpty && syncAt != null) {
        await _localCache.advanceCursor(
          userId: userId,
          salonId: widget.salonId,
          sentAt: syncAt,
          messageId: id,
        );
      }
    }
    if (!mounted) return;
    setState(() {
      _messages = [...merged, ...pending];
      _loading = false;
    });
    _initialSalonMessagesLoaded = true;
    if (newlyReceived.isNotEmpty) {
      unawaited(_autoCacheIncomingMedia(newlyReceived));
    }
    try {
      await _client.rpc('mark_salon_messages_read', params: {'p_salon_id': widget.salonId});
    } catch (error) {
      debugPrint('[SALON_READ] Could not mark salon messages as read: $error');
    }
    if (!_initialScrollApplied) {
      _initialScrollApplied = true;
      final anchorId = _initialAnchorMessageId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (anchorId != null && anchorId.isNotEmpty) {
          _scrollToMessage(anchorId);
        } else if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  void _scrollToMessage(String messageId) {
    final key = _messageKeys[messageId];
    final targetContext = key?.currentContext;
    if (targetContext == null) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      return;
    }
    Scrollable.ensureVisible(
      targetContext,
      alignment: 0.72,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _markVisibleMessageRead(Map<String, dynamic> message) async {
    final userId = _client.auth.currentUser?.id;
    final messageId = message['id']?.toString() ?? '';
    if (userId == null || messageId.isEmpty ||
        message['sender_id']?.toString() == userId ||
        !_readThroughInFlight.add(messageId)) return;
    try {
      await _client.rpc('mark_salon_messages_read_through', params: {
        'p_salon_id': widget.salonId,
        'p_message_id': messageId,
      });
    } catch (error) {
      debugPrint('[SALON_READ] Could not advance read position to $messageId: $error');
      _readThroughInFlight.remove(messageId);
    }
  }

  Future<void> _autoCacheIncomingMedia(List<Map<String, dynamic>> messages) async {
    if (!_autoDownloadIncomingMedia || !mounted) return;
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null) return;
    for (final message in messages) {
      if (message['sender_id']?.toString() == currentUserId) continue;
      final id = message['id']?.toString() ?? '';
      if (id.isEmpty || !_autoDownloadedMediaMessageIds.add(id)) continue;
      final type = message['type']?.toString();
      final keys = <String>[];
      if (type == 'image' && message['media_object_keys'] is List) {
        keys.addAll((message['media_object_keys'] as List)
            .map((value) => value.toString())
            .where((value) => value.isNotEmpty));
      } else if (type == 'image' || type == 'video' || type == 'audio' || type == 'file') {
        final key = (type == 'audio'
                ? message['audio_url']
                : message['media_object_key'] ?? message['content'])
            ?.toString() ?? '';
        if (key.isNotEmpty) keys.add(key);
      }
      try {
        for (final key in keys) {
          await ChatMediaCache.instance.resolveLocalPath(key);
        }
      } catch (error) {
        _autoDownloadedMediaMessageIds.remove(id);
        debugPrint('[SALON_MEDIA_CACHE] Private media download failed: $error');
      }
    }
  }

  Future<void> _loadMessages() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final cursor = await _localCache.readCursor(userId: userId, salonId: widget.salonId);
      dynamic data;
      if (cursor == null) {
        // First open: restore the exact notification target or the last-read
        // message, keeping unread messages below the reading position.
        String? anchorId = widget.targetMessageId;
        if (anchorId == null || anchorId.isEmpty) {
          final position = await _client.rpc('get_salon_read_position', params: {
            'p_salon_id': widget.salonId,
          });
          if (position is List && position.isNotEmpty) {
            anchorId = (position.first as Map)['last_read_message_id']?.toString();
          }
        }
        if (anchorId != null && anchorId.isNotEmpty) {
          _initialAnchorMessageId = anchorId;
          data = await _client.rpc('get_salon_messages_around', params: {
            'p_salon_id': widget.salonId,
            'p_message_id': anchorId,
            'p_before': 30,
            'p_after': 50,
          });
          await _applyRemoteSalonMessages(data as List);
        } else {
          data = await _client.rpc('get_salon_messages', params: {
            'p_salon_id': widget.salonId,
            'p_limit': 100,
          });
          final ordered = (data as List).reversed.toList();
          await _applyRemoteSalonMessages(ordered);
        }
      } else {
        // Drain all pending revisions in bounded batches after long offline periods.
        while (mounted) {
          final currentCursor = await _localCache.readCursor(
            userId: userId,
            salonId: widget.salonId,
          );
          if (currentCursor == null) break;
          data = await _client.rpc('get_salon_messages_since', params: {
            'p_salon_id': widget.salonId,
            'p_after_sent_at': currentCursor['sent_at'],
            'p_after_id': currentCursor['id'],
            'p_limit': 300,
          });
          final batch = data as List;
          if (batch.isEmpty) break;
          await _applyRemoteSalonMessages(batch);
          if (batch.length < 300) break;
        }
        if (mounted) setState(() => _loading = false);
      }
    } catch (error) {
      debugPrint('[SALON_SYNC] Incremental sync failed: $error');
      if (!mounted) return;
      setState(() => _loading = false);
      if (_messages.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${'chat_groups_messages_error'.tr} : $error')),
        );
      }
    }
  }

  Future<void> _syncMessageDelta(String messageId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null || messageId.isEmpty) return;
    try {
      final rows = await _client.rpc('get_salon_message_delta', params: {
        'p_message_id': messageId,
      }) as List;
      if (rows.isEmpty) {
        await _localCache.deleteMessage(userId: userId, salonId: widget.salonId, messageId: messageId);
        if (!mounted) return;
        setState(() => _messages.removeWhere((message) => message['id']?.toString() == messageId));
        return;
      }
      await _applyRemoteSalonMessages(rows);
    } catch (error) {
      debugPrint('[SALON_SYNC] Realtime delta failed for $messageId: $error');
      // A missed broadcast is recovered by the next cursor-based sync.
    }
  }

  Future<String> _uploadFile(
    String path, {
    required String mediaType,
  }) async {
    final uploaded = await R2MediaRepository().uploadFile(
      file: File(path),
      category: 'salon_message_media',
      mediaType: mediaType,
      entityId: widget.salonId,
    );
    return uploaded.objectKey;
  }

  Future<void> _pickMedia() async {
    if (_sending || _uploadingMedia || (!_imageMessagesAllowed && !_videoMessagesAllowed)) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (galleryContext) => MediaGallerySheet(
        allowMixedMedia: true,
        onSelected: (files) {
          Navigator.of(galleryContext).pop();
          _uploadAndSendGalleryFiles(files);
        },
      ),
    );
  }

  Future<File?> _prepareSalonVideo(XFile pickedFile) async {
    final source = File(pickedFile.path);
    final controller = VideoPlayerController.file(source);
    try {
      await controller.initialize();
      final duration = controller.value.duration;
      if (duration <= const Duration(seconds: 30)) return source;
    } finally {
      await controller.dispose();
    }
    if (!mounted) return null;
    final trimmed = await Navigator.of(context).push<File?>(
      MaterialPageRoute(
        builder: (_) => VideoTrimScreen(
          videoFile: source,
          maxDuration: const Duration(seconds: 30),
        ),
      ),
    );
    if (trimmed == null || !await trimmed.exists()) return null;
    final verify = VideoPlayerController.file(trimmed);
    try {
      await verify.initialize();
      if (verify.value.duration > const Duration(seconds: 30)) {
        throw StateError('La vidéo découpée dépasse encore 30 secondes.');
      }
    } finally {
      await verify.dispose();
    }
    return trimmed;
  }

  Future<void> _uploadAndSendGalleryFiles(List<XFile> files) async {
    if (files.isEmpty || _uploadingMedia) return;
    if (mounted) setState(() => _uploadingMedia = true);
    final currentUserId = _client.auth.currentUser?.id;
    final pendingIds = <String>[];
    try {
      // Préparer toute la sélection avant de créer les messages optimistes.
      // Les photos seront regroupées dans un seul message ; chaque vidéo
      // conserve son propre message car le contrat SQL vidéo est unitaire.
      final preparedMedia = <Map<String, dynamic>>[];
      for (final picked in files) {
        final extension = picked.path.split('.').last.toLowerCase();
        final isVideo = const {'mp4', 'mov', 'm4v', 'webm'}.contains(extension) ||
            (picked.mimeType?.startsWith('video/') ?? false);
        if (isVideo && !_videoMessagesAllowed) {
          throw Exception('chat_groups_video_not_allowed'.tr);
        }
        if (!isVideo && !_imageMessagesAllowed) {
          throw Exception('chat_groups_image_not_allowed'.tr);
        }

        File sourceFile = File(picked.path);
        Duration? videoDuration;
        if (isVideo) {
          final prepared = await _prepareSalonVideo(picked);
          if (prepared == null) continue;
          sourceFile = prepared;
          final durationController = VideoPlayerController.file(sourceFile);
          try {
            await durationController.initialize();
            videoDuration = durationController.value.duration;
          } finally {
            await durationController.dispose();
          }
          if (videoDuration > const Duration(seconds: 30)) {
            throw StateError('La vidéo doit durer 30 secondes maximum.');
          }
        }
        preparedMedia.add({
          'file': sourceFile,
          'is_video': isVideo,
          'duration': videoDuration,
        });
      }
      if (preparedMedia.isEmpty) return;

      // Un groupe de photos = un message. Les vidéos restent des messages
      // distincts, dans l'ordre de leur première apparition dans la sélection.
      final outgoingGroups = <Map<String, dynamic>>[];
      Map<String, dynamic>? imageGroup;
      for (var index = 0; index < preparedMedia.length; index++) {
        final item = preparedMedia[index];
        final isVideo = item['is_video'] == true;
        if (isVideo) {
          outgoingGroups.add({
            'id': _newUuid(),
            'type': 'video',
            'indices': <int>[index],
            'duration': item['duration'],
          });
        } else {
          imageGroup ??= {
            'id': _newUuid(),
            'type': 'image',
            'indices': <int>[],
          };
          (imageGroup['indices'] as List<int>).add(index);
          if (!outgoingGroups.contains(imageGroup)) outgoingGroups.add(imageGroup);
        }
      }

      for (final group in outgoingGroups) {
        final indices = group['indices'] as List<int>;
        final id = group['id'].toString();
        pendingIds.add(id);
        final isImageGroup = group['type'] == 'image';
        final localMessage = <String, dynamic>{
          'id': id,
          'sender_id': currentUserId,
          'sender_name': 'MOI',
          'type': group['type'],
          'content': '',
          if (isImageGroup)
            'local_media_paths': indices
                .map((index) => (preparedMedia[index]['file'] as File).path)
                .toList(),
          if (!isImageGroup)
            'local_media_path':
                (preparedMedia[indices.first]['file'] as File).path,
          'is_uploading': true,
          'is_deleted': false,
          'sent_at': DateTime.now().toUtc().toIso8601String(),
        };
        if (mounted) setState(() => _messages.add(localMessage));
      }

      // Future.wait conserve l'ordre des clés tout en téléversant en parallèle.
      final uploadedKeys = await Future.wait(preparedMedia.map((item) async {
        final uploaded = await R2MediaRepository().uploadFile(
          file: item['file'] as File,
          category: 'salon_message_media',
          mediaType: item['is_video'] == true ? 'video' : 'image',
          entityId: widget.salonId,
          videoDuration: item['duration'] as Duration?,
        );
        return uploaded.objectKey;
      }));

      for (final group in outgoingGroups) {
        final indices = group['indices'] as List<int>;
        final isImageGroup = group['type'] == 'image';
        final id = group['id'].toString();
        final content = isImageGroup
            ? jsonEncode(indices.map((index) => uploadedKeys[index]).toList())
            : uploadedKeys[indices.first];
        final duration = group['duration'] as Duration?;
        await _client.rpc('send_salon_message', params: {
          'p_id': id,
          'p_salon_id': widget.salonId,
          'p_content': content,
          'p_type': group['type'],
          'p_replied_to_id': null,
          if (!isImageGroup && duration != null)
            'p_media_duration_seconds': duration.inMilliseconds / 1000,
        });
        if (mounted) {
          setState(() => _messages.removeWhere((message) => message['id']?.toString() == id));
        }
      }
      await _loadMessages();
    } catch (e) {
      if (mounted) {
        setState(() => _messages.removeWhere(
          (message) => pendingIds.contains(message['id']?.toString()),
        ));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${'chat_groups_media_send_error'.tr} : $e')),
        );
        await _loadMessages();
      }
    } finally {
      if (mounted) setState(() => _uploadingMedia = false);
    }
  }

  Future<void> _cancelRecording() async {
    if (!_recording) return;
    try {
      await _recorder.stop();
    } catch (_) {}
    if (mounted) setState(() {
      _recording = false;
      _recordingStartedAt = null;
    });
  }

  Widget _recordingPanel(ColorScheme colors) {
    final elapsed = _recordingStartedAt == null
        ? 0 : DateTime.now().difference(_recordingStartedAt!).inSeconds;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        child: GestureDetector(
          onHorizontalDragUpdate: (details) {
            if (details.delta.dx < -8) _cancelRecording();
          },
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: colors.outline.withOpacity(.12)),
              boxShadow: [BoxShadow(color: colors.shadow.withOpacity(.14), blurRadius: 18, offset: const Offset(0, 7))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  const Icon(Icons.mic_rounded, size: 18, color: Color(0xFFEF5B25)),
                  const SizedBox(width: 8),
                  Text('Enregistrement vocal', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: colors.onSurface)),
                  const Spacer(),
                  Text('${elapsed}s', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFFEF5B25))),
                ]),
                const SizedBox(height: 8),
                SizedBox(
                  height: 82, width: double.infinity,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: ColoredBox(
                      color: colors.surface.withOpacity(.5),
                      child: CustomPaint(painter: _SalonWaveformPainter(
                        active: const Color(0xFFEF5B25),
                        inactive: colors.onSurfaceVariant.withOpacity(.22),
                      )),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  _SalonCircleAction(icon: Icons.close_rounded, onTap: _cancelRecording, size: 48),
                  const Spacer(),
                  _SalonCircleAction(icon: Icons.mic_rounded, primary: true, onTap: _stopRecordingAndSend, size: 74),
                  const Spacer(),
                  _SalonCircleAction(icon: Icons.stop_rounded, onTap: _stopRecordingAndSend, size: 48),
                ]),
                const SizedBox(height: 8),
                Text('Glissez vers la gauche pour annuler',
                  style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant.withOpacity(.7))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _startRecording() async {
    if (_recording || _uploadingMedia) return;
    final permission = await Permission.microphone.request();
    if (!permission.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('chat_groups_microphone_permission'.tr)),
        );
      }
      return;
    }
    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/salon_voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(), path: path);
      if (mounted) {
        setState(() {
          _recording = true;
          _recordingStartedAt = DateTime.now();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${'chat_groups_audio_start_error'.tr} : $e')),
        );
      }
    }
  }

  Future<void> _stopRecordingAndSend() async {
    if (!_recording) return;
    await _toggleRecording();
  }

  Future<void> _toggleRecording() async {
    if (!_audioMessagesAllowed) return;
    if (_recording) {
      try {
        final path = await _recorder.stop();
        final duration = _recordingStartedAt == null ? 0 : DateTime.now().difference(_recordingStartedAt!).inSeconds;
        if (path == null || duration < 1) {
          if (mounted) setState(() => _recording = false);
          return;
        }
        setState(() { _recording = false; _uploadingMedia = true; });
        final key = await _uploadFile(path, mediaType: 'audio');
        await _client.rpc('send_salon_message', params: {
          'p_id': _newUuid(), 'p_salon_id': widget.salonId, 'p_content': '', 'p_type': 'audio',
          'p_audio_url': key, 'p_replied_to_id': null,
        });
        await _loadMessages();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${'chat_groups_audio_send_error'.tr} : $e')));
      } finally { if (mounted) setState(() { _recording = false; _uploadingMedia = false; }); }
      return;
    }
    final permission = await Permission.microphone.request();
    if (!permission.isGranted) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('chat_groups_microphone_permission'.tr)));
      return;
    }
    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/salon_voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(), path: path);
      if (mounted) setState(() { _recording = true; _recordingStartedAt = DateTime.now(); });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${'chat_groups_audio_start_error'.tr} : $e')));
    }
  }

  Future<void> _send() async {
    final content = _input.text.trim();
    if (content.isEmpty || _sending || !_textMessagesAllowed) return;
    setState(() => _sending = true);
    try {
      await _client.rpc('send_salon_message', params: {
        'p_id': _newUuid(), 'p_salon_id': widget.salonId, 'p_content': content, 'p_type': 'texte',
        'p_replied_to_id': _replyToMessage?['id'],
      });
      _input.clear();
      if (mounted) setState(() => _replyToMessage = null);
      await _loadMessages();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${'chat_groups_send_error'.tr} : $e')));
    } finally { if (mounted) setState(() => _sending = false); }
  }

  String _newUuid() {
    final secureRandom = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => secureRandom.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0,8)}-${hex.substring(8,12)}-${hex.substring(12,16)}-${hex.substring(16,20)}-${hex.substring(20,32)}';
  }

  @override
  void dispose() {
    NotificationService.instance.setActiveSalon(null);
    _connectivitySubscription?.cancel();
    _input.dispose();
    _scroll.dispose();
    _messageKeys.clear();
    _recorder.dispose();
    if (_channel != null) _client.removeChannel(_channel!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = _client.auth.currentUser?.id;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _openGroupSettings,
        child: Row(children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: colors.primaryContainer,
            backgroundImage: _conversationAvatarUrl != null && _conversationAvatarUrl!.isNotEmpty ? NetworkImage(_conversationAvatarUrl!) : null,
            child: _conversationAvatarUrl == null || _conversationAvatarUrl!.isEmpty
                ? Icon(Icons.forum_outlined, color: colors.onPrimaryContainer, size: 19)
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_conversationName, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(widget.communityName, style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
          ])),
        ]),
      )),
      body: Column(children: [
        Expanded(child: _loading ? Center(child: CircularProgressIndicator()) : _messages.isEmpty
          ? Center(child: Text('chat_groups_first_message'.tr))
          : ListView.builder(controller: _scroll, padding: const EdgeInsets.all(12), itemCount: _messages.length, itemBuilder: (_, i) {
            final message = _messages[i];
            final messageId = message['id']?.toString() ?? 'pending-$i';
            final messageKey = _messageKeys.putIfAbsent(messageId, () => GlobalKey());
            final messageIsMine = message['sender_id']?.toString() == uid;
            final mine = message['sender_id']?.toString() == uid;
            final deleted = message['is_deleted'] == true;
            final type = message['type']?.toString() ?? 'texte';
            final mediaKeys = message['media_object_keys'] is List
                ? (message['media_object_keys'] as List)
                    .map((value) => value.toString())
                    .where((value) => value.isNotEmpty)
                    .toList()
                : <String>[];
            // Stable R2 object keys are the media references persisted and displayed.
            // ChatMediaCache resolves a key to a signed URL only when the file is needed.
            final mediaUrl = (message['media_object_key'] ??
                (mediaKeys.isNotEmpty ? mediaKeys.first : null) ??
                message['content'] ??
                message['media_signed_url'] ??
                '').toString();
            final mediaUrls = mediaKeys.isNotEmpty
                ? mediaKeys
                : (message['media_signed_urls'] is List
                    ? (message['media_signed_urls'] as List)
                        .map((value) => value.toString())
                        .where((value) => value.isNotEmpty)
                        .toList()
                    : (mediaUrl.isNotEmpty ? <String>[mediaUrl] : <String>[]));
            final localMediaPaths = message['local_media_paths'] is List
                ? (message['local_media_paths'] as List)
                    .map((value) => value.toString())
                    .where((value) => value.isNotEmpty)
                    .toList()
                : (message['local_media_path'] != null
                    ? <String>[message['local_media_path'].toString()]
                    : <String>[]);
            final audioUrl = (message['audio_url'] ?? message['audio_signed_url'] ?? '').toString();
            final senderName = (message['sender_name'] ?? 'Membre').toString();
            final sentAt = DateTime.tryParse(message['sent_at']?.toString() ?? '');
            final timeLabel = sentAt == null ? '' : TimeOfDay.fromDateTime(sentAt.toLocal()).format(context);
            final isAudio = type == 'audio' && audioUrl.isNotEmpty;
            final isMedia = (type == 'image' || type == 'video') &&
                (mediaUrl.isNotEmpty || mediaUrls.isNotEmpty);
            final timeColor = colors.onSurfaceVariant.withOpacity(.52);
            return VisibilityDetector(
              key: ValueKey('salon-message-$messageId'),
              onVisibilityChanged: (info) {
                if (info.visibleFraction >= 0.6) {
                  unawaited(_markVisibleMessageRead(message));
                }
              },
              child: GestureDetector(
              onDoubleTap: () => _showMessageActions(message, mine),
              child: Padding(
                key: messageKey,
                padding: const EdgeInsets.only(top: 9, bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 4,
                      height: isAudio || isMedia ? 50 : 50,
                      decoration: BoxDecoration(
                        color: (mine ? Colors.grey : colors.primary).withOpacity(.42),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            mine ? 'MOI' : senderName.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: mine ? colors.onSurfaceVariant.withOpacity(.65) : colors.primary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (deleted)
                            Text('chat_groups_deleted_message'.tr,
                              style: TextStyle(color: colors.onSurfaceVariant, fontStyle: FontStyle.italic))
                          else if (isAudio)
                            DirectVoiceMessagePlayer(
                              voiceMessage: legacy.VoiceMessage(
                                fileName: 'audio.m4a', sizeLabel: '',
                                durationLabel: '${message['duration_seconds'] ?? ''}',
                                url: audioUrl,
                              ),
                              audioPath: audioUrl, messageId: message['id'].toString(), isMine: mine,
                            )
                          else if (localMediaPaths.isNotEmpty || isMedia)
                            if (type == 'image')
                              Wrap(
                                spacing: 5,
                                runSpacing: 5,
                                children: (localMediaPaths.isNotEmpty
                                    ? localMediaPaths
                                    : mediaUrls).asMap().entries.map((entry) {
                                  final source = entry.value;
                                  final mediaIndex = entry.key;
                                  final isLocal = localMediaPaths.isNotEmpty;
                                  final allImageSources = localMediaPaths.isNotEmpty
                                      ? localMediaPaths
                                      : mediaUrls;
                                  final isSingle = (localMediaPaths.isNotEmpty
                                          ? localMediaPaths.length
                                          : mediaUrls.length) == 1;
                                  final width = isSingle ? 250.0 : 118.0;
                                  final height = isSingle ? 190.0 : 118.0;
                                  return GestureDetector(
                                    onTap: message['is_uploading'] == true
                                        ? null
                                        : () => _openSalonMediaViewer(
                                            urls: allImageSources,
                                            type: 'image',
                                            initialIndex: mediaIndex,
                                          ),
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(13),
                                          child: isLocal
                                              ? Image.file(File(source), width: width, height: height, fit: BoxFit.cover)
                                              : ChatCachedMedia(
                                                   remoteUrl: source,
                                                   width: width,
                                                   height: height,
                                                   fit: BoxFit.cover,
                                                   borderRadius: BorderRadius.circular(13),
                                                 ),
                                        ),
                                      if (message['is_uploading'] == true)
                                        Container(
                                          width: width, height: height,
                                          decoration: BoxDecoration(
                                            color: Colors.black.withOpacity(.38),
                                            borderRadius: BorderRadius.circular(13),
                                          ),
                                          child: const Center(
                                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                                          ),
                                          ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              )
                            else
                              GestureDetector(
                                onTap: message['is_uploading'] == true
                                    ? null
                                    : () => _openSalonMediaViewer(
                                        urls: localMediaPaths.isNotEmpty
                                            ? localMediaPaths
                                            : <String>[mediaUrl],
                                        type: 'video',
                                      ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(13),
                                      child: localMediaPaths.isNotEmpty
                                          ? _SalonVideoPlayer(url: localMediaPaths.first, isLocal: true)
                                          : _SalonVideoPlayer(url: mediaUrl),
                                    ),
                                  if (message['is_uploading'] == true)
                                    Container(
                                      width: 250, height: 190,
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(.38),
                                        borderRadius: BorderRadius.circular(13),
                                      ),
                                      child: const Center(
                                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                                      ),
                                      ),
                                  ],
                                ),
                              )
                          else if ((message['content'] ?? '').toString().isNotEmpty)
                            Text((message['content'] ?? '').toString(),
                              style: TextStyle(color: colors.onSurface.withOpacity(.92), fontSize: 14.5, height: 1.35)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(timeLabel, style: TextStyle(fontSize: 9, color: timeColor)),
                        if (mine) ...[
                          const SizedBox(height: 2),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.done_all_rounded, size: 12,
                                color: colors.onSurfaceVariant.withOpacity(.55)),
                              const SizedBox(width: 3),
                              Text('Envoyé', style: TextStyle(fontSize: 9, color: timeColor)),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              ),
            );
          })),
        if (_recording)
          _recordingPanel(colors)
        else
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: BoxDecoration(
                color: colors.surface.withOpacity(.97),
                border: Border(top: BorderSide(color: colors.outlineVariant.withOpacity(.35), width: .6)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_replyToMessage != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(color: colors.primaryContainer.withOpacity(.45), borderRadius: BorderRadius.circular(13)),
                      child: Row(children: [
                        Icon(Icons.reply_rounded, size: 17, color: colors.primary),
                        const SizedBox(width: 8),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('chat_groups_replying_to'.trParams({'name': (_replyToMessage?['sender_name'] ?? 'Membre').toString()}), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: colors.primary)),
                          Text((_replyToMessage?['content'] ?? (_replyToMessage?['type'] == 'image' ? 'chat_groups_pick_image'.tr : _replyToMessage?['type'] == 'video' ? 'chat_groups_pick_video'.tr : 'chat_groups_audio_message'.tr)).toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
                        ])),
                        IconButton(visualDensity: VisualDensity.compact, onPressed: () => setState(() => _replyToMessage = null), icon: const Icon(Icons.close_rounded, size: 18)),
                      ]),
                    ),
                  Row(
                    children: [
                  _SalonCircleAction(
                    icon: Icons.photo_library_outlined,
                    onTap: _sending || _uploadingMedia || (!_imageMessagesAllowed && !_videoMessagesAllowed) ? null : _pickMedia,
                    size: 42,
                  ),
                  const SizedBox(width: 8),
                  if (_textMessagesAllowed)
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'chat_groups_message_hint'.tr,
                          hintStyle: TextStyle(color: colors.onSurfaceVariant),
                          filled: true,
                          fillColor: colors.surfaceContainerHighest.withOpacity(.3),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(color: colors.outlineVariant.withOpacity(.35), width: .5),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(color: colors.outlineVariant.withOpacity(.35), width: .5),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(color: colors.outline.withOpacity(.55), width: .7),
                          ),
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                  if (_audioMessagesAllowed) const SizedBox(width: 8),
                  if (_audioMessagesAllowed)
                    _SalonCircleAction(
                      icon: _textMessagesAllowed && _input.text.trim().isNotEmpty ? Icons.send_rounded : Icons.mic_none_rounded,
                      primary: _textMessagesAllowed && _input.text.trim().isNotEmpty,
                      onTap: _sending || _uploadingMedia
                          ? null
                          : (_textMessagesAllowed && _input.text.trim().isNotEmpty
                              ? _send
                              : (_recording ? _stopRecordingAndSend : _startRecording)),
                      onLongPress: _textMessagesAllowed ? null : _startRecording,
                      onLongPressUp: _recording ? _stopRecordingAndSend : null,
                      size: 42,
                    )
                  else if (_textMessagesAllowed)
                    _SalonCircleAction(
                      icon: Icons.send_rounded,
                      primary: true,
                      onTap: _input.text.trim().isNotEmpty && !_sending && !_uploadingMedia ? _send : null,
                      size: 42,
                    ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ]),
    );
  }
}


class _SalonWaveformPainter extends CustomPainter {
  const _SalonWaveformPainter({required this.active, required this.inactive});
  final Color active, inactive;
  static const List<double> _heights = [
    .18,.28,.45,.7,.38,.62,.3,.52,.76,.4,.66,.25,.5,.32,.72,.46,
    .22,.58,.8,.35,.64,.42,.25,.55,.74,.34,.62,.45,.2,.5,.7,.3,
    .56,.78,.38,.62,.28,.48,.68,.34,.58,.76,.4,.24,.52,.72,.36,.6,
  ];
  @override
  void paint(Canvas canvas, Size size) {
    final spacing = size.width / _heights.length;
    final barWidth = math.max(2.0, spacing * .34);
    for (var i = 0; i < _heights.length; i++) {
      final h = math.max(5.0, _heights[i] * size.height * .72);
      final x = spacing * i + (spacing - barWidth) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x + barWidth / 2, size.height / 2), width: barWidth, height: h),
          const Radius.circular(3),
        ),
        Paint()..color = i < 29 ? active : inactive,
      );
    }
  }
  @override
  bool shouldRepaint(covariant _SalonWaveformPainter oldDelegate) =>
      oldDelegate.active != active || oldDelegate.inactive != inactive;
}

class _SalonCircleAction extends StatelessWidget {
  const _SalonCircleAction({
    required this.icon, required this.onTap, this.primary = false,
    this.loading = false, this.recording = false, this.onLongPress, this.onLongPressUp, this.size = 43,
  });
  final IconData icon;
  final VoidCallback? onTap;
  final bool primary, loading, recording;
  final VoidCallback? onLongPress, onLongPressUp;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = recording ? colors.error : primary ? colors.primary : colors.onSurfaceVariant;
    return GestureDetector(
      onTap: onTap, onLongPress: onLongPress, onLongPressUp: onLongPressUp,
      child: Container(
        width: size, height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(.13)),
        alignment: Alignment.center,
        child: loading
          ? SizedBox(width: 19, height: 19, child: CircularProgressIndicator(strokeWidth: 2, color: color))
          : Icon(icon, size: 22, color: color),
      ),
    );
  }
}

class _SalonVideoPlayer extends StatefulWidget {
  const _SalonVideoPlayer({required this.url, this.isLocal = false});
  final String url;
  final bool isLocal;

  @override
  State<_SalonVideoPlayer> createState() => _SalonVideoPlayerState();
}

class _SalonVideoPlayerState extends State<_SalonVideoPlayer> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final localPath = widget.isLocal
          ? widget.url
          : await ChatMediaCache.instance.resolveLocalPath(widget.url);
      final controller = localPath != null && await File(localPath).exists()
          ? VideoPlayerController.file(File(localPath))
          : VideoPlayerController.networkUrl(Uri.parse(widget.url));
      _controller = controller;
      await controller.initialize();
      if (mounted) setState(() => _ready = true);
    } catch (error) {
      debugPrint('[SALON_MEDIA] Video preview failed: $error');
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_failed) return const SizedBox(width: 230, height: 130, child: Center(child: Icon(Icons.videocam_off_outlined)));
    if (!_ready || controller == null) return const SizedBox(width: 230, height: 130, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    return SizedBox(
      width: 230,
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(controller),
            IconButton.filledTonal(
              onPressed: () => setState(() {
                controller.value.isPlaying ? controller.pause() : controller.play();
              }),
              icon: Icon(controller.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
