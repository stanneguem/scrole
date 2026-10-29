import 'dart:io';
import 'package:intl/intl.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../centre/services/community_service.dart';
import '../../../../app/service_global/media_service.dart';
import '../../../../app/repository_global/storage_repository.dart';
import '../../../../shared/widgets/media_gallery_sheet.dart';

// --- Écran B : Gestion de la communauté (3 entrées principales) ---
class _SettingsSectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsSectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(title.toUpperCase(), style: TextStyle(fontSize: 11, letterSpacing: 0.8, fontWeight: FontWeight.w700, color: colors.onSurfaceVariant)),
      ),
      Container(
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.35)),
        ),
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 16, endIndent: 16, color: colors.outlineVariant.withValues(alpha: 0.25)),
            children[i],
          ],
        ]),
      ),
    ]);
  }
}

class _IosSwitchTile extends StatelessWidget {
  final Widget title;
  final Widget? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _IosSwitchTile({required this.title, this.subtitle, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          DefaultTextStyle(style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colors.onSurface), child: title),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            DefaultTextStyle(style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant), child: subtitle!),
          ],
        ])),
        const SizedBox(width: 12),
        CupertinoSwitch(value: value, onChanged: onChanged, activeTrackColor: colors.primary),
      ]),
    );
  }
}

class _CommunityImageEditCard extends StatelessWidget {
  final String title;
  final String? imageUrl;
  final bool isProfile;
  final bool isLoading;
  final VoidCallback onChange;

  const _CommunityImageEditCard({
    required this.title,
    required this.imageUrl,
    required this.isProfile,
    required this.isLoading,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasImage = imageUrl != null && imageUrl!.trim().isNotEmpty;

    if (isProfile) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Container(
              width: 92,
              height: 92,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: colors.primary.withValues(alpha: 0.35), width: 1.5),
              ),
              child: ClipOval(
                child: hasImage
                    ? Image.network(imageUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder(colors))
                    : _placeholder(colors),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: colors.onSurface)),
                  const SizedBox(height: 5),
                  Text('community_settings_profile_photo'.tr, style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: isLoading ? null : onChange,
                    icon: const Icon(Icons.photo_camera_back_outlined, size: 17),
                    label: Text('community_settings_change_photo'.tr),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: colors.onSurface)),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: AspectRatio(
            aspectRatio: 1.9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (hasImage)
                  Image.network(imageUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder(colors))
                else
                  _placeholder(colors),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black.withValues(alpha: 0.02), Colors.black.withValues(alpha: 0.62)],
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          hasImage ? 'community_settings_cover_photo'.tr : 'community_banner_label'.tr,
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: isLoading ? null : onChange,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black87,
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.edit_outlined, size: 17),
                        label: Text('community_settings_change_photo'.tr),
                      ),
                    ],
                  ),
                ),
                if (!hasImage)
                  Center(child: Icon(Icons.add_photo_alternate_outlined, size: 42, color: colors.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _placeholder(ColorScheme colors) => Container(
    color: colors.surfaceContainerHighest,
    alignment: Alignment.center,
    child: Icon(isProfile ? Icons.groups_rounded : Icons.image_outlined, size: 34, color: colors.onSurfaceVariant),
  );
}

class CommunitySettingsMainScreen extends StatefulWidget {
  final String communityId;
  final String communityName;
  final String? communityAvatar;
  final String? communitySlogan;

  const CommunitySettingsMainScreen({
    super.key,
    required this.communityId,
    required this.communityName,
    this.communityAvatar,
    this.communitySlogan,
  });

  @override
  State<CommunitySettingsMainScreen> createState() => _CommunitySettingsMainScreenState();
}

class _CommunitySettingsMainScreenState extends State<CommunitySettingsMainScreen> {
  final CommunityService _service = Get.find<CommunityService>();
  bool _isLoading = true;
  bool _communityStatsAvailable = false;
  bool _isCommunityOwner = false;
  bool _communityCertified = false;
  String _role = 'member';
  Map<String, dynamic> _modCounts = {};
  String? _communityName;
  String? _avatarUrl;
  String? _slogan;

  @override
  void initState() {
    super.initState();
    _loadRoleAndCounts();
  }

  Future<void> _loadRoleAndCounts() async {
    try {
      _role = await _service.getCurrentUserRole(widget.communityId);
      try {
        final certification = await Supabase.instance.client.rpc(
          'scrole_get_entity_certification_status',
          params: {'p_entity_type': 'community', 'p_entity_id': widget.communityId},
        );
        if (certification is Map) {
          _isCommunityOwner = certification['is_owner'] == true;
          _communityCertified = certification['entity_certified'] == true;
        }
      } catch (e) {
        debugPrint('[CommunitySettingsMainScreen] Certification status unavailable: $e');
      }
      if (!_isCommunityOwner && _role != 'admin' && _role != 'moderator') {
        Get.back();
        Get.snackbar('error'.tr, 'community_access_denied'.tr, snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
        return;
      }
      try {
        final stats = await Supabase.instance.client.rpc(
          'get_community_certification_stats',
          params: {'p_community_id': widget.communityId},
        );
        _communityStatsAvailable = stats is Map;
      } catch (_) {
        // L'API n'autorise les statistiques qu'au propriétaire d'une communauté certifiée.
        _communityStatsAvailable = false;
      }
      try {
        _modCounts = await _service.getCommunityModerationCounts(widget.communityId);
      } catch (e) {
        debugPrint('[CommunitySettingsMainScreen] Moderation counts unavailable: $e');
      }
      try {
        final comm = await _service.getCommunityById(widget.communityId);
        if (comm != null) {
          _communityName = comm.name;
          _avatarUrl = comm.avatarUrl;
          _slogan = widget.communitySlogan ?? comm.description;
        }
      } catch (e) {
        debugPrint('[CommunitySettingsMainScreen] Local community summary unavailable: $e');
      }
      if (_role == 'admin') {
        try {
          final snapshot = await _service.getCommunityManagementSettings(widget.communityId);
          final community = snapshot['community'] is Map
              ? Map<String, dynamic>.from(snapshot['community'] as Map)
              : <String, dynamic>{};
          _communityName = community['name']?.toString() ?? _communityName;
          _avatarUrl = community['photo_profile']?.toString() ?? _avatarUrl;
          _slogan = community['slogan']?.toString() ?? _slogan;
        } catch (e) {
          debugPrint('[CommunitySettingsMainScreen] Summary refresh failed: $e');
        }
      }
    } catch (e) {
      debugPrint('[CommunitySettingsMainScreen] Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool get _isAdmin => _role == 'admin';

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return Scaffold(appBar: AppBar(title: Text('community_management_title'.tr)), body: const Center(child: CircularProgressIndicator()));
    }

    if (!_isCommunityOwner && !_isAdmin && _role != 'moderator') {
      return Scaffold(
        appBar: AppBar(title: Text('community_management_title'.tr)),
        body: Center(child: Text('community_access_denied'.tr, style: TextStyle(color: colorScheme.error, fontSize: 16))),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('community_management_title'.tr),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _communityName ?? widget.communityName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: colorScheme.onSurface),
                ),
                const SizedBox(height: 5),
                Text(
                  'community_management_title'.tr,
                  style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          // 1. Identity and community information first.
          if (_isAdmin || _isCommunityOwner)
            _buildTile(
              icon: Icons.info_outline_rounded,
              iconColor: Colors.deepOrange,
              title: 'community_mgmt_info'.tr,
              subtitle: 'community_mgmt_info_sub'.tr,
              onTap: () async {
                await Get.to(() => CommunityInfoHubScreen(
                  communityId: widget.communityId,
                  communityName: _communityName ?? widget.communityName,
                  communityAvatar: _avatarUrl,
                ));
                if (mounted) await _loadRoleAndCounts();
              },
            ),
          if (_isAdmin || _isCommunityOwner) const SizedBox(height: 12),

          // 2. Membership access and community rules.
          if (_isAdmin || _isCommunityOwner)
            _buildTile(
              icon: Icons.security_outlined,
              iconColor: Colors.green,
              title: 'community_mgmt_access'.tr,
              subtitle: 'community_mgmt_access_sub'.tr,
              onTap: () => Get.to(() => CommunityAccessRulesHubScreen(
                communityId: widget.communityId,
                communityName: _communityName ?? widget.communityName,
                communityAvatar: _avatarUrl,
              )),
            ),
          if (_isAdmin || _isCommunityOwner) const SizedBox(height: 12),

          // 3. Certification and related statistics.
          if (_isCommunityOwner)
            _buildTile(
              icon: Icons.verified_rounded,
              iconColor: _communityCertified ? Colors.green : Colors.deepPurple,
              title: 'entity_cert_community_title'.tr,
              subtitle: _communityCertified
                  ? 'entity_cert_status_active'.tr
                  : 'entity_cert_use_included'.tr,
              onTap: () async {
                await Get.to(() => EntityCertificationManagementScreen(
                  entityType: 'community',
                  entityId: widget.communityId,
                  entityName: _communityName ?? widget.communityName,
                ));
                if (mounted) await _loadRoleAndCounts();
              },
            ),
          if (_communityStatsAvailable) ...[
            const SizedBox(height: 12),
            _buildTile(
              icon: Icons.query_stats_rounded,
              iconColor: Colors.teal,
              title: 'community_cert_stats_title'.tr,
              subtitle: 'community_cert_stats_subtitle'.tr,
              onTap: () => Get.to(() => CommunityCertificationStatsScreen(
                communityId: widget.communityId,
                communityName: _communityName ?? widget.communityName,
              )),
            ),
          ],
          if (_isCommunityOwner || _communityStatsAvailable) const SizedBox(height: 12),

          // 4. Moderation and pending actions.
          if (_isAdmin || _role == 'moderator' || _isCommunityOwner)
            _buildTile(
              icon: Icons.admin_panel_settings_outlined,
              iconColor: Colors.indigo,
              title: 'community_mgmt_mod'.tr,
              subtitle: 'community_mgmt_mod_sub'.tr,
              badgeCount: ((_modCounts['reports'] as num?)?.toInt() ?? (_modCounts['pending_reports'] as num?)?.toInt() ?? 0) +
                  ((_modCounts['pending_posts'] as num?)?.toInt() ?? 0) +
                  ((_modCounts['join_requests'] as num?)?.toInt() ?? (_modCounts['pending_join_requests'] as num?)?.toInt() ?? 0) +
                  ((_modCounts['spam'] as num?)?.toInt() ?? 0),
              onTap: () => Get.to(() => CommunityModerationCenterScreen(
                communityId: widget.communityId,
                communityName: _communityName ?? widget.communityName,
                communityAvatar: _avatarUrl,
              )),
            ),
          if (_isAdmin || _isCommunityOwner) const SizedBox(height: 18),

          // Destructive action is deliberately isolated at the end.
          if (_isAdmin || _isCommunityOwner)
            _buildTile(
              icon: Icons.delete_forever_outlined,
              iconColor: Colors.red,
              title: 'community_delete_action'.tr,
              subtitle: 'community_delete_subtitle'.tr,
              onTap: _confirmDeleteCommunity,
            ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteCommunity() async {
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: Text('community_delete_confirm_title'.tr),
        content: Text('community_delete_confirm_message'.tr),
        actions: [
          TextButton(onPressed: () => Get.back(result: false), child: Text('cancel'.tr)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Get.back(result: true),
            child: Text('community_delete_action'.tr),
          ),
        ],
      ),
      barrierDismissible: false,
    );
    if (confirmed != true) return;
    try {
      await _service.deleteCommunity(widget.communityId);
      Get.until((route) => route.isFirst);
      Get.snackbar('community_delete_action'.tr, 'community_deleted_success'.tr);
    } catch (error) {
      Get.snackbar('error'.tr, _service.localizedCommunityError(error), snackPosition: SnackPosition.BOTTOM);
    }
  }

  Widget _buildTile({required IconData icon, Color? iconColor, required String title, required String subtitle, int badgeCount = 0, required VoidCallback onTap}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: (iconColor ?? colorScheme.primary).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor ?? colorScheme.primary, size: 24),
        ),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: colorScheme.onSurface)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (badgeCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                child: Text('$badgeCount', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, color: colorScheme.outline),
          ],
        ),
      ),
    );
  }
}

class CommunityCertificationStatsScreen extends StatefulWidget {
  final String communityId;
  final String communityName;

