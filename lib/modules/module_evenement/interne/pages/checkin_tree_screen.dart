import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/widgets/scrole_bottom_sheet.dart';
import '../../centre/models/checkin_model.dart';
import '../../centre/repositories/event_repository.dart';

class CheckinTreeScreen extends StatefulWidget {
  final String eventId;

  const CheckinTreeScreen({super.key, required this.eventId});

  @override
  State<CheckinTreeScreen> createState() => _CheckinTreeScreenState();
}

class _CheckinTreeScreenState extends State<CheckinTreeScreen> {
  bool _isLoading = true;
  List<CheckinModel> _allCheckins = [];

  @override
  void initState() {
    super.initState();
    _loadCheckinsTree();
  }

  Future<void> _loadCheckinsTree() async {
    setState(() => _isLoading = true);
    final repo = Get.find<EventRepository>();
    try {
      final tree = await repo.getEventCheckinsTree(widget.eventId);
      setState(() {
        _allCheckins = tree;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[CheckinTreeScreen] Error loading tree: $e');
      setState(() => _isLoading = false);
    }
  }

  void _showInvalidateDialog(CheckinModel checkin) {
    final reasonController = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ScroleBottomSheet(
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Invalider en chaîne', style: AppTextStyles.h4),
              const SizedBox(height: 8),
              Text(
                'Avertissement : L\'invalidation du check-in de ${checkin.userName} invalidera également TOUTE sa descendance dans la chaîne de validation.',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.error, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Motif obligatoire de l\'invalidation...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Get.back(),
                    child: const Text('Annuler'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () async {
                      final reason = reasonController.text.trim();
                      if (reason.isEmpty) {
                        Get.snackbar('Erreur', 'Le motif de l\'invalidation est obligatoire.');
                        return;
                      }
                      Get.back();
                      final repo = Get.find<EventRepository>();
                      try {
                        await repo.invalidateCheckinChain(checkin.id, reason);
                        Get.snackbar('Invalidation', 'Chaîne invalidée avec succès !');
                        // Exigence §4.9 : Re-fetch complet de tout l'arbre
                        await _loadCheckinsTree();
                      } catch (e) {
                        Get.snackbar('Erreur Invalidation', e.toString());
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
                    child: const Text('Invalider la chaîne'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Arbre des Check-ins')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final rootCheckins = _allCheckins.where((c) => c.parentCheckinId == null || c.parentCheckinId!.isEmpty).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Arbre des Check-ins',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadCheckinsTree,
          ),
        ],
      ),
      body: _allCheckins.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.account_tree_outlined, size: 64, color: AppColors.textSecondary),
                  const SizedBox(height: 16),
                  Text('Aucun check-in enregistré pour cet événement.', style: AppTextStyles.body),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: rootCheckins.map((root) => _buildCheckinNode(root, depth: 0)).toList(),
            ),
    );
  }

  Widget _buildCheckinNode(CheckinModel checkin, {required int depth}) {
    final children = _allCheckins.where((c) => c.parentCheckinId == checkin.id).toList();
    final isInvalidated = checkin.status == CheckinStatus.invalidated;

    return Padding(
      padding: EdgeInsets.only(left: depth * 16.0, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            color: isInvalidated ? AppColors.error.withValues(alpha: 0.08) : null,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: isInvalidated ? const BorderSide(color: AppColors.error, width: 1.5) : BorderSide.none,
            ),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: isInvalidated ? AppColors.error : Colors.green[700],
                child: Icon(
                  isInvalidated ? Icons.block_rounded : Icons.check_circle_outline_rounded,
                  color: Colors.white,
                ),
              ),
              title: Text(
                checkin.userName,
                style: AppTextStyles.body.copyWith(
                  fontWeight: FontWeight.bold,
                  decoration: isInvalidated ? TextDecoration.lineThrough : null,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Validé par: ${checkin.validatorName}', style: AppTextStyles.bodySmall),
                  if (isInvalidated && checkin.invalidatedReason != null)
                    Text(
                      'Motif: ${checkin.invalidatedReason}',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.error, fontWeight: FontWeight.bold),
                    ),
                ],
              ),
              trailing: !isInvalidated
                  ? OutlinedButton(
                      onPressed: () => _showInvalidateDialog(checkin),
                      child: const Text('Invalider', style: TextStyle(color: AppColors.error)),
                    )
                  : const Text('Invalidé', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
            ),
          ),
          if (children.isNotEmpty)
            ...children.map((child) => _buildCheckinNode(child, depth: depth + 1)),
        ],
      ),
    );
  }
}
