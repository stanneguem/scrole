import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:scrole/app/theme/app_colors.dart';
import '../../centre/models/community_post.dart';
import '../../externe/repositories/home_feed_repository.dart';
import '../../../module_authentification/centre/services/auth_service.dart';
import '../../../../shared/widgets/user_certified_badge.dart';
import '../../../../shared/widgets/user_identity_row.dart';
import '../../../../shared/widgets/comment_share_poster.dart';
import '../../../../shared/widgets/linkified_text.dart';
import '../pages/create_story_screen.dart';

class _MentionHighlightingController extends TextEditingController {
  static final RegExp _mentionPattern = RegExp(r'@[A-Za-z0-9_.]+|[*~]\{[^}]+\}');

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final baseStyle = style ?? const TextStyle();
    final text = value.text;
    final spans = <InlineSpan>[];
    var lastEnd = 0;
    for (final match in _mentionPattern.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: baseStyle,
        ));
      }
      spans.add(TextSpan(
        text: match.group(0),
        style: baseStyle.copyWith(color: Colors.blue, fontWeight: FontWeight.w600),
      ));
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: baseStyle,
      ));
    }
    if (spans.isEmpty) {
      spans.add(TextSpan(text: text, style: baseStyle.copyWith(color: Colors.black)));
    }
    return TextSpan(style: baseStyle, children: spans);
  }
}

class CommunityCommentsSheet extends StatefulWidget {
  final CommunityPost post;
  final dynamic controller;
  final String? targetCommentId;

  const CommunityCommentsSheet({
    super.key,
    required this.post,
    required this.controller,
    this.targetCommentId,
  });

  @override
  State<CommunityCommentsSheet> createState() => _CommunityCommentsSheetState();
}

class _CommunityCommentsSheetState extends State<CommunityCommentsSheet> {
  final HomeFeedRepository _repo = HomeFeedRepository();
  final _MentionHighlightingController _commentController = _MentionHighlightingController();
  final FocusNode _commentFocusNode = FocusNode();

  bool _isLoading = true;
  List<Map<String, dynamic>> _comments = [];
  String? _nextCursor;
  bool _hasMore = false;

  final ScrollController _commentsScrollController = ScrollController();
  final Map<String, GlobalKey> _commentKeys = <String, GlobalKey>{};
  bool _targetCommentNavigationStarted = false;
  final Map<String, List<Map<String, dynamic>>> _repliesMap = {};
  final Map<String, bool> _expandedReplies = {};
  final Map<String, bool> _loadingReplies = {};
  final Map<String, String?> _repliesNextCursor = {};
  final Map<String, bool> _repliesHasMore = {};

  Map<String, dynamic>? _replyingTo;
  final List<Map<String, dynamic>> _selectedMentions = [];
  final Set<String> _selectedCommunityIds = {};
  final Set<String> _selectedEventIds = {};
  final LayerLink _mentionLayerLink = LayerLink();
  OverlayEntry? _mentionOverlay;
  Timer? _mentionSearchDebounce;
  List<Map<String, dynamic>> _mentionSuggestions = [];
  String? _activeMentionType;
  int _mentionStart = -1;
  int _mentionRequest = 0;

  final Map<String, PostReaction> _commentReactions = {};
  final Map<String, int> _commentLikeCounts = {};
  final Map<String, int> _commentDislikeCounts = {};

  Future<void> _toggleCommentReaction(String commentId, PostReaction reaction, int baseLikes, int baseDislikes) async {
    final current = _commentReactions[commentId] ?? PostReaction.none;
    final newReaction = current == reaction ? null : (reaction == PostReaction.like ? 'like' : 'dislike');

    setState(() {
      final likes = _commentLikeCounts[commentId] ?? baseLikes;
      final dislikes = _commentDislikeCounts[commentId] ?? baseDislikes;

      if (current == reaction) {
        _commentReactions[commentId] = PostReaction.none;
        if (reaction == PostReaction.like) _commentLikeCounts[commentId] = (likes > 0) ? likes - 1 : 0;
        if (reaction == PostReaction.dislike) _commentDislikeCounts[commentId] = (dislikes > 0) ? dislikes - 1 : 0;
      } else {
        if (current == PostReaction.like) _commentLikeCounts[commentId] = (likes > 0) ? likes - 1 : 0;
        if (current == PostReaction.dislike) _commentDislikeCounts[commentId] = (dislikes > 0) ? dislikes - 1 : 0;

        _commentReactions[commentId] = reaction;
        if (reaction == PostReaction.like) _commentLikeCounts[commentId] = likes + 1;
        if (reaction == PostReaction.dislike) _commentDislikeCounts[commentId] = dislikes + 1;
      }
    });

    try {
      await _repo.setCommentReaction(commentId, newReaction);
    } catch (e) {
      debugPrint('[POST_ACTIONS] Error setting comment reaction: $e');
      setState(() {
        _commentReactions[commentId] = current;
        _commentLikeCounts[commentId] = baseLikes;
        _commentDislikeCounts[commentId] = baseDislikes;
      });
    }
  }

