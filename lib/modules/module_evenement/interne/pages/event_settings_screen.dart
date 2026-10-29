import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../app/routes/app_pages.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/widgets/scrole_bottom_sheet.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../centre/models/event_model.dart';
import '../controllers/event_management_controller.dart';
import '../enums/event_enum.dart';
import 'event_pricing_screen.dart';
import 'event_stats_dashboard_screen.dart';
import 'event_interests_screen.dart';
import 'event_guest_invitations_screen.dart';
import 'event_sponsors_screen.dart';
import 'event_open_days_screen.dart';
import 'package:scrole/modules/module_communautes/interne/pages/community_settings_main_screen.dart';

class EventSettingsScreen extends StatelessWidget {
  const EventSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final EventModel event = Get.arguments is Map ? Get.arguments['event'] : Get.arguments;
    final controller = Get.put(EventManagementController(event: event), tag: event.id);
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    // La propriété repose sur l'identifiant du créateur, pas sur le rôle d'affichage.
    // L'accès à la certification est en plus confirmé par le RPC serveur.
    final isCreator = event.creatorId == currentUserId;
    final isPendingValidation = event.status == EventStatus.draft;

    // Un événement en attente de validation reste consultable en aperçu,
    // mais ses paramètres ne doivent pas être accessibles avant publication.
    if (isPendingValidation) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            'event_settings'.tr,
            style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.hourglass_top_rounded, size: 48, color: Colors.orange.shade700),
                const SizedBox(height: 16),
                Text(
                  'Paramètres indisponibles',
                  style: AppTextStyles.h4,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Cet événement est encore en attente de validation administrative. Tu pourras accéder à ses paramètres dès qu’il sera validé.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: Get.back,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Retour à l’aperçu'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'event_settings'.tr,
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(event.name, style: AppTextStyles.h4, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          
          Obx(() {
            final currentStatus = controller.status.value;
            if (currentStatus == EventStatus.draft) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: const Text(
                    'Votre événement est en cours de validation par un administrateur. Il sera publié dès qu\'il sera validé.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              );
            }
            if (currentStatus == EventStatus.pendingDeletion) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                  ),
                  child: const Text(
                    'Cet événement est en attente de suppression définitive (délai de rétention de 30 jours).',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: AppColors.error),
                  ),
                ),
              );
            }
            return const SizedBox.shrink();
          }),

          // --- CERTIFICATION (source de vérité : backend) ---
          FutureBuilder<dynamic>(
            future: Supabase.instance.client.rpc(
              'scrole_get_entity_certification_status',
              params: {'p_entity_type': 'event', 'p_entity_id': event.id},
            ),
            builder: (context, snapshot) {
              final status = snapshot.data is Map
                  ? Map<String, dynamic>.from(snapshot.data as Map)
                  : <String, dynamic>{};
              if (snapshot.connectionState == ConnectionState.waiting ||
                  status['is_owner'] != true) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: ScroleBottomSheetGroup(
                  children: [
                    ScroleBottomSheetAction(
                      icon: Icons.verified_user_outlined,
                      label: 'Certifier l’événement',
                      subtitle: status['entity_certified'] == true
                          ? 'Certification active · gérer les droits'
                          : 'Consulter vos droits inclus ou acheter une certification',
                      onTap: () => Get.to(() => EntityCertificationManagementScreen(
                        entityType: 'event',
                        entityId: event.id,
                        entityName: event.name,
                      )),
                    ),
                  ],
                ),
              );
            },
          ),

          // --- SECTION ÉVÉNEMENT ---
          Text(
            'Événement',
            style: AppTextStyles.labelSmall.copyWith(color: Theme.of(context).colorScheme.primary, letterSpacing: 1.2),
          ),
          const SizedBox(height: 8),
          ScroleBottomSheetGroup(
            children: [
              ScroleBottomSheetAction(
                icon: Icons.edit_outlined,
                label: 'Modifier les informations',
                onTap: () => Get.toNamed(
                  AppPages.eventEdit.replaceFirst(':id', event.id),
                  arguments: event,
                ),
              ),
              const ScroleBottomSheetDivider(),
              ScroleBottomSheetAction(
                icon: Icons.security_outlined,
                label: 'Gérer les conditions d\'accès',
                onTap: () => Get.toNamed(
                  AppPages.eventVisibility.replaceFirst(':id', event.id),
                  arguments: event,
                ),
              ),
              const ScroleBottomSheetDivider(),
              ScroleBottomSheetAction(
                icon: Icons.payments_outlined,
                label: 'Tarification de l\'événement',
                subtitle: event.isFree ? 'Gratuit (Aucun billet payant)' : 'Payant (Billets configurés)',
                onTap: () => Get.to(() => EventPricingScreen(event: event)),
              ),
              const ScroleBottomSheetDivider(),
              ScroleBottomSheetAction(
                icon: Icons.interests_outlined,
                label: 'Centres d\'intérêt de l\'événement',
                subtitle: 'Sélectionner jusqu\'à 5 centres d\'intérêt',
                onTap: () => Get.to(() => EventInterestsScreen(event: event)),
              ),
              if (event.endsAt != null && DateTime(event.endsAt!.year, event.endsAt!.month, event.endsAt!.day).difference(DateTime(event.startsAt.year, event.startsAt.month, event.startsAt.day)).inDays >= 1) ...[
                const ScroleBottomSheetDivider(),
                ScroleBottomSheetAction(
                  icon: Icons.date_range_rounded,
                  label: 'Gérer les jours ouverts',
                  subtitle: 'Définir les jours d\'ouverture de l\'événement',
                  onTap: () => Get.to(() => EventOpenDaysScreen(event: event)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),

          // --- SECTION ÉQUIPE & GESTION ---
          Text(
            'Équipe & Gestion',
            style: AppTextStyles.labelSmall.copyWith(color: Theme.of(context).colorScheme.primary, letterSpacing: 1.2),
          ),
          const SizedBox(height: 8),
          FutureBuilder<dynamic>(
            future: Supabase.instance.client.rpc(
              'scrole_get_entity_certification_status',
              params: {'p_entity_type': 'event', 'p_entity_id': event.id},
            ),
            builder: (context, snapshot) {
              final cert = snapshot.data is Map
                  ? Map<String, dynamic>.from(snapshot.data as Map)
                  : <String, dynamic>{};
              final eventCertified = cert['entity_certified'] == true;
              final communityCertified = cert['community_certified'] == true;
              final actions = <Widget>[];
              if (eventCertified) {
                actions.add(ScroleBottomSheetAction(
                  icon: Icons.insights_rounded,
                  label: 'Statistiques de l\'événement',
                  subtitle: 'Tableau de bord et indicateurs de performance',
                  onTap: () => Get.to(() => EventStatsDashboardScreen(event: event)),
                ));
                actions.add(const ScroleBottomSheetDivider());
              }
              actions.add(ScroleBottomSheetAction(
                icon: Icons.stars_outlined,
                label: 'Gérer les co-fondateurs',
                subtitle: 'Limites applicables aux événements non certifiés',
                onTap: () => Get.toNamed(
                  AppPages.eventCoCreators.replaceFirst(':id', event.id),
                  arguments: event,
                ),
              ));
              actions.add(const ScroleBottomSheetDivider());
              actions.add(ScroleBottomSheetAction(
                icon: Icons.people_outline,
                label: 'Gérer le staff',
                subtitle: eventCertified ? 'Gérer l’équipe et attribuer les activités' : 'Plafond du staff applicable aux événements non certifiés',
                onTap: () => Get.toNamed(
                  AppPages.eventStaff.replaceFirst(':id', event.id),
                  arguments: {'event': event, 'initialTab': 0},
                ),
              ));
              if (eventCertified) {
                actions.addAll([
                  const ScroleBottomSheetDivider(),
                  ScroleBottomSheetAction(
                    icon: Icons.mark_email_read_outlined,
                    label: 'Invitations d\'honneur',
                    subtitle: 'Inviter des personnalités ou profils publics',
                    onTap: () => Get.to(() => EventGuestInvitationsScreen(event: event)),
                  ),
                  const ScroleBottomSheetDivider(),
                  ScroleBottomSheetAction(
                    icon: Icons.workspace_premium_outlined,
                    label: 'Sponsors',
                    subtitle: 'Inviter et gérer les sponsors de l\'événement',
                    onTap: () => Get.to(() => EventSponsorsScreen(event: event)),
                  ),
                ]);
              }
              if (eventCertified || communityCertified) {
                actions.addAll([
                  const ScroleBottomSheetDivider(),
                  ScroleBottomSheetAction(
                    icon: Icons.confirmation_number_outlined,
                    label: 'Gérer la billetterie',
                    onTap: () => Get.toNamed(
                      AppPages.eventTickets.replaceFirst(':id', event.id),
                      arguments: event,
                    ),
                  ),
                ]);
              }
              actions.addAll([
                const ScroleBottomSheetDivider(),
                ScroleBottomSheetAction(
                  icon: Icons.assignment_outlined,
                  label: 'Gérer les activités',
                  onTap: () => Get.toNamed(
                    AppPages.eventActivities.replaceFirst(':id', event.id),
                    arguments: event,
                  ),
                ),
              ]);
              return ScroleBottomSheetGroup(children: actions);
            },
          ),
          const SizedBox(height: 20),

          // --- SECTION PROPRIÉTÉ (Réservée au créateur) ---
          if (isCreator) ...[
            Text(
              'Propriété',
              style: AppTextStyles.labelSmall.copyWith(color: Theme.of(context).colorScheme.primary, letterSpacing: 1.2),
            ),
            const SizedBox(height: 8),
            ScroleBottomSheetGroup(
              children: [
                ScroleBottomSheetAction(
                  icon: Icons.swap_horiz_rounded,
                  label: 'Transférer la propriété',
                  subtitle: 'Uniquement vers un co-fondateur accepté',
                  onTap: () => Get.toNamed(
                    AppPages.eventTransfer.replaceFirst(':id', event.id),
                    arguments: event,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            Text(
              'Zone de danger',
              style: AppTextStyles.labelSmall.copyWith(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            ScroleBottomSheetGroup(
              children: [
                ScroleBottomSheetAction(
                  icon: Icons.delete_forever_outlined,
                  label: 'Supprimer l\'événement',
                  color: Theme.of(context).colorScheme.error,
                  onTap: () => _showDeleteConfirmation(context, controller),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, EventManagementController controller) {
    Get.dialog(
      AlertDialog(
        title: const Text('Supprimer l\'événement ?'),
        content: const Text(
          'L\'événement passera en statut "En attente de suppression" pendant 30 jours avant sa purge définitive, et sera purgé du cache local de tous les participants.'
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              Get.back();
              controller.deleteEvent();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Confirmer la suppression'),
          ),
        ],
      ),
    );
  }
}
