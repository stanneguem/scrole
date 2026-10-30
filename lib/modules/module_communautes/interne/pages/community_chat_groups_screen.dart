import 'dart:math' as math;
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';
import 'package:scrole/app/repository_global/r2_media_repository.dart';
import 'package:scrole/modules/module_discussion_direct/interne/widgets/direct_voice_message_player.dart';
import 'package:scrole/shared/models/chat_message.dart' as legacy;
import 'package:scrole/shared/widgets/image_source_sheet.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'create_community_chat_group_screen.dart';
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
    try {
      final result = await _client.rpc('request_community_chat_group_access', params: {'p_salon_id': group['id']});
      final status = result is Map ? result['status']?.toString() : 'accepted';
      if (status == 'accepted') {
        if (!mounted) return;
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CommunityChatGroupConversation(
          salonId: group['id'].toString(), name: group['name']?.toString() ?? 'Discussion',
          communityName: widget.communityName,
          avatarUrl: group['avatar_url']?.toString(),
        )));
        await _load();
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('chat_groups_request_sent'.tr)));
        await _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${'chat_groups_access_error'.tr} : $e')));
    }
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

class CommunityChatGroupConversation extends StatefulWidget {
  final String salonId;
  final String name;
  final String communityName;
  final String? avatarUrl;
  const CommunityChatGroupConversation({super.key, required this.salonId, required this.name, required this.communityName, this.avatarUrl});
  @override
  State<CommunityChatGroupConversation> createState() => _CommunityChatGroupConversationState();
}

