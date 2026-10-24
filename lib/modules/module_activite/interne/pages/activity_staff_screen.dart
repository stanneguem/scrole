import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../app/service_global/supabse_service.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../app/utils/supabase_error_mapper.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../../centre/models/activity_model.dart';
import '../../externe/repositories/activity_repository.dart';
import 'activity_staff_invite_screen.dart';

class ActivityStaffScreen extends StatefulWidget {
  final Activity activity;

  const ActivityStaffScreen({super.key, required this.activity});

  @override
  State<ActivityStaffScreen> createState() => _ActivityStaffScreenState();
}

class _ActivityStaffScreenState extends State<ActivityStaffScreen> {
  final ActivityRepository _repository = ActivityRepository();
  bool _isLoading = true;
  List<Map<String, dynamic>> _staffMembers = [];

  @override
  void initState() {
    super.initState();
    _loadStaffMembers();
  }

  Future<void> _loadStaffMembers() async {
    setState(() => _isLoading = true);
    try {
      // 1. Appel RPC officielle get_activity_staff_members
      final rpcMembers = await _repository.getActivityStaffMembersRpc(widget.activity.id);
      if (rpcMembers.isNotEmpty) {
        if (mounted) {
          setState(() {
            _staffMembers = rpcMembers;
            _isLoading = false;
          });
        }
        return;
      }

      // 2. Fallback si RPC vide ou non activée
      final client = Get.find<SupabaseService>().client;
      List<dynamic> rawStaff = [];
      try {
        rawStaff = await client
            .from('activity_staff')
            .select('*, user_profiles(user_id, first_name, last_name, username, photo_url)')
            .eq('activity_id', widget.activity.id)
            .eq('status', 'acceptee');
      } catch (embeddedErr) {
        rawStaff = await client
            .from('activity_staff')
            .select()
            .eq('activity_id', widget.activity.id)
            .eq('status', 'acceptee');
      }

      final List<Map<String, dynamic>> resultList = [];
      final Set<String> missingUserIds = {};

      for (final item in rawStaff) {
        final map = Map<String, dynamic>.from(item as Map);
        final profile = map['user_profiles'];
        if ((profile == null || profile is! Map) && map['user_id'] != null) {
          missingUserIds.add(map['user_id'].toString());
        }
      }

      final Map<String, Map<String, dynamic>> profilesMap = {};
      if (missingUserIds.isNotEmpty) {
        try {
          final profiles = await client
              .from('user_profiles')
              .select('user_id, first_name, last_name, username, photo_url')
              .inFilter('user_id', missingUserIds.toList());
          for (final p in profiles) {
            final pm = Map<String, dynamic>.from(p as Map);
            profilesMap[pm['user_id'].toString()] = pm;
          }
        } catch (_) {}
      }

      for (final item in rawStaff) {
        final map = Map<String, dynamic>.from(item as Map);
        final uid = map['user_id']?.toString();
        if ((map['user_profiles'] == null || map['user_profiles'] is! Map) && uid != null && profilesMap.containsKey(uid)) {
          map['user_profiles'] = profilesMap[uid];
        }
        resultList.add(map);
      }

      if (mounted) {
        setState(() {
          _staffMembers = resultList;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[ActivityStaffScreen] Error loading staff: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _removeStaff(String userId, String name) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Retirer ce membre ?'),
        content: Text('Voulez-vous retirer $name du staff de cette activité ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await _repository.removeActivityStaffRpc(widget.activity.id, userId);
                Get.snackbar('Staff', '$name a été retiré du staff.');
                _loadStaffMembers();
              } catch (e) {
                showAppErrorDialog(context, e);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Retirer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          'Gérer le staff',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Get.back(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : _staffMembers.isEmpty
                      ? _buildEmptyState(colorScheme)
                      : RefreshIndicator(
                          color: AppColors.primary,
                          onRefresh: _loadStaffMembers,
                          child: ListView.separated(
                            padding: const EdgeInsets.all(20),
                            itemCount: _staffMembers.length,
                            separatorBuilder: (ctx, i) => const SizedBox(height: 12),
                            itemBuilder: (ctx, index) {
                              final item = _staffMembers[index];
                              final profile = item['user_profiles'] as Map<String, dynamic>? ?? {};
                              final userId = item['user_id'].toString();
                              final firstName = (profile['first_name'] ?? '').toString().trim();
                              final lastName = (profile['last_name'] ?? '').toString().trim();
                              final username = (profile['username'] ?? '').toString().trim();
                              final photoUrl = profile['photo_url']?.toString();
                              final status = (item['status'] ?? 'en_attente').toString();
                              final name = '$firstName $lastName'.trim().isEmpty ? username : '$firstName $lastName'.trim();

                              return Card(
                                margin: EdgeInsets.zero,
                                color: colorScheme.surfaceContainerLow,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  leading: SizedBox(
                                    width: 44,
                                    height: 44,
                                    child: ClipOval(
                                      child: photoUrl != null && photoUrl.isNotEmpty
                                          ? AppCachedImage(imageUrl: photoUrl, fit: BoxFit.cover)
                                          : Container(
                                              color: AppColors.primary.withValues(alpha: 0.12),
                                              child: const Icon(Icons.person_rounded, color: AppColors.primary),
                                            ),
                                    ),
                                  ),
                                  title: Text(name, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
                                  subtitle: Row(
                                    children: [
                                      Text('@$username', style: AppTextStyles.bodySmall),
                                      const SizedBox(width: 8),
                                      _buildStatusBadge(status),
                                    ],
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.person_remove_rounded, color: AppColors.error, size: 20),
                                    onPressed: () => _removeStaff(userId, name),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: ElevatedButton.icon(
                onPressed: () async {
                  await Get.to(() => ActivityStaffInviteScreen(activity: widget.activity));
                  _loadStaffMembers();
                },
                icon: const Icon(Icons.person_add_rounded, color: Colors.white),
                label: const Text('Inviter un membre du staff', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    final isAccepted = status == 'acceptee' || status == 'accepted' || status == 'active';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isAccepted ? AppColors.success.withValues(alpha: 0.15) : Colors.amber[800]!.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isAccepted ? 'Accepté' : 'En attente',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
          color: isAccepted ? AppColors.success : Colors.amber[800],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.group_outlined, size: 48, color: AppColors.primary),
            ),
            const SizedBox(height: 20),
            Text('Aucun membre du staff', style: AppTextStyles.h5.copyWith(color: colorScheme.onSurface)),
            const SizedBox(height: 8),
            Text(
              'Invitez vos amis à devenir gestionnaires de cette activité pour vous aider à la gérer.',
              style: AppTextStyles.bodySmall.copyWith(color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
