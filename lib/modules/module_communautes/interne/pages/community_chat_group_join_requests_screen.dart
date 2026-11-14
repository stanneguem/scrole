import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:scrole/shared/widgets/app_cached_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CommunityChatGroupJoinRequestsScreen extends StatefulWidget {
  const CommunityChatGroupJoinRequestsScreen({super.key, required this.salonId, required this.groupName});
  final String salonId;
  final String groupName;

  @override
  State<CommunityChatGroupJoinRequestsScreen> createState() => _CommunityChatGroupJoinRequestsScreenState();
}

class _CommunityChatGroupJoinRequestsScreenState extends State<CommunityChatGroupJoinRequestsScreen> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _requests = [];
  bool _loading = true;
  final Set<String> _processing = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await _db.rpc('get_community_chat_group_requests', params: {'p_salon_id': widget.salonId});
      final requests = (raw as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (!mounted) return;
      setState(() {
        _requests = requests;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('community_join_requests_load_error'.trParams({'error': e.toString()}));
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  String _date(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return '';
    final now = DateTime.now();
    final today = DateUtils.isSameDay(date, now);
    final yesterday = DateUtils.isSameDay(date, now.subtract(const Duration(days: 1)));
    final time = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    if (today) return '${'community_join_requests_today'.tr} · $time';
    if (yesterday) return '${'community_join_requests_yesterday'.tr} · $time';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} · $time';
  }

  Future<void> _review(Map<String, dynamic> request, String decision) async {
    final id = request['request_id']?.toString() ?? '';
    if (id.isEmpty || _processing.contains(id)) return;
    final accepted = decision == 'accepted';
    final name = (request['username'] ?? 'community_join_requests_user'.tr).toString();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(accepted ? 'community_join_requests_accept_title'.tr : 'community_join_requests_reject_title'.tr),
        content: Text((accepted ? 'community_join_requests_accept_body' : 'community_join_requests_reject_body').trParams({'name': name})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text('community_join_requests_cancel'.tr)),
          FilledButton(
            style: accepted ? null : FilledButton.styleFrom(backgroundColor: Theme.of(dialogContext).colorScheme.error),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(accepted ? 'community_join_requests_accept'.tr : 'community_join_requests_reject'.tr),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _processing.add(id));
    try {
      await _db.rpc('review_community_chat_group_request', params: {
        'p_request_id': id,
        'p_decision': decision,
      });
      if (!mounted) return;
      setState(() => _requests.removeWhere((item) => item['request_id']?.toString() == id));
      _toast((accepted ? 'community_join_requests_accepted_toast' : 'community_join_requests_rejected_toast').trParams({'name': name}));
    } catch (e) {
      _toast('community_join_requests_action_error'.trParams({'error': e.toString()}));
    } finally {
      if (mounted) setState(() => _processing.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('community_join_requests_title'.tr),
          Text(widget.groupName, style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _requests.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(32, 100, 32, 32),
                      children: [
                        Icon(Icons.mark_email_read_outlined, size: 64, color: colors.onSurfaceVariant.withOpacity(.55)),
                        const SizedBox(height: 18),
                        Text('community_join_requests_empty_title'.tr,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text('community_join_requests_empty_description'.tr,
                            textAlign: TextAlign.center, style: TextStyle(color: colors.onSurfaceVariant)),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                      itemCount: _requests.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final request = _requests[index];
                        final id = request['request_id']?.toString() ?? '';
                        final username = (request['username'] ?? 'community_join_requests_user'.tr).toString();
                        final photo = request['photo_url']?.toString();
                        final busy = _processing.contains(id);
                        return Container(
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHighest.withOpacity(.38),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: colors.outlineVariant.withOpacity(.45)),
                          ),
                          child: Column(children: [
                            Row(children: [
                              ClipOval(
                                child: SizedBox(
                                  width: 52,
                                  height: 52,
                                  child: photo != null && photo.isNotEmpty
                                      ? AppCachedImage(imageUrl: photo, fit: BoxFit.cover)
                                      : ColoredBox(
                                          color: colors.primaryContainer,
                                          child: Icon(Icons.person_outline, color: colors.onPrimaryContainer),
                                        ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(username, maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                const SizedBox(height: 4),
                                Text(_date(request['requested_at']),
                                    style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
                              ])),
                              if (busy) const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                            ]),
                            const SizedBox(height: 13),
                            Row(children: [
                              Expanded(child: OutlinedButton.icon(
                                onPressed: busy ? null : () => _review(request, 'rejected'),
                                icon: const Icon(Icons.close_rounded, size: 18),
                                label: Text('community_join_requests_reject'.tr),
                                style: OutlinedButton.styleFrom(foregroundColor: colors.error),
                              )),
                              const SizedBox(width: 10),
                              Expanded(child: FilledButton.icon(
                                onPressed: busy ? null : () => _review(request, 'accepted'),
                                icon: const Icon(Icons.check_rounded, size: 18),
                                label: Text('community_join_requests_accept'.tr),
                              )),
                            ]),
                          ]),
                        );
                      },
                    ),
            ),
    );
  }
}
