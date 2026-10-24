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

class ActivityTransferScreen extends StatefulWidget {
  final Activity activity;

  const ActivityTransferScreen({super.key, required this.activity});

  @override
  State<ActivityTransferScreen> createState() => _ActivityTransferScreenState();
}

class _ActivityTransferScreenState extends State<ActivityTransferScreen> {
  final ActivityRepository _repository = ActivityRepository();
  bool _isLoading = true;
  List<Map<String, dynamic>> _staffMembers = [];
  Map<String, dynamic>? _pendingTransfer;

  @override
  void initState() {
    super.initState();
    _loadTransferData();
  }

  Future<void> _loadTransferData() async {
    setState(() => _isLoading = true);
    try {
      final client = Get.find<SupabaseService>().client;

      // 1. Charger les transferts en attente
      Map<String, dynamic>? transferRes;
      try {
        transferRes = await client
            .from('activity_transfers')
            .select('*, user_profiles(user_id, first_name, last_name, username)')
            .eq('activity_id', widget.activity.id)
            .eq('status', 'en_attente')
            .maybeSingle();
      } catch (e) {
        debugPrint('[ActivityTransferScreen] Transfer select error: $e');
      }

      // 2. Charger les membres du staff acceptés
      List<dynamic> staffRes = [];
      try {
        staffRes = await client
            .from('activity_staff')
            .select('*, user_profiles(user_id, first_name, last_name, username, photo_url)')
            .eq('activity_id', widget.activity.id);
      } catch (e) {
        staffRes = await client
            .from('activity_staff')
            .select()
            .eq('activity_id', widget.activity.id);
      }

      final List<Map<String, dynamic>> resultList = [];
      final Set<String> missingUserIds = {};

      for (final item in staffRes) {
        final map = Map<String, dynamic>.from(item as Map);
        final status = (map['status'] ?? '').toString();
        // Seuls les membres acceptés sont éligibles
        if (status == 'acceptee' || status == 'accepted' || status == 'active') {
          final profile = map['user_profiles'];
          if ((profile == null || profile is! Map) && map['user_id'] != null) {
            missingUserIds.add(map['user_id'].toString());
          }
          resultList.add(map);
        }
      }

      if (missingUserIds.isNotEmpty) {
        try {
          final profiles = await client
              .from('user_profiles')
              .select('user_id, first_name, last_name, username, photo_url')
              .inFilter('user_id', missingUserIds.toList());
          final Map<String, Map<String, dynamic>> pMap = {};
          for (final p in profiles) {
            final pm = Map<String, dynamic>.from(p as Map);
            pMap[pm['user_id'].toString()] = pm;
          }
          for (final map in resultList) {
            final uid = map['user_id']?.toString();
            if ((map['user_profiles'] == null || map['user_profiles'] is! Map) && uid != null && pMap.containsKey(uid)) {
              map['user_profiles'] = pMap[uid];
            }
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _pendingTransfer = transferRes;
          _staffMembers = resultList;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[ActivityTransferScreen] Error loading data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _proposeTransfer(String userId, String name) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmer la proposition'),
        content: Text('Proposer la propriété de l\'activité "${widget.activity.name}" à $name ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await _repository.proposeActivityTransferRpc(widget.activity.id, userId);
                Get.snackbar('Transfert', 'La proposition a été envoyée à $name.');
                _loadTransferData();
              } catch (e) {
                showAppErrorDialog(context, e);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Proposer'),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelTransfer(String transferId) async {
    try {
      await _repository.cancelActivityTransferRpc(transferId);
      Get.snackbar('Transfert', 'La proposition a été annulée.');
      _loadTransferData();
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
          'Transférer la propriété',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Get.back(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Banner d'avertissement
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: widget.activity.isActive
                    ? colorScheme.errorContainer.withValues(alpha: 0.12)
                    : Colors.amber[800]!.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: widget.activity.isActive ? AppColors.error.withValues(alpha: 0.3) : Colors.amber[800]!.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    widget.activity.isActive ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
                    color: widget.activity.isActive ? AppColors.error : Colors.amber[800],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.activity.isActive
                          ? 'Attention : Le transfert de propriété est définitif. Une fois accepté par le destinataire, vous perdez tous les droits de propriété sur cette activité.'
                          : 'Seules les activités au statut "Active" peuvent être transférées. Cette activité est actuellement au statut "${widget.activity.status}". Si la suppression est programmée, annulez-la d\'abord.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: widget.activity.isActive ? AppColors.error : Colors.amber[800],
                        fontWeight: widget.activity.isActive ? FontWeight.normal : FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Transfert en attente si présent
            if (_pendingTransfer != null) ...[
              Text('PROPOSITION EN COURS', style: AppTextStyles.labelSmall.copyWith(letterSpacing: 1.2, color: Colors.amber[800])),
              const SizedBox(height: 10),
              Card(
                margin: EdgeInsets.zero,
                color: colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  title: const Text('Transfert proposé', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('En attente de la réponse du destinataire', style: TextStyle(color: Colors.amber)),
                  trailing: TextButton(
                    onPressed: () => _cancelTransfer(_pendingTransfer!['id'].toString()),
                    child: const Text('Annuler', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],

            Text('MEMBRES DU STAFF ÉLIGIBLES', style: AppTextStyles.labelSmall.copyWith(letterSpacing: 1.2, color: colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Text(
              'Vous pouvez uniquement transférer l\'activité à un membre accepté de son staff.',
              style: AppTextStyles.bodySmall,
            ),
            const SizedBox(height: 16),

            if (_isLoading)
              const Center(child: CircularProgressIndicator(color: AppColors.primary))
            else if (_staffMembers.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text('Aucun membre du staff éligible.', style: AppTextStyles.body),
                ),
              )
            else
              ..._staffMembers.map((item) {
                final profile = item['user_profiles'] as Map<String, dynamic>? ?? {};
                final userId = item['user_id'].toString();
                final firstName = (profile['first_name'] ?? '').toString().trim();
                final lastName = (profile['last_name'] ?? '').toString().trim();
                final username = (profile['username'] ?? '').toString().trim();
                final photoUrl = profile['photo_url']?.toString();
                final name = '$firstName $lastName'.trim().isEmpty ? username : '$firstName $lastName'.trim();

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
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
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: widget.activity.isActive ? () => _proposeTransfer(userId, name) : null,
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