  const CommunityCertificationStatsScreen({
    super.key,
    required this.communityId,
    required this.communityName,
  });

  @override
  State<CommunityCertificationStatsScreen> createState() => _CommunityCertificationStatsScreenState();
}

class _CommunityCertificationStatsScreenState extends State<CommunityCertificationStatsScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _stats = {};

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() { _loading = true; _error = null; });
    try {
      final response = await Supabase.instance.client.rpc(
        'get_community_certification_stats',
        params: {'p_community_id': widget.communityId},
      );
      if (response is! Map) throw Exception('community_cert_stats_load_error'.tr);
      if (!mounted) return;
      setState(() { _stats = Map<String, dynamic>.from(response); _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _error = 'community_cert_stats_load_error'.tr; _loading = false; });
    }
  }

  int _value(String key) => (_stats[key] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final items = <(String, String, IconData)>[
      ('community_cert_stats_members', 'members_count', Icons.groups_rounded),
      ('community_cert_stats_new_members', 'new_members_30d', Icons.person_add_alt_1_rounded),
      ('community_cert_stats_posts', 'active_posts_count', Icons.article_outlined),
      ('community_cert_stats_new_posts', 'new_posts_30d', Icons.post_add_rounded),
      ('community_cert_stats_comments', 'comments_count', Icons.mode_comment_outlined),
      ('community_cert_stats_reactions', 'reactions_count', Icons.favorite_border_rounded),
    ];

    return Scaffold(
      appBar: AppBar(title: Text('community_cert_stats_title'.tr)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.workspace_premium_outlined, size: 42, color: colorScheme.onSurfaceVariant),
                      const SizedBox(height: 12),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      OutlinedButton(onPressed: _loadStats, child: Text('retry'.tr)),
                    ]),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadStats,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(widget.communityName, style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 6),
                      Text('community_cert_stats_subtitle'.tr,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 18),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: items.length,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 1.35,
                        ),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return Card(
                            elevation: 0,
                            color: colorScheme.surfaceContainerLow,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                              side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: .35)),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Icon(item.$3, color: colorScheme.primary, size: 22),
                                  Text('${_value(item.$2)}',
                                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                                  Text(item.$1.tr,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
    );
  }
}

// --- Écran C : Modération (2 entrées : Signalements -> Écran D, Demandes -> Écran D2) ---
class CommunityModerationCenterScreen extends StatelessWidget {
  final String communityId;
  final String communityName;
  final String? communityAvatar;

  const CommunityModerationCenterScreen({
    super.key,
    required this.communityId,
    required this.communityName,
    this.communityAvatar,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('community_mgmt_mod'.tr)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.35),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3))),
            child: ListTile(
              onTap: () => Get.to(() => CommunityPendingPostsScreen(communityId: communityId)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.pending_actions_outlined, color: Colors.orange, size: 24),
              ),
              title: Text('community_mod_pending_posts_title'.tr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              subtitle: Text('community_mod_pending_posts_subtitle'.tr, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12.5)),
              trailing: Icon(Icons.chevron_right_rounded, color: colorScheme.outline),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.35),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3))),
            child: ListTile(
              onTap: () => Get.to(() => CommunitySpamQueueScreen(communityId: communityId)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: Colors.deepOrange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.gpp_bad_outlined, color: Colors.deepOrange, size: 24),
              ),
              title: Text('community_mod_spam_title'.tr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              subtitle: Text('community_mod_spam_subtitle'.tr, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12.5)),
              trailing: Icon(Icons.chevron_right_rounded, color: colorScheme.outline),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.35),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3))),
            child: ListTile(
              onTap: () => Get.to(() => CommunityAlertsScreen(
                communityId: communityId,
                communityName: communityName,
                communityAvatar: communityAvatar,
              )),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.notifications_active_outlined, color: Colors.amber, size: 24),
              ),
              title: Text('community_alerts_title'.tr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              subtitle: Text('community_alerts_subtitle'.tr, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12.5)),
              trailing: Icon(Icons.chevron_right_rounded, color: colorScheme.outline),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.35),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3))),
            child: ListTile(
              onTap: () => Get.to(() => CommunityReportsHubScreen(communityId: communityId, communityName: communityName, communityAvatar: communityAvatar)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.report_problem_outlined, color: Colors.red, size: 24),
              ),
              title: Text('community_mod_section_reports'.tr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              subtitle: Text('community_mod_tab_reports'.tr, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12.5)),
              trailing: Icon(Icons.chevron_right_rounded, color: colorScheme.outline),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.35),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3))),
            child: ListTile(
              onTap: () => Get.to(() => CommunityJoinRequestsScreen(communityId: communityId, communityName: communityName, communityAvatar: communityAvatar)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.group_add_outlined, color: colorScheme.primary, size: 24),
              ),
              title: Text('community_mod_section_requests'.tr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              subtitle: Text('community_mod_tab_requests'.tr, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12.5)),
              trailing: Icon(Icons.chevron_right_rounded, color: colorScheme.outline),
            ),
          ),
        ],
      ),
    );
  }
}


class CommunityPendingPostsScreen extends StatefulWidget {
  final String communityId;
  const CommunityPendingPostsScreen({super.key, required this.communityId});

  @override
  State<CommunityPendingPostsScreen> createState() => _CommunityPendingPostsScreenState();
}

