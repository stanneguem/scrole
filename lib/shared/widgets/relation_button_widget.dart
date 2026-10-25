import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/text_styles.dart';
import '../../modules/module_discussion_direct/externe/repositories/social_repository.dart';
import '../../modules/module_discussion_direct/centre/services/follow_error_mapper.dart';

class RelationButtonWidget extends StatefulWidget {
  final String targetUserId;
  final String? requestId;
  final String? senderId;
  final DateTime? nextRetryAt;
  final VoidCallback? onRelationChanged;
  final bool compact;

  const RelationButtonWidget({
    super.key,
    required this.targetUserId,
    this.requestId,
    this.senderId,
    this.nextRetryAt,
    this.onRelationChanged,
    this.compact = false,
  });

  @override
  State<RelationButtonWidget> createState() => _RelationButtonWidgetState();
}

class _RelationButtonWidgetState extends State<RelationButtonWidget> {
  final SocialRepository _socialRepo = SocialRepository();
  Map<String, dynamic> _relationship = const {};
  bool _isLoading = true;
  bool _isSaving = false;
  RealtimeChannel? _relationshipChannel;

  String get _state => (_relationship['state'] ?? 'none').toString();
  String? get _requestId => (_relationship['request_id'] ?? widget.requestId)?.toString();
  DateTime? get _retryAt {
    final value = _relationship['retry_at'];
    return value == null ? widget.nextRetryAt : DateTime.tryParse(value.toString());
  }

  @override
  void initState() {
    super.initState();
    _loadState();
    _subscribeToRelationshipChanges();
  }