class _CommunityChatGroupConversationState extends State<CommunityChatGroupConversation> {
  final _client = Supabase.instance.client;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  bool _recording = false;
  bool _uploadingMedia = false;
  final AudioRecorder _recorder = AudioRecorder();
  DateTime? _recordingStartedAt;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _channel = _client.channel('salon:${widget.salonId}', opts: const RealtimeChannelConfig(private: true))
      .onBroadcast(event: 'salon_message_sent', callback: (_) { _loadMessages(); })
      .onBroadcast(event: 'salon_message_edited', callback: (_) { _loadMessages(); })
      .onBroadcast(event: 'salon_message_deleted', callback: (_) { _loadMessages(); })
      .subscribe();
  }

  Future<void> _loadMessages() async {
    try {
      final data = await _client.rpc('get_salon_messages', params: {'p_salon_id': widget.salonId, 'p_limit': 100});
      if (!mounted) return;
      final messages = (data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList().reversed.toList();
      for (final message in messages) {
        final type = message['type']?.toString();
        final field = type == 'audio' ? 'audio_url' : 'content';
        if (type == 'audio' || type == 'image' || type == 'video' || type == 'file') {
          final key = message[field]?.toString() ?? '';
          if (key.isNotEmpty) {
            try {
              final response = await _client.functions.invoke('r2-media-upload', body: {
                'action': 'create-download-url',
                'object_key': key,
              });
              if (response.status >= 200 && response.status < 300 && response.data is Map) {
                final url = (response.data as Map)['url']?.toString();
                if (url != null && url.isNotEmpty) {
                  message[type == 'audio' ? 'audio_signed_url' : 'media_signed_url'] = url;
                }
              }
            } catch (error) {
              debugPrint('[SALON_MEDIA] URL resolution failed: $error');
            }
          }
        }
      }
      final senderIds = messages
          .map((message) => message['sender_id']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      if (senderIds.isNotEmpty) {
        try {
          final profiles = await _client
              .from('user_profiles')
              .select('user_id, username, first_name, last_name')
              .inFilter('user_id', senderIds);
          final namesById = <String, String>{};
          for (final rawProfile in profiles) {
            final profile = Map<String, dynamic>.from(rawProfile as Map);
            final fullName = [profile['first_name'], profile['last_name']]
                .where((part) => part != null && part.toString().trim().isNotEmpty)
                .map((part) => part.toString().trim())
                .join(' ');
            final displayName = fullName.isNotEmpty
                ? fullName
                : (profile['username'] ?? 'Membre').toString();
            namesById[profile['user_id'].toString()] = displayName;
          }
          for (final message in messages) {
            final senderId = message['sender_id']?.toString();
            if (senderId != null) {
              message['sender_name'] = namesById[senderId] ??
                  (senderId.length > 8 ? senderId.substring(0, 8) : senderId);
            }
          }
        } catch (_) {
          for (final message in messages) {
            final senderId = message['sender_id']?.toString();
            if (senderId != null) {
              message['sender_name'] =
                  senderId.length > 8 ? senderId.substring(0, 8) : senderId;
            }
          }
        }
      }
      setState(() { _messages = messages; _loading = false; });
      WidgetsBinding.instance.addPostFrameCallback((_) { if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent); });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${'chat_groups_messages_error'.tr} : $e')));
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
    if (_sending || _uploadingMedia) return;
    final picker = ImagePicker();
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(child: Wrap(children: [
        ListTile(leading: const Icon(Icons.photo_library_outlined), title: Text('chat_groups_pick_image'.tr), onTap: () => Navigator.pop(ctx, 'image')),
        ListTile(leading: const Icon(Icons.videocam_outlined), title: Text('chat_groups_pick_video'.tr), onTap: () => Navigator.pop(ctx, 'video')),
        ListTile(leading: const Icon(Icons.camera_alt_outlined), title: Text('chat_groups_take_photo'.tr), onTap: () => Navigator.pop(ctx, 'camera')),
      ])),
    );
    if (choice == null) return;
    try {
      XFile? file;
      if (choice == 'image') file = await picker.pickImage(source: ImageSource.gallery);
      if (choice == 'video') file = await picker.pickVideo(source: ImageSource.gallery);
      if (choice == 'camera') file = await picker.pickImage(source: ImageSource.camera);
      if (file == null) return;
      setState(() => _uploadingMedia = true);
      final isVideo = choice == 'video' || file.mimeType?.startsWith('video/') == true;
      final key = await _uploadFile(file.path, mediaType: isVideo ? 'video' : 'image');
      await _client.rpc('send_salon_message', params: {
        'p_id': _newUuid(), 'p_salon_id': widget.salonId, 'p_content': key,
        'p_type': isVideo ? 'video' : 'image', 'p_audio_url': null, 'p_replied_to_id': null,
      });
      await _loadMessages();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${'chat_groups_media_send_error'.tr} : $e')));
    } finally { if (mounted) setState(() => _uploadingMedia = false); }
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
    if (content.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _client.rpc('send_salon_message', params: {'p_id': _newUuid(), 'p_salon_id': widget.salonId, 'p_content': content, 'p_type': 'texte'});
      _input.clear();
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
    _input.dispose(); _scroll.dispose();
    _recorder.dispose();
    if (_channel != null) _client.removeChannel(_channel!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = _client.auth.currentUser?.id;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Row(children: [
        CircleAvatar(
          radius: 19,
          backgroundColor: colors.primaryContainer,
          backgroundImage: widget.avatarUrl != null && widget.avatarUrl!.isNotEmpty ? NetworkImage(widget.avatarUrl!) : null,
          child: widget.avatarUrl == null || widget.avatarUrl!.isEmpty
              ? Icon(Icons.forum_outlined, color: colors.onPrimaryContainer, size: 19)
              : null,
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(widget.communityName, style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
        ])),
      ])),
      body: Column(children: [
        Expanded(child: _loading ? Center(child: CircularProgressIndicator()) : _messages.isEmpty
          ? Center(child: Text('chat_groups_first_message'.tr))
          : ListView.builder(controller: _scroll, padding: const EdgeInsets.all(12), itemCount: _messages.length, itemBuilder: (_, i) {
            final message = _messages[i];
            final mine = message['sender_id']?.toString() == uid;
            final deleted = message['is_deleted'] == true;
            final type = message['type']?.toString() ?? 'texte';
            final mediaUrl = (message['media_signed_url'] ?? '').toString();
            final audioUrl = (message['audio_signed_url'] ?? '').toString();
            final senderName = (message['sender_name'] ?? 'Membre').toString();
            final sentAt = DateTime.tryParse(message['sent_at']?.toString() ?? '');
            final timeLabel = sentAt == null ? '' : TimeOfDay.fromDateTime(sentAt.toLocal()).format(context);
            final isAudio = type == 'audio' && audioUrl.isNotEmpty;
            final isMedia = (type == 'image' || type == 'video') && mediaUrl.isNotEmpty;
            final timeColor = colors.onSurfaceVariant.withOpacity(.52);
            return GestureDetector(
              onLongPress: () => _showMessageActions(message, mine),
              child: Padding(
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
                          else if (isMedia)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(13),
                              child: type == 'video'
                                ? _SalonVideoPlayer(url: mediaUrl)
                                : Image.network(mediaUrl, width: 250, height: 190, fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const SizedBox(width: 250, height: 90,
                                      child: Center(child: Icon(Icons.broken_image_outlined))),
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
              child: Row(
                children: [
                  _SalonCircleAction(
                    icon: Icons.photo_library_outlined,
                    onTap: _sending || _uploadingMedia ? null : _pickMedia,
                    loading: _uploadingMedia,
                    size: 42,
                  ),
                  const SizedBox(width: 8),
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
                  const SizedBox(width: 8),
                  _SalonCircleAction(
                    icon: _input.text.trim().isNotEmpty ? Icons.send_rounded : Icons.mic_none_rounded,
                    primary: _input.text.trim().isNotEmpty,
                    onTap: _sending || _uploadingMedia ? null :
                      (_input.text.trim().isNotEmpty ? _send : _startRecording),
                    size: 42,
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
  const _SalonVideoPlayer({required this.url});
  final String url;

  @override
  State<_SalonVideoPlayer> createState() => _SalonVideoPlayerState();
}

class _SalonVideoPlayerState extends State<_SalonVideoPlayer> {
  late final VideoPlayerController _controller;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (mounted) setState(() => _ready = true);
      }).catchError((_) {
        if (mounted) setState(() => _failed = true);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const SizedBox(width: 230, height: 130, child: Center(child: Icon(Icons.videocam_off_outlined)));
    if (!_ready) return const SizedBox(width: 230, height: 130, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    return SizedBox(
      width: 230,
      child: AspectRatio(
        aspectRatio: _controller.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(_controller),
            IconButton.filledTonal(
              onPressed: () => setState(() {
                _controller.value.isPlaying ? _controller.pause() : _controller.play();
              }),
              icon: Icon(_controller.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
