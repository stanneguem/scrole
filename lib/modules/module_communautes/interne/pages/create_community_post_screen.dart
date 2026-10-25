import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';
import 'package:scrole/shared/widgets/video_trim_screen.dart';
import 'package:scrole/app/theme/app_colors.dart';
import 'package:scrole/app/theme/text_styles.dart';
import 'package:scrole/app_controller.dart';
import 'package:scrole/shared/widgets/app_cached_image.dart';
import 'package:scrole/shared/widgets/user_certified_badge.dart';
import 'package:scrole/shared/widgets/media_gallery_sheet.dart';
import 'package:scrole/shared/constants/post_media_limits.dart';
import 'package:scrole/modules/module_communautes/interne/controllers/community/community_feed_controller.dart';
import 'package:scrole/modules/module_principale/interne/controllers/home_feed_controller.dart';
import 'package:scrole/modules/module_principale/centre/models/community_post.dart';
import 'package:scrole/modules/module_principale/interne/widgets/feed_post_card.dart';
import 'package:scrole/modules/module_communautes/centre/services/community_service.dart';
import 'package:scrole/modules/module_communautes/centre/models/news/community_hashtag.dart';
import 'community_poll_composer_screen.dart';
import 'community_post_hashtag_selection_screen.dart';

class CreateCommunityPostScreen extends StatefulWidget {
  final String communityName;
  final String? communityId;
  final String? prefilledText;
  final String? prefilledMediaUrl;
  final CommunityPost? sharedPost;

  const CreateCommunityPostScreen({
    super.key,
    required this.communityName,
    this.communityId,
    this.prefilledText,
    this.prefilledMediaUrl,
    this.sharedPost,
  });

  @override
  State<CreateCommunityPostScreen> createState() => _CreateCommunityPostScreenState();
}

class _SelectedPostMedia {
  final File file;
  final bool isVideo;
  const _SelectedPostMedia({required this.file, required this.isVideo});
}

class _CreateCommunityPostScreenState extends State<CreateCommunityPostScreen> {
  late final TextEditingController _textController;
  // Single source of truth: this list preserves the exact order in which media are selected.
  final List<_SelectedPostMedia> _selectedMedia = [];
  List<File> get _selectedFiles => _selectedMedia.where((m) => !m.isVideo).map((m) => m.file).toList();
  List<File> get _selectedVideos => _selectedMedia.where((m) => m.isVideo).map((m) => m.file).toList();
  final ImagePicker _mediaPicker = ImagePicker();
  int get _selectedMediaCount => _selectedMedia.length;
  int get _selectedPhotoCount => _selectedMedia.where((m) => !m.isVideo).length;
  String? _prefilledUrl;
  Map<String, dynamic>? _pollData;
  bool _isPublishing = false;

  bool _commentsEnabled = true;
  bool _sharingEnabled = true;
  bool _reactionsEnabled = true;
  String _audience = 'public'; // 'public' | 'followers' | 'friends'
  bool _allowPromotion = true; // false keeps the post exclusive to its community