class _CommunityPendingPostsScreenState extends State<CommunityPendingPostsScreen> {
  final CommunityService _service = Get.find<CommunityService>();
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  int _offset = 0;
  String? _loadError;
  List<dynamic> _posts = [];
  final Set<String> _busyPostIds = {};

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  Future<void> _loadPosts({bool loadMore = false}) async {
    if (loadMore) {
      if (!_hasMore || _isLoadingMore || _isLoading) return;
      if (mounted) setState(() => _isLoadingMore = true);
    } else {
      if (mounted) {
        setState(() {
          _isLoading = true;
          _loadError = null;
        });
      }
      _offset = 0;
    }
    try {
      final response = await _service.getCommunityPendingPosts(
        widget.communityId,
        limit: 20,
        offset: loadMore ? _offset : 0,
      );
      if (response['items'] is! List) {
        throw const FormatException('Réponse invalide des publications en attente.');
      }
      final items = response['items'] as List;
      if (loadMore) {
        _posts.addAll(items);
      } else {
        _posts = items;
      }
      _offset = _posts.length;
      _hasMore = response['has_more'] == true;
    } catch (e) {
      debugPrint('[CommunityPendingPostsScreen] Failed to load pending posts: $e');
      if (loadMore) {
        Get.snackbar('community_save_error'.tr, _service.localizedCommunityError(e),
            snackPosition: SnackPosition.BOTTOM);
      } else {
        _loadError = _service.localizedCommunityError(e);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _moderate(String postId, String action) async {
    if (_busyPostIds.contains(postId)) return;
    String? rejectionReason;
    if (action == 'reject') {
      final reasonController = TextEditingController();
      final result = await Get.dialog<String>(
        AlertDialog(
          title: Text('community_mod_reject_post_confirm_title'.tr),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('community_mod_reject_post_confirm_message'.tr),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonController,
                  maxLength: 500,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'community_mod_reject_post_reason_label'.tr,
                    hintText: 'community_mod_reject_post_reason_hint'.tr,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Get.back(), child: Text('cancel'.tr)),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Get.back(result: reasonController.text.trim()),
              child: Text('community_mod_reject_post'.tr),
            ),
          ],
        ),
      );
      reasonController.dispose();
      if (result == null) return;
      rejectionReason = result.isEmpty ? null : result;
    }
    setState(() => _busyPostIds.add(postId));
    try {
      await _service.moderateCommunityPost(postId, action, reason: rejectionReason);
      await _loadPosts();
      Get.snackbar(
        'community_save_success'.tr,
        action == 'approve'
            ? 'community_mod_post_approved'.tr
            : 'community_mod_post_rejected'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      debugPrint('[CommunityPendingPostsScreen] Moderation failed: $e');
      Get.snackbar(
        'community_save_error'.tr,
        _service.localizedCommunityError(e),
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      if (mounted) {
        setState(() {
          _busyPostIds.remove(postId);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('community_mod_pending_posts_title'.tr)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_loadError!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        OutlinedButton(onPressed: () => _loadPosts(), child: Text('retry'.tr)),
                      ],
                    ),
                  ),
                )
              : _posts.isEmpty
                  ? Center(child: Text('community_mod_pending_posts_empty'.tr))
                  : RefreshIndicator(
                      onRefresh: () => _loadPosts(),
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _posts.length + (_hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index >= _posts.length) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                child: _isLoadingMore
                                    ? const CircularProgressIndicator()
                                    : TextButton(
                                        onPressed: () => _loadPosts(loadMore: true),
                                        child: Text('community_load_more'.tr),
                                      ),
                              ),
                            );
                          }
                          final post = Map<String, dynamic>.from(_posts[index] as Map);
                          final id = post['id']?.toString() ?? '';
                          final author = post['author'] is Map
                              ? Map<String, dynamic>.from(post['author'] as Map)
                              : <String, dynamic>{};
                          final authorName = '${author['first_name'] ?? ''} ${author['last_name'] ?? ''}'.trim();
                          final username = author['username']?.toString();
                          final content = post['content']?.toString() ?? '';
                          final mediaItems = post['media'] is List
                              ? (post['media'] as List)
                                  .whereType<Map>()
                                  .map((item) => Map<String, dynamic>.from(item))
                                  .toList()
                              : <Map<String, dynamic>>[];
                          final busy = _busyPostIds.contains(id);
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    authorName.isNotEmpty ? authorName : (username == null ? 'excluded_members_unknown_user'.tr : '@$username'),
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  if (content.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(content, maxLines: 6, overflow: TextOverflow.ellipsis),
                                  ],
                                  if (mediaItems.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    SizedBox(
                                      height: 120,
                                      child: ListView.separated(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: mediaItems.length,
                                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                                        itemBuilder: (context, mediaIndex) {
                                          final media = mediaItems[mediaIndex];
                                          final type = media['type']?.toString() ?? 'photo';
                                          final imageUrl = type == 'video'
                                              ? media['thumbnail_url']?.toString()
                                              : media['url']?.toString();
                                          return ClipRRect(
                                            borderRadius: BorderRadius.circular(10),
                                            child: SizedBox(
                                              width: 120,
                                              height: 120,
                                              child: Stack(
                                                fit: StackFit.expand,
                                                children: [
                                                  if (imageUrl != null && imageUrl.isNotEmpty)
                                                    Image.network(
                                                      imageUrl,
                                                      fit: BoxFit.cover,
                                                      errorBuilder: (_, __, ___) => Container(
                                                        color: colorScheme.surfaceContainerHighest,
                                                        child: const Icon(Icons.broken_image_outlined),
                                                      ),
                                                    )
                                                  else
                                                    Container(
                                                      color: colorScheme.surfaceContainerHighest,
                                                      child: const Icon(Icons.perm_media_outlined),
                                                    ),
                                                  if (type == 'video')
                                                    const Center(
                                                      child: Icon(Icons.play_circle_fill, size: 42, color: Colors.white),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: busy || id.isEmpty ? null : () => _moderate(id, 'reject'),
                                          icon: const Icon(Icons.close),
                                          label: Text('community_mod_reject_post'.tr),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: FilledButton.icon(
                                          onPressed: busy || id.isEmpty ? null : () => _moderate(id, 'approve'),
                                          icon: const Icon(Icons.check),
                                          label: Text('community_mod_approve_post'.tr),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (busy) const LinearProgressIndicator(),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

// --- Écran D : Signalements (TabView interne avec Contenus et Membres) ---
class CommunitySpamQueueScreen extends StatefulWidget {
  final String communityId;
  const CommunitySpamQueueScreen({super.key, required this.communityId});

  @override
  State<CommunitySpamQueueScreen> createState() => _CommunitySpamQueueScreenState();
}

class _CommunitySpamQueueScreenState extends State<CommunitySpamQueueScreen> {
  final CommunityService _service = Get.find<CommunityService>();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _offset = 0;
  String? _error;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (more) {
      if (!_hasMore || _loadingMore || _loading) return;
      setState(() => _loadingMore = true);
    } else {
      setState(() {
        _loading = true;
        _error = null;
        _offset = 0;
      });
    }
    try {
      final result = await _service.getCommunitySpamQueue(
        widget.communityId,
        limit: 20,
        offset: more ? _offset : 0,
      );
      final raw = result['items'];
      if (raw is! List) throw const FormatException('Réponse invalide de la file de spam.');
      final page = raw.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
      if (!mounted) return;
      setState(() {
        if (more) {
          _items.addAll(page);
        } else {
          _items = page;
        }
        _offset = _items.length;
        _hasMore = result['has_more'] == true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _service.localizedCommunityError(e));
    } finally {
      if (mounted) setState(() {
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _moderate(Map<String, dynamic> item, String action) async {
    final postId = item['post_id']?.toString() ?? '';
    if (postId.isEmpty || _busy.contains(postId)) return;
    setState(() => _busy.add(postId));
    try {
      await _service.moderateCommunityPost(
        postId,
        action,
        reason: action == 'reject' ? 'Spam confirmé par la modération' : null,
      );
      await _load();
      Get.snackbar(
        'community_save_success'.tr,
        action == 'approve'
            ? 'community_mod_post_approved'.tr
            : 'community_mod_post_rejected'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar(
        'community_save_error'.tr,
        _service.localizedCommunityError(e),
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) setState(() => _busy.remove(postId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('community_mod_spam_title'.tr)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        OutlinedButton(onPressed: _load, child: Text('retry'.tr)),
                      ],
                    ),
                  ),
                )
              : _items.isEmpty
                  ? Center(child: Text('community_mod_spam_empty'.tr))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _items.length + (_hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index >= _items.length) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: _loadingMore
                                    ? const CircularProgressIndicator()
                                    : TextButton(
                                        onPressed: () => _load(more: true),
                                        child: Text('community_load_more'.tr),
                                      ),
                              ),
                            );
                          }
                          final item = _items[index];
                          final postId = item['post_id']?.toString() ?? '';
                          final author = item['author'] is Map
                              ? Map<String, dynamic>.from(item['author'] as Map)
                              : <String, dynamic>{};
                          final name = '${author['first_name'] ?? ''} ${author['last_name'] ?? ''}'.trim();
                          final username = author['username']?.toString() ?? '';
                          final reasons = item['reasons'] is List
                              ? (item['reasons'] as List).map((e) => e.toString()).join(', ')
                              : '';
                          final photos = item['photos'] is List
                              ? (item['photos'] as List).map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
                              : <String>[];
                          final video = item['video'] is Map
                              ? Map<String, dynamic>.from(item['video'] as Map)
                              : <String, dynamic>{};
                          final busy = _busy.contains(postId);
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.warning_amber_rounded, color: Colors.deepOrange),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          name.isNotEmpty ? name : (username.isNotEmpty ? '@$username' : 'excluded_members_unknown_user'.tr),
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      Text('${'community_moderation_score'.tr}: ${item['score'] ?? 0}', style: TextStyle(color: colors.error, fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                  if (reasons.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text('${'community_moderation_reasons'.tr}: $reasons', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
                                  ],
                                  if ((item['content']?.toString() ?? '').trim().isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Text(item['content'].toString(), maxLines: 6, overflow: TextOverflow.ellipsis),
                                  ],
                                  if (photos.isNotEmpty || video.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    SizedBox(
                                      height: 88,
                                      child: ListView(
                                        scrollDirection: Axis.horizontal,
                                        children: [
                                          ...photos.map((url) => Padding(
                                            padding: const EdgeInsets.only(right: 8),
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(10),
                                              child: Image.network(url, width: 88, height: 88, fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) => Container(width: 88, height: 88, color: colors.surfaceContainerHighest, child: const Icon(Icons.broken_image_outlined)),
                                              ),
                                            ),
                                          )),
                                          if (video['thumbnail_url']?.toString().isNotEmpty == true)
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(10),
                                              child: Image.network(video['thumbnail_url'].toString(), width: 88, height: 88, fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) => Container(width: 88, height: 88, color: colors.surfaceContainerHighest, child: const Icon(Icons.videocam_outlined)),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: busy ? null : () => _moderate(item, 'reject'),
                                          icon: const Icon(Icons.close_rounded, color: Colors.red),
                                          label: Text('community_mod_reject_post'.tr),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: FilledButton.icon(
                                          onPressed: busy ? null : () => _moderate(item, 'approve'),
                                          icon: const Icon(Icons.check_rounded),
                                          label: Text('community_mod_approve_post'.tr),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

class CommunityAlertsScreen extends StatefulWidget {
  final String communityId;
  final String communityName;
  final String? communityAvatar;

  const CommunityAlertsScreen({
    super.key,
    required this.communityId,
    required this.communityName,
    this.communityAvatar,
  });

  @override
  State<CommunityAlertsScreen> createState() => _CommunityAlertsScreenState();
}

class _CommunityAlertsScreenState extends State<CommunityAlertsScreen> {
  final CommunityService _service = Get.find<CommunityService>();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _service.getCommunityAlerts(widget.communityId);
      final raw = response['items'];
      if (raw is! List) throw const FormatException('Réponse invalide des alertes.');
      if (!mounted) return;
      setState(() {
        _items = raw.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
      });
    } catch (e) {
      if (mounted) setState(() => _error = _service.localizedCommunityError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _titleFor(Map<String, dynamic> item) {
    final type = item['type']?.toString() ?? '';
    switch (type) {
      case 'reported_content':
        return 'community_alert_reported_content'.trParams({
          'count': (item['reports_count'] ?? 0).toString(),
        });
      case 'spam_author':
        return 'community_alert_spam_author'.trParams({
          'username': item['username']?.toString() ?? 'excluded_members_unknown_user'.tr,
          'count': (item['confirmed_count'] ?? 0).toString(),
        });
      case 'overdue_posts':
        return 'community_alert_overdue_posts'.trParams({
          'count': (item['count'] ?? 0).toString(),
        });
      case 'overdue_join_requests':
        return 'community_alert_overdue_join_requests'.trParams({
          'count': (item['count'] ?? 0).toString(),
        });
      case 'overdue_reports':
        return 'community_alert_overdue_reports'.trParams({
          'count': (item['count'] ?? 0).toString(),
        });
      default:
        return type;
    }
  }

  void _openAlert(Map<String, dynamic> item) {
    final type = item['type']?.toString() ?? '';
    if (type == 'reported_content' || type == 'overdue_reports') {
      Get.to(() => CommunityReportsHubScreen(
        communityId: widget.communityId,
        communityName: widget.communityName,
        communityAvatar: widget.communityAvatar,
      ));
    } else if (type == 'spam_author') {
      Get.to(() => CommunitySpamQueueScreen(communityId: widget.communityId));
    } else if (type == 'overdue_posts') {
      Get.to(() => CommunityPendingPostsScreen(communityId: widget.communityId));
    } else if (type == 'overdue_join_requests') {
      Get.to(() => CommunityJoinRequestsScreen(
        communityId: widget.communityId,
        communityName: widget.communityName,
        communityAvatar: widget.communityAvatar,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('community_alerts_title'.tr)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        OutlinedButton(onPressed: _load, child: Text('retry'.tr)),
                      ],
                    ),
                  ),
                )
              : _items.isEmpty
                  ? Center(child: Text('community_alerts_empty'.tr))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          return Card(
                            child: ListTile(
                              leading: const Icon(Icons.notifications_active_outlined, color: Colors.amber),
                              title: Text(_titleFor(item)),
                              subtitle: item['first_reported_at'] != null
                                  ? Text(item['first_reported_at'].toString(), style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12))
                                  : null,
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () => _openAlert(item),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

class CommunityReportsHubScreen extends StatefulWidget {
  final String communityId;
  final String communityName;
  final String? communityAvatar;

  const CommunityReportsHubScreen({
    super.key,
    required this.communityId,
    required this.communityName,
    this.communityAvatar,
  });

  @override
  State<CommunityReportsHubScreen> createState() => _CommunityReportsHubScreenState();
}

class _CommunityReportsHubScreenState extends State<CommunityReportsHubScreen> with SingleTickerProviderStateMixin {
  final CommunityService _service = Get.find<CommunityService>();
  late TabController _tabController;

  bool _isLoading = true;
  String _role = 'member';
  String? _loadError;
  List<dynamic> _reports = [];
  List<dynamic> _userReports = [];
  int _reportsOffset = 0;
  int _userReportsOffset = 0;
  bool _reportsHasMore = false;
  bool _userReportsHasMore = false;
  bool _loadingMoreReports = false;
  bool _loadingMoreUserReports = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadReports();
  }

  Future<void> _loadReports() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      _role = await _service.getCurrentUserRole(widget.communityId);
      final reportsRes = await _service.getCommunityReports(widget.communityId, limit: 20, offset: 0);
      final userReportsRes = await _service.getCommunityUserReports(widget.communityId, limit: 20, offset: 0);
      if (reportsRes['items'] is! List || userReportsRes['items'] is! List) {
        throw const FormatException('Réponse invalide lors du chargement des signalements.');
      }
      _reports = reportsRes['items'] as List;
      _userReports = userReportsRes['items'] as List;
      _reportsOffset = _reports.length;
      _userReportsOffset = _userReports.length;
      _reportsHasMore = reportsRes['has_more'] == true;
      _userReportsHasMore = userReportsRes['has_more'] == true;
    } catch (e) {
      debugPrint('[CommunityReportsHubScreen] Failed to load reports: $e');
      _loadError = 'community_reports_load_error'.tr;
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadMoreReports({required bool members}) async {
    if (members) {
      if (!_userReportsHasMore || _loadingMoreUserReports) return;
      setState(() => _loadingMoreUserReports = true);
    } else {
      if (!_reportsHasMore || _loadingMoreReports) return;
      setState(() => _loadingMoreReports = true);
    }
    try {
      final response = members
          ? await _service.getCommunityUserReports(widget.communityId, limit: 20, offset: _userReportsOffset)
          : await _service.getCommunityReports(widget.communityId, limit: 20, offset: _reportsOffset);
      if (response['items'] is! List) {
        throw const FormatException('Réponse invalide lors du chargement des signalements.');
      }
      final items = response['items'] as List;
      if (members) {
        _userReports.addAll(items);
        _userReportsOffset = _userReports.length;
        _userReportsHasMore = response['has_more'] == true;
      } else {
        _reports.addAll(items);
        _reportsOffset = _reports.length;
        _reportsHasMore = response['has_more'] == true;
      }
    } catch (e) {
      debugPrint('[CommunityReportsHubScreen] Failed to load more reports: $e');
      Get.snackbar('community_save_error'.tr, _service.localizedCommunityError(e),
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      if (mounted) {
        setState(() {
          _loadingMoreReports = false;
          _loadingMoreUserReports = false;
        });
      }
    }
  }

  Future<void> _resolveReport(String reportId, String action) async {
    if (action == 'remove_content') {
      final confirmed = await Get.dialog<bool>(
        AlertDialog(
          title: Text('community_report_remove_confirm_title'.tr),
          content: Text('community_report_remove_confirm_message'.tr),
          actions: [
            TextButton(onPressed: () => Get.back(result: false), child: Text('cancel'.tr)),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Get.back(result: true),
              child: Text('community_report_remove_confirm_action'.tr),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    try {
      await _service.resolveCommunityReport(reportId, action);
      await _loadReports();
      Get.snackbar('community_save_success'.tr, '', snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('community_save_error'.tr, _service.localizedCommunityError(e), snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  Future<void> _resolveUserReport(String reportId, String action) async {
    if (action == 'exclude_member') {
      final confirmed = await Get.dialog<bool>(
        AlertDialog(
          title: Text('community_report_exclude_confirm_title'.tr),
          content: Text('community_report_exclude_confirm_message'.tr),
          actions: [
            TextButton(onPressed: () => Get.back(result: false), child: Text('cancel'.tr)),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Get.back(result: true),
              child: Text('community_exclude_action'.tr),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    try {
      await _service.resolveCommunityUserReport(reportId, action);
      await _loadReports();
      Get.snackbar('community_save_success'.tr, '', snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('community_save_error'.tr, _service.localizedCommunityError(e), snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('community_mod_section_reports'.tr),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'community_reports_tab_content'.tr),
            Tab(text: 'community_reports_tab_members'.tr),
          ],
        ),
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
                        Text(_loadError!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        OutlinedButton(onPressed: _loadReports, child: Text('excluded_members_retry'.tr)),
                      ],
                    ),
                  ),
                )
              : TabBarView(
              controller: _tabController,
              children: [
                // 1. Content Reports
                _reports.isEmpty
                    ? Center(child: Text('community_reports_content_empty'.tr))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _reports.length + (_reportsHasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index >= _reports.length) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: _loadingMoreReports
                                    ? const CircularProgressIndicator()
                                    : TextButton(
                                        onPressed: () => _loadMoreReports(members: false),
                                        child: Text('community_load_more'.tr),
                                      ),
                              ),
                            );
                          }
                          final r = Map<String, dynamic>.from(_reports[index] as Map);
                          final target = r['target'] is Map
                              ? Map<String, dynamic>.from(r['target'] as Map)
                              : <String, dynamic>{};
                          final targetAuthor = target['author'] is Map
                              ? Map<String, dynamic>.from(target['author'] as Map)
                              : <String, dynamic>{};
                          final reporter = r['reporter'] is Map
                              ? Map<String, dynamic>.from(r['reporter'] as Map)
                              : <String, dynamic>{};
                          final reasonData = r['reason'] is Map
                              ? Map<String, dynamic>.from(r['reason'] as Map)
                              : <String, dynamic>{};
                          final reason = reasonData['nom']?.toString() ?? reasonData['code']?.toString() ?? '';
                          final description = r['description']?.toString() ?? '';
                          final targetContent = target['content']?.toString() ?? '';
                          final targetPhotos = target['photos'] is List
                              ? (target['photos'] as List).map((url) => url.toString()).where((url) => url.isNotEmpty).toList()
                              : <String>[];
                          final targetHasVideo = target['video_url']?.toString().isNotEmpty == true;
                          final reporterName = '${reporter['first_name'] ?? ''} ${reporter['last_name'] ?? ''}'.trim();
                          final targetAuthorName = '${targetAuthor['first_name'] ?? ''} ${targetAuthor['last_name'] ?? ''}'.trim();
                          final targetType = r['target_type']?.toString() ?? '';
                          final reportsCount = (r['reports_count'] as num?)?.toInt() ?? 1;
                          final reportId = r['id']?.toString() ?? '';
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              isThreeLine: true,
                              title: Text('community_report_item_title'.trParams({'type': targetType})),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (targetAuthorName.isNotEmpty || targetAuthor['username'] != null)
                                    Text('community_report_target_author'.trParams({
                                      'name': targetAuthorName.isNotEmpty
                                          ? targetAuthorName
                                          : '@${targetAuthor['username']}',
                                    })),
                                  if (reporterName.isNotEmpty || reporter['username'] != null)
                                    Text('community_reported_by'.trParams({
                                      'name': reporterName.isNotEmpty
                                          ? reporterName
                                          : '@${reporter['username']}',
                                    })),
                                  if (reason.isNotEmpty)
                                    Text('community_report_reason_prefix'.trParams({'reason': reason})),
                                  if (description.isNotEmpty) Text(description),
                                  if (targetContent.isNotEmpty)
                                    Text(
                                      'community_report_target_content'.trParams({'content': targetContent}),
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  if (targetPhotos.isNotEmpty || targetHasVideo) ...[
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      height: 84,
                                      child: ListView.separated(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: targetPhotos.length + (targetHasVideo ? 1 : 0),
                                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                                        itemBuilder: (context, mediaIndex) {
                                          if (mediaIndex >= targetPhotos.length) {
                                            return Container(
                                              width: 84,
                                              decoration: BoxDecoration(
                                                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: const Icon(Icons.play_circle_outline, size: 34),
                                            );
                                          }
                                          return ClipRRect(
                                            borderRadius: BorderRadius.circular(8),
                                            child: Image.network(
                                              targetPhotos[mediaIndex],
                                              width: 84,
                                              height: 84,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => Container(
                                                width: 84,
                                                height: 84,
                                                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                                child: const Icon(Icons.broken_image_outlined),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                  if (reportsCount > 1)
                                    Text('community_report_reports_count'.trParams({'count': reportsCount.toString()})),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'community_report_dismiss'.tr,
                                    icon: const Icon(Icons.close, color: Colors.grey),
                                    onPressed: reportId.isEmpty ? null : () => _resolveReport(reportId, 'dismiss'),
                                  ),
                                  if (targetType == 'post' || targetType == 'comment')
                                    IconButton(
                                      tooltip: 'community_report_remove_confirm_action'.tr,
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: reportId.isEmpty ? null : () => _resolveReport(reportId, 'remove_content'),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                // 2. Member Reports
                _userReports.isEmpty
                    ? Center(child: Text('community_reports_members_empty'.tr))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _userReports.length + (_userReportsHasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index >= _userReports.length) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: _loadingMoreUserReports
                                    ? const CircularProgressIndicator()
                                    : TextButton(
                                        onPressed: () => _loadMoreReports(members: true),
                                        child: Text('community_load_more'.tr),
                                      ),
                              ),
                            );
                          }
                          final r = Map<String, dynamic>.from(_userReports[index] as Map);
                          final target = r['target'] is Map
                              ? Map<String, dynamic>.from(r['target'] as Map)
                              : <String, dynamic>{};
                          final reporter = r['reporter'] is Map
                              ? Map<String, dynamic>.from(r['reporter'] as Map)
                              : <String, dynamic>{};
                          final reasonData = r['reason'] is Map
                              ? Map<String, dynamic>.from(r['reason'] as Map)
                              : <String, dynamic>{};
                          final reason = reasonData['nom']?.toString() ?? reasonData['code']?.toString() ?? '';
                          final description = r['description']?.toString() ?? '';
                          final targetName = '${target['first_name'] ?? ''} ${target['last_name'] ?? ''}'.trim();
                          final reporterName = '${reporter['first_name'] ?? ''} ${reporter['last_name'] ?? ''}'.trim();
                          final reportId = r['id']?.toString() ?? '';
                          final reportsCount = (r['reports_count'] as num?)?.toInt() ?? 1;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              title: Text('community_member_report_title'.tr),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('community_user_report_target'.trParams({
                                    'name': targetName.isNotEmpty
                                        ? targetName
                                        : (target['username'] == null ? 'excluded_members_unknown_user'.tr : '@${target['username']}'),
                                  })),
                                  if (reporterName.isNotEmpty || reporter['username'] != null)
                                    Text('community_reported_by'.trParams({
                                      'name': reporterName.isNotEmpty
                                          ? reporterName
                                          : '@${reporter['username']}',
                                    })),
                                  if (reason.isNotEmpty)
                                    Text('community_report_reason_prefix'.trParams({'reason': reason})),
                                  if (description.isNotEmpty) Text(description),
                                  if (reportsCount > 1)
                                    Text('community_report_reports_count'.trParams({'count': reportsCount.toString()})),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'community_report_dismiss'.tr,
                                    icon: const Icon(Icons.close, color: Colors.grey),
                                    onPressed: reportId.isEmpty ? null : () => _resolveUserReport(reportId, 'dismiss'),
                                  ),
                                  if (_role == 'admin')
                                    IconButton(
                                      tooltip: 'community_exclude_action'.tr,
                                      icon: const Icon(Icons.block, color: Colors.red),
                                      onPressed: reportId.isEmpty ? null : () => _resolveUserReport(reportId, 'exclude_member'),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ],
            ),
    );
  }
}

// --- Écran D2 : Demandes d'adhésion ---
class CommunityJoinRequestsScreen extends StatefulWidget {
  final String communityId;
  final String communityName;
  final String? communityAvatar;

  const CommunityJoinRequestsScreen({
    super.key,
    required this.communityId,
    required this.communityName,
    this.communityAvatar,
  });

  @override
  State<CommunityJoinRequestsScreen> createState() => _CommunityJoinRequestsScreenState();
}

class _CommunityJoinRequestsScreenState extends State<CommunityJoinRequestsScreen> {
  final CommunityService _service = Get.find<CommunityService>();
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  String? _nextCursor;
  String? _loadError;
  List<dynamic> _joinRequests = [];

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests({bool loadMore = false}) async {
    if (loadMore) {
      if (!_hasMore || _isLoadingMore || _isLoading) return;
      if (mounted) setState(() => _isLoadingMore = true);
    } else {
      if (mounted) {
        setState(() {
          _isLoading = true;
          _loadError = null;
        });
      }
      _nextCursor = null;
    }
    try {
      final reqsRes = await _service.getCommunityJoinRequests(
        widget.communityId,
        limit: 20,
        cursor: loadMore ? _nextCursor : null,
      );
      if (reqsRes['items'] is! List) {
        throw const FormatException('Réponse invalide des demandes d’adhésion.');
      }
      final items = reqsRes['items'] as List;
      if (loadMore) {
        _joinRequests.addAll(items);
      } else {
        _joinRequests = items;
      }
      _hasMore = reqsRes['has_more'] == true;
      _nextCursor = reqsRes['next_cursor']?.toString();
    } catch (e) {
      debugPrint('[CommunityJoinRequestsScreen] Failed to load requests: $e');
      if (loadMore) {
        Get.snackbar('community_save_error'.tr, _service.localizedCommunityError(e),
            snackPosition: SnackPosition.BOTTOM);
      } else {
        _loadError = _service.localizedCommunityError(e);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _respondRequest(String requestId, bool accepted) async {
    try {
      await _service.respondCommunityJoinRequest(requestId, accepted);
      await _loadRequests();
      Get.snackbar('community_save_success'.tr, '', snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('community_save_error'.tr, _service.localizedCommunityError(e), snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('community_mod_section_requests'.tr)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_loadError!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: () => _loadRequests(), child: Text('retry'.tr)),
                  ]),
                ))
              : _joinRequests.isEmpty && !_hasMore
                  ? Center(child: Text('community_requests_empty'.tr))
                  : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _joinRequests.length + (_hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= _joinRequests.length) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: _isLoadingMore
                              ? const CircularProgressIndicator()
                              : TextButton(
                                  onPressed: () => _loadRequests(loadMore: true),
                                  child: Text('community_load_more'.tr),
                                ),
                        ),
                      );
                    }
                    final req = Map<String, dynamic>.from(_joinRequests[index] as Map);
                    final user = req['user'] is Map
                        ? Map<String, dynamic>.from(req['user'] as Map)
                        : req;
                    final name = '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'.trim();
                    final username = user['username']?.toString();
                    final requestId = req['id']?.toString() ?? '';
                    return Card(
                      child: ListTile(
                        title: Text(name.isEmpty ? (username == null ? 'excluded_members_unknown_user'.tr : '@$username') : name),
                        subtitle: Text(username != null ? '@$username' : ''),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(icon: const Icon(Icons.check, color: Colors.green), onPressed: requestId.isEmpty ? null : () => _respondRequest(requestId, true)),
                            IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: requestId.isEmpty ? null : () => _respondRequest(requestId, false)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

// --- Écran E : Accès et règles Hub (3 entrées) ---
class CommunityAccessRulesHubScreen extends StatelessWidget {
  final String communityId;
  final String communityName;
  final String? communityAvatar;

  const CommunityAccessRulesHubScreen({
    super.key,
    required this.communityId,
    required this.communityName,
    this.communityAvatar,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('community_mgmt_access'.tr)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHubTile(context, title: 'community_access_sub_posts'.tr, subtitle: 'community_access_sub_posts_desc'.tr, icon: Icons.article_outlined, iconColor: Colors.blue, onTap: () => Get.to(() => CommunityPostSettingsScreen(communityId: communityId))),
          const SizedBox(height: 12),
          _buildHubTile(context, title: 'community_access_sub_access'.tr, subtitle: 'community_access_sub_access_desc'.tr, icon: Icons.security_outlined, iconColor: Colors.green, onTap: () => Get.to(() => CommunityAccessDetailsScreen(communityId: communityId))),
          const SizedBox(height: 12),
          _buildHubTile(context, title: 'community_access_sub_rules'.tr, subtitle: 'community_access_sub_rules_desc'.tr, icon: Icons.rule_rounded, iconColor: Colors.deepOrange, onTap: () => Get.to(() => CommunityRulesScreen(communityId: communityId))),
        ],
      ),
    );
  }

  Widget _buildHubTile(BuildContext context, {required String title, required String subtitle, required IconData icon, required Color iconColor, required VoidCallback onTap}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3))),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: iconColor, size: 24),
        ),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: colorScheme.onSurface)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant)),
        trailing: Icon(Icons.chevron_right_rounded, color: colorScheme.outline),
      ),
    );
  }
}

// --- Écran H : Informations de la communauté Hub (3 entrées) ---
class CommunityInfoHubScreen extends StatefulWidget {
  final String communityId;
  final String communityName;
  final String? communityAvatar;

  const CommunityInfoHubScreen({
    super.key,
    required this.communityId,
    required this.communityName,
    this.communityAvatar,
  });

  @override
  State<CommunityInfoHubScreen> createState() => _CommunityInfoHubScreenState();
}

class _CommunityInfoHubScreenState extends State<CommunityInfoHubScreen> {
  final CommunityService _service = Get.find<CommunityService>();
  late String _communityName;
  String? _communityAvatar;

  @override
  void initState() {
    super.initState();
    _communityName = widget.communityName;
    _communityAvatar = widget.communityAvatar;
    _loadCommunitySummary();
  }

  Future<void> _loadCommunitySummary() async {
    try {
      final snapshot = await _service.getCommunityManagementSettings(widget.communityId);
      final community = snapshot['community'] is Map
          ? Map<String, dynamic>.from(snapshot['community'] as Map)
          : <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _communityName = community['name']?.toString() ?? _communityName;
        _communityAvatar = community['photo_profile']?.toString() ?? _communityAvatar;
      });
    } catch (e) {
      debugPrint('[CommunityInfoHubScreen] Failed to refresh community summary: $e');
    }
  }

  Future<void> _openSubpage(Widget page) async {
    await Get.to(() => page);
    await _loadCommunitySummary();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('community_mgmt_info'.tr)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHubTile(context, title: 'community_info_sub_desc'.tr, subtitle: 'community_info_sub_desc_desc'.tr, icon: Icons.info_outline_rounded, iconColor: Colors.orange, onTap: () => _openSubpage(CommunityInfoSettingsScreen(communityId: widget.communityId, communityName: _communityName))),
          const SizedBox(height: 12),
          _buildHubTile(context, title: 'community_info_sub_interests'.tr, subtitle: 'community_info_sub_interests_desc'.tr, icon: Icons.favorite_border_rounded, iconColor: Colors.pink, onTap: () => _openSubpage(CommunityInterestsScreen(communityId: widget.communityId))),
          const SizedBox(height: 12),
          _buildHubTile(context, title: 'community_info_sub_images'.tr, subtitle: 'community_info_sub_images_desc'.tr, icon: Icons.image_outlined, iconColor: Colors.purple, onTap: () => _openSubpage(CommunityImagesScreen(communityId: widget.communityId))),
        ],
      ),
    );
  }

  Widget _buildHubTile(BuildContext context, {required String title, required String subtitle, required IconData icon, required Color iconColor, required VoidCallback onTap}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3))),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: iconColor, size: 24),
        ),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: colorScheme.onSurface)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant)),
        trailing: Icon(Icons.chevron_right_rounded, color: colorScheme.outline),
      ),
    );
  }
}

// 1. Informations descriptives
class CommunityInfoSettingsScreen extends StatefulWidget {
  final String communityId;
  final String communityName;
  const CommunityInfoSettingsScreen({super.key, required this.communityId, required this.communityName});

  @override
  State<CommunityInfoSettingsScreen> createState() => _CommunityInfoSettingsScreenState();
}

class _CommunityInfoSettingsScreenState extends State<CommunityInfoSettingsScreen> {
  final CommunityService _service = Get.find<CommunityService>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _sloganController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadCommunityInfo();
  }

  Future<void> _loadCommunityInfo() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final snapshot = await _service.getCommunityManagementSettings(widget.communityId);
      final community = snapshot['community'] is Map
          ? Map<String, dynamic>.from(snapshot['community'] as Map)
          : <String, dynamic>{};
      _nameController.text = community['name']?.toString() ?? widget.communityName;
      _sloganController.text = community['slogan']?.toString() ?? '';
      _descController.text = community['description']?.toString() ?? '';
    } catch (e) {
      debugPrint('[CommunityInfoSettingsScreen] Failed to load current values: $e');
      _loadError = _service.localizedCommunityError(e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _sloganController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isLoading = true);
    try {
      final name = _nameController.text.trim();
      if (name.isEmpty) {
        Get.snackbar('community_save_error'.tr, 'community_settings_name_required'.tr,
            snackPosition: SnackPosition.BOTTOM);
        return;
      }
      await _service.updateCommunityInfo(
        id: widget.communityId,
        name: name,
        slogan: _sloganController.text.trim(),
        description: _descController.text.trim(),
      );
      Get.snackbar('community_save_success'.tr, '', snackPosition: SnackPosition.BOTTOM);
      Get.back();
    } catch (e) {
      debugPrint('[CommunityInfoSettingsScreen] Save failed: $e');
      Get.snackbar('community_save_error'.tr, _service.localizedCommunityError(e), snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('community_info_sub_desc'.tr), actions: [IconButton(tooltip: 'community_save'.tr, onPressed: _isLoading ? null : _save, icon: const Icon(Icons.check_rounded)), const SizedBox(width: 4)]),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_loadError!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: _loadCommunityInfo, child: Text('retry'.tr)),
                  ]),
                ))
              : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Theme(
          data: Theme.of(context).copyWith(inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.22),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.45))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.4)),
          )),
          child: Column(
          children: [
            TextField(
              controller: _nameController,
              maxLength: 60,
              decoration: InputDecoration(labelText: 'community_settings_name_label'.tr),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _sloganController,
              maxLength: 160,
              decoration: InputDecoration(labelText: 'community_settings_slogan_label'.tr),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descController,
              maxLength: 500,
              maxLines: 4,
              decoration: InputDecoration(labelText: 'community_settings_desc_label'.tr, alignLabelWithHint: true),
            ),
          ],
          ),
        ),
      ),
    );
  }
}

