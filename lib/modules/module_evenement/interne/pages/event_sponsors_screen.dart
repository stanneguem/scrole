import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../../centre/models/event_model.dart';
import '../../centre/models/event_sponsor_invitation_model.dart';
import '../controllers/sponsor_invitation_controller.dart';
import 'invite_sponsor_candidate_screen.dart';

class EventSponsorsScreen extends StatefulWidget {
  final EventModel? event;

  const EventSponsorsScreen({super.key, this.event});

  @override
  State<EventSponsorsScreen> createState() => _EventSponsorsScreenState();
}

class _EventSponsorsScreenState extends State<EventSponsorsScreen> {
  late final EventModel _event;
  late final SponsorInvitationController controller;

  @override
  void initState() {
    super.initState();
    final args = widget.event ?? Get.arguments;
    if (args is EventModel) {
      _event = args;
    } else {
      _event = EventModel(
        id: Get.parameters['id'] ?? '',
        creatorId: '',
        name: 'Événement',
        slug: '',
        startsAt: DateTime.now(),
        createdAt: DateTime.now(),
      );
    }
    controller = Get.put(SponsorInvitationController(eventId: _event.id), tag: _event.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Sponsors',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: () => Get.to(() => InviteSponsorCandidateScreen(controller: controller)),
              child: const Text(
                'Inviter',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Obx(() {
        if (controller.isLoadingInvitations.value) {
          return const Center(child: CircularProgressIndicator());
        }

        final accepted = controller.acceptedSponsors;
        final pending = controller.pendingSponsors;
        final declined = controller.declinedSponsors;
        final isEmpty = controller.invitations.isEmpty;

        if (isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.workspace_premium_outlined, size: 64, color: AppColors.textSecondary),
                  const SizedBox(height: 16),
                  Text('Aucun sponsor pour cet événement', style: AppTextStyles.h4, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(
                    'Invitez des sponsors ou partenaires publics à votre événement en appuyant sur « Inviter » en haut à droite.',
                    style: AppTextStyles.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (accepted.isNotEmpty) ...[
              _buildSectionTitle('SPONSORS (${accepted.length})', AppColors.primary),
              ...accepted.map((sponsor) => _SponsorTile(sponsor: sponsor, controller: controller)),
            ],
            if (pending.isNotEmpty) ...[
              const SizedBox(height: 20),
              _buildSectionTitle('INVITATIONS EN ATTENTE (${pending.length})', Colors.orange),
              ...pending.map((sponsor) => _SponsorTile(sponsor: sponsor, controller: controller)),
            ],
            if (declined.isNotEmpty) ...[
              const SizedBox(height: 20),
              _buildSectionTitle('INVITATIONS REFUSÉES (${declined.length})', AppColors.error),
              ...declined.map((sponsor) => _SponsorTile(sponsor: sponsor, controller: controller)),
            ],
          ],
        );
      }),
    );
  }

  Widget _buildSectionTitle(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        title,
        style: AppTextStyles.labelSmall.copyWith(color: color, letterSpacing: 1.2, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _SponsorTile extends StatelessWidget {
  final EventSponsorInvitationModel sponsor;
  final SponsorInvitationController controller;

  const _SponsorTile({required this.sponsor, required this.controller});

  void _showRemoveDialog(BuildContext context) {
    Get.dialog(
      AlertDialog(
        title: const Text('Retirer le sponsor ?'),
        content: Text(
          'Voulez-vous vraiment retirer ${sponsor.userName} des sponsors ? Si l\'invitation avait été acceptée, le rôle sponsor sera révoqué.',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              Get.back();
              controller.removeSponsor(sponsor);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Retirer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusText = sponsor.status == SponsorInvitationStatus.accepted
        ? 'Sponsor'
        : (sponsor.status == SponsorInvitationStatus.pending ? 'En attente' : 'Refusé');

    final statusColor = sponsor.status == SponsorInvitationStatus.accepted
        ? AppColors.primary
        : (sponsor.status == SponsorInvitationStatus.pending ? Colors.orange : AppColors.error);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: sponsor.avatarUrl != null && sponsor.avatarUrl!.isNotEmpty
              ? AppCachedImage(imageUrl: sponsor.avatarUrl!, width: 48, height: 48, fit: BoxFit.cover)
              : Container(
                  width: 48,
                  height: 48,
                  color: statusColor.withValues(alpha: 0.12),
                  child: Icon(Icons.workspace_premium_rounded, color: statusColor),
                ),
        ),
        title: Text(sponsor.userName, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
        subtitle: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                statusText,
                style: AppTextStyles.caption.copyWith(color: statusColor, fontWeight: FontWeight.bold),
              ),
            ),
            if (sponsor.userUsername != null && sponsor.userUsername!.isNotEmpty) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '@${sponsor.userUsername}',
                  style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
        trailing: TextButton(
          onPressed: () => _showRemoveDialog(context),
          child: const Text('Retirer', style: TextStyle(color: AppColors.error, fontSize: 13)),
        ),
      ),
    );
  }
}
