import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../../centre/models/event_model.dart';
import '../../centre/models/event_guest_invitation_model.dart';
import '../controllers/guest_invitation_controller.dart';
import 'invite_guest_candidate_screen.dart';

class EventGuestInvitationsScreen extends StatefulWidget {
  final EventModel? event;

  const EventGuestInvitationsScreen({super.key, this.event});

  @override
  State<EventGuestInvitationsScreen> createState() => _EventGuestInvitationsScreenState();
}

class _EventGuestInvitationsScreenState extends State<EventGuestInvitationsScreen> {
  late final EventModel _event;
  late final GuestInvitationController controller;

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
    controller = Get.put(GuestInvitationController(eventId: _event.id), tag: _event.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Invitations d\'honneur',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: () => Get.to(() => InviteGuestCandidateScreen(controller: controller)),
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

        final accepted = controller.acceptedGuests;
        final pending = controller.pendingGuests;
        final declined = controller.declinedGuests;
        final isEmpty = controller.invitations.isEmpty;

        if (isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.mark_email_read_outlined, size: 64, color: AppColors.textSecondary),
                  const SizedBox(height: 16),
                  Text('Aucun invité d\'honneur', style: AppTextStyles.h4, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(
                    'Invitez des personnalités ou profils publics de Scrole à votre événement en appuyant sur « Inviter » en haut à droite.',
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
              _buildSectionTitle('INVITÉS D\'HONNEUR (${accepted.length})', AppColors.primary),
              ...accepted.map((guest) => _GuestTile(guest: guest, controller: controller)),
            ],
            if (pending.isNotEmpty) ...[
              const SizedBox(height: 20),
              _buildSectionTitle('INVITATIONS EN ATTENTE (${pending.length})', Colors.orange),
              ...pending.map((guest) => _GuestTile(guest: guest, controller: controller)),
            ],
            if (declined.isNotEmpty) ...[
              const SizedBox(height: 20),
              _buildSectionTitle('INVITATIONS REFUSÉES (${declined.length})', AppColors.error),
              ...declined.map((guest) => _GuestTile(guest: guest, controller: controller)),
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

class _GuestTile extends StatelessWidget {
  final EventGuestInvitationModel guest;
  final GuestInvitationController controller;

  const _GuestTile({required this.guest, required this.controller});

  void _showRemoveDialog(BuildContext context) {
    Get.dialog(
      AlertDialog(
        title: const Text('Retirer l\'invité ?'),
        content: Text(
          'Voulez-vous vraiment retirer ${guest.userName} des invités d\'honneur ? Si l\'invitation avait été acceptée, l\'événement sera également retiré de son agenda.',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              Get.back();
              controller.removeGuest(guest);
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
    final statusText = guest.status == GuestInvitationStatus.accepted
        ? 'Invité d\'honneur'
        : (guest.status == GuestInvitationStatus.pending ? 'En attente' : 'Refusé');

    final statusColor = guest.status == GuestInvitationStatus.accepted
        ? AppColors.primary
        : (guest.status == GuestInvitationStatus.pending ? Colors.orange : AppColors.error);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: guest.avatarUrl != null && guest.avatarUrl!.isNotEmpty
              ? AppCachedImage(imageUrl: guest.avatarUrl!, width: 48, height: 48, fit: BoxFit.cover)
              : Container(
                  width: 48,
                  height: 48,
                  color: statusColor.withValues(alpha: 0.12),
                  child: Icon(Icons.workspace_premium_rounded, color: statusColor),
                ),
        ),
        title: Text(guest.userName, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
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
            if (guest.userUsername != null && guest.userUsername!.isNotEmpty) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '@${guest.userUsername}',
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