  final List<CommunityHashtag> _selectedHashtags = [];
  List<Map<String, dynamic>> _selectedMentions = [];
  List<String> _selectedMentionIds = [];
  final Set<String> _selectedCommunityIds = {};
  final Set<String> _selectedEventIds = {};
  final LayerLink _mentionLayerLink = LayerLink();
  OverlayEntry? _mentionOverlay;
  Timer? _mentionSearchDebounce;
  List<Map<String, dynamic>> _mentionSuggestions = [];
  String? _activeMentionType;
  int _mentionStart = -1;
  int _mentionRequest = 0;
  List<Map<String, dynamic>> _liveSuggestions = [];
  String? _suggestionTrigger;
  String _suggestionQuery = '';
  bool _loadingSuggestions = false;
  Timer? _suggestionDebounce;
  int _suggestionRequestId = 0;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.prefilledText ?? '');
    _prefilledUrl = widget.prefilledMediaUrl;
  }

  @override
  void dispose() {
    _suggestionDebounce?.cancel();
    _mentionOverlay?.remove();
    _mentionSearchDebounce?.cancel();
    _textController.dispose();
    super.dispose();
  }

  bool get _canPublish =>
      widget.sharedPost != null ||
      _textController.text.trim().isNotEmpty ||
      _selectedMedia.isNotEmpty ||
      (_prefilledUrl != null && _prefilledUrl!.isNotEmpty) ||
      _pollData != null;

  void _handleLegacyComposerTextChanged(String value) {
    setState(() {});
    _suggestionDebounce?.cancel();
    final cursor = _textController.selection.baseOffset;
    if (cursor < 0 || cursor > value.length) { _hideLiveSuggestions(); return; }
    final match = RegExp(r'(?:^|\s)([#@])([^\s#@]*)$').firstMatch(value.substring(0, cursor));
    if (match == null) { _hideLiveSuggestions(); return; }
    final trigger = match.group(1)!;
    final query = match.group(2) ?? '';
    if (query.isEmpty) { _hideLiveSuggestions(); return; }
    setState(() {
      _suggestionTrigger = trigger;
      _suggestionQuery = query;
      _liveSuggestions = [];
      _loadingSuggestions = true;
    });
    final requestId = ++_suggestionRequestId;
    _suggestionDebounce = Timer(const Duration(milliseconds: 250), () {
      if (trigger == '#') { _searchLiveHashtags(query, requestId); }
      else { _searchLiveMentions(query, requestId); }
    });
  }

  void _removeMentionOverlay() {
    _mentionOverlay?.remove();
    _mentionOverlay = null;
    _activeMentionType = null;
    _mentionSuggestions = [];
  }

  void _onPostTextChanged(String value) {
    final cursor = _textController.selection.baseOffset;
    if (cursor >= 0 && cursor <= value.length) {
      final prefix = value.substring(0, cursor);
      final match = RegExp(r'(^|\s)([@*~])([^\s@*~]*)$').firstMatch(prefix);
      if (match != null) {
        _hideLiveSuggestions();
        final trigger = match.group(2)!;
        _activeMentionType = trigger == '@' ? 'user' : trigger == '*' ? 'event' : 'community';
        _mentionStart = cursor - trigger.length - (match.group(3) ?? '').length;
        final query = match.group(3) ?? '';
        _mentionSearchDebounce?.cancel();
        _mentionSearchDebounce = Timer(const Duration(milliseconds: 180), () {
          _searchPostMentionSuggestions(query, _activeMentionType!);
        });
        setState(() {});
        return;
      }
    }
    _removeMentionOverlay();
    _handleLegacyComposerTextChanged(value);
  }

  Future<void> _searchPostMentionSuggestions(String query, String type) async {
    final request = ++_mentionRequest;
    try {
      final client = Supabase.instance.client;
      List<Map<String, dynamic>> results = [];
      if (type == 'user') {
        final userId = client.auth.currentUser?.id;
        if (userId != null) {
          final allowedIds = <String>{};
          final communityId = widget.communityId;
          if (communityId != null && communityId.isNotEmpty) {
            final members = await client.from('community_members')
                .select('user_id').eq('community_id', communityId).limit(1000);
            allowedIds.addAll(members.map((m) => m['user_id'].toString()));
          } else {
            final friendships = await client.from('friendships').select('user_a_id,user_b_id')
                .or('user_a_id.eq.$userId,user_b_id.eq.$userId').limit(500);
            for (final relation in friendships) {
              final other = relation['user_a_id']?.toString() == userId
                  ? relation['user_b_id']?.toString() : relation['user_a_id']?.toString();
              if (other != null && other.isNotEmpty) allowedIds.add(other);
            }
            final followers = await client.from('user_follows').select('follower_id')
                .eq('followed_id', userId).limit(1000);
            allowedIds.addAll(followers.map((r) => r['follower_id'].toString()));
          }
          allowedIds.remove(userId);
          if (allowedIds.isNotEmpty) {
            final safeQuery = query.replaceAll(',', '').replaceAll('%', '').replaceAll('_', r'\_');
            final rows = await client.from('user_profiles')
                .select('user_id, username, first_name, last_name, photo_url, is_verified')
                .inFilter('user_id', allowedIds.toList())
                .eq('account_status', 'active').isFilter('deleted_at', null)
                .or('username.ilike.%$safeQuery%,first_name.ilike.%$safeQuery%,last_name.ilike.%$safeQuery%')
                .order('username').limit(7);
            results = rows.map((r) => Map<String, dynamic>.from(r)).toList();
          }
        }
      } else if (type == 'community') {
        final rows = await client.from('communities')
            .select('id, name, photo_profile, visibility')
            .eq('status', 'active').ilike('name', '%$query%')
            .order('name').limit(7);
        results = rows.map((r) => Map<String, dynamic>.from(r)).toList();
      } else {
        final rows = await client.from('events')
            .select('id, name, photo, starts_at, status')
            .ilike('name', '%$query%').order('starts_at').limit(12);
        results = rows.map((r) => Map<String, dynamic>.from(r))
            .where((r) => !const {'deleted', 'cancelled', 'archived'}.contains((r['status'] ?? '').toString().toLowerCase()))
            .take(7).toList();
      }
      if (!mounted || request != _mentionRequest || _activeMentionType != type) return;
      setState(() => _mentionSuggestions = results);
      _showPostMentionOverlay();
    } catch (e) {
      debugPrint('[MENTIONS] Post suggestion search failed: $e');
      if (request == _mentionRequest) _removeMentionOverlay();
    }
  }

  void _showPostMentionOverlay() {
    if (_mentionSuggestions.isEmpty || _activeMentionType == null) {
      _removeMentionOverlay();
      return;
    }
    _mentionOverlay ??= OverlayEntry(builder: (overlayContext) {
      final type = _activeMentionType;
      final items = List<Map<String, dynamic>>.from(_mentionSuggestions);
      return Positioned(
        width: MediaQuery.of(context).size.width - 32,
        child: CompositedTransformFollower(
          link: _mentionLayerLink, showWhenUnlinked: false,
          targetAnchor: Alignment.bottomLeft, followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 8),
          child: Material(
            elevation: 12, color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14), clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 250),
              child: ListView.separated(
                padding: EdgeInsets.zero, shrinkWrap: true, itemCount: items.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: Theme.of(context).dividerColor.withValues(alpha: .35)),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final isUser = type == 'user';
                  final title = isUser
                      ? ((item['username'] ?? '').toString().isNotEmpty ? '@${item['username']}' : '${item['first_name'] ?? ''} ${item['last_name'] ?? ''}'.trim())
                      : (item['name'] ?? '').toString();
                  final subtitle = isUser ? '${item['first_name'] ?? ''} ${item['last_name'] ?? ''}'.trim()
                      : type == 'event' ? (item['starts_at'] ?? '').toString().replaceFirst('T', ' ') : 'Communauté';
                  final image = (item[isUser ? 'photo_url' : type == 'event' ? 'photo' : 'photo_profile'] ?? '').toString();
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      backgroundImage: image.startsWith('http') ? NetworkImage(image) : null,
                      child: image.startsWith('http') ? null : Icon(isUser ? Icons.person_outline : type == 'event' ? Icons.event_outlined : Icons.groups_outlined, size: 19),
                    ),
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        ),
                        if (isUser && (item['user_id'] ?? item['id']) != null) ...[
                          const SizedBox(width: 4),
                          UserCertifiedBadge(
                            userId: (item['user_id'] ?? item['id']).toString(),
                            size: 15,
                            showTooltip: true,
                          ),
                        ],
                      ],
                    ),
                    subtitle: subtitle.isEmpty ? null : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                    onTap: () => _insertPostMention(type!, item),
                  );
                },
              ),
            ),
          ),
        ),
      );
    });
    final overlay = Overlay.of(context);
    if (!_mentionOverlay!.mounted) overlay.insert(_mentionOverlay!);
    else _mentionOverlay!.markNeedsBuild();
  }

  void _insertPostMention(String type, Map<String, dynamic> item) {
    final id = (item[type == 'user' ? 'user_id' : 'id'] ?? '').toString();
    final token = type == 'user' ? '@${item['username'] ?? item['first_name'] ?? 'utilisateur'}'
        : type == 'event' ? '*${item['name'] ?? 'événement'}' : '~${item['name'] ?? 'communauté'}';
    final text = _textController.text;
    final cursor = _textController.selection.baseOffset.clamp(0, text.length);
    final start = _mentionStart.clamp(0, cursor);
    _textController.value = TextEditingValue(
      text: text.replaceRange(start, cursor, '$token '),
      selection: TextSelection.collapsed(offset: start + token.length + 1),
    );
    if (id.isNotEmpty) {
      if (type == 'user') {
        _selectedMentions.removeWhere((m) => (m['user_id'] ?? '').toString() == id);
        _selectedMentions.add(item);
        _selectedMentionIds = _selectedMentions.map((m) => (m['user_id'] ?? m['id'] ?? '').toString()).where((x) => x.isNotEmpty).toList();
      } else if (type == 'event') {
        _selectedEventIds.add(id);
      } else {
        _selectedCommunityIds.add(id);
      }
    }
    _removeMentionOverlay();
    setState(() {});
  }

  void _hideLiveSuggestions() {
    if (_suggestionTrigger == null && _liveSuggestions.isEmpty && !_loadingSuggestions) return;
    _suggestionRequestId++;
    setState(() {
      _suggestionTrigger = null;
      _suggestionQuery = '';
      _liveSuggestions = [];
      _loadingSuggestions = false;
    });
  }

  Future<void> _searchLiveHashtags(String query, int requestId) async {
    try {
      final response = await Supabase.instance.client.rpc(
        'search_community_hashtags',
        params: {'p_query': query.replaceFirst(RegExp(r'^#+'), ''), 'p_limit': 8},
      );
      dynamic decoded = response;
      if (decoded is String) decoded = jsonDecode(decoded);
      final results = decoded is List
          ? decoded.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
          : <Map<String, dynamic>>[];
      if (!mounted || requestId != _suggestionRequestId) return;
      setState(() { _liveSuggestions = results; _loadingSuggestions = false; });
    } catch (error) {
      debugPrint('[PostComposer] hashtag autocomplete failed: $error');
      if (!mounted || requestId != _suggestionRequestId) return;
      setState(() { _liveSuggestions = []; _loadingSuggestions = false; });
    }
  }

  Future<void> _searchLiveMentions(String query, int requestId) async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) {
        if (mounted && requestId == _suggestionRequestId) setState(() { _liveSuggestions = []; _loadingSuggestions = false; });
        return;
      }
      List<Map<String, dynamic>> results = [];
      final communityId = widget.communityId;
      if (communityId != null && communityId.isNotEmpty) {
        final service = Get.isRegistered<CommunityService>()
            ? Get.find<CommunityService>() : Get.put(CommunityService());
        final response = await service.getCommunityMembersRpc(
          communityId: communityId, limit: 12, query: query,
        );
        final raw = response['items'] ?? response['members'] ?? response['data'] ?? [];
        if (raw is List) {
          results = raw.whereType<Map>().map((item) {
            final row = Map<String, dynamic>.from(item);
            final profile = row['user_profiles'] is Map
                ? Map<String, dynamic>.from(row['user_profiles'] as Map) : <String, dynamic>{};
            return {
              ...profile, ...row,
              'user_id': row['user_id'] ?? profile['user_id'] ?? row['userId'] ?? row['profile_id'] ?? profile['id'],
              'username': row['username'] ?? profile['username'],
              'first_name': row['first_name'] ?? profile['first_name'],
              'last_name': row['last_name'] ?? profile['last_name'],
              'photo_url': row['photo_url'] ?? profile['photo_url'],
            };
          }).where((item) => (item['user_id'] ?? '').toString() != userId).toList();
        }
      } else {
        final friendships = await client.from('friendships')
            .select('user_a_id,user_b_id')
            .or('user_a_id.eq.$userId,user_b_id.eq.$userId').limit(200);
        final friendIds = <String>{};
        for (final relation in friendships) {
          final otherId = relation['user_a_id']?.toString() == userId
              ? relation['user_b_id']?.toString() : relation['user_a_id']?.toString();
          if (otherId != null && otherId.isNotEmpty && otherId != userId) friendIds.add(otherId);
        }
        if (friendIds.isNotEmpty) {
          final safeQuery = query.replaceAll(',', '').replaceAll('%', '').replaceAll('_', r'\_');
          final profiles = await client.from('user_profiles')
              .select('user_id,username,first_name,last_name,photo_url,is_verified')
              .inFilter('user_id', friendIds.toList())
              .or('username.ilike.%$safeQuery%,first_name.ilike.%$safeQuery%,last_name.ilike.%$safeQuery%')
              .limit(8);
          results = List<Map<String, dynamic>>.from(profiles);
        }
      }
      if (!mounted || requestId != _suggestionRequestId) return;
      setState(() { _liveSuggestions = results.take(8).toList(); _loadingSuggestions = false; });
    } catch (error) {
      debugPrint('[PostComposer] mention autocomplete failed: $error');
      if (!mounted || requestId != _suggestionRequestId) return;
      setState(() { _liveSuggestions = []; _loadingSuggestions = false; });
    }
  }

  void _insertLiveSuggestion(Map<String, dynamic> suggestion) {
    final trigger = _suggestionTrigger;
    if (trigger == null) return;
    final username = (suggestion['username'] ?? '').toString().trim();
    final cleanName = (trigger == '#'
        ? (suggestion['name'] ?? suggestion['normalized_name'] ?? '').toString().trim().replaceFirst(RegExp(r'^#+'), '')
        : username).replaceFirst(RegExp(r'^[@#]+'), '');
    final insertionValue = cleanName.isNotEmpty ? '$trigger$cleanName ' : '';
    if (insertionValue.isEmpty) return;
    final cursor = _textController.selection.baseOffset.clamp(0, _textController.text.length);
    final start = (cursor - _suggestionQuery.length - 1).clamp(0, cursor);
    final newText = _textController.text.replaceRange(start, cursor, insertionValue);
    _textController.value = TextEditingValue(text: newText,
        selection: TextSelection.collapsed(offset: start + insertionValue.length));
    if (trigger == '#') {
      if (!_selectedHashtags.any((tag) => tag.name.toLowerCase() == cleanName.toLowerCase())) {
        _selectedHashtags.add(CommunityHashtag(
          id: (suggestion['id'] ?? cleanName).toString(), name: cleanName,
          postCount: (suggestion['post_count'] as num?)?.toInt() ?? 0,
        ));
      }
    } else {
      final id = (suggestion['user_id'] ?? suggestion['id'] ?? '').toString();
      if (id.isNotEmpty && !_selectedMentionIds.contains(id)) {
        _selectedMentionIds.add(id);
        _selectedMentions.add({...suggestion, 'user_id': id});
      }
    }
    _hideLiveSuggestions();
    setState(() {});
  }

  Widget _buildLiveSuggestions(ColorScheme colors) {
    final trigger = _suggestionTrigger;
    if (trigger == null) return const SizedBox.shrink();
    final scope = widget.communityId != null && widget.communityId!.isNotEmpty ? 'cette communauté' : 'tes amis';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 260),
        decoration: BoxDecoration(
          color: colors.surface, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.outlineVariant.withValues(alpha: .8)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .06), blurRadius: 14, offset: const Offset(0, 5))],
        ),
        child: _loadingSuggestions
            ? const Padding(padding: EdgeInsets.all(16), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))))
            : _liveSuggestions.isEmpty
                ? Padding(padding: const EdgeInsets.all(14), child: Text(
                    trigger == '#' ? 'Aucun hashtag trouvé pour le moment.' : 'Aucun compte correspondant dans ${scope}.',
                    style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant)))
                : ListView.separated(
                    shrinkWrap: true, padding: const EdgeInsets.symmetric(vertical: 5),
                    itemCount: _liveSuggestions.length,
                    separatorBuilder: (_, __) => Divider(height: 1, indent: 54, color: colors.outlineVariant.withValues(alpha: .45)),
                    itemBuilder: (context, index) {
                      final item = _liveSuggestions[index];
                      final isTag = trigger == '#';
                      final displayName = isTag ? (item['name'] ?? '').toString()
                          : '${item['first_name'] ?? ''} ${item['last_name'] ?? ''}'.trim();
                      final handle = isTag ? '${item['post_count'] ?? 0} publication(s)' : '${item['username'] ?? ''}';
                      final photo = (item['photo_url'] ?? '').toString();
                      return ListTile(
                        dense: true,
                        leading: isTag
                            ? CircleAvatar(backgroundColor: colors.primary.withValues(alpha: .12), child: Icon(Icons.tag_rounded, color: colors.primary))
                            : CircleAvatar(backgroundColor: colors.surfaceContainerHighest,
                                backgroundImage: photo.startsWith('http') ? NetworkImage(photo) : null,
                                child: photo.startsWith('http') ? null : Icon(Icons.person_outline_rounded, color: colors.onSurfaceVariant)),
                        title: Text(isTag ? '#$displayName' : (displayName.isEmpty ? handle : displayName),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        subtitle: Text(handle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
                        onTap: () => _insertLiveSuggestion(item),
                      );
                    },
                  ),
      ),
    );
  }


  Future<void> _openPollCreator() async {
    if (_selectedMedia.isNotEmpty || (_prefilledUrl != null && _prefilledUrl!.isNotEmpty)) {
      Get.snackbar('post_composer_attention'.tr, 'post_composer_poll_no_photos'.tr, backgroundColor: Colors.black87, colorText: Colors.white);
      return;
    }
    final pollMap = await Get.to<Map<String, dynamic>>(() => const CommunityPollComposerScreen(), transition: Transition.rightToLeft);
    if (pollMap != null) {
      setState(() {
        _pollData = pollMap;
      });
    }
  }

  Future<void> _publish() async {
    if (!_canPublish || _isPublishing) return;

    final sharedPost = widget.sharedPost;
    if (sharedPost != null) {
      setState(() => _isPublishing = true);
      try {
        final feedController = Get.find<HomeFeedController>();
        await feedController.sharePost(
          originalPostId: sharedPost.sharedPostId ?? sharedPost.id,
          communityId: widget.communityId,
          audience: _audience,
          comment: _textController.text.trim().isNotEmpty
              ? _textController.text.trim()
              : null,
        );
        if (!mounted) return;
        FocusManager.instance.primaryFocus?.unfocus();
        Get.back(closeOverlays: true);
        if (widget.communityId != null && widget.communityId!.isNotEmpty) {
          try {
            final communityFeed = Get.find<CommunityFeedController>(
              tag: widget.communityId,
            );
            unawaited(communityFeed.fetchCommunityFeed(isRefresh: true));
          } catch (e) {
            debugPrint('[POST_ACTIONS] Community feed refresh skipped: $e');
          }
          Get.snackbar(
            'Succès',
            'Publication repartagée dans ${widget.communityName}.',
            snackPosition: SnackPosition.BOTTOM,
          );
        } else {
          unawaited(feedController.fetchFeed(refresh: true));
          Get.snackbar(
            'Succès',
            'Publication repartagée sur votre fil.',
            snackPosition: SnackPosition.BOTTOM,
          );
        }
      } catch (e) {
        debugPrint('[POST_ACTIONS] Republish from composer error: $e');
        if (mounted) {
          setState(() => _isPublishing = false);
          Get.snackbar(
            'Erreur',
            e.toString().replaceFirst('Exception: ', ''),
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.red,
            colorText: Colors.white,
          );
        }
      }
      return;
    }

    final orderedMedia = List<_SelectedPostMedia>.from(_selectedMedia);
    List<File> filesToPublish = orderedMedia.where((m) => !m.isVideo).map((m) => m.file).toList();
    final videosToPublish = orderedMedia.where((m) => m.isVideo).map((m) => m.file).toList();
    final orderedFilesForService = orderedMedia.map((m) => m.file).toList();
    final orderedTypesForService = orderedMedia.map((m) => m.isVideo ? 'video' : 'photo').toList();
    if (filesToPublish.isEmpty && _prefilledUrl != null && _prefilledUrl!.isNotEmpty && !_prefilledUrl!.startsWith('http')) {
      filesToPublish.add(File(_prefilledUrl!));
      orderedFilesForService.add(File(_prefilledUrl!));
      orderedTypesForService.add('photo');
    }

    final content = _textController.text.trim();

    if (content.isEmpty && filesToPublish.isEmpty && videosToPublish.isEmpty && _pollData == null) {
      Get.snackbar('post_composer_empty_title'.tr, 'post_composer_empty_message'.tr, backgroundColor: Colors.black87, colorText: Colors.white);
      return;
    }

    if (_pollData != null && content.isEmpty) {
      Get.snackbar('post_composer_attention'.tr, 'post_composer_poll_question_missing'.tr, backgroundColor: Colors.black87, colorText: Colors.white);
      return;
    }

    if (filesToPublish.length + videosToPublish.length > maxPostMedia) {
      Get.snackbar('post_composer_limit_title'.tr, 'post_composer_media_limit'.trParams({'max': '$maxPostMedia'}), backgroundColor: Colors.black87, colorText: Colors.white);
      return;
    }

    if (_isPublishing) return;
    setState(() => _isPublishing = true);

    CommunityFeedController? feedController;
    try {
      if (widget.communityId != null && widget.communityId!.isNotEmpty) {
        feedController = Get.find<CommunityFeedController>(tag: widget.communityId);
      } else {
        feedController = Get.find<CommunityFeedController>();
      }
    } catch (_) {
      try {
        feedController = Get.find<CommunityFeedController>();
      } catch (_) {}
    }

    final postContent = content.isNotEmpty ? content : null;
    // Keep explicitly selected tags and also persist hashtags typed directly in the text.
    final hashtagsList = <String>[];
    final seenHashtags = <String>{};
    void addHashtag(String raw) {
      final clean = raw.trim().replaceFirst(RegExp(r'^#+'), '');
      if (clean.isEmpty) return;
      final key = clean.toLowerCase();
      if (seenHashtags.add(key)) hashtagsList.add(clean);
    }
    for (final tag in _selectedHashtags) {
      addHashtag(tag.name);
    }
    for (final match in RegExp(r'(?<![A-Za-z0-9_])#([A-Za-z0-9_À-ÿ]+)').allMatches(content)) {
      addHashtag(match.group(1) ?? '');
    }
    final postId = const Uuid().v4();
    final mentionsList = _selectedMentionIds.toSet().toList();
    final isCommunity = widget.communityId != null && widget.communityId!.isNotEmpty;
    final cId = widget.communityId ?? '';

    final service = Get.isRegistered<CommunityService>() ? Get.find<CommunityService>() : Get.put(CommunityService());

    try {
      await service.createCommunityPost(
        requestedPostId: postId,
        communityId: cId,
        content: postContent,
        imageFiles: filesToPublish,
        videoFiles: videosToPublish,
        orderedMediaFiles: orderedFilesForService,
        orderedMediaTypes: orderedTypesForService,
        audience: isCommunity ? 'public' : _audience,
        commentsEnabled: _commentsEnabled,
        sharingEnabled: _sharingEnabled,
        reactionsEnabled: _reactionsEnabled,
        hashtags: hashtagsList,
        mentions: mentionsList,
        poll: _pollData,
        allowPromotion: isCommunity ? _allowPromotion : true,
      );
      if (_selectedCommunityIds.isNotEmpty || _selectedEventIds.isNotEmpty) {
        final communityIds = _selectedCommunityIds.toList();
        final eventIds = _selectedEventIds.toList();
        // Entity mentions are ancillary to the durable post queue; never keep
        // the composer open while this secondary RPC runs.
        unawaited(Supabase.instance.client.rpc('save_content_entity_mentions', params: {
          'p_source_type': 'post',
          'p_source_id': postId,
          'p_community_ids': communityIds,
          'p_event_ids': eventIds,
        }).then((_) {}).catchError((Object error) {
          debugPrint('[POST] Saving entity mentions failed postId=$postId error=$error');
        }));
      }
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
      Get.back(closeOverlays: true);
      if (isCommunity) {
        if (feedController != null) {
          unawaited(feedController.fetchCommunityFeed(isRefresh: true));
        }
      } else if (Get.isRegistered<HomeFeedController>()) {
        unawaited(Get.find<HomeFeedController>().fetchFeed(refresh: true));
      }
      Get.snackbar(
        'Publication mise en file',
        'Ta publication apparaît dans le fil et sera activée après confirmation du serveur.',
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      debugPrint('[POST] Publish failed for community=$cId post=$postId: $e');
      if (mounted) {
        setState(() => _isPublishing = false);
        Get.snackbar(
          'Publication non confirmée',
          e.toString().replaceFirst('Exception: ', ''),
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white,
          duration: const Duration(seconds: 6),
        );
      }
    }
  }

  Future<void> _openGallery() async {
    if (_pollData != null) {
      Get.snackbar('post_composer_attention'.tr, 'post_composer_poll_no_photos'.tr, backgroundColor: Colors.black87, colorText: Colors.white);
      return;
    }

    final maxAllowed = maxPostMedia - _selectedMediaCount;
    if (maxAllowed <= 0) {
      Get.snackbar(
        'Limite atteinte',
        'Vous pouvez ajouter au maximum $maxPostMedia médias, dont $maxPostPhotos photos.',
        backgroundColor: Colors.black87,
        colorText: Colors.white,
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MediaGallerySheet(
        maxSelection: maxAllowed,
        onSelected: _handleGallerySelection,
      ),
    );
  }


  Future<void> _handleGallerySelection(List<XFile> files) async {
    for (final picked in files) {
      if (!mounted || _selectedMediaCount >= maxPostMedia) break;
      final file = File(picked.path);
      final extension = p.extension(picked.path).replaceFirst('.', '').toLowerCase();
      final isVideo = const {'mp4', 'mov'}.contains(extension);
      if (!isVideo) {
        if (_selectedPhotoCount >= maxPostPhotos) {
          Get.snackbar('post_composer_photo_limit_title'.tr, 'post_composer_photo_limit_message'.trParams({'max': '$maxPostPhotos'}));
          continue;
        }
        setState(() {
          _selectedMedia.add(_SelectedPostMedia(file: file, isVideo: false));
          _prefilledUrl = null;
        });
        continue;
      }
      try {
        var videoFile = file;
        final controller = VideoPlayerController.file(videoFile);
        Duration duration;
        try {
          await controller.initialize();
          duration = controller.value.duration;
        } finally {
          await controller.dispose();
        }
        if (duration > const Duration(seconds: 29)) {
          final trimmed = await Get.to<File>(() => VideoTrimScreen(videoFile: videoFile, maxDuration: const Duration(seconds: 29)));
          if (trimmed == null || !mounted) continue;
          videoFile = trimmed;
          final verify = VideoPlayerController.file(videoFile);
          try {
            await verify.initialize();
            if (verify.value.duration > const Duration(seconds: 29)) {
              Get.snackbar('post_composer_attention'.tr, 'post_composer_video_too_long'.tr);
              continue;
            }
          } finally {
            await verify.dispose();
          }
        }
        if (!mounted) return;
        setState(() {
          _selectedMedia.add(_SelectedPostMedia(file: videoFile, isVideo: true));
          _prefilledUrl = null;
        });
      } catch (e) {
        if (mounted) Get.snackbar('post_composer_video_invalid_title'.tr, 'post_composer_video_invalid_message'.tr);
        debugPrint('[POST_COMPOSER] incompatible gallery video: $e');
      }
    }
  }

  Future<void> _pickVideo() async {
    if (_pollData != null) {
      Get.snackbar('Attention', 'Un sondage ne peut pas contenir de vidéo.', backgroundColor: Colors.black87, colorText: Colors.white);
      return;
    }
    if (_selectedMediaCount >= maxPostMedia) {
      Get.snackbar('post_composer_media_limit_title'.tr, 'post_composer_media_limit_message'.trParams({'max': '$maxPostMedia'}), backgroundColor: Colors.black87, colorText: Colors.white);
      return;
    }
    try {
      final picked = await _mediaPicker.pickVideo(source: ImageSource.gallery);
      if (picked == null || !mounted) return;
      var file = File(picked.path);
      final controller = VideoPlayerController.file(file);
      Duration duration;
      try {
        await controller.initialize();
        duration = controller.value.duration;
      } finally {
        await controller.dispose();
      }
      if (duration > const Duration(seconds: 29)) {
        final trimmed = await Get.to<File>(() => VideoTrimScreen(videoFile: file, maxDuration: const Duration(seconds: 29)));
        if (trimmed == null || !mounted) return;
        file = trimmed;
        final verify = VideoPlayerController.file(file);
        try {
          await verify.initialize();
          if (verify.value.duration > const Duration(seconds: 29)) {
            Get.snackbar('post_composer_attention'.tr, 'post_composer_trim_invalid'.tr, backgroundColor: Colors.black87, colorText: Colors.white);
            return;
          }
        } finally {
          await verify.dispose();
        }
      }
      if (!mounted) return;
      setState(() {
        _selectedMedia.add(_SelectedPostMedia(file: file, isVideo: true));
        _prefilledUrl = null;
      });
    } catch (e) {
      if (mounted) Get.snackbar('post_composer_video_select_error'.tr, e.toString(), backgroundColor: Colors.black87, colorText: Colors.white);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appController = Get.find<AppController>();
    final profileRaw = appController.profile.value ?? {};
    final profile = (profileRaw['profile'] is Map)
        ? Map<String, dynamic>.from(profileRaw['profile'] as Map)
        : profileRaw;
    final firstName = profile['first_name']?.toString() ?? profile['prenom']?.toString() ?? '';
    final lastName = profile['last_name']?.toString() ?? profile['nom']?.toString() ?? '';
    final fullName = "$firstName $lastName".trim();
    final username = profile['username']?.toString() ?? '';
    final displayName = fullName.isEmpty ? (username.isEmpty ? 'profile_default_username'.tr : username) : fullName;
    final avatarUrl = profile['photo_url']?.toString() ?? '';
    final isCertified = profile['is_certified'] == true || profile['is_verified'] == true || profile['is_certified'] == 1 || profile['is_verified'] == 1;
    final certificationUserId = Supabase.instance.client.auth.currentUser?.id
        ?? profile['user_id']?.toString()
        ?? profile['id']?.toString();

    final isCommunity = widget.communityId != null && widget.communityId!.isNotEmpty;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        centerTitle: false,
        title: Text('post_composer_title'.tr),
        titleTextStyle: AppTextStyles.h5.copyWith(color: colorScheme.onSurface),
        leading: IconButton(
          onPressed: () => Get.back(),
          icon: const Icon(Icons.close_rounded, size: 28),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: TextButton(
              onPressed: _canPublish && !_isPublishing ? _publish : null,
              style: TextButton.styleFrom(
                foregroundColor: _canPublish ? colorScheme.primary : colorScheme.outline,
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: _isPublishing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(
                      'post_composer_publish'.tr,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: _canPublish ? colorScheme.primary : colorScheme.outline.withValues(alpha: 0.6),
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Profil + Badge Communauté ou Audience Selector
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: colorScheme.surfaceContainerHighest),
                            child: ClipOval(
                              child: avatarUrl.isNotEmpty
                                  ? AppCachedImage(imageUrl: avatarUrl, width: 44, height: 44, fit: BoxFit.cover)
                                  : Icon(Icons.person, color: colorScheme.onSurfaceVariant),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: RichText(
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        text: TextSpan(
                                          style: AppTextStyles.h6.copyWith(fontWeight: FontWeight.bold, fontSize: 15, color: colorScheme.onSurface),
                                          children: [
                                            TextSpan(text: displayName),
                                            if (username.isNotEmpty)
                                              TextSpan(
                                                text: ' @$username',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.normal,
                                                  fontSize: 13.5,
                                                  color: colorScheme.onSurfaceVariant,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (isCertified) ...[
                                      const SizedBox(width: 4),
                                      UserCertifiedBadge(
                                        size: 15,
                                        userId: certificationUserId,
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                if (isCommunity)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'post_composer_community_label'.trParams({'name': widget.communityName}),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  )
                                else
                                  Text(
                                    'post_composer_feed_label'.tr,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Champ de texte
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: CompositedTransformTarget(
                        link: _mentionLayerLink,
                        child: TextField(
                        controller: _textController,
                        autofocus: true,
                        maxLines: null,
                        maxLength: 5000,
                        style: AppTextStyles.bodyXL.copyWith(fontSize: 18, height: 1.4, color: colorScheme.onSurface),
                        decoration: InputDecoration(
                          hintText: _pollData != null ? 'post_composer_poll_question'.tr : 'post_composer_whats_new'.tr,
                          hintStyle: AppTextStyles.bodyXL.copyWith(fontSize: 18, color: colorScheme.outline.withValues(alpha: 0.5)),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                          filled: false,
                          counterText: '',
                        ),
                        onChanged: _onPostTextChanged,
                        ),
                      ),
                    ),
                    _buildLiveSuggestions(colorScheme),

                    if (widget.sharedPost != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: IgnorePointer(
                            child: FeedPostCard(
                              post: widget.sharedPost!,
                              onReactionTap: (_) {},
                              onCommentTap: () {},
                            ),
                          ),
                        ),
                      ),

                    if (_selectedHashtags.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: _selectedHashtags.map((h) => Chip(
                            label: Text('#${h.name}'),
                            onDeleted: () => setState(() => _selectedHashtags.removeWhere((item) => item.name.toLowerCase() == h.name.toLowerCase())),
                            backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                            labelStyle: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold),
                          )).toList(),
                        ),
                      ),

                    if (_selectedMentions.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: _selectedMentions.map((m) {
                            final username = m['username'] ?? m['user_profiles']?['username'] ?? 'membre';
                            return Chip(
                              label: Text('@$username'),
                              onDeleted: () => setState(() {
                                final uId = (m['user_id'] ?? m['id'] ?? '').toString();
                                _selectedMentions.removeWhere((item) => (item['user_id'] ?? item['id']).toString() == uId);
                                _selectedMentionIds.remove(uId);
                              }),
                              backgroundColor: colorScheme.surfaceContainerHighest,
                              labelStyle: TextStyle(color: colorScheme.onSurface, fontSize: 12, fontWeight: FontWeight.bold),
                            );
                          }).toList(),
                        ),
                      ),

                    // Interactive poll / quiz preview
                    if (_pollData != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: .55)),
                            boxShadow: [BoxShadow(color: colorScheme.shadow.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? .08 : .04), blurRadius: 22, offset: const Offset(0, 7))],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: colorScheme.primary.withValues(alpha: 0.13),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Icon(
                                      _pollData!['kind'] == 'quiz' ? Icons.lightbulb_rounded : Icons.poll_rounded,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          switch (_pollData!['kind']) {
                                            'quiz' => 'Quiz',
                                            'multiple' => 'Sondage à choix multiples',
                                            'this_or_that' => 'Tu préfères…',
                                            _ => 'Sondage classique',
                                          },
                                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: colorScheme.onSurface),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          '${(_pollData!['options'] as List).length} options · prêt à publier',
                                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'post_composer_delete_poll'.tr,
                                    onPressed: () => setState(() => _pollData = null),
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              ...((_pollData!['options'] as List).asMap().entries.map((entry) {
                                final rawOption = entry.value;
                                final option = rawOption is Map
                                    ? (rawOption['label'] ?? '').toString()
                                    : rawOption.toString();
                                final isCorrect = _pollData!['kind'] == 'quiz' &&
                                    rawOption is Map && rawOption['is_correct'] == true;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 9),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: colorScheme.surface.withValues(alpha: 0.9),
                                      borderRadius: BorderRadius.circular(15),
                                      border: Border.all(
                                        color: isCorrect ? Colors.green.withValues(alpha: 0.7) : colorScheme.outlineVariant.withValues(alpha: 0.55),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isCorrect ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                          size: 18,
                                          color: isCorrect ? Colors.green : colorScheme.outline,
                                        ),
                                        const SizedBox(width: 9),
                                        Expanded(child: Text(option, style: TextStyle(fontSize: 13, color: colorScheme.onSurface))),
                                        if (isCorrect)
                                          Text('post_composer_correct_answer'.tr, style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.w700)),
                                      ],
                                    ),
                                  ),
                                );
                              })),
                            ],
                          ),
                        ),
                      ),

                    // Media Preview Grid (backend limit)
                    if (_selectedMediaCount > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: _selectedMediaCount == 1 ? 1 : 2,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: _selectedMediaCount == 1 ? 1.6 : 1.2,
                          ),
                          itemCount: _selectedMediaCount,
                          itemBuilder: (context, index) {
                            final media = _selectedMedia[index];
                            final isVideo = media.isVideo;
                            final file = media.file;
                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: isVideo
                                      ? _SelectedVideoPreview(file: file)
                                      : Image.file(file, width: double.infinity, height: double.infinity, fit: BoxFit.cover),
                                ),
                                Positioned(
                                  top: 6,
                                  right: 6,
                                  child: GestureDetector(
                                    onTap: () => setState(() => _selectedMedia.removeAt(index)),
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: Colors.black54,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.close_rounded, color: Colors.white, size: 16),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      )
                    else if (_prefilledUrl != null && _prefilledUrl!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: _prefilledUrl!.startsWith('http')
                                  ? AppCachedImage(imageUrl: _prefilledUrl!, width: double.infinity, height: 280, fit: BoxFit.cover)
                                  : Image.file(File(_prefilledUrl!), width: double.infinity, height: 280, fit: BoxFit.cover),
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: IconButton.filled(
                                onPressed: () => setState(() => _prefilledUrl = null),
                                icon: const Icon(Icons.close),
                                style: IconButton.styleFrom(backgroundColor: Colors.black54),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Bottom action bar
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    onPressed: _openGallery,
                    icon: Icon(Icons.camera_alt_rounded, color: colorScheme.onSurface, size: 24),
                    tooltip: 'post_composer_media_tooltip'.trParams({'max': '$maxPostMedia'}),
                  ),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    onPressed: _openPollCreator,
                    icon: Icon(Icons.poll_rounded, color: _pollData != null ? colorScheme.primary : colorScheme.onSurface, size: 24),
                    tooltip: 'post_composer_poll_tooltip'.tr,
                  ),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    onPressed: () {
                      final value = _textController.value;
                      final text = value.text;
                      final cursor = value.selection.isValid
                          ? value.selection.baseOffset.clamp(0, text.length)
                          : text.length;
                      final before = cursor > 0 ? text[cursor - 1] : '';
                      final insertion = before.isEmpty || RegExp(r'\\s').hasMatch(before) ? '@' : ' @';
                      final nextText = text.replaceRange(cursor, cursor, insertion);
                      _textController.value = TextEditingValue(
                        text: nextText,
                        selection: TextSelection.collapsed(offset: cursor + insertion.length),
                      );
                      _onPostTextChanged(nextText);
                    },
                    icon: Icon(Icons.alternate_email_rounded, color: colorScheme.onSurface, size: 24),
                    tooltip: 'Mentionner une personne (@)',
                  ),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    onPressed: () async {
                      final result = await Get.to<List<CommunityHashtag>>(() => CommunityPostHashtagSelectionScreen(
                        initialSelected: _selectedHashtags,
                      ));
                      if (result != null) {
                        setState(() {
                          _selectedHashtags.clear();
                          _selectedHashtags.addAll(result);
                        });
                      }
                    },
                    icon: Icon(Icons.tag_rounded, color: _selectedHashtags.isNotEmpty ? colorScheme.primary : colorScheme.onSurface, size: 24),
                    tooltip: 'post_composer_hashtags_tooltip'.tr,
                  ),

                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// Aperçu vidéo réel dans le compositeur : l'utilisateur peut vérifier le média
/// et lire/mettre en pause sans quitter l'écran de préparation de publication.
class _SelectedVideoPreview extends StatefulWidget {
  final File file;
  const _SelectedVideoPreview({required this.file});

  @override
  State<_SelectedVideoPreview> createState() => _SelectedVideoPreviewState();
}

class _SelectedVideoPreviewState extends State<_SelectedVideoPreview> {
  late final VideoPlayerController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file);
    _controller.initialize().then((_) {
      if (mounted) setState(() => _ready = true);
    }).catchError((Object error) {
      debugPrint('[POST_COMPOSER] video preview initialization failed: $error');
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        if (_ready)
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _controller.value.size.width,
              height: _controller.value.size.height,
              child: VideoPlayer(_controller),
            ),
          )
        else
          const Center(child: CircularProgressIndicator(color: Colors.white)),
        Positioned.fill(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                if (!_ready) return;
                setState(() {
                  _controller.value.isPlaying ? _controller.pause() : _controller.play();
                });
              },
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.48),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white70),
                  ),
                  child: Icon(
                    _ready && _controller.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 8,
          bottom: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.videocam_rounded, color: Colors.white, size: 14),
                SizedBox(width: 4),
                Text('Vidéo', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