  @override
  void didUpdateWidget(covariant RelationButtonWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetUserId != widget.targetUserId) _loadState();
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
              if (payload['user_id']?.toString() == widget.targetUserId) {
                debugPrint('[FOLLOW] relationship_changed button user=${widget.targetUserId}');
                _loadState();
              }
            },
          )
          ..subscribe();
    } catch (e, stack) {
      debugPrint('[FOLLOW] button realtime subscription exception=$e\\n$stack');
    }
  }

  @override
  void dispose() {
    final channel = _relationshipChannel;
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
    }
    super.dispose();
  }

  Future<void> _loadState() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final relation = await _socialRepo.getRelationship(widget.targetUserId, forceRefresh: true);
      if (mounted) setState(() { _relationship = relation; _isLoading = false; });
    } catch (e, stack) {
      debugPrint('[FOLLOW] get_relationship button user=${widget.targetUserId} exception=$e\\n$stack');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _run(Future<dynamic> Function() action, {String? optimisticState}) async {
    if (_isSaving) return;
    if (mounted) setState(() {
      _isSaving = true;
      if (optimisticState != null) _relationship = {..._relationship, 'state': optimisticState};
    });
    try {
      final result = await action();
      if (result is Map) {
        final nested = result['relationship'];
        _relationship = Map<String, dynamic>.from(nested is Map ? nested : result);
      }
      await _loadState();
      widget.onRelationChanged?.call();
    } catch (e, stack) {
      debugPrint('[FOLLOW] relation button action user=${widget.targetUserId} exception=$e\\n$stack');
      await _loadState();
      final retryAt = _retryAt;
      if (mounted && retryAt != null && retryAt.isAfter(DateTime.now())) {
        Get.snackbar('error_title'.tr, 'follow_retry_at'.trParams({
          'date': DateFormat('dd/MM/yyyy HH:mm').format(retryAt.toLocal()),
        }));
      } else if (mounted) {
        Get.snackbar('error_title'.tr, FollowErrorMapper.keyFor(e).tr);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _showMenu() async {
    final action = await Get.bottomSheet<String>(
      _RelationshipButtonMenu(isFriend: _state == 'friends'),
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
    );
    if (action == 'unfollow') {
      await _run(() => _socialRepo.unfollowUser(widget.targetUserId), optimisticState: _relationship['follows_me'] == true ? 'follow_back' : 'none');
    } else if (action == 'remove_friend') {
      await _run(() => _socialRepo.removeFriend(widget.targetUserId), optimisticState: 'none');
    }
  }

  Future<void> _respond(bool accepted) async {
    final id = _requestId;
    if (id == null || id.isEmpty) return;
    await _run(() => _socialRepo.respondFollowRequest(id, accepted, targetUserId: widget.targetUserId), optimisticState: accepted ? 'follow_back' : 'none');
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return SizedBox(width: widget.compact ? 20 : 24, height: widget.compact ? 20 : 24, child: const CircularProgressIndicator(strokeWidth: 2));
    }
    if (_state == 'self' || _state == 'blocked') return const SizedBox.shrink();

    final retryAt = _retryAt;
    if (retryAt != null && retryAt.isAfter(DateTime.now())) {
      final date = DateFormat('dd/MM/yyyy HH:mm').format(retryAt.toLocal());
      return Tooltip(
        message: 'follow_retry_at'.trParams({'date': date}),
        child: OutlinedButton(
          onPressed: null,
          child: Text('follow_state_requested'.tr, style: AppTextStyles.bodySmall),
        ),
      );
    }

    if (_state == 'request_received') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'refuse'.tr,
            onPressed: _isSaving ? null : () => _respond(false),
            icon: const Icon(Icons.close_rounded, color: AppColors.error),
          ),
          IconButton(
            tooltip: 'accept'.tr,
            onPressed: _isSaving ? null : () => _respond(true),
            icon: const Icon(Icons.check_rounded, color: AppColors.success),
          ),
        ],
      );
    }

    if (_state == 'following' || _state == 'friends') {
      return TextButton(
        onPressed: _isSaving ? null : _showMenu,
        child: Text(
          _state == 'friends' ? 'follow_state_friends'.tr : 'follow_state_following'.tr,
          style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w700),
        ),
      );
    }

    final requested = _state == 'requested';
    final followBack = _state == 'follow_back';
    return ElevatedButton.icon(
      onPressed: _isSaving ? null : requested
          ? () => _run(() => _socialRepo.cancelFollowRequest(widget.targetUserId), optimisticState: 'none')
          : () => _run(() => _socialRepo.followUser(widget.targetUserId), optimisticState: _relationship['follows_me'] == true ? 'friends' : 'following'),
      icon: Icon(requested ? Icons.hourglass_top_rounded : Icons.person_add_alt_1_rounded, size: widget.compact ? 14 : 16),
      label: Text(
        requested
            ? 'follow_state_requested'.tr
            : followBack
                ? 'follow_state_follow_back'.tr
                : 'follow_state_follow'.tr,
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: requested ? Theme.of(context).colorScheme.surfaceContainerHigh : AppColors.primary,
        foregroundColor: requested ? Theme.of(context).colorScheme.onSurface : Colors.white,
        elevation: widget.compact ? 0 : 1,
        minimumSize: widget.compact ? const Size(0, 34) : null,
        tapTargetSize: widget.compact ? MaterialTapTargetSize.shrinkWrap : MaterialTapTargetSize.padded,
        visualDensity: widget.compact ? VisualDensity.compact : VisualDensity.standard,
        padding: widget.compact
            ? const EdgeInsets.symmetric(horizontal: 9, vertical: 4)
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(widget.compact ? 12 : 20)),
        textStyle: AppTextStyles.bodySmall.copyWith(fontSize: widget.compact ? 11 : null, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _RelationshipButtonMenu extends StatelessWidget {
  const _RelationshipButtonMenu({required this.isFriend});
  final bool isFriend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget item(String value, String label, IconData icon) => ListTile(
      leading: Icon(icon, color: scheme.error),
      title: Text(label),
      onTap: () => Navigator.of(context).pop(value),
    );
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(18)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            item('unfollow', 'follow_unfollow_action'.tr, Icons.person_remove_alt_1_rounded),
            if (isFriend) item('remove_friend', 'follow_remove_friend_action'.tr, Icons.person_off_outlined),
            ListTile(leading: const Icon(Icons.close_rounded), title: Text('cancel'.tr), onTap: () => Navigator.of(context).pop()),
          ],
        ),
      ),
    );
  }
}