// 2. Centres d'intérêt
class CommunityInterestsScreen extends StatefulWidget {
  final String communityId;
  const CommunityInterestsScreen({super.key, required this.communityId});

  @override
  State<CommunityInterestsScreen> createState() => _CommunityInterestsScreenState();
}

class _CommunityInterestsScreenState extends State<CommunityInterestsScreen> {
  final CommunityService _service = Get.find<CommunityService>();
  bool _isLoading = true;
  String? _loadError;
  List<Map<String, dynamic>> _allInterests = [];
  Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _loadInterests();
  }

  Future<void> _loadInterests() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final all = await _service.getAvailableInterests();
      final current = await _service.getCommunityInterests(widget.communityId);
      _allInterests = all;
      _selectedIds = current.map((i) => i['id']?.toString() ?? '').where((id) => id.isNotEmpty).toSet();
    } catch (e) {
      debugPrint('[CommunityInterestsScreen] Failed to load interests: $e');
      _loadError = _service.localizedCommunityError(e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    if (_selectedIds.length > 10) {
      Get.snackbar('error'.tr, 'community_max_interests_error'.tr, snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _service.updateCommunityInterests(widget.communityId, _selectedIds.toList());
      Get.snackbar('community_save_success'.tr, '', snackPosition: SnackPosition.BOTTOM);
      Get.back();
    } catch (e) {
      Get.snackbar('community_save_error'.tr, _service.localizedCommunityError(e), snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('community_info_sub_interests'.tr),
        actions: [
          IconButton(icon: const Icon(Icons.check), onPressed: _isLoading ? null : _save),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_loadError!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: _loadInterests, child: Text('retry'.tr)),
                  ]),
                ))
              : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _allInterests.length,
              itemBuilder: (context, index) {
                final item = _allInterests[index];
                final id = item['id']?.toString() ?? '';
                final name = item['nom']?.toString() ?? item['name']?.toString() ?? '';
                final isSelected = _selectedIds.contains(id);
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3)),
                  ),
                  child: CheckboxListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  controlAffinity: ListTileControlAffinity.trailing,
                  title: Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  value: isSelected,
                  onChanged: (val) {
                    if (val == true && !_selectedIds.contains(id) && _selectedIds.length >= 10) {
                      Get.snackbar(
                        'error'.tr,
                        'community_max_interests_error'.tr,
                        snackPosition: SnackPosition.BOTTOM,
                      );
                      return;
                    }
                    setState(() {
                      if (val == true) {
                        _selectedIds.add(id);
                      } else {
                        _selectedIds.remove(id);
                      }
                    });
                  },
                  ),
                );
              },
            ),
    );
  }
}

