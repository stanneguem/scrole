import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:scrole/app/routes/app_pages.dart';
import 'package:scrole/modules/module_communautes/centre/services/community_service.dart';
import 'package:scrole/shared/widgets/user_identity_row.dart';
import 'package:scrole/shared/widgets/user_certified_badge.dart';

class CommunityMembersScreen extends StatefulWidget {
  final String communityId;
  final String communityName;
  final bool isAdmin;

  const CommunityMembersScreen({
    super.key,
    required this.communityId,
    required this.communityName,
    required this.isAdmin,
  });

  @override
  State<CommunityMembersScreen> createState() => _CommunityMembersScreenState();
}

String _formatReputation(num value) {
  final rounded = (value.clamp(0, 5) * 10).round() / 10;
  return rounded.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
}

class _CommunityMembersScreenState extends State<CommunityMembersScreen> {
  final CommunityService _service = Get.find<CommunityService>();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _searchDebounce;

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _isStaff = false;
  bool _isAdminUser = false;
  String _userRole = 'member';
  List<Map<String, dynamic>> _members = [];
  final Map<String, double> _communityReputations = {};
  String? _nextCursor;
  bool _hasMore = false;
  String _searchQuery = '';
  String? _errorMessage;
  String? _errorCategory;

  @override
  void initState() {
    super.initState();
    _isAdminUser = widget.isAdmin;
    _scrollController.addListener(_onScroll);
    _checkStaffAndLoad();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _hasMore) {
        _loadMembers();
      }
    }
  }

  Future<void> _checkStaffAndLoad() async {
    bool isStaff = false;
    bool isAdmin = widget.isAdmin;
    String role = 'member';

    try {
      final staffRpc = await _service.isCommunityStaffRpc(widget.communityId);
      role = await _service.getCurrentUserRole(widget.communityId);
      isStaff = staffRpc || widget.isAdmin || role == 'admin' || role == 'moderator';
      isAdmin = widget.isAdmin || role == 'admin';
    } catch (e) {
      debugPrint('[CommunityMembersScreen] Error checking staff status: $e');
      // On error during staff check, never assume user is staff!
      isStaff = widget.isAdmin;
      isAdmin = widget.isAdmin;
    }

    if (mounted) {
      setState(() {
        _isStaff = isStaff;
        _isAdminUser = isAdmin;
        _userRole = role;
      });
    }

    await _loadMembers(refresh: true);
  }

  Future<void> _loadMembers({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _errorCategory = null;
        _nextCursor = null;
        _hasMore = false;
      });
    } else {
      if (_isLoadingMore || !_hasMore) return;
      setState(() => _isLoadingMore = true);
    }

    try {
      final res = await _service.getCommunityMembersRpc(
        communityId: widget.communityId,
        limit: 50,
        cursor: refresh ? null : _nextCursor,
        query: _searchQuery.isNotEmpty ? _searchQuery : null,
      );

      final rawItems = res['items'] is List ? res['items'] as List : [];
      final newMembers = rawItems.map((e) => Map<String, dynamic>.from(e)).toList();
      final nextCursor = res['next_cursor']?.toString();
      final hasMore = res['has_more'] == true;
      await _loadCommunityReputations(newMembers);

      if (mounted) {
        setState(() {
          if (refresh) {
            _members = newMembers;
          } else {
            final existingIds = _members.map((m) => m['user_id']?.toString()).toSet();
            final uniqueNew = newMembers.where((m) => !existingIds.contains(m['user_id']?.toString())).toList();
            _members.addAll(uniqueNew);
          }
          _nextCursor = nextCursor;
          _hasMore = hasMore;
          _errorMessage = null;
          _errorCategory = null;
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    } on PostgrestException catch (e) {
      final isHidden = e.code == 'P0001' || e.message.toLowerCase().contains('masquée') || e.message.toLowerCase().contains('masque');
      if (isHidden) {
        if (_isStaff) {
          debugPrint('[CommunityMembersScreen] Supposed staff account (role=$_userRole) received P0001 for communityId=${widget.communityId}');
        } else {
          debugPrint('[CommunityMembersScreen] Members list is hidden by community policy for communityId=${widget.communityId}');
        }
      } else {
        debugPrint('[CommunityMembersScreen] PostgrestException loading members: code=${e.code}, message=${e.message}');
      }

      String category = 'unknown';
      final msgLower = e.message.toLowerCase();
      if (isHidden) {
        category = 'hidden_list';
      } else if (msgLower.contains('non membre') || msgLower.contains('pas membre') || e.code == '403' || e.code == 'PGRST301') {
        category = 'not_member';
      } else if (msgLower.contains('unauthenticated') || msgLower.contains('non authentifié') || e.code == '401') {
        category = 'unauthenticated';
      }

      if (mounted) {
        setState(() {
          _errorMessage = e.message;
          _errorCategory = category;
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    } catch (e, st) {
      debugPrint('[CommunityMembersScreen] Unexpected error loading members: $e\n$st');
      String category = 'unknown';
      final eStr = e.toString().toLowerCase();
      if (eStr.contains('socket') || eStr.contains('network') || eStr.contains('connection') || eStr.contains('timeout')) {
        category = 'network';
      } else if (e is FormatException || e is TypeError) {
        category = 'invalid_response';
      }

      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
          _errorCategory = category;
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _loadCommunityReputations(List<Map<String, dynamic>> members) async {
    final ids = members
        .map((member) => member['user_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return;
    try {
      final response = await Supabase.instance.client.rpc(
        'get_community_member_reputations',
        params: {'p_community_id': widget.communityId, 'p_user_ids': ids},
      );
      if (response is! List || !mounted) return;
      setState(() {
        for (final raw in response) {
          if (raw is! Map) continue;
          final row = Map<String, dynamic>.from(raw);
          final id = row['user_id']?.toString();
          final score = (row['score'] as num?)?.toDouble();
          if (id != null && score != null) {
            _communityReputations[id] = score.clamp(0.0, 5.0).toDouble();
          }
        }
      });
    } catch (e) {
      // The UI remains usable while the V2 migration is awaiting deployment.
      debugPrint('[CommunityMembersScreen] Community reputation unavailable: $e');
    }
  }


  void _onSearchChanged(String val) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) {
        setState(() => _searchQuery = val.trim());
        _loadMembers(refresh: true);
      }
    });
  }

  Future<void> _showExclusionDialog(String userId, String userName) async {
    final reasonController = TextEditingController();
    var deleteContent = false;

    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('community_exclude_title'.trParams({'name': userName}), style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('community_exclude_confirm'.tr),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                labelText: 'community_exclude_reason_label'.tr,
                hintText: 'community_exclude_reason_hint'.tr,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              maxLength: 500,
              maxLines: 2,
            ),
            const SizedBox(height: 8),
            StatefulBuilder(
              builder: (context, setStateSB) => CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('community_exclude_delete_content'.tr, style: const TextStyle(fontSize: 13)),
                value: deleteContent,
                onChanged: (val) => setStateSB(() => deleteContent = val ?? false),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Get.back(result: false), child: Text('cancel'.tr)),
          ElevatedButton(
            onPressed: () => Get.back(result: true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: Text('community_exclude_action'.tr),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _service.excludeCommunityMember(
          widget.communityId,
          userId,
          reason: reasonController.text.trim().isNotEmpty ? reasonController.text.trim() : null,
          deleteContent: deleteContent,
        );
        Get.snackbar(
          'community_exclude_success_title'.tr,
          'community_exclude_success_message'.trParams({'name': userName}),
          snackPosition: SnackPosition.BOTTOM,
        );
        await _loadMembers(refresh: true);
      } catch (e) {
        debugPrint('[CommunityMembersScreen] Exclusion failed: $e');
        Get.snackbar(
          'community_save_error'.tr,
          _service.localizedCommunityError(e),
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    }
    reasonController.dispose();
  }


  Future<void> _changeRole(String userId, String userName, String newRole) async {
    try {
      await _service.updateMemberRole(widget.communityId, userId, newRole);
      Get.snackbar('Rôle mis à jour', 'Le rôle de $userName a été mis à jour avec succès.', snackPosition: SnackPosition.BOTTOM);
      await _loadMembers(refresh: true);
    } catch (e) {
      debugPrint('[CommunityMembersScreen] Role update failed: $e');
      Get.snackbar('community_save_error'.tr, _service.localizedCommunityError(e), snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  void _onMemberSingleTap(Map<String, dynamic> member) {
    final userId = member['user_id']?.toString() ?? '';
    final isSelf = member['is_self'] == true || member['is_self'] == 1 || member['is_self'] == 'true';

    if (isSelf) return; // Do not open external profile for oneself

    if (userId.isNotEmpty) {
      Get.toNamed(AppPages.externalProfilePath(userId));
    }
  }

  Future<void> _reportCommunityMember(String userId, String userName) async {
    final reasons = await _service.getSignalementRaisons();
    if (reasons.isEmpty) {
      Get.snackbar(
        'community_save_error'.tr,
        'Impossible de charger les motifs de signalement. Réessaie plus tard.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    String? selectedReasonId = reasons.first['id']?.toString();
    String? selectedReasonCode =
        reasons.first['code']?.toString() ?? reasons.first['nom']?.toString();
    final descriptionController = TextEditingController();
    bool submitting = false;

    await Get.dialog<void>(
      StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final isOther = selectedReasonCode?.toLowerCase() == 'autre' ||
              selectedReasonCode?.toLowerCase() == 'other';
          final description = descriptionController.text.trim();
          final valid = selectedReasonId != null &&
              selectedReasonId!.isNotEmpty &&
              (!isOther || description.isNotEmpty);
          return AlertDialog(
            title: Text('community_report_member_title'.trParams({'name': userName})),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('community_report_reason_label'.tr),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: selectedReasonId,
                      isExpanded: true,
                      items: reasons.map((reason) {
                        final id = reason['id']?.toString() ?? '';
                        final code = reason['code']?.toString() ??
                            reason['nom']?.toString() ??
                            'Motif';
                        String label = code;
                        if (code == 'harcelement') {
                          label = 'community_report_reason_harassment'.tr;
                        } else if (code == 'dangereux_risqué' ||
                            code == 'dangereux_riske') {
                          label = 'community_report_reason_dangerous'.tr;
                        } else if (code == 'copie_contrefacon') {
                          label = 'community_report_reason_copy'.tr;
                        } else if (code == 'autre') {
                          label = 'community_report_reason_other'.tr;
                        }
                        return DropdownMenuItem<String>(
                          value: id,
                          child: Text(label),
                        );
                      }).toList(),
                      onChanged: submitting
                          ? null
                          : (value) => setDialogState(() {
                                selectedReasonId = value;
                                final selected = reasons.firstWhereOrNull(
                                  (item) => item['id']?.toString() == value,
                                );
                                selectedReasonCode = selected?['code']?.toString() ??
                                    selected?['nom']?.toString();
                              }),
                    ),
                    const SizedBox(height: 12),
                    Text('community_report_description_label'.tr),
                    const SizedBox(height: 8),
                    TextField(
                      controller: descriptionController,
                      maxLength: 1000,
                      maxLines: 3,
                      onChanged: (_) => setDialogState(() {}),
                      decoration: InputDecoration(
                        hintText: 'community_report_description_hint'.tr,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    if (isOther && description.isEmpty)
                      Text(
                        'community_report_other_desc_required'.tr,
                        style: TextStyle(color: Theme.of(dialogContext).colorScheme.error),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: submitting ? null : () => Get.back(),
                child: Text('cancel'.tr),
              ),
              FilledButton(
                onPressed: !valid || submitting
                    ? null
                    : () async {
                        setDialogState(() => submitting = true);
                        try {
                          await Supabase.instance.client.rpc(
                            'report_community_member',
                            params: {
                              'p_community_id': widget.communityId,
                              'p_user_id': userId,
                              'p_reason_id': selectedReasonId,
                              'p_description': descriptionController.text.trim(),
                            },
                          );
                          Get.back();
                          Get.snackbar(
                            'Signalement transmis',
                            'community_report_community_success_msg'.tr,
                            snackPosition: SnackPosition.BOTTOM,
                          );
                        } catch (e) {
                          setDialogState(() => submitting = false);
                          Get.snackbar(
                            'community_save_error'.tr,
                            e.toString().replaceFirst('Exception: ', ''),
                            snackPosition: SnackPosition.BOTTOM,
                          );
                        }
                      },
                child: submitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('community_report_submit'.tr),
              ),
            ],
          );
        },
      ),
      barrierDismissible: !submitting,
    );
    descriptionController.dispose();
  }

  void _onMemberLongPress(Map<String, dynamic> member) {
    final userId = member['user_id']?.toString() ?? '';
    final isSelf = member['is_self'] == true || member['is_self'] == 1 || member['is_self'] == 'true';

    if (isSelf || userId.isEmpty) return;

    final userName = (member['first_name'] != null && member['first_name'].toString().isNotEmpty)
        ? '${member['first_name']} ${member['last_name'] ?? ''}'.trim()
        : (member['username']?.toString() ?? 'excluded_members_unknown_user'.tr);
    final currentRole = member['role']?.toString() ?? 'member';

    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'community_member_manage_title'.trParams({'name': userName}),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: Colors.orange),
              title: Text('community_report_member_title'.tr),
              onTap: () {
                Get.back();
                _reportCommunityMember(userId, userName);
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_outline_rounded),
              title: Text('community_member_view_profile'.tr),
              onTap: () {
                Get.back();
                Get.toNamed(AppPages.externalProfilePath(userId));
              },
            ),
            if (_isAdminUser) ...[
              if (currentRole != 'admin')
                ListTile(
                  leading: const Icon(Icons.admin_panel_settings_outlined, color: Colors.purple),
                  title: Text('community_member_promote_admin'.tr),
                  onTap: () {
                    Get.back();
                    _changeRole(userId, userName, 'admin');
                  },
                ),
              if (currentRole != 'moderator')
                ListTile(
                  leading: const Icon(Icons.security_rounded, color: Colors.orange),
                  title: Text('community_member_promote_moderator'.tr),
                  onTap: () {
                    Get.back();
                    _changeRole(userId, userName, 'moderator');
                  },
                ),
              if (currentRole != 'member')
                ListTile(
                  leading: const Icon(Icons.person_rounded, color: Colors.blue),
                  title: Text('community_member_demote'.tr),
                  onTap: () {
                    Get.back();
                    _changeRole(userId, userName, 'member');
                  },
                ),
            ],
            if (_isAdminUser)
              ListTile(
                leading: const Icon(Icons.block_rounded, color: Colors.red),
                title: Text('community_exclude_action'.tr, style: const TextStyle(color: Colors.red)),
                onTap: () {
                  Get.back();
                  _showExclusionDialog(userId, userName);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        title: Text(
          'community_members_title'.tr,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, color: colorScheme.onSurfaceVariant, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      decoration: InputDecoration(
                        hintText: 'community_member_search_hint'.tr,
                        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  if (_searchQuery.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                        _loadMembers(refresh: true);
                      },
                      child: Icon(Icons.close_rounded, color: colorScheme.onSurfaceVariant, size: 18),
                    ),
                ],
              ),
            ),
          ),

          // Members List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null && _members.isEmpty
                    ? _buildErrorStateWidget(colorScheme)
                    : _members.isEmpty
                        ? Center(
                            child: Text(
                              'Aucun membre trouvé',
                              style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 16),
                            ),
                          )
                        : RefreshIndicator(
                        onRefresh: () => _loadMembers(refresh: true),
                        child: ListView.builder(
                          controller: _scrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: _members.length + (_isLoadingMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == _members.length) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                              );
                            }

                            final member = _members[index];
                            final firstName = member['first_name']?.toString() ?? '';
                            final lastName = member['last_name']?.toString() ?? '';
                            final fullName = '$firstName $lastName'.trim().isNotEmpty
                                ? '$firstName $lastName'.trim()
                                : (member['username']?.toString() ?? 'excluded_members_unknown_user'.tr);
                            final username = member['username']?.toString() ?? '';
                            final avatar = member['photo_url']?.toString();
                            final isCertified = member['is_certified'] == true || member['is_certified'] == 1 || member['is_certified'] == 'true';
                            final isVerified = (member['is_verified'] == true || member['is_verified'] == 1 || member['is_verified'] == 'true') && !isCertified;
                            final role = member['role']?.toString() ?? 'member';
                            final isSelf = member['is_self'] == true || member['is_self'] == 1 || member['is_self'] == 'true';
            final memberId = member['user_id']?.toString() ?? '';
            final communityScore = _communityReputations[memberId];

                            String roleTag = '';
                            if (role == 'admin') roleTag = isSelf ? ' (Admin · Vous)' : ' (Admin)';
                            else if (role == 'moderator') roleTag = isSelf ? ' (Modérateur · Vous)' : ' (Modérateur)';
                            else if (isSelf) roleTag = ' (Vous)';

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.35),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                                ),
                                child: InkWell(
                                  onTap: () => _onMemberSingleTap(member),
                                  onLongPress: () => _onMemberLongPress(member),
                                  borderRadius: BorderRadius.circular(16),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: UserIdentityRow(
                                      name: fullName,
                                      username: username,
                                      avatarUrl: avatar,
                                      isCertified: isCertified,
                                      userId: member['user_id']?.toString(),
                                      prefixWidget: isVerified ? UserCertifiedBadge(size: 16, userId: member['user_id']?.toString()) : null,
                                      subtitle: [if (roleTag.isNotEmpty) roleTag, if (communityScore != null) '★ ${_formatReputation(communityScore)}/5'].join('  ').isNotEmpty ? [if (roleTag.isNotEmpty) roleTag, if (communityScore != null) '★ ${_formatReputation(communityScore)}/5 · Réputation communauté'].join('  ') : null,
                                      trailing: !isSelf
                                          ? Icon(Icons.more_vert_rounded, size: 18, color: colorScheme.onSurfaceVariant)
                                          : null,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorStateWidget(ColorScheme colorScheme) {
    IconData iconData;
    String title;
    String message = _errorMessage ?? 'Une erreur est survenue';
    bool showRetry = true;

    switch (_errorCategory) {
      case 'hidden_list':
        iconData = Icons.lock_outline_rounded;
        title = 'Liste des membres masquée';
        showRetry = false;
        break;
      case 'not_member':
        iconData = Icons.no_accounts_outlined;
        title = 'Accès réservé aux membres';
        showRetry = false;
        break;
      case 'unauthenticated':
        iconData = Icons.account_circle_outlined;
        title = 'Session expirée';
        message = 'Veuillez vous reconnecter pour accéder aux membres.';
        showRetry = true;
        break;
      case 'network':
        iconData = Icons.wifi_off_rounded;
        title = 'Erreur réseau';
        message = 'Impossible de se connecter au serveur. Vérifiez votre connexion internet.';
        showRetry = true;
        break;
      case 'invalid_response':
        iconData = Icons.data_object_rounded;
        title = 'Erreur de réponse';
        message = 'La réponse reçue du serveur est invalide.';
        showRetry = true;
        break;
      default:
        iconData = Icons.error_outline_rounded;
        title = 'Erreur de chargement';
        showRetry = true;
        break;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(iconData, size: 52, color: colorScheme.error),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
            if (showRetry) ...[
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => _loadMembers(refresh: true),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text('excluded_members_retry'.tr),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
