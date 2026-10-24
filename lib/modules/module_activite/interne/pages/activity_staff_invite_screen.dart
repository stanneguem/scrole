import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../app/service_global/supabse_service.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../app/utils/supabase_error_mapper.dart';
import '../../../../modules/module_discussion_direct/externe/repositories/social_repository.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../../centre/models/activity_model.dart';
import '../../externe/repositories/activity_repository.dart';

class ActivityStaffInviteScreen extends StatefulWidget {
  final Activity activity;

  const ActivityStaffInviteScreen({super.key, required this.activity});

  @override
  State<ActivityStaffInviteScreen> createState() => _ActivityStaffInviteScreenState();
}

class _ActivityStaffInviteScreenState extends State<ActivityStaffInviteScreen> {
  final SocialRepository _socialRepository = SocialRepository();
  final ActivityRepository _activityRepository = ActivityRepository();

  bool _isLoading = true;
  List<Map<String, dynamic>> _contacts = [];
  List<Map<String, dynamic>> _filteredContacts = [];
  final Set<String> _invitedUserIds = {};
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    setState(() => _isLoading = true);
    try {
      // 1. Appel de la RPC get_activity_staff_candidates(p_activity_id)
      final rpcCandidates = await _activityRepository.getActivityStaffCandidatesRpc(widget.activity.id);

      List<Map<String, dynamic>> candidates = [];
      if (rpcCandidates.isNotEmpty) {
        candidates = rpcCandidates;
      } else {
        // Fallback: Récupérer les amis et vérifier leur staff_status localement
        final friends = await _socialRepository.getAcceptedConnections();
        final client = Get.find<SupabaseService>().client;
        final staffRows = await client
            .from('activity_staff')
            .select('user_id, status')
            .eq('activity_id', widget.activity.id);

        final Map<String, String> statusMap = {};
        for (final r in staffRows) {
          statusMap[r['user_id'].toString()] = r['status'].toString();
        }

        candidates = friends.map((f) {
          final uid = f['user_id'].toString();
          return {
            ...f,
            'staff_status': statusMap[uid],
          };
        }).toList();
      }

      if (mounted) {
        setState(() {
          _contacts = candidates;
          _filteredContacts = candidates;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[ActivityStaffInviteScreen] Error loading candidates: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _filterContacts(String query) {
    _searchQuery = query.toLowerCase().trim();
    setState(() {
      if (_searchQuery.isEmpty) {
        _filteredContacts = _contacts;
      } else {
        _filteredContacts = _contacts.where((c) {
          final first = (c['first_name'] ?? '').toString().toLowerCase();
          final last = (c['last_name'] ?? '').toString().toLowerCase();
          final username = (c['username'] ?? '').toString().toLowerCase();
          return first.contains(_searchQuery) || last.contains(_searchQuery) || username.contains(_searchQuery);
        }).toList();
      }
    });
  }

  Future<void> _inviteContact(String userId, String name) async {
    try {
      await _activityRepository.inviteActivityStaffRpc(widget.activity.id, userId);
      setState(() {
        for (final c in _contacts) {
          if (c['user_id'].toString() == userId) {
            c['staff_status'] = 'en_attente';
          }
        }
      });
      Get.snackbar('Invitation envoyée', 'Une demande a été envoyée à $name.');
    } catch (e) {
      showAppErrorDialog(context, e);
    }
  }

  Future<void> _cancelInvite(String userId, String name) async {
    try {
      await _activityRepository.cancelActivityStaffInviteRpc(widget.activity.id, userId);
      setState(() {
        for (final c in _contacts) {
          if (c['user_id'].toString() == userId) {
            c['staff_status'] = null;
          }
        }
      });
      Get.snackbar('Invitation annulée', 'L\'invitation pour $name a été annulée.');
    } catch (e) {
      showAppErrorDialog(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          'Inviter un gestionnaire',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Get.back(),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              onChanged: _filterContacts,
              decoration: InputDecoration(
                hintText: 'Rechercher un ami...',
                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primary),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _filteredContacts.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text('Aucun ami trouvé.', style: AppTextStyles.body),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(20),
                    itemCount: _filteredContacts.length,
                    separatorBuilder: (ctx, i) => const SizedBox(height: 12),
                    itemBuilder: (ctx, index) {
                      final item = _filteredContacts[index];
                      final userId = (item['user_id'] ?? '').toString();
                      final firstName = (item['first_name'] ?? '').toString().trim();
                      final lastName = (item['last_name'] ?? '').toString().trim();
                      final username = (item['username'] ?? '').toString().trim();
                      final photoUrl = item['photo_url']?.toString();
                      final name = '$firstName $lastName'.trim().isEmpty ? username : '$firstName $lastName'.trim();
                      final isInvited = _invitedUserIds.contains(userId);

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
                          subtitle: Text('@$username', style: AppTextStyles.bodySmall),
                          trailing: _buildTrailingWidget(userId, name, item['staff_status']?.toString()),
                        ),
                      );
                    },
                  ),
      ),
    );
  }

  Widget _buildTrailingWidget(String userId, String name, String? staffStatus) {
    if (staffStatus == 'acceptee' || staffStatus == 'accepted' || staffStatus == 'active') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text('Déjà membre', style: AppTextStyles.caption.copyWith(color: AppColors.success, fontWeight: FontWeight.bold)),
      );
    }

    if (staffStatus == 'en_attente' || staffStatus == 'pending') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.amber[800]!.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('Demande en cours', style: AppTextStyles.caption.copyWith(color: Colors.amber[800], fontWeight: FontWeight.bold, fontSize: 11)),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: AppColors.error, size: 18),
            tooltip: 'Annuler l\'invitation',
            onPressed: () => _cancelInvite(userId, name),
          ),
        ],
      );
    }

    return ElevatedButton.icon(
      onPressed: () => _inviteContact(userId, name),
      icon: const Icon(Icons.add, size: 16, color: Colors.white),
      label: const Text('Inviter', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}