// 3. Images
class CommunityImagesScreen extends StatefulWidget {
  final String communityId;
  const CommunityImagesScreen({super.key, required this.communityId});

  @override
  State<CommunityImagesScreen> createState() => _CommunityImagesScreenState();
}

class _CommunityImagesScreenState extends State<CommunityImagesScreen> {
  final CommunityService _service = Get.find<CommunityService>();
  final StorageRepository _storage = StorageRepository();
  final MediaService _mediaService = MediaService();
  bool _isLoading = true;
  String? _loadError;
  String? _currentAvatarUrl;
  String? _currentCoverUrl;

  @override
  void initState() {
    super.initState();
    _loadImages();
  }

  Future<void> _loadImages() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final snapshot = await _service.getCommunityManagementSettings(widget.communityId);
      final community = snapshot['community'] is Map
          ? Map<String, dynamic>.from(snapshot['community'] as Map)
          : <String, dynamic>{};
      if (mounted) {
        setState(() {
          _currentAvatarUrl = community['photo_profile']?.toString();
          _currentCoverUrl = community['photo_cover']?.toString();
        });
      }
    } catch (e) {
      debugPrint('[CommunityImagesScreen] Failed to load images: $e');
      _loadError = _service.localizedCommunityError(e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickAndUploadImage({required bool isProfile}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MediaGallerySheet(
        maxSelection: 1,
        onSelected: (files) {
          if (files.isNotEmpty) {
            _processImageFile(isProfile: isProfile, pickedFile: File(files.first.path));
          }
        },
      ),
    );
  }

  Future<void> _processImageFile({required bool isProfile, required File pickedFile}) async {
    setState(() => _isLoading = true);
    String? uploadedUrl;
    final previousUrl = ((isProfile ? _currentAvatarUrl : _currentCoverUrl) ?? '').trim();
    bool databaseUpdated = false;
    try {
      final file = await _mediaService.compressImage(pickedFile, quality: 75);
      if (file == null) {
        throw Exception('community_settings_image_compression_failed');
      }
      if (await file.length() > 5 * 1024 * 1024) {
        throw Exception('community_settings_image_too_large');
      }
      uploadedUrl = isProfile
          ? await _storage.uploadCommunityAvatar(file, communityId: widget.communityId)
          : await _storage.uploadCommunityBanner(file, communityId: widget.communityId);

      final snapshot = await _service.getCommunityManagementSettings(widget.communityId);
      final community = snapshot['community'] is Map
          ? Map<String, dynamic>.from(snapshot['community'] as Map)
          : <String, dynamic>{};
      await _service.updateCommunityInfo(
        id: widget.communityId,
        name: community['name']?.toString() ?? '',
        slogan: community['slogan']?.toString(),
        description: community['description']?.toString() ?? '',
        photoProfile: isProfile ? uploadedUrl : _currentAvatarUrl,
        photoCover: !isProfile ? uploadedUrl : _currentCoverUrl,
      );
      databaseUpdated = true;
      if (mounted) {
        setState(() {
          if (isProfile) _currentAvatarUrl = uploadedUrl;
          else _currentCoverUrl = uploadedUrl;
        });
      }

      // Ne supprimer l'ancienne image qu'après que l'update DB a réussi.
      // Les anciennes URL Supabase Storage sont ignorées par le repository R2.
      if (previousUrl.isNotEmpty && previousUrl != uploadedUrl) {
        try {
          await _storage.deleteProfileAvatar(previousUrl);
        } catch (cleanupError) {
          debugPrint('[CommunityImagesScreen] Old R2 image cleanup deferred: $cleanupError');
        }
      }
      Get.snackbar('community_save_success'.tr, '', snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      if (uploadedUrl != null && !databaseUpdated) {
        try { await _storage.deleteProfileAvatar(uploadedUrl); } catch (cleanupError) {
          debugPrint('[CommunityImagesScreen] Orphan R2 upload cleanup deferred: $cleanupError');
        }
      }
      debugPrint('[CommunityImagesScreen] Upload failed: $e');
      final rawError = e.toString().replaceFirst('Exception: ', '');
      final userMessage = rawError == 'community_settings_image_too_large' ||
              rawError == 'community_settings_image_compression_failed'
          ? rawError.tr
          : _service.localizedCommunityError(e);
      Get.snackbar('community_save_error'.tr, userMessage, snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('community_info_sub_images'.tr)),
      body: _isLoading && _currentAvatarUrl == null && _currentCoverUrl == null
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null && _currentAvatarUrl == null && _currentCoverUrl == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_off_outlined, size: 38, color: colorScheme.error),
                        const SizedBox(height: 12),
                        Text(_loadError!, textAlign: TextAlign.center, style: TextStyle(color: colorScheme.error)),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(onPressed: _loadImages, icon: const Icon(Icons.refresh), label: Text('retry'.tr)),
                      ],
                    ),
                  ),
                )
              : Stack(
                  children: [
                    ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                      children: [
                        Container(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'community_info_sub_images'.tr,
                                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: colorScheme.onSurface),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'community_settings_images_description'.tr,
                                style: TextStyle(fontSize: 13, height: 1.45, color: colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        _CommunityImageEditCard(
                          title: 'community_settings_cover_photo'.tr,
                          imageUrl: _currentCoverUrl,
                          isProfile: false,
                          isLoading: _isLoading,
                          onChange: () => _pickAndUploadImage(isProfile: false),
                        ),
                        const SizedBox(height: 24),
                        _CommunityImageEditCard(
                          title: 'community_settings_profile_photo'.tr,
                          imageUrl: _currentAvatarUrl,
                          isProfile: true,
                          isLoading: _isLoading,
                          onChange: () => _pickAndUploadImage(isProfile: true),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline_rounded, size: 17, color: colorScheme.onSurfaceVariant),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'community_settings_images_tip'.tr,
                                style: TextStyle(fontSize: 12, height: 1.4, color: colorScheme.onSurfaceVariant),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (_isLoading && (_currentAvatarUrl != null || _currentCoverUrl != null))
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: LinearProgressIndicator(minHeight: 2, color: colorScheme.primary),
                      ),
                  ],
                ),
    );
  }
}

