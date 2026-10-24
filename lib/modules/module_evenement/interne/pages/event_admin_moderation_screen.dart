import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../../../../shared/widgets/scrole_bottom_sheet.dart';
import '../../centre/models/event_model.dart';
import '../../centre/repositories/event_repository.dart';

class EventAdminModerationScreen extends StatefulWidget {
  const EventAdminModerationScreen({super.key});

  @override
  State<EventAdminModerationScreen> createState() => _EventAdminModerationScreenState();
}

class _EventAdminModerationScreenState extends State<EventAdminModerationScreen> {
  bool _isLoading = true;
  List<EventModel> _pendingEvents = [];

  @override
  void initState() {
    super.initState();
    _loadPendingEvents();
  }

  Future<void> _loadPendingEvents() async {
    setState(() => _isLoading = true);
    final repo = Get.find<EventRepository>();
    try {
      final events = await repo.getPendingEventsAdmin();
      setState(() {
        _pendingEvents = events;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[EventAdminModerationScreen] Error: $e');
      Get.snackbar('Accès Refusé', 'Privilèges administrateur requis.');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _validateEvent(String eventId) async {
    final repo = Get.find<EventRepository>();
    try {
      await repo.validateEventAdmin(eventId);
      setState(() {
        _pendingEvents.removeWhere((e) => e.id == eventId);
      });
      Get.snackbar('Modération', 'Événement validé avec succès !');
    } catch (e) {
      Get.snackbar('Erreur Modération', e.toString());
    }
  }

  void _showRejectDialog(String eventId) {
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
              Text('Rejeter l\'événement', style: AppTextStyles.h4),
              const SizedBox(height: 8),
              Text(
                'Veuillez saisir le motif obligatoire du rejet qui sera transmis au créateur.',
                style: AppTextStyles.bodySmall,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Ex: Contenu inapproprié ou informations manquantes...',
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
                        Get.snackbar('Erreur', 'Le motif du rejet est obligatoire.');
                        return;
                      }
                      Get.back();
                      final repo = Get.find<EventRepository>();
                      try {
                        await repo.rejectEventAdmin(eventId, reason);
                        setState(() {
                          _pendingEvents.removeWhere((e) => e.id == eventId);
                        });
                        Get.snackbar('Modération', 'Événement rejeté.');
                      } catch (e) {
                        Get.snackbar('Erreur Modération', e.toString());
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
                    child: const Text('Confirmer le rejet'),
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
        appBar: AppBar(title: const Text('Modération Administrateur')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Modération des Événements',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        ),
      ),
      body: _pendingEvents.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.verified_user_outlined, size: 64, color: AppColors.textSecondary),
                  const SizedBox(height: 16),
                  Text('Aucun événement en attente de modération.', style: AppTextStyles.body),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _pendingEvents.length,
              itemBuilder: (context, index) {
                final event = _pendingEvents[index];

                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (event.coverImageUrl != null && event.coverImageUrl!.isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: AppCachedImage(
                              imageUrl: event.coverImageUrl!,
                              height: 140,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                        const SizedBox(height: 12),
                        Text(event.name, style: GoogleFonts.spaceGrotesk(fontSize: 20, fontWeight: FontWeight.bold)),
                        Text('@${event.slug}', style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text(event.description ?? 'Pas de description', style: AppTextStyles.bodySmall),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.calendar_today_rounded, size: 16, color: AppColors.primary),
                            const SizedBox(width: 8),
                            Text(event.startsAt.toString().substring(0, 16), style: AppTextStyles.bodySmall),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _showRejectDialog(event.id),
                              icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.error),
                              label: const Text('Rejeter', style: TextStyle(color: AppColors.error)),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton.icon(
                              onPressed: () => _validateEvent(event.id),
                              icon: const Icon(Icons.check_rounded, size: 18),
                              label: const Text('Valider'),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700]),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
