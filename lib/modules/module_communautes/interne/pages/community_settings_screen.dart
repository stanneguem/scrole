import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:scrole/modules/module_communautes/centre/services/community_service.dart';
import 'package:scrole/shared/controllers/search_controller.dart';
import 'community_members_screen.dart';
import 'excluded_members_screen.dart';
import 'community_settings_main_screen.dart';

class CommunitySettingsScreen extends StatefulWidget {
  final String communityId;
  final String communityName;
  final String? communityAvatar;
  final String? communitySlogan;

  const CommunitySettingsScreen({
    super.key,
    required this.communityId,
    required this.communityName,
    this.communityAvatar,
    this.communitySlogan,
  });

  @override
  State<CommunitySettingsScreen> createState() => _CommunitySettingsScreenState();
}

class _CommunitySettingsScreenState extends State<CommunitySettingsScreen> {
  final CommunityService _service = Get.find<CommunityService>();
  final TextEditingController _searchController = TextEditingController();
  bool _isLoadingRole = true;
  String _role = 'member';
  String _searchQuery = '';
  String? _avatarUrl;
  String? _coverUrl;
  String? _slogan;

  @override
  void initState() {
    super.initState();
    _loadRoleAndInfo();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRoleAndInfo() async {
    try {
      final role = await _service.getCurrentUserRole(widget.communityId);
      final comm = await _service.getCommunityById(widget.communityId);
      if (mounted) {
        setState(() {
          _role = role;
          _avatarUrl = comm?.avatarUrl ?? widget.communityAvatar;
          _coverUrl = comm?.bannerUrl;
          _slogan = widget.communitySlogan ?? comm?.description;
          _isLoadingRole = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingRole = false);
    }
  }

  bool get _isAdminOrModerator => _role == 'admin' || _role == 'moderator';
  bool get _isAdmin => _role == 'admin';

  Future<void> _showLeaveOptions() async {
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'community_leave_options_title'.tr,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'community_leave_confirmation_message'.tr,
              style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () {
                Get.back();
                _reportAndLeave();
              },
              child: Text('community_leave_and_report_action'.tr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () {
                Get.back();
                _executeLeave();
              },
              child: Text('community_leave_only_action'.tr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Get.back(),
              child: Text('cancel'.tr, style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          ],
        ),
      ),
      isScrollControlled: true,
    );
  }

  Future<void> _executeLeave() async {
    try {
      final result = await _service.leaveCommunity(widget.communityId);
      try {
        if (Get.isRegistered<AppSearchController>()) {
          Get.find<AppSearchController>().invalidateSearchCache();
        }
      } catch (_) {}
      Get.until((route) => route.isFirst);
      final action = result['action']?.toString();
      final successMessage = action == 'deleted'
          ? 'community_deleted_success'.tr
          : action == 'transferred'
              ? 'community_ownership_transferred_success'.tr
              : 'community_leave_success_msg'.tr;
      Get.snackbar(
        'community_leave_success_title'.tr,
        successMessage,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      String msg = e.toString().replaceFirst('Exception: ', '').tr;
      Get.snackbar(
        'community_leave_title'.tr,
        msg,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  Future<void> _reportAndLeave() async {
    _reportCommunity(onReportSuccess: _executeLeave);
  }

  Future<void> _reportCommunity({VoidCallback? onReportSuccess}) async {
    List<Map<String, dynamic>> reasons = [];
    bool isLoadingReasons = true;
    String? selectedReasonId;
    String? selectedReasonCode;
    bool isSubmitting = false;
    final descriptionController = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setStateSB) {
          if (isLoadingReasons) {
            _service.getSignalementRaisons().then((res) {
              if (mounted) setStateSB(() {
                reasons = res;
                isLoadingReasons = false;
                if (reasons.isNotEmpty) {
                  selectedReasonId = reasons.first['id']?.toString();
                  selectedReasonCode = reasons.first['code']?.toString() ?? reasons.first['nom']?.toString();
                }
              });
            }).catchError((_) {
              if (mounted) setStateSB(() => isLoadingReasons = false);
            });
          }
          final colors = Theme.of(context).colorScheme;
          final isOther = ['autre', 'other'].contains(selectedReasonCode?.toLowerCase());
          final desc = descriptionController.text.trim();
          final valid = selectedReasonId != null && (!isOther || desc.isNotEmpty);
          return Container(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            decoration: BoxDecoration(color: colors.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
            child: SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .86),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const SizedBox(height: 10),
                  Container(width: 38, height: 4, decoration: BoxDecoration(color: colors.onSurfaceVariant.withValues(alpha: .35), borderRadius: BorderRadius.circular(4))),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                    child: Row(children: [
                      Container(width: 40, height: 40, decoration: BoxDecoration(color: colors.errorContainer, borderRadius: BorderRadius.circular(14)), child: Icon(Icons.flag_rounded, color: colors.onErrorContainer)),
                      const SizedBox(width: 12),
                      Expanded(child: Text('community_report_title'.tr, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                      TextButton(onPressed: isSubmitting ? null : () => Navigator.of(sheetContext).pop(), child: Text('cancel'.tr)),
                      TextButton(
                        onPressed: isSubmitting || !valid || isLoadingReasons ? null : () async {
                          setStateSB(() => isSubmitting = true);
                          try {
                            await _service.reportCommunity(communityId: widget.communityId, reasonId: selectedReasonId!, description: descriptionController.text.trim());
                            if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                            Get.snackbar('community_report_success_title'.tr, 'community_report_success_msg'.tr, snackPosition: SnackPosition.BOTTOM);
                            onReportSuccess?.call();
                          } catch (e) {
                            setStateSB(() => isSubmitting = false);
                            Get.snackbar('community_report_title'.tr, e.toString().replaceFirst('Exception: ', '').tr, snackPosition: SnackPosition.BOTTOM, backgroundColor: colors.error, colorText: colors.onError);
                          }
                        },
                        child: isSubmitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Text('community_report_submit'.tr, style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ]),
                  ),
                  Flexible(child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('community_report_safety_intro'.tr, style: TextStyle(fontSize: 13, height: 1.4, color: colors.onSurfaceVariant)),
                      const SizedBox(height: 20),
                      Text('community_report_reason_label'.tr, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 8),
                      if (isLoadingReasons) const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(strokeWidth: 2)))
                      else if (reasons.isEmpty) Text('community_report_reasons_unavailable'.tr, style: TextStyle(color: colors.error, fontSize: 13))
                      else DropdownButtonFormField<String>(
                        isExpanded: true, value: selectedReasonId,
                        decoration: InputDecoration(hintText: 'community_report_reason_hint'.tr, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)), contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14)),
                        items: reasons.map((r) {
                          final id = r['id']?.toString() ?? '';
                          final code = r['code']?.toString() ?? r['nom']?.toString() ?? 'Motif';
                          String label = code;
                          if (code == 'harcelement') label = 'community_report_reason_harassment'.tr;
                          else if (code == 'dangereux_risqué' || code == 'dangereux_riske') label = 'community_report_reason_dangerous'.tr;
                          else if (code == 'copie_contrefacon') label = 'community_report_reason_copy'.tr;
                          else if (['autre', 'other'].contains(code.toLowerCase())) label = 'community_report_reason_other'.tr;
                          return DropdownMenuItem<String>(value: id, child: Text(label, style: const TextStyle(fontSize: 14)));
                        }).toList(),
                        onChanged: isSubmitting ? null : (value) => setStateSB(() {
                          selectedReasonId = value;
                          final match = reasons.firstWhereOrNull((r) => r['id']?.toString() == value);
                          selectedReasonCode = match?['code']?.toString() ?? match?['nom']?.toString();
                        }),
                      ),
                      const SizedBox(height: 20),
                      Text('community_report_description_label'.tr, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 8),
                      TextField(controller: descriptionController, maxLength: 1000, minLines: 3, maxLines: 5, onChanged: (_) => setStateSB(() {}), decoration: InputDecoration(hintText: 'community_report_description_hint'.tr, alignLabelWithHint: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)))),
                      if (isOther && desc.isEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('community_report_other_desc_required'.tr, style: TextStyle(color: colors.error, fontSize: 12))),
                    ]),
                  )),
                ]),
              ),
            ),
          );
        },
      ),
    );
    descriptionController.dispose();
  }


  Future<void> _openCommunityImages() async {
    if (!_isAdmin) return;
    await Get.to(() => CommunityImagesScreen(communityId: widget.communityId));
    if (!mounted) return;
    try {
      final comm = await _service.getCommunityById(widget.communityId);
      if (mounted && comm != null) {
        setState(() {
          _avatarUrl = comm.avatarUrl ?? _avatarUrl;
          _coverUrl = comm.bannerUrl ?? _coverUrl;
        });
      }
    } catch (_) {}
  }

  Widget _communityHero(ColorScheme colors) {
    final hasCover = _coverUrl != null && _coverUrl!.trim().isNotEmpty;
    final hasAvatar = _avatarUrl != null && _avatarUrl!.trim().isNotEmpty;
    return SizedBox(
      height: 258,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            bottom: 34,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(26)),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasCover)
                    Image.network(_coverUrl!, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _coverPlaceholder(colors))
                  else
                    _coverPlaceholder(colors),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(.28),
                          Colors.transparent,
                          Colors.black.withOpacity(.78),
                        ],
                        stops: const [0, .38, 1],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    left: 12,
                    child: _heroButton(Icons.arrow_back_rounded, () => Navigator.of(context).pop()),
                  ),
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 48,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.communityName,
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 23,
                            fontWeight: FontWeight.w800, letterSpacing: -.4)),
                        if ((_slogan ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(_slogan!, maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.white.withOpacity(.9), fontSize: 13, height: 1.3)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 20,
            bottom: 0,
            child: Stack(
              children: [
                Container(
                  width: 82,
                  height: 82,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(.16), blurRadius: 12, offset: const Offset(0, 3))],
                  ),
                  child: ClipOval(
                    child: hasAvatar
                      ? Image.network(_avatarUrl!, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _avatarPlaceholder(colors))
                      : _avatarPlaceholder(colors),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: 20,
            bottom: 9,
            child: Row(
              children: [
                Icon(Icons.groups_rounded, size: 16, color: colors.onSurfaceVariant),
                const SizedBox(width: 5),
                Text('community_members_title'.tr,
                  style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroButton(IconData icon, VoidCallback onTap) => Material(
    color: Colors.black.withOpacity(.42),
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: SizedBox(width: 42, height: 42,
        child: Icon(icon, color: Colors.white, size: 20)),
    ),
  );

  Widget _coverPlaceholder(ColorScheme colors) => Container(
    color: colors.primaryContainer,
    child: Center(child: Icon(Icons.groups_rounded, size: 54, color: colors.onPrimaryContainer.withOpacity(.55))),
  );

  Widget _avatarPlaceholder(ColorScheme colors) => Container(
    color: colors.primaryContainer,
    alignment: Alignment.center,
    child: Text(widget.communityName.isNotEmpty ? widget.communityName[0].toUpperCase() : 'C',
      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: colors.onPrimaryContainer)),
  );

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: _isLoadingRole
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              children: [
                // --- En-tête visuel de la communauté ---
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: _communityHero(colorScheme),
                ),
                const SizedBox(height: 20),

                // --- Section A : GESTION (Admins / Modérateurs) ---
                if (_isAdminOrModerator) ...[
                  _SettingsCard(
                    children: [
                      _SettingsMenuTile(
                        icon: Icons.admin_panel_settings_outlined,
                        iconColor: Colors.deepOrange,
                        title: 'community_management_title'.tr,
                        subtitle: 'community_management_subtitle'.tr,
                        onTap: () {
                          Get.to(() => CommunitySettingsMainScreen(
                                communityId: widget.communityId,
                                communityName: widget.communityName,
                                communityAvatar: _avatarUrl,
                                communitySlogan: _slogan,
                              ));
                        },
                      ),
                      if (_isAdmin) ...[
                        const Divider(height: 1, indent: 68, endIndent: 16),
                        _SettingsMenuTile(
                          icon: Icons.block_outlined,
                          iconColor: Colors.redAccent,
                          title: 'excluded_members_title'.tr,
                          subtitle: 'excluded_members_subtitle'.tr,
                          onTap: () {
                            Get.to(() => ExcludedMembersScreen(communityId: widget.communityId));
                          },
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // --- Section B : COMMUNAUTÉ ---
                _SettingsCard(
                  children: [
                    _SettingsMenuTile(
                      icon: Icons.group_outlined,
                      iconColor: colorScheme.primary,
                      title: 'community_members_title'.tr,
                      subtitle: 'community_members_subtitle'.tr,
                      onTap: () {
                        Get.to(() => CommunityMembersScreen(
                              communityId: widget.communityId,
                              communityName: widget.communityName,
                              isAdmin: _isAdmin,
                            ));
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // --- Section C : ASSISTANCE & SÉCURITÉ ---
                _SettingsCard(
                  children: [
                    _SettingsMenuTile(
                      icon: Icons.flag_outlined,
                      iconColor: Colors.amber.shade800,
                      title: 'community_report_title'.tr,
                      subtitle: 'community_report_community_subtitle'.tr,
                      onTap: () => _reportCommunity(),
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                // --- Section D : Quitter la communauté ---
                Center(
                  child: TextButton.icon(
                    onPressed: _showLeaveOptions,
                    icon: const Icon(Icons.exit_to_app_rounded, color: Colors.redAccent, size: 20),
                    label: Text(
                      'community_leave_only_action'.tr,
                      style: TextStyle(color: Colors.redAccent, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: children,
        ),
      ),
    );
  }
}

class _SettingsMenuTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsMenuTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: iconColor, size: 22),
      ),
      title: Text(
        title,
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
      ),
      trailing: Icon(Icons.chevron_right_rounded, size: 20, color: colorScheme.outline),
    );
  }
}