// --- Écran G : Accès Details ---
class CommunityAccessDetailsScreen extends StatefulWidget {
  final String communityId;
  const CommunityAccessDetailsScreen({super.key, required this.communityId});

  @override
  State<CommunityAccessDetailsScreen> createState() => _CommunityAccessDetailsScreenState();
}

class _CommunityAccessDetailsScreenState extends State<CommunityAccessDetailsScreen> {
  final CommunityService _service = Get.find<CommunityService>();
  bool _isLoading = true;
  String? _loadError;
  String _visibility = 'public';
  bool _requireManualApproval = false;
  String _salonAllowedCreators = 'admins_moderators';
  bool _certificationRequired = false;
  bool _membersListVisible = true;
  bool _allowReports = true;
  bool _allowComments = true;
  bool _allowReactions = true;
  bool _countriesEnabled = false;
  bool _citiesEnabled = false;
  String? _genderRestriction;
  int? _ageMin;
  int? _ageMax;
  final TextEditingController _ageMinController = TextEditingController();
  final TextEditingController _ageMaxController = TextEditingController();
  List<Map<String, dynamic>> _countries = [];
  List<Map<String, dynamic>> _cities = [];
  Set<String> _allowedCountries = {};
  Set<String> _allowedCities = {};

  List<String> _toIdList(dynamic value) {
    if (value is! List) return <String>[];
    return value.map((item) => item.toString()).where((id) => id.isNotEmpty).toList();
  }