  void _shareComment(Map<String, dynamic> comment) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ShareCommentSheetWidget(comment: comment, post: widget.post),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadComments().then((_) {
      if (widget.targetCommentId != null && widget.targetCommentId!.isNotEmpty) {
        unawaited(_navigateToTargetComment());
      }
    });
  }

  @override
  void dispose() {
    _mentionOverlay?.remove();
    _mentionSearchDebounce?.cancel();
    _commentController.dispose();
    _commentFocusNode.dispose();
    _commentsScrollController.dispose();
    super.dispose();
  }

  Future<void> _navigateToTargetComment() async {
    if (_targetCommentNavigationStarted || widget.targetCommentId == null) return;
    _targetCommentNavigationStarted = true;
    try {
      var attempts = 0;
      while (mounted &&
          !_comments.any((comment) => comment['id']?.toString() == widget.targetCommentId) &&
          _hasMore &&
          attempts < 10) {
        final previousCount = _comments.length;
        await _loadComments(loadMore: true);
        attempts++;
        if (_comments.length == previousCount) break;
      }
      if (!mounted) return;
      var index = _comments.indexWhere((comment) => comment['id']?.toString() == widget.targetCommentId);
      if (index < 0) {
        // The target may be a reply rather than a top-level comment. Expand
        // each parent until the reply is found, then scroll to its parent.
        for (var i = 0; i < _comments.length; i++) {
          final parentId = _comments[i]['id']?.toString();
          if (parentId == null) continue;
          await _loadReplies(parentId);
          final replies = _repliesMap[parentId] ?? const <Map<String, dynamic>>[];
          if (replies.any((reply) => reply['id']?.toString() == widget.targetCommentId)) {
            index = i;
            break;
          }
        }
      }
      if (index < 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('comments_unavailable'.tr)),
          );
        }
        return;
      }
      final targetId = _comments[index]['id']?.toString();
      if (targetId == null) return;
      await WidgetsBinding.instance.endOfFrame;
      for (var attempt = 0; attempt < 4; attempt++) {
        final targetContext = _commentKeys[targetId]?.currentContext;
        if (targetContext != null) {
          await Scrollable.ensureVisible(
            targetContext,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOut,
            alignment: 0.15,
          );
          break;
        }
        if (!_commentsScrollController.hasClients) break;
        _commentsScrollController.jumpTo(
          (index * 180.0)
              .clamp(0.0, _commentsScrollController.position.maxScrollExtent)
              .toDouble(),
        );
        await WidgetsBinding.instance.endOfFrame;
      }
    } catch (e, st) {
      debugPrint('[CommunityCommentsSheet] Target comment navigation failed: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  Future<void> _loadComments({bool loadMore = false}) async {
    if (loadMore && (_isLoading || !_hasMore)) return;
    if (!loadMore) setState(() => _isLoading = true);

    try {
      final res = await _repo.getCommunityPostComments(
        widget.post.id,
        limit: 20,
        cursor: loadMore ? _nextCursor : null,
      );

      final items = res['items'] is List ? List<Map<String, dynamic>>.from(res['items']) : <Map<String, dynamic>>[];
      final nextCursor = res['next_cursor']?.toString();
      final hasMore = res['has_more'] == true;

      if (mounted) {
        setState(() {
          if (loadMore) {
            final existingIds = _comments.map((c) => c['id']?.toString()).toSet();
            for (final item in items) {
              if (!existingIds.contains(item['id']?.toString())) {
                _comments.add(item);
              }
            }
          } else {
            _comments = items;
          }
          _nextCursor = nextCursor;
          _hasMore = hasMore;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[POST_ACTIONS] Error loading comments: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadReplies(String commentId, {bool loadMore = false}) async {
    if (_loadingReplies[commentId] == true) return;
    if (loadMore && _repliesHasMore[commentId] != true) return;

    setState(() => _loadingReplies[commentId] = true);

    try {
      final cursor = loadMore ? _repliesNextCursor[commentId] : null;
      final res = await _repo.getCommunityCommentReplies(commentId, limit: 20, cursor: cursor);

      final items = res['items'] is List ? List<Map<String, dynamic>>.from(res['items']) : <Map<String, dynamic>>[];
      final nextCursor = res['next_cursor']?.toString();
      final hasMore = res['has_more'] == true;

      if (mounted) {
        setState(() {
          final existing = _repliesMap[commentId] ?? [];
          if (loadMore) {
            final existingIds = existing.map((r) => r['id']?.toString()).toSet();
            for (final item in items) {
              if (!existingIds.contains(item['id']?.toString())) {
                existing.add(item);
              }
            }
          } else {
            _repliesMap[commentId] = items;
          }
          _expandedReplies[commentId] = true;
          _repliesNextCursor[commentId] = nextCursor;
          _repliesHasMore[commentId] = hasMore;
          _loadingReplies[commentId] = false;
        });
      }
    } catch (e) {
      debugPrint('[POST_ACTIONS] Error loading replies: $e');
      if (mounted) setState(() => _loadingReplies[commentId] = false);
    }
  }

  void _removeMentionOverlay() {
    _mentionOverlay?.remove();
    _mentionOverlay = null;
    _activeMentionType = null;
    _mentionSuggestions = [];
  }

  void _onCommentChanged(String value) {
    final cursor = _commentController.selection.baseOffset;
    if (cursor < 0 || cursor > value.length) { _removeMentionOverlay(); return; }
    final prefix = value.substring(0, cursor);
    final match = RegExp(r'(^|\s)([@*~])([^\s@*~]*)$').firstMatch(prefix);
    if (match == null) { _removeMentionOverlay(); return; }
    final trigger = match.group(2)!;
    _activeMentionType = trigger == '@' ? 'user' : trigger == '*' ? 'event' : 'community';
    _mentionStart = cursor - trigger.length - (match.group(3) ?? '').length;
    final query = match.group(3) ?? '';
    _mentionSearchDebounce?.cancel();
    _mentionSearchDebounce = Timer(const Duration(milliseconds: 180), () {
      _searchMentionSuggestions(query, _activeMentionType!);
    });
  }

  Future<void> _searchMentionSuggestions(String query, String type) async {
    final request = ++_mentionRequest;
    try {
      final client = Supabase.instance.client;
      List<Map<String, dynamic>> results = [];
      if (type == 'user') {
        final uid = client.auth.currentUser?.id;
        if (uid == null) {
          results = [];
        } else {
          final allowedIds = <String>{};
          // Personal-feed comments: friends only, never followers.
          final friendshipRows = await client.from('friendships')
              .select('user_a_id,user_b_id')
              .or('user_a_id.eq.$uid,user_b_id.eq.$uid')
              .limit(500);
          for (final row in friendshipRows) {
            final other = row['user_a_id']?.toString() == uid
                ? row['user_b_id']?.toString()
                : row['user_a_id']?.toString();
            if (other != null && other.isNotEmpty && other != uid) allowedIds.add(other);
          }

          // On a private community post, only its current members can be
          // suggested. On a public community post, members are added to friends.
          final communityId = widget.post.communityId;
          if (communityId != null && communityId.isNotEmpty) {
            final community = await client.from('communities')
                .select('visibility')
                .eq('id', communityId)
                .maybeSingle();
            final visibility = (community?['visibility'] ?? 'private').toString().toLowerCase();
            if (visibility == 'private') {
              allowedIds.clear();
            }
            final members = await client.from('community_members')
                .select('user_id')
                .eq('community_id', communityId)
                .limit(1000);
            allowedIds.addAll(members.map((m) => m['user_id'].toString()));
          }
          allowedIds.remove(uid);
          if (allowedIds.isNotEmpty) {
            final rows = await client.from('user_profiles')
                .select('user_id, username, first_name, last_name, photo_url, is_verified')
                .inFilter('user_id', allowedIds.toList())
                .eq('account_status', 'active')
                .isFilter('deleted_at', null)
                .or('username.ilike.%$query%,first_name.ilike.%$query%,last_name.ilike.%$query%')
                .order('username').limit(7);
            results = rows.map((r) => Map<String, dynamic>.from(r)).toList();
          }
        }
      } else if (type == 'community') {
        final rows = await client.from('communities').select('id, name, photo_profile, visibility')
            .eq('status', 'active').ilike('name', '%$query%').order('name').limit(7);
        results = rows.map((r) => Map<String, dynamic>.from(r)).toList();
      } else {
        final rows = await client.from('events').select('id, name, photo, starts_at, status')
            .ilike('name', '%$query%').order('starts_at').limit(12);
        results = rows.map((r) => Map<String, dynamic>.from(r))
            .where((r) => !const {'deleted', 'cancelled', 'archived'}.contains((r['status'] ?? '').toString().toLowerCase()))
            .take(7).toList();
      }
      if (!mounted || request != _mentionRequest || _activeMentionType != type) return;
      setState(() => _mentionSuggestions = results);
      _showMentionOverlay();
    } catch (e) {
      debugPrint('[MENTIONS] Suggestion search failed: $e');
      if (request == _mentionRequest) _removeMentionOverlay();
    }
  }

  void _showMentionOverlay() {
    if (_mentionSuggestions.isEmpty || _activeMentionType == null) { _removeMentionOverlay(); return; }
    _mentionOverlay ??= OverlayEntry(builder: (_) {
      final type = _activeMentionType;
      final items = List<Map<String, dynamic>>.from(_mentionSuggestions);
      return Positioned(
        width: MediaQuery.of(context).size.width - 56,
        child: CompositedTransformFollower(
          link: _mentionLayerLink, showWhenUnlinked: false,
          targetAnchor: Alignment.topLeft, followerAnchor: Alignment.bottomLeft,
          offset: const Offset(0, -8),
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
                    title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    subtitle: subtitle.isEmpty ? null : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                    onTap: () => _insertMention(type!, item),
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

  void _insertMention(String type, Map<String, dynamic> item) {
    final id = (item[type == 'user' ? 'user_id' : 'id'] ?? '').toString();
    final token = type == 'user' ? '@${item['username'] ?? item['first_name'] ?? 'utilisateur'}'
        : type == 'event' ? '*{${item['name'] ?? 'événement'}}' : '~{${item['name'] ?? 'communauté'}}';
    final text = _commentController.text;
    final cursor = _commentController.selection.baseOffset.clamp(0, text.length);
    final start = _mentionStart.clamp(0, cursor);
    _commentController.value = TextEditingValue(
      text: text.replaceRange(start, cursor, '$token '),
      selection: TextSelection.collapsed(offset: start + token.length + 1),
    );
    if (id.isNotEmpty) {
      if (type == 'user') {
        _selectedMentions.removeWhere((m) => (m['user_id'] ?? '').toString() == id);
        _selectedMentions.add(item);
      } else if (type == 'event') {
        _selectedEventIds.add(id);
      } else {
        _selectedCommunityIds.add(id);
      }
    }
    _removeMentionOverlay();
    if (mounted) setState(() {});
    _commentFocusNode.requestFocus();
  }

  Future<void> _saveEntityMentions(String commentId) async {
    if (_selectedCommunityIds.isEmpty && _selectedEventIds.isEmpty) return;
    await Supabase.instance.client.rpc('save_content_entity_mentions', params: {
      'p_source_type': 'comment', 'p_source_id': commentId,
      'p_community_ids': _selectedCommunityIds.toList(), 'p_event_ids': _selectedEventIds.toList(),
    });
  }

  Future<void> _submitComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    final pId = const Uuid().v4();
    final currentUserId = Get.isRegistered<AuthService>() ? Get.find<AuthService>().userId ?? 'me' : 'me';

    final targetReplyTo = _replyingTo;
    final mentionIds = _selectedMentions
        .map((m) => (m['user_id'] ?? m['id'] ?? m['user_profiles']?['user_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final tempComment = {
      'id': pId,
      'post_id': widget.post.id,
      'author_id': currentUserId,
      'content': text,
      'created_at': DateTime.now().toIso8601String(),
      'parent_comment_id': targetReplyTo != null ? targetReplyTo['id']?.toString() : null,
      'replies_count': 0,
      'author': {
        'user_id': currentUserId,
        'username': 'Moi',
        'first_name': 'Moi',
      },
      'is_pending': true,
    };

    setState(() {
      if (targetReplyTo != null) {
        final parentId = targetReplyTo['id']?.toString();
        if (parentId != null) {
          _repliesMap[parentId] ??= [];
          _repliesMap[parentId]!.add(tempComment);
          _expandedReplies[parentId] = true;
        }
      } else {
        _comments.add(tempComment);
      }
      _commentController.clear();
      _replyingTo = null;
    });

    try {
      await _repo.commentCommunityPost(
        p_id: pId,
        postId: widget.post.id,
        content: text,
        mentions: mentionIds,
        parentCommentId: targetReplyTo != null ? targetReplyTo['id']?.toString() : null,
      );
      try { await _saveEntityMentions(pId); } catch (e) { debugPrint('[MENTIONS] Entity mention save failed: $e'); }
      if (mounted) setState(() {
        _selectedMentions.clear(); _selectedCommunityIds.clear(); _selectedEventIds.clear();
      });
      await _loadComments();
      if (targetReplyTo != null) {
        final parentId = targetReplyTo['id']?.toString();
        if (parentId != null) {
          await _loadReplies(parentId);
        }
      }
    } catch (e) {
      debugPrint('[POST_ACTIONS] Error submitting comment: $e');
      Get.snackbar('Erreur', e.toString().replaceFirst('Exception: ', '').tr, snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
      setState(() {
        if (targetReplyTo != null) {
          final parentId = targetReplyTo['id']?.toString();
          if (parentId != null) {
            _repliesMap[parentId]?.removeWhere((r) => r['id'] == pId);
          }
        } else {
          _comments.removeWhere((c) => c['id'] == pId);
        }
      });
    }
  }

  Future<void> _deleteComment(String commentId, bool isReply, String? parentId) async {
    try {
      await _repo.deleteCommunityComment(commentId);
      setState(() {
        if (isReply && parentId != null) {
          _repliesMap[parentId]?.removeWhere((r) => r['id'].toString() == commentId);
        } else {
          _comments.removeWhere((c) => c['id'].toString() == commentId);
          _repliesMap.remove(commentId);
        }
      });
      Get.snackbar('Succès', 'Commentaire supprimé', snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('Erreur', e.toString().replaceFirst('Exception: ', '').tr, snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  String _formatTime(String raw) {
    if (raw.isEmpty) return '';
    final dt = DateTime.tryParse(raw);
    if (dt != null) {
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.isNegative || diff.inSeconds < 60) return 'relative_just_now'.tr;
      if (diff.inMinutes < 60) return 'relative_minutes_short'.trParams({'count': '${diff.inMinutes}'});
      if (diff.inHours < 24) return 'relative_hours_short'.trParams({'count': '${diff.inHours}'});
      if (diff.inDays < 7) return 'relative_days_short'.trParams({'count': '${diff.inDays}'});
      return '${dt.day}/${dt.month}/${dt.year}';
    }
    return '';
  }

  Widget _buildHighlightedContent(String content, ColorScheme colorScheme) {
    return LinkifiedText(
      text: content,
      style: TextStyle(fontSize: 13.5, color: colorScheme.onSurface, height: 1.35),
      linkColor: colorScheme.primary,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (!widget.post.commentsEnabled) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('comments_disabled_title'.tr, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text('comments_disabled_message'.tr, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: () => Navigator.of(context).pop(), child: Text('common_close'.tr)),
          ],
        ),
      );
    }

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 15,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        bottom: true,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).viewInsets.bottom + 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('comments_title'.tr, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Comments List
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _comments.isEmpty
                        ? Center(
                            child: Text('comments_empty'.tr, style: TextStyle(color: colorScheme.onSurfaceVariant)),
                          )
                        : RefreshIndicator(
                            onRefresh: () => _loadComments(),
                            child: ListView.builder(
                              controller: _commentsScrollController,
                              itemCount: _comments.length + (_hasMore ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index >= _comments.length) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    child: Center(
                                      child: TextButton(
                                        onPressed: () => _loadComments(loadMore: true),
                                        child: Text('comments_load_more'.tr),
                                      ),
                                    ),
                                  );
                                }

                                final comment = _comments[index];
                                final commentId = comment['id']?.toString() ?? 'comment_$index';
                                final commentKey = _commentKeys.putIfAbsent(commentId, () => GlobalKey());
                                return KeyedSubtree(
                                  key: commentKey,
                                  child: _buildCommentItem(comment, isReply: false, parentId: null),
                                );
                              },
                            ),
                          ),
              ),

              // Replying banner
              if (_replyingTo != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'comments_replying_to'.trParams({'name': '@${(_replyingTo!['author'] is Map ? _replyingTo!['author']['username'] : 'utilisateur')}'}),
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: colorScheme.primary),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _replyingTo = null),
                        child: Icon(Icons.close_rounded, size: 16, color: colorScheme.primary),
                      ),
                    ],
                  ),
                ),
              ],

              if (_selectedMentions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: _selectedMentions.map((member) {
                      final profile = member['user_profiles'] is Map
                          ? Map<String, dynamic>.from(member['user_profiles'])
                          : member;
                      final username = (profile['username'] ?? member['username'] ?? 'membre').toString();
                      final id = (profile['user_id'] ?? profile['id'] ?? member['user_id'] ?? member['id'] ?? '').toString();
                      return InputChip(
                        label: Text('@$username'),
                        onDeleted: () => setState(() {
                          _selectedMentions.removeWhere((item) {
                            final nested = item['user_profiles'] is Map
                                ? Map<String, dynamic>.from(item['user_profiles'])
                                : item;
                            return (nested['user_id'] ?? nested['id'] ?? item['user_id'] ?? item['id'] ?? '').toString() == id;
                          });
                        }),
                      );
                    }).toList(),
                  ),
                ),

              // Modern Input field at bottom
              const SizedBox(height: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: _commentFocusNode.hasFocus
                        ? colorScheme.primary.withValues(alpha: 0.65)
                        : colorScheme.outlineVariant.withValues(alpha: 0.7),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.shadow.withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      margin: const EdgeInsets.only(right: 8, bottom: 1),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.09),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.chat_bubble_outline_rounded, size: 17, color: colorScheme.primary),
                    ),
                    Expanded(
                      child: CompositedTransformTarget(
                        link: _mentionLayerLink,
                        child: TextField(
                          controller: _commentController,
                          onChanged: _onCommentChanged,
                          focusNode: _commentFocusNode,
                          style: TextStyle(color: colorScheme.onSurface, fontSize: 14.5, height: 1.35),
                          minLines: 1,
                          maxLines: 4,
                          textCapitalization: TextCapitalization.sentences,
                          textInputAction: TextInputAction.newline,
                          decoration: InputDecoration(
                            hintText: _replyingTo != null ? 'comments_reply_hint'.tr : 'comments_input_hint'.tr,
                            hintStyle: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8), fontSize: 13.5),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 9),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _submitComment,
                      child: Container(
                        width: 38,
                        height: 38,
                        margin: const EdgeInsets.only(bottom: 1),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [colorScheme.primary, colorScheme.primary.withValues(alpha: 0.82)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCommentItem(Map<String, dynamic> comment, {required bool isReply, String? parentId}) {
    final colorScheme = Theme.of(context).colorScheme;
    final author = comment['author'] is Map ? Map<String, dynamic>.from(comment['author']) : <String, dynamic>{};
    final authorName = author['first_name'] != null ? '${author['first_name']} ${author['last_name'] ?? ''}'.trim() : (author['username']?.toString() ?? 'Utilisateur');
    final username = author['username']?.toString() ?? '';
    final avatar = author['photo_url']?.toString() ?? author['avatar_url']?.toString();
    final content = comment['content']?.toString() ?? '';
    final commentId = comment['id']?.toString() ?? '';
    final repliesCount = (comment['replies_count'] as num?)?.toInt() ?? 0;
    final isPending = comment['is_pending'] == true;
    final isCertified = author['is_certified'] == true || 
                        author['is_verified'] == true || 
                        author['is_certified'] == 1 || 
                        author['is_verified'] == 1 || 
                        author['certified'] == true || 
                        author['certified'] == 1 ||
                        author['is_certified']?.toString() == 'true' ||
                        author['is_verified']?.toString() == 'true';

    final currentUserId = Get.isRegistered<AuthService>() ? Get.find<AuthService>().userId : null;
    final isAuthor = currentUserId != null && currentUserId == comment['author_id']?.toString();
    final isPostAuthor = comment['author_id']?.toString() == widget.post.authorId;

    final baseLikes = (comment['likes_count'] as num?)?.toInt() ?? 0;
    final baseDislikes = (comment['dislikes_count'] as num?)?.toInt() ?? 0;
    final currentReaction = _commentReactions[commentId] ?? PostReaction.none;
    final currentLikes = _commentLikeCounts[commentId] ?? baseLikes;
    final currentDislikes = _commentDislikeCounts[commentId] ?? baseDislikes;

    return Padding(
      padding: EdgeInsets.only(left: isReply ? 36.0 : 0.0, top: 10, bottom: 10),
      child: Opacity(
        opacity: isPending ? 0.6 : 1.0,
        child: Container(
          padding: isReply ? const EdgeInsets.only(left: 12) : EdgeInsets.zero,
          decoration: isReply
              ? BoxDecoration(
                  border: Border(
                    left: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6), width: 2),
                  ),
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              UserIdentityRow(
                name: authorName,
                username: username,
                avatarUrl: avatar,
                isCertified: isCertified,
                userId: author['user_id']?.toString() ?? comment['author_id']?.toString(),
                avatarRadius: isReply ? 15 : 18,
                subtitle: '· ${_formatTime(comment['created_at']?.toString() ?? '')}',
                nameStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: isReply ? 13 : 14, color: colorScheme.onSurface),
                usernameStyle: TextStyle(fontSize: isReply ? 11.5 : 12.5, color: colorScheme.onSurfaceVariant),
                trailing: isPostAuthor
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'comments_author_badge'.tr,
                          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: colorScheme.primary),
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: 4),
              Padding(
                padding: EdgeInsets.only(left: (isReply ? 15 : 18) * 2 + 12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHighlightedContent(content, colorScheme),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: () {
                            if (isReply && parentId != null) {
                              final parent = _comments.firstWhereOrNull((c) => c['id'].toString() == parentId);
                              setState(() {
                                _replyingTo = parent ?? comment;
                                _commentController.text = '@$username ';
                                _commentController.selection = TextSelection.fromPosition(TextPosition(offset: _commentController.text.length));
                              });
                            } else {
                              setState(() {
                                _replyingTo = comment;
                                if (isReply && username.isNotEmpty) {
                                  _commentController.text = '@$username ';
                                  _commentController.selection = TextSelection.fromPosition(TextPosition(offset: _commentController.text.length));
                                }
                              });
                            }
                          },
                          child: Text(
                            'comments_reply_action'.tr,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant),
                          ),
                        ),
                        if (repliesCount > 0 && !isReply)
                          GestureDetector(
                            onTap: () {
                              if (_expandedReplies[commentId] == true) {
                                setState(() => _expandedReplies[commentId] = false);
                              } else {
                                _loadReplies(commentId);
                              }
                            },
                            child: Text(
                              _expandedReplies[commentId] == true ? 'comments_hide_replies'.tr : 'comments_replies_count'.trParams({'count': '$repliesCount'}),
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.primary),
                            ),
                          ),
                        if (isAuthor)
                          GestureDetector(
                            onTap: () => _deleteComment(commentId, isReply, parentId),
                            child: Text(
                              'comments_delete_action'.tr,
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.redAccent),
                            ),
                          ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              onTap: () => _shareComment(comment),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                child: Icon(Icons.ios_share_rounded, size: 15, color: colorScheme.onSurfaceVariant),
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: () => _toggleCommentReaction(commentId, PostReaction.like, baseLikes, baseDislikes),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.north_rounded,
                                      size: 16,
                                      color: currentReaction == PostReaction.like ? AppColors.primary : colorScheme.onSurfaceVariant,
                                    ),
                                    if (currentLikes > 0) ...[
                                      const SizedBox(width: 2),
                                      Text('$currentLikes', style: TextStyle(fontSize: 11.5, color: currentReaction == PostReaction.like ? AppColors.primary : colorScheme.onSurfaceVariant, fontWeight: currentReaction == PostReaction.like ? FontWeight.bold : FontWeight.normal)),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            InkWell(
                              onTap: () => _toggleCommentReaction(commentId, PostReaction.dislike, baseLikes, baseDislikes),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.south_rounded,
                                      size: 16,
                                      color: currentReaction == PostReaction.dislike ? Colors.orangeAccent : colorScheme.onSurfaceVariant,
                                    ),
                                    if (currentDislikes > 0) ...[
                                      const SizedBox(width: 2),
                                      Text('$currentDislikes', style: TextStyle(fontSize: 11.5, color: currentReaction == PostReaction.dislike ? Colors.orangeAccent : colorScheme.onSurfaceVariant, fontWeight: currentReaction == PostReaction.dislike ? FontWeight.bold : FontWeight.normal)),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    // Replies nested section
                    if (!isReply && repliesCount > 0 && _expandedReplies[commentId] == true)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          if (_loadingReplies[commentId] == true)
                            const Padding(
                              padding: EdgeInsets.only(top: 8, left: 16),
                              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                            ),
                          if (_repliesMap[commentId] != null)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final reply in _repliesMap[commentId]!)
                                  _buildCommentItem(reply, isReply: true, parentId: commentId),
                                if (_repliesHasMore[commentId] == true)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 16, top: 4),
                                    child: TextButton(
                                      onPressed: () => _loadReplies(commentId, loadMore: true),
                                      child: Text('comments_load_more_replies'.tr, style: const TextStyle(fontSize: 12)),
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShareCommentSheetWidget extends StatelessWidget {
  final Map<String, dynamic> comment;
  final CommunityPost post;

  const _ShareCommentSheetWidget({
    required this.comment,
    required this.post,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final author = comment['author'] is Map ? Map<String, dynamic>.from(comment['author']) : <String, dynamic>{};
    final authorName = author['first_name'] != null ? '${author['first_name']} ${author['last_name'] ?? ''}'.trim() : (author['username']?.toString() ?? 'Utilisateur');
    final username = author['username']?.toString() ?? '';
    final content = comment['content']?.toString() ?? '';
    final commentId = comment['id']?.toString() ?? '';

    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 24),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Partager le commentaire', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          const SizedBox(height: 16),

          // Compact Comment Preview
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(authorName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                    if (username.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Text('@$username', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(content, style: TextStyle(fontSize: 12.5, color: colorScheme.onSurface), maxLines: 3, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text('Destinations', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey), textAlign: TextAlign.left),
          const SizedBox(height: 14),

          // Horizontal Share Options Row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // 1. Ma story
                _ShareCommentOptionItem(
                  svgAsset: 'assets/svg_icons/story-svgrepo-com.svg',
                  color: Colors.pink,
                  label: 'Ma story',
                  onTap: () async {
                    Navigator.of(context).pop();
                    try {
                      final image = await CommentSharePosterService.generateImage(
                        authorName: authorName,
                        username: username,
                        content: content,
                        context: context,
                      );
                      Get.to(() => CreateStoryScreen(
                            prefilledText: 'Commentaire de @${username.isEmpty ? authorName : username}',
                            prefilledMediaUrl: image.path,
                          ));
                    } catch (e) {
                      Get.snackbar('Erreur', 'Impossible de préparer la carte du commentaire.');
                    }
                  },
                ),
                const SizedBox(width: 16),

                // 2. Republier sur mon fil
                _ShareCommentOptionItem(
                  svgAsset: 'assets/svg_icons/repost-round-svgrepo-com.svg',
                  color: colorScheme.primary,
                  label: 'Republier',
                  onTap: () async {
                    Navigator.of(context).pop();
                    final pId = const Uuid().v4();
                    try {
                      final repo = HomeFeedRepository();
                      await repo.shareComment(
                        p_id: pId,
                        p_comment_id: commentId,
                      );
                      Get.snackbar('Succès', 'Commentaire partagé sur votre fil avec succès !', snackPosition: SnackPosition.BOTTOM);
                    } catch (e) {
                      Get.snackbar('Erreur', e.toString().replaceFirst('Exception: ', '').tr, snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
                    }
                  },
                ),
                const SizedBox(width: 16),

                // 3. Communauté
                _ShareCommentOptionItem(
                  svgAsset: 'assets/svg_icons/ecosystem-svgrepo-com.svg',
                  color: Colors.purple,
                  label: 'Communauté',
                  onTap: () {
                    Navigator.of(context).pop();
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => _CommunityShareCommentSheet(commentId: commentId),
                    );
                  },
                ),
                const SizedBox(width: 16),

                // 4. Autres applications
                _ShareCommentOptionItem(
                  icon: Icons.ios_share_rounded,
                  color: Colors.green,
                  label: 'Autres apps',
                  onTap: () async {
                    Navigator.of(context).pop();
                    try {
                      await CommentSharePosterService.shareImage(
                        authorName: authorName,
                        username: username,
                        content: content,
                        context: context,
                      );
                    } catch (e) {
                      Get.snackbar('Erreur', 'Impossible de partager l’image du commentaire.');
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class _ShareCommentOptionItem extends StatelessWidget {
  final IconData? icon;
  final String? svgAsset;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _ShareCommentOptionItem({
    this.icon,
    this.svgAsset,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 76,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
              ),
              alignment: Alignment.center,
              child: svgAsset != null
                  ? SvgPicture.asset(
                      svgAsset!,
                      width: 26,
                      height: 26,
                      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                    )
                  : Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _CommunityShareCommentSheet extends StatefulWidget {
  final String commentId;
  const _CommunityShareCommentSheet({required this.commentId});

  @override
  State<_CommunityShareCommentSheet> createState() => _CommunityShareCommentSheetState();
}

class _CommunityShareCommentSheetState extends State<_CommunityShareCommentSheet> {
  bool _isLoading = true;
  List<dynamic> _communities = [];

  @override
  void initState() {
    super.initState();
    _loadCommunities();
  }

  Future<void> _loadCommunities() async {
    try {
      final repo = HomeFeedRepository();
      final comms = await repo.client.rpc('get_my_communities');
      if (mounted) {
        setState(() {
          _communities = comms is List ? comms : [];
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Partager dans une communauté', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_communities.isEmpty)
            const Center(child: Text('Vous n\'avez rejoint aucune communauté'))
          else
            Expanded(
              child: ListView.builder(
                itemCount: _communities.length,
                itemBuilder: (context, index) {
                  final comm = _communities[index];
                  final commId = comm['id']?.toString() ?? '';
                  final commName = comm['name']?.toString() ?? 'Communauté';

                  return ListTile(
                    title: Text(commName, style: const TextStyle(fontWeight: FontWeight.bold)),
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                    onTap: () async {
                      Navigator.of(context).pop();
                      final pId = const Uuid().v4();
                      try {
                        final repo = HomeFeedRepository();
                        await repo.shareComment(
                          p_id: pId,
                          p_comment_id: widget.commentId,
                          p_community_id: commId,
                        );
                        Get.snackbar('Succès', 'Commentaire partagé dans la communauté $commName !', snackPosition: SnackPosition.BOTTOM);
                      } catch (e) {
                        Get.snackbar('Erreur', e.toString().replaceFirst('Exception: ', '').tr, snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
                      }
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
