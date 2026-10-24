import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:scrole/modules/module_communautes/centre/models/excluded_user.dart';
import 'package:scrole/modules/module_communautes/centre/services/community_service.dart';
import 'package:scrole/shared/widgets/app_cached_image.dart';
import 'package:scrole/shared/widgets/user_certified_badge.dart';

class ExcludedMembersScreen extends StatefulWidget {
  final String communityId;
  const ExcludedMembersScreen({super.key, required this.communityId});

  @override
  State<ExcludedMembersScreen> createState() => _ExcludedMembersScreenState();
}

class _ExcludedMembersScreenState extends State<ExcludedMembersScreen> {
  final CommunityService _service = Get.find<CommunityService>();
  bool _isLoading = true;
  String? _loadError;
  List<ExcludedUser> _excluded = [];

  @override
  void initState() {
    super.initState();
    _loadExclusions();
  }

  Future<void> _loadExclusions() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final res = await _service.getCommunityExclusions(widget.communityId);
      final rawItems = res['items'];
      if (rawItems is! List) {
        throw const FormatException('Réponse invalide pour la liste des exclusions.');
      }
      final parsed = rawItems
          .map((item) => ExcludedUser.fromJson(item is Map ? Map<String, dynamic>.from(item) : <String, dynamic>{}))
          .where((user) => user.userId.isNotEmpty)
          .toList();
      if (mounted) {
        setState(() {
          _excluded = parsed;
          _isLoading = false;
          _loadError = null;
        });
      }
    } catch (e) {
      debugPrint('[ExcludedMembersScreen] Failed to load exclusions: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = 'excluded_members_load_error'.tr;
        });
      }
    }
  }

  Future<void> _unexclude(String userId, String name) async {
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: Text('excluded_members_readmit_title'.tr),
        content: Text('excluded_members_readmit_confirm'.tr),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: Text('cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: Text('excluded_members_readmit'.tr),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _service.unexcludeCommunityMember(widget.communityId, userId);
      Get.snackbar(
        'excluded_members_readmit_title'.tr,
        'excluded_members_readmit_msg'.trParams({'name': name}),
        snackPosition: SnackPosition.BOTTOM,
      );
      await _loadExclusions();
    } catch (e) {
      debugPrint('[ExcludedMembersScreen] Removing exclusion failed: $e');
      Get.snackbar(
        'community_save_error'.tr,
        _service.localizedCommunityError(e),
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        title: Text('excluded_members_title'.tr, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, size: 42, color: colorScheme.error),
                        const SizedBox(height: 12),
                        Text(_loadError!, textAlign: TextAlign.center, style: TextStyle(color: colorScheme.onSurfaceVariant)),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: _loadExclusions,
                          child: Text('excluded_members_retry'.tr),
                        ),
                      ],
                    ),
                  ),
                )
              : _excluded.isEmpty
                  ? Center(
                      child: Text('excluded_members_empty'.tr, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 16)),
                    )
                  : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _excluded.length,
                  itemBuilder: (context, index) {
                    final excludedUser = _excluded[index];
                    final displayName = excludedUser.displayName;
                    final avatar = excludedUser.avatarUrl;
                    final reason = excludedUser.reason;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: avatar != null && avatar.isNotEmpty
                                ? AppCachedImage(imageUrl: avatar, width: 44, height: 44, fit: BoxFit.cover)
                                : Container(
                                    width: 44,
                                    height: 44,
                                    color: colorScheme.primary.withValues(alpha: 0.2),
                                    alignment: Alignment.center,
                                    child: Text(displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U', style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.bold)),
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
                                      child: Text(
                                        displayName,
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: colorScheme.onSurface),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (excludedUser.isVerified) ...[
                                      const SizedBox(width: 4),
                                      UserCertifiedBadge(size: 16, userId: excludedUser.userId),
                                    ],
                                  ],
                                ),
                                if (reason != null && reason.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text('${'excluded_members_reason_prefix'.tr} $reason', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                                ],
                              ],
                            ),
                          ),
                          OutlinedButton(
                            onPressed: () => _unexclude(excludedUser.userId, displayName),
                            style: OutlinedButton.styleFrom(foregroundColor: colorScheme.primary),
                            child: Text('excluded_members_readmit'.tr),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