  Future<Set<String>?> _chooseLocations({
    required String title,
    required List<Map<String, dynamic>> items,
    required Set<String> selected,
  }) async {
    final searchController = TextEditingController();
    final draft = Set<String>.from(selected);
    final result = await Get.dialog<Set<String>>(
      StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final query = searchController.text.trim().toLowerCase();
          final filtered = items.where((item) {
            final name = item['nom']?.toString().toLowerCase() ?? '';
            final code = item['code_iso']?.toString().toLowerCase() ?? '';
            return query.isEmpty || name.contains(query) || code.contains(query);
          }).toList();
          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 420,
              height: MediaQuery.of(dialogContext).size.height * 0.55,
              child: Column(
                children: [
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'community_settings_location_search'.tr,
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(child: Text('community_settings_no_locations'.tr))
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final item = filtered[index];
                              final id = item['id']?.toString() ?? '';
                              final name = item['nom']?.toString() ?? '';
                              if (id.isEmpty) return const SizedBox.shrink();
                              return CheckboxListTile(
                                dense: true,
                                title: Text(name),
                                subtitle: item['code_iso'] == null ? null : Text(item['code_iso'].toString()),
                                value: draft.contains(id),
                                onChanged: (checked) => setDialogState(() {
                                  if (checked == true) {
                                    draft.add(id);
                                  } else {
                                    draft.remove(id);
                                  }
                                }),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Get.back(),
                child: Text('cancel'.tr),
              ),
              FilledButton(
                onPressed: () => Get.back(result: draft),
                child: Text('confirm'.tr),
              ),
            ],
          );
        },
      ),
    );
    searchController.dispose();
    return result;
  }

  @override
  void dispose() {
    _ageMinController.dispose();
    _ageMaxController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  Future<void> _loadRules() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final snapshot = await _service.getCommunityManagementSettings(widget.communityId);
      final community = snapshot['community'] is Map
          ? Map<String, dynamic>.from(snapshot['community'] as Map)
          : <String, dynamic>{};
      final access = snapshot['access_rules'] is Map
          ? Map<String, dynamic>.from(snapshot['access_rules'] as Map)
          : <String, dynamic>{};
      final settings = snapshot['settings'] is Map
          ? Map<String, dynamic>.from(snapshot['settings'] as Map)
          : <String, dynamic>{};
      _visibility = community['visibility']?.toString() ?? 'public';
      _requireManualApproval = community['require_manual_approval'] == true;
      try {
        _salonAllowedCreators = (await Supabase.instance.client.rpc('get_community_salon_creation_setting', params: {'p_community_id': widget.communityId})).toString();
      } catch (_) {
        _salonAllowedCreators = 'admins_moderators';
      }
      _membersListVisible = settings['members_list_visible'] != false;
      _allowReports = settings['allow_reports'] != false;
      _allowComments = settings['allow_comments'] != false;
      _allowReactions = settings['allow_reactions'] != false;
      _certificationRequired = access['certification_required'] == true;
      _countriesEnabled = access['countries_enabled'] == true;
      _citiesEnabled = access['cities_enabled'] == true;
      _allowedCountries = _toIdList(access['allowed_countries']).toSet();
      _allowedCities = _toIdList(access['allowed_cities']).toSet();
      _genderRestriction = access['gender_restriction']?.toString();
      _ageMin = (access['age_min'] as num?)?.toInt();
      _ageMax = (access['age_max'] as num?)?.toInt();
      _ageMinController.text = _ageMin?.toString() ?? '';
      _ageMaxController.text = _ageMax?.toString() ?? '';
      _countries = await _service.getAvailableCountries();
      _cities = await _service.getAvailableCities();
      final activeCountryIds = _countries.map((item) => item['id']?.toString() ?? '').toSet();
      final activeCityIds = _cities.map((item) => item['id']?.toString() ?? '').toSet();
      _allowedCountries.removeWhere((id) => !activeCountryIds.contains(id));
      _allowedCities.removeWhere((id) => !activeCityIds.contains(id));
      if (_countriesEnabled && _allowedCountries.isNotEmpty) {
        _allowedCities.removeWhere((cityId) {
          final matches = _cities.where((item) => item['id']?.toString() == cityId);
          final city = matches.isEmpty ? null : matches.first;
          final countryId = city?['country_id']?.toString();
          return countryId == null || !_allowedCountries.contains(countryId);
        });
      }
    } catch (e) {
      debugPrint('[CommunityAccessDetailsScreen] Failed to load settings: $e');
      _loadError = _service.localizedCommunityError(e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    final parsedAgeMin = int.tryParse(_ageMinController.text.trim());
    final parsedAgeMax = int.tryParse(_ageMaxController.text.trim());
    if ((_ageMinController.text.trim().isNotEmpty && parsedAgeMin == null) ||
        (_ageMaxController.text.trim().isNotEmpty && parsedAgeMax == null) ||
        (parsedAgeMin != null && (parsedAgeMin < 0 || parsedAgeMin > 120)) ||
        (parsedAgeMax != null && (parsedAgeMax < 0 || parsedAgeMax > 120)) ||
        (parsedAgeMin != null && parsedAgeMax != null && parsedAgeMin > parsedAgeMax)) {
      Get.snackbar('community_save_error'.tr, 'community_settings_age_invalid'.tr,
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    if (_countriesEnabled && _allowedCountries.isEmpty) {
      Get.snackbar('community_save_error'.tr, 'community_settings_select_at_least_one_country'.tr,
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    if (_citiesEnabled && _allowedCities.isEmpty) {
      Get.snackbar('community_save_error'.tr, 'community_settings_select_at_least_one_city'.tr,
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _service.updateCommunityManagementSettings(
        communityId: widget.communityId,
        visibility: _visibility,
        requireManualApproval: _requireManualApproval,
        membersListVisible: _membersListVisible,
        allowReports: _allowReports,
        allowComments: _allowComments,
        allowReactions: _allowReactions,
        certificationRequired: _certificationRequired,
        countriesEnabled: _countriesEnabled,
        allowedCountries: _allowedCountries.toList(),
        citiesEnabled: _citiesEnabled,
        allowedCities: _allowedCities.toList(),
        genderRestriction: _genderRestriction,
        ageMin: parsedAgeMin,
        ageMax: parsedAgeMax,
        clearAgeMin: _ageMinController.text.trim().isEmpty,
        clearAgeMax: _ageMaxController.text.trim().isEmpty,
        clearGender: _genderRestriction == null,
      );
      await Supabase.instance.client.rpc('set_community_salon_creation_setting', params: {
        'p_community_id': widget.communityId,
        'p_allowed_creators': _salonAllowedCreators,
      });
      Get.snackbar('community_save_success'.tr, '', snackPosition: SnackPosition.BOTTOM);
      Get.back();
    } catch (e) {
      debugPrint('[CommunityAccessDetailsScreen] Save failed: $e');
      Get.snackbar('community_save_error'.tr, _service.localizedCommunityError(e), snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('community_access_sub_access'.tr), actions: [IconButton(tooltip: 'community_save'.tr, onPressed: _isLoading ? null : _save, icon: const Icon(Icons.check_rounded)), const SizedBox(width: 4)]),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_loadError!, style: TextStyle(color: colorScheme.error)),
                      const SizedBox(height: 12),
                      ElevatedButton(onPressed: _loadRules, child: Text('retry'.tr)),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _SettingsSectionCard(
                        title: 'community_chat_group_creation_permissions'.tr,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Text(
                              'community_chat_group_creation_permissions_help'.tr,
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                            ),
                          ),
                          RadioListTile<String>(
                            value: 'admins_only',
                            groupValue: _salonAllowedCreators,
                            onChanged: (value) => setState(() => _salonAllowedCreators = value!),
                            title: Text('community_chat_group_creators_admins'.tr),
                          ),
                          RadioListTile<String>(
                            value: 'admins_moderators',
                            groupValue: _salonAllowedCreators,
                            onChanged: (value) => setState(() => _salonAllowedCreators = value!),
                            title: Text('community_chat_group_creators_admins_moderators'.tr),
                          ),
                          RadioListTile<String>(
                            value: 'all_members',
                            groupValue: _salonAllowedCreators,
                            onChanged: (value) => setState(() => _salonAllowedCreators = value!),
                            title: Text('community_chat_group_creators_all_members'.tr),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _SettingsSectionCard(
                        title: 'community_mgmt_access'.tr,
                        children: [
                          _IosSwitchTile(
                            title: Text('community_settings_manual_approval'.tr),
                            value: _requireManualApproval,
                            onChanged: (val) => setState(() => _requireManualApproval = val),
                          ),
                          _IosSwitchTile(
                            title: Text('community_settings_certification'.tr),
                            value: _certificationRequired,
                            onChanged: (val) => setState(() => _certificationRequired = val),
                          ),
                          _IosSwitchTile(
                            title: Text('community_settings_members_visible'.tr),
                            value: _membersListVisible,
                            onChanged: (val) => setState(() => _membersListVisible = val),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _SettingsSectionCard(
                        title: 'community_access_sub_posts'.tr,
                        children: [
                          _IosSwitchTile(
                            title: Text('community_settings_allow_reports'.tr),
                            value: _allowReports,
                            onChanged: (val) => setState(() => _allowReports = val),
                          ),
                          _IosSwitchTile(
                            title: Text('community_settings_allow_comments'.tr),
                            value: _allowComments,
                            onChanged: (val) => setState(() => _allowComments = val),
                          ),
                          _IosSwitchTile(
                            title: Text('community_settings_allow_reactions'.tr),
                            value: _allowReactions,
                            onChanged: (val) => setState(() => _allowReactions = val),
                          ),
                        ],
                      ),
                      _SettingsSectionCard(
                        title: 'community_settings_countries_enabled'.tr,
                        children: [
                      _IosSwitchTile(
                        title: Text('community_settings_countries_enabled'.tr),
                        subtitle: Text('community_settings_countries_help'.tr),
                        value: _countriesEnabled,
                        onChanged: (val) => setState(() {
                          _countriesEnabled = val;
                          if (val && _allowedCountries.isNotEmpty) {
                            _allowedCities.removeWhere((cityId) {
                              final matches = _cities.where((item) => item['id']?.toString() == cityId);
                              final city = matches.isEmpty ? null : matches.first;
                              final countryId = city?['country_id']?.toString();
                              return countryId == null || !_allowedCountries.contains(countryId);
                            });
                          }
                        }),
                      ),
                      ListTile(
                        enabled: _countriesEnabled,
                        title: Text('community_settings_choose_countries'.tr),
                        subtitle: Text('community_settings_selected_count'.trParams({'count': _allowedCountries.length.toString()})),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: !_countriesEnabled ? null : () async {
                          final selected = await _chooseLocations(
                            title: 'community_settings_choose_countries'.tr,
                            items: _countries,
                            selected: _allowedCountries,
                          );
                          if (selected != null && mounted) {
                            setState(() {
                              _allowedCountries = selected;
                              if (_countriesEnabled) {
                                _allowedCities.removeWhere((cityId) {
                                  final matches = _cities.where((item) => item['id']?.toString() == cityId);
                                  final city = matches.isEmpty ? null : matches.first;
                                  final countryId = city?['country_id']?.toString();
                                  return countryId == null || !_allowedCountries.contains(countryId);
                                });
                              }
                            });
                          }
                        },
                      ),
                      _IosSwitchTile(
                        title: Text('community_settings_cities_enabled'.tr),
                        subtitle: Text('community_settings_cities_help'.tr),
                        value: _citiesEnabled,
                        onChanged: (val) => setState(() => _citiesEnabled = val),
                      ),
                      ListTile(
                        enabled: _citiesEnabled,
                        title: Text('community_settings_choose_cities'.tr),
                        subtitle: Text('community_settings_selected_count'.trParams({'count': _allowedCities.length.toString()})),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: !_citiesEnabled ? null : () async {
                          final selected = await _chooseLocations(
                            title: 'community_settings_choose_cities'.tr,
                            items: _countriesEnabled && _allowedCountries.isNotEmpty
                                ? _cities.where((city) => _allowedCountries.contains(city['country_id']?.toString())).toList()
                                : _cities,
                            selected: _allowedCities,
                          );
                          if (selected != null && mounted) setState(() => _allowedCities = selected);
                        },
                      ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _genderRestriction ?? 'none',
                        decoration: InputDecoration(labelText: 'community_settings_gender_restriction'.tr),
                        items: [
                          DropdownMenuItem(value: 'none', child: Text('community_settings_no_gender_restriction'.tr)),
                          DropdownMenuItem(value: 'homme', child: Text('community_settings_gender_male'.tr)),
                          DropdownMenuItem(value: 'femme', child: Text('community_settings_gender_female'.tr)),
                        ],
                        onChanged: (value) => setState(() => _genderRestriction = value == null || value == 'none' ? null : value),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _ageMinController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(labelText: 'community_settings_age_min'.tr),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _ageMaxController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(labelText: 'community_settings_age_max'.tr),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _visibility,
                        decoration: InputDecoration(labelText: 'community_settings_visibility_label'.tr),
                        items: [
                          DropdownMenuItem(value: 'public', child: Text('community_settings_visibility_public'.tr)),
                          DropdownMenuItem(value: 'prive', child: Text('community_settings_visibility_private'.tr)),
                        ],
                        onChanged: (val) => setState(() => _visibility = val ?? 'public'),
                      ),
                    ],
                  ),
                ),
    );
  }
}

// --- Écran G2 : Règles ---
class CommunityRulesScreen extends StatefulWidget {
  final String communityId;
  const CommunityRulesScreen({super.key, required this.communityId});

  @override
  State<CommunityRulesScreen> createState() => _CommunityRulesScreenState();
}

class _CommunityRulesScreenState extends State<CommunityRulesScreen> {
  final CommunityService _service = Get.find<CommunityService>();
  bool _isLoading = true;
  List<Map<String, dynamic>> _rules = [];

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  String? _loadError;

  Future<void> _loadRules() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      _rules = await _service.getCommunityRules(widget.communityId);
    } catch (e) {
      debugPrint('[CommunityRulesScreen] Failed to load rules: $e');
      _loadError = _service.localizedCommunityError(e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showRuleDialog({Map<String, dynamic>? existingRule}) async {
    final textController = TextEditingController(text: existingRule?['text']?.toString() ?? '');
    final ruleId = existingRule?['id']?.toString() ?? const Uuid().v4();
    final orderIndex = existingRule?['order_index'] is int ? existingRule!['order_index'] as int : _rules.length;

    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: Text(existingRule == null ? 'community_rule_add'.tr : 'community_rule_edit'.tr),
        content: TextField(
          controller: textController,
          maxLines: 3,
          maxLength: 1000,
          decoration: InputDecoration(hintText: 'community_rule_hint'.tr),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(result: false), child: Text('cancel'.tr)),
          ElevatedButton(onPressed: () => Get.back(result: true), child: Text('confirm'.tr)),
        ],
      ),
    );
    final ruleText = textController.text.trim();
    textController.dispose();

    if (confirmed == true && ruleText.isEmpty) {
      Get.snackbar('community_save_error'.tr, 'community_rule_required'.tr,
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    if (confirmed == true && ruleText.isNotEmpty) {
      try {
        await _service.setCommunityRule(
          p_id: ruleId,
          p_community_id: widget.communityId,
          p_text: ruleText,
          p_order_index: orderIndex,
        );
        _rules = await _service.getCommunityRules(widget.communityId);
        if (mounted) setState(() {});
        Get.snackbar('community_save_success'.tr, '', snackPosition: SnackPosition.BOTTOM);
      } catch (e) {
        debugPrint('[CommunityRulesScreen] Save rule failed: $e');
        Get.snackbar('community_save_error'.tr, _service.localizedCommunityError(e), snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
      }
    }
  }

  Future<void> _deleteRule(String ruleId) async {
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: Text('community_rule_delete_title'.tr),
        content: Text('community_rule_delete_msg'.tr),
        actions: [
          TextButton(onPressed: () => Get.back(result: false), child: Text('cancel'.tr)),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), onPressed: () => Get.back(result: true), child: Text('confirm'.tr)),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _service.deleteCommunityRule(ruleId);
        _rules.removeWhere((r) => r['id']?.toString() == ruleId);
        setState(() {});
        Get.snackbar('community_save_success'.tr, '', snackPosition: SnackPosition.BOTTOM);
      } catch (e) {
        Get.snackbar('community_save_error'.tr, _service.localizedCommunityError(e), snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('community_access_sub_rules'.tr)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_loadError!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: _loadRules, child: Text('retry'.tr)),
                  ]),
                ))
              : _rules.isEmpty
                  ? Center(child: Text('community_rules_empty'.tr, style: TextStyle(color: colorScheme.onSurfaceVariant)))
                  : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _rules.length,
                  itemBuilder: (context, index) {
                    final rule = _rules[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        title: Text(rule['text']?.toString() ?? ''),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _showRuleDialog(existingRule: rule)),
                            IconButton(icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red), onPressed: () => _deleteRule(rule['id']?.toString() ?? '')),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showRuleDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}

// --- Écran F : Publications ---
class CommunityPostSettingsScreen extends StatefulWidget {
  final String communityId;
  const CommunityPostSettingsScreen({super.key, required this.communityId});

  @override
  State<CommunityPostSettingsScreen> createState() => _CommunityPostSettingsScreenState();
}

class _CommunityPostSettingsScreenState extends State<CommunityPostSettingsScreen> {
  final CommunityService _service = Get.find<CommunityService>();
  bool _isLoading = true;
  String? _loadError;
  bool _postsRequireApproval = false;
  String _postPermission = 'everyone';

  @override
  void initState() {
    super.initState();
    _loadPostSettings();
  }

  Future<void> _loadPostSettings() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final snapshot = await _service.getCommunityManagementSettings(widget.communityId);
      final settings = snapshot['settings'] is Map
          ? Map<String, dynamic>.from(snapshot['settings'] as Map)
          : <String, dynamic>{};
      _postsRequireApproval = settings['posts_require_approval'] == true;
      final permission = settings['post_permission']?.toString() ?? 'everyone';
      _postPermission = const {'everyone', 'admins_and_moderators', 'nobody'}.contains(permission)
          ? permission
          : 'everyone';
    } catch (e) {
      debugPrint('[CommunityPostSettingsScreen] Failed to load settings: $e');
      _loadError = _service.localizedCommunityError(e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _isLoading = true);
    try {
      await _service.updateCommunityPostSettings(
        communityId: widget.communityId,
        postPermission: _postPermission,
        postsRequireApproval: _postsRequireApproval,
      );
      Get.snackbar('community_save_success'.tr, '', snackPosition: SnackPosition.BOTTOM);
      Get.back();
    } catch (e) {
      debugPrint('[CommunityPostSettingsScreen] Save failed: $e');
      Get.snackbar('community_save_error'.tr, _service.localizedCommunityError(e), snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('community_access_sub_posts'.tr), actions: [IconButton(tooltip: 'community_save'.tr, onPressed: _isLoading ? null : _save, icon: const Icon(Icons.check_rounded)), const SizedBox(width: 4)]),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_loadError!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: _loadPostSettings, child: Text('retry'.tr)),
                  ]),
                ))
              : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _SettingsSectionCard(
              title: 'community_access_sub_posts'.tr,
              children: [
                _IosSwitchTile(
                  title: Text('community_settings_posts_approval'.tr),
                  value: _postsRequireApproval,
                  onChanged: (val) => setState(() => _postsRequireApproval = val),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: DropdownButtonFormField<String>(
                    value: _postPermission,
                    decoration: InputDecoration(labelText: 'community_post_permissions_label'.tr),
                    items: [
                      DropdownMenuItem(value: 'everyone', child: Text('community_post_permission_everyone'.tr)),
                      DropdownMenuItem(value: 'admins_and_moderators', child: Text('community_post_permission_admins'.tr)),
                      DropdownMenuItem(value: 'nobody', child: Text('community_post_permission_nobody'.tr)),
                    ],
                    onChanged: (val) => setState(() => _postPermission = val ?? 'everyone'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


class EntityCertificationManagementScreen extends StatefulWidget {
  final String entityType;
  final String entityId;
  final String entityName;

  const EntityCertificationManagementScreen({
    super.key,
    required this.entityType,
    required this.entityId,
    required this.entityName,
  });

  @override
  State<EntityCertificationManagementScreen> createState() => _EntityCertificationManagementScreenState();
}

class _EntityCertificationManagementScreenState extends State<EntityCertificationManagementScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  Map<String, dynamic> _status = {};
  Map<String, dynamic> _entitlements = {};

  bool get _isEvent => widget.entityType == 'event';
  bool get _isCertified => _status['entity_certified'] == true;

  // Normalize JSON values returned by Postgres RPCs. Older deployments may
  // return numeric counters as strings, and may expose legacy key aliases.
  int _intFor(List<String> keys) {
    for (final key in keys) {
      final value = _entitlements[key];
      if (value is num) return value.toInt();
      if (value is String) {
        final parsed = int.tryParse(value.trim());
        if (parsed != null) return parsed;
      }
    }
    return 0;
  }

  String _formatDate(dynamic value) {
    if (value == null || value.toString().trim().isEmpty) return '';
    final parsed = DateTime.tryParse(value.toString());
    if (parsed == null) return value.toString();
    return DateFormat('dd/MM/yyyy HH:mm').format(parsed.toLocal());
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final client = Supabase.instance.client;
      final status = await client.rpc('scrole_get_entity_certification_status', params: {
        'p_entity_type': widget.entityType,
        'p_entity_id': widget.entityId,
      });
      final entitlements = await client.rpc('scrole_get_my_subscription_entitlements');
      if (status is! Map || entitlements is! Map) throw Exception('entity_cert_error_invalid_response'.tr);
      if (status['is_owner'] != true) throw Exception('entity_cert_error_owner_only'.tr);
      if (!mounted) return;
      setState(() {
        _status = Map<String, dynamic>.from(status);
        _entitlements = Map<String, dynamic>.from(entitlements);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  Future<void> _activateIncluded() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final client = Supabase.instance.client;
      await client.rpc('scrole_certify_owned_entity_with_subscription', params: {
        'p_entity_type': widget.entityType,
        'p_entity_id': widget.entityId,
      });
      if (!mounted) return;
      Get.snackbar('entity_cert_success_title'.tr, 'entity_cert_success_message'.trParams({'name': widget.entityName}),
        snackPosition: SnackPosition.BOTTOM);
      await _load();
    } catch (e) {
      if (!mounted) return;
      final message = e.toString();
      Get.snackbar('entity_cert_failure_title'.tr, _friendlyError(message),
        snackPosition: SnackPosition.BOTTOM, backgroundColor: Theme.of(context).colorScheme.error,
        colorText: Theme.of(context).colorScheme.onError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendlyError(String message) {
    if (message.contains('active_profile_certification_required')) return 'entity_cert_error_profile_required'.tr;
    if (message.contains('active_pro_or_premium_profile_certification_required') || message.contains('active_pro_or_premium_subscription_required')) return 'entity_cert_error_pro_premium_required'.tr;
    if (message.contains('quota_exceeded')) return 'entity_cert_error_quota_exceeded'.tr;
    if (message.contains('entity_not_owned_by_current_user')) return 'entity_cert_error_owner_only'.tr;
    return message.replaceFirst('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final remaining = _intFor(_isEvent
        ? const ['event_remaining', 'events_remaining', 'remaining_events']
        : const ['community_remaining', 'communities_remaining', 'remaining_communities']);
    final quota = _intFor(_isEvent
        ? const ['event_quota', 'events_quota', 'quota_events']
        : const ['community_quota', 'communities_quota', 'quota_communities']);
    final used = _intFor(_isEvent
        ? const ['event_used', 'events_used', 'used_events']
        : const ['community_used', 'communities_used', 'used_communities']);
    final planCode = (_entitlements['plan_code'] ??
        _entitlements['plan'] ??
        _entitlements['subscription_plan'] ??
        '').toString().trim();
    final basis = (_entitlements['entitlement_basis'] ??
        _entitlements['basis'] ??
        '').toString().trim();
    final endsAt = _formatDate(_entitlements['ends_at'] ??
        _entitlements['valid_until'] ??
        _entitlements['expires_at']);
    return Scaffold(
      appBar: AppBar(title: Text((_isEvent ? 'entity_cert_event_label' : 'entity_cert_community_title').tr)),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
          ? Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.shield_outlined, size: 42),
                const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: _load, child: Text('retry'.tr)),
              ]),
            ))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(20), children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _isCertified ? colors.primaryContainer : colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(_isCertified ? Icons.verified_rounded : Icons.workspace_premium_outlined,
                      size: 36, color: _isCertified ? colors.primary : colors.onSurfaceVariant),
                    const SizedBox(height: 12),
                    Text(widget.entityName, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(_isCertified ? 'entity_cert_status_active'.tr : 'entity_cert_status_inactive'.tr,
                      style: Theme.of(context).textTheme.bodyLarge),
                    if (_status['source'] != null) ...[
                      const SizedBox(height: 6),
                      Text('${'entity_cert_source'.tr}: ${_status['source']}', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ]),
                ),
                const SizedBox(height: 18),
                Text('entity_cert_included_rights'.tr, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text((_entitlements['active'] == true)
                        ? 'entity_cert_plan_active'.trParams({
                            'plan': planCode.isEmpty ? '—' : planCode.toUpperCase(),
                            'basis': basis == 'profile_certification'
                                ? 'entity_cert_basis_profile'.tr
                                : 'entity_cert_basis_subscription'.tr,
                          })
                        : 'entity_cert_no_active_entitlement'.tr),
                      const SizedBox(height: 10),
                      Text('entity_cert_quota_summary'.trParams({'used': '$used', 'quota': '$quota', 'remaining': '$remaining'})),
                      if (endsAt.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text('${'entity_cert_subscription_ends'.tr}: $endsAt', style: Theme.of(context).textTheme.bodySmall),
                      ],
                      const SizedBox(height: 14),
                      SizedBox(width: double.infinity, child: FilledButton.icon(
                        onPressed: (_isCertified || remaining <= 0 || _entitlements['active'] != true || _busy) ? null : _activateIncluded,
                        icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.verified_user_outlined),
                        label: Text(_isCertified ? 'entity_cert_already_certified'.tr : 'entity_cert_use_included'.tr),
                      )),
                    ]),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.shopping_bag_outlined, size: 30),
                      const SizedBox(height: 8),
                      Text('entity_cert_buy_title'.tr, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text('entity_cert_purchase_payment_notice'.tr),
                      const SizedBox(height: 12),
                      SizedBox(width: double.infinity, child: OutlinedButton(
                        onPressed: () => Get.to(() => EntityCertificationPurchaseScreen(
                          entityType: widget.entityType,
                          entityId: widget.entityId,
                          entityName: widget.entityName,
                        )),
                        child: Text('entity_cert_view_offers'.tr),
                      )),
                    ]),
                  ),
                ),
              ]),
            ),
    );
  }
}


/// Destination dédiée à l'achat individuel d'une certification d'entité.
/// Elle ne redirige jamais vers les certifications de profil.
class EntityCertificationPurchaseScreen extends StatefulWidget {
  const EntityCertificationPurchaseScreen({
    super.key,
    required this.entityType,
    required this.entityId,
    required this.entityName,
  });

  final String entityType;
  final String entityId;
  final String entityName;

  @override
  State<EntityCertificationPurchaseScreen> createState() => _EntityCertificationPurchaseScreenState();
}

class _EntityCertificationPurchaseScreenState extends State<EntityCertificationPurchaseScreen> {
  bool get _isEvent => widget.entityType == 'event';

  bool _loadingPrice = true;
  String? _countryName;
  String? _priceError;
  double? _amount;
  String _currency = '';
  String _pricingGroup = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadingPrice && _amount == null && _priceError == null) _loadRegionalPrice();
  }

  Future<void> _loadRegionalPrice() async {
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) throw Exception('entity_cert_price_auth'.tr);
      final profile = await client.from('user_profiles').select('country_id').eq('user_id', user.id).limit(1).maybeSingle();
      final countryId = profile?['country_id']?.toString();
      if (countryId == null || countryId.isEmpty) throw Exception('entity_cert_price_country_missing'.tr);
      // Le pays peut être lié à plusieurs groupes de prix de certification
      // (profil, événement, communauté). Ne pas choisir arbitrairement une ligne
      // avec limit(1), car cela peut classer l'Allemagne comme « Afrique ».
      final country = await client
          .from('countries')
          .select('nom,code_iso,default_currency_code')
          .eq('id', countryId)
          .maybeSingle();
      final countryName = country?['nom']?.toString();
      final countryCode = (country?['code_iso']?.toString() ?? '').toUpperCase();

      const centralAfricaCodes = {
        'CM', 'CF', 'TD', 'CG', 'CD', 'GQ', 'GA', 'ST',
      };
      const africaCodes = {
        'DZ', 'AO', 'BJ', 'BW', 'BF', 'BI', 'CV', 'CM', 'CF', 'TD',
        'KM', 'CG', 'CD', 'CI', 'DJ', 'EG', 'GQ', 'ER', 'SZ', 'ET',
        'GA', 'GM', 'GH', 'GN', 'GW', 'KE', 'LS', 'LR', 'LY', 'MG',
        'MW', 'ML', 'MR', 'MU', 'MA', 'MZ', 'NA', 'NE', 'NG', 'RW',
        'ST', 'SN', 'SC', 'SL', 'SO', 'ZA', 'SS', 'SD', 'TZ', 'TG',
        'TN', 'UG', 'ZM', 'ZW',
      };
      final priceGroup = centralAfricaCodes.contains(countryCode)
          ? 'Afrique centrale'
          : (africaCodes.contains(countryCode) ? 'Afrique' : 'Hors Afrique');
      // Le schéma de tarifs actuellement déployé utilise les groupes régionaux
      // simples (sans préfixe event:). Le type d'entité ne doit donc pas modifier
      // la clé tant qu'une colonne entity_type n'existe pas dans cette table.
      final price = await client.from('scrole_entity_certification_prices')
          .select('amount,currency,pricing_group')
          .eq('pricing_group', priceGroup)
          .eq('active', true)
          .maybeSingle();
      if (price == null) throw Exception('entity_cert_price_unavailable'.tr);
      if (!mounted) return;
      setState(() {
        _countryName = countryName;
        _amount = (price['amount'] as num).toDouble();
        _currency = price['currency'].toString();
        _pricingGroup = priceGroup;
        _loadingPrice = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _priceError = e.toString().replaceFirst('Exception: ', ''); _loadingPrice = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final kind = _isEvent ? 'entity_cert_event_label'.tr : 'entity_cert_community_label'.tr;
    final locale = Localizations.localeOf(context).toString();
    final formattedPrice = _amount == null ? '' : NumberFormat.currency(
      locale: locale, name: _currency, decimalDigits: _currency == 'XAF' ? 0 : 2,
    ).format(_amount);
    return Scaffold(
      appBar: AppBar(title: Text(_isEvent ? 'entity_cert_event_title'.tr : 'entity_cert_community_title'.tr)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: colors.outlineVariant.withValues(alpha: .6)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 54, height: 54,
                decoration: BoxDecoration(color: colors.primaryContainer, borderRadius: BorderRadius.circular(18)),
                child: Icon(_isEvent ? Icons.event_available_rounded : Icons.groups_rounded, color: colors.onPrimaryContainer, size: 28),
              ),
              const SizedBox(height: 18),
              Text(widget.entityName, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -.5)),
              const SizedBox(height: 8),
              Text('entity_cert_individual_label'.trParams({'kind': kind}),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: colors.primary, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Text('entity_cert_individual_desc'.trParams({'kind': kind}),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.55)),
            ]),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: colors.outlineVariant.withValues(alpha: .6))),
            child: _loadingPrice
              ? const Center(child: Padding(padding: EdgeInsets.all(18), child: CircularProgressIndicator()))
              : _priceError != null
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('entity_cert_price_unavailable_title'.tr, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(_priceError!, style: Theme.of(context).textTheme.bodyMedium),
                    TextButton.icon(onPressed: () { setState(() { _loadingPrice = true; _priceError = null; }); _loadRegionalPrice(); }, icon: const Icon(Icons.refresh), label: Text('retry'.tr)),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('entity_cert_price_title'.tr, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('entity_cert_price_region'.trParams({'region': _pricingGroup, 'country': _countryName ?? ''}), style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 14),
                    Text(formattedPrice, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: colors.primary)),
                    const SizedBox(height: 8),
                    Text('entity_cert_one_price'.tr, style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: colors.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(Icons.info_outline, color: colors.primary),
                        const SizedBox(width: 10),
                        Expanded(child: Text('entity_cert_payment_not_ready'.tr, style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.45))),
                      ]),
                    ),
                  ]),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(onPressed: () => Get.back(), icon: const Icon(Icons.arrow_back_rounded), label: Text('entity_cert_back'.tr)),
        ],
      ),
    );
  }
}
