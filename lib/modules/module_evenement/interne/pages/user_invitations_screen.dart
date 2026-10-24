import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../centre/models/co_creator_model.dart';
import '../../centre/models/staff_model.dart';
import '../../centre/models/event_guest_invitation_model.dart';
import '../../centre/models/event_sponsor_invitation_model.dart';
import '../../centre/repositories/event_repository.dart';
import '../controllers/event_controller.dart';

class UserInvitationsScreen extends StatefulWidget {
  const UserInvitationsScreen({super.key});

  @override
  State<UserInvitationsScreen> createState() => _UserInvitationsScreenState();
}

class _UserInvitationsScreenState extends State<UserInvitationsScreen> {
  bool _isLoading = true;
  List<CoCreatorModel> _coCreatorInvites = [];
  List<StaffMemberModel> _staffInvites = [];
  List<EventGuestInvitationModel> _guestInvites = [];
  List<EventSponsorInvitationModel> _sponsorInvites = [];

  @override
  void initState() {
    super.initState();
    _loadInvites();
  }

  Future<void> _loadInvites() async {
    setState(() => _isLoading = true);
    final repo = Get.find<EventRepository>();
    try {
      final coCreators = await repo.getMyPendingCoCreatorInvites();
      final staff = await repo.getMyPendingStaffInvites();
      final guests = await repo.getMyPendingGuestInvites();
      final sponsors = await repo.getMyPendingSponsorInvites();
      setState(() {
        _coCreatorInvites = coCreators;
        _staffInvites = staff;
        _guestInvites = guests;
        _sponsorInvites = sponsors;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[UserInvitationsScreen] Error: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _respondCoCreator(String inviteId, bool accept) async {
    final repo = Get.find<EventRepository>();
    try {
      await repo.respondToCoCreatorInvite(inviteId, accept);
      setState(() {
        _coCreatorInvites.removeWhere((i) => i.id == inviteId);
      });
      Get.snackbar('Co-créateur', accept ? 'Invitation acceptée !' : 'Invitation refusée.');
      if (Get.isRegistered<EventController>()) {
        await Get.find<EventController>().fetchMyEvents();
      }
    } catch (e) {
      Get.snackbar('Erreur', e.toString());
    }
  }

  Future<void> _respondStaff(String inviteId, bool accept) async {
    final repo = Get.find<EventRepository>();
    try {
      await repo.respondToStaffInvite(inviteId, accept);
      setState(() {
        _staffInvites.removeWhere((i) => i.id == inviteId);
      });
      Get.snackbar('Staff', accept ? 'Invitation acceptée !' : 'Invitation refusée.');
      if (Get.isRegistered<EventController>()) {
        await Get.find<EventController>().refreshStaffEvents();
      }
    } catch (e) {
      Get.snackbar('Erreur', e.toString());
    }
  }

  Future<void> _respondGuest(String inviteId, bool accept) async {
    final repo = Get.find<EventRepository>();
    try {
      await repo.respondToGuestInvite(inviteId: inviteId, accept: accept);
      setState(() {
        _guestInvites.removeWhere((i) => i.id == inviteId);
      });
      Get.snackbar(
        'Invité d\'honneur',
        accept ? 'Invitation acceptée ! L\'événement a été ajouté à votre agenda.' : 'Invitation refusée.',
      );
    } catch (e) {
      Get.snackbar('Erreur', e.toString());
    }
  }

  Future<void> _respondSponsor(String inviteId, bool accept) async {
    final repo = Get.find<EventRepository>();
    try {
      await repo.respondToSponsorInvite(inviteId: inviteId, accept: accept);
      setState(() {
        _sponsorInvites.removeWhere((i) => i.id == inviteId);
      });
      Get.snackbar(
        'Sponsor',
        accept ? 'Invitation sponsor acceptée ! L\'événement a été ajouté à votre agenda.' : 'Invitation refusée.',
      );
    } catch (e) {
      Get.snackbar('Erreur', e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mes invitations')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final isEmpty = _coCreatorInvites.isEmpty && _staffInvites.isEmpty && _guestInvites.isEmpty && _sponsorInvites.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Mes Invitations',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        ),
      ),
      body: isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.mail_outline_rounded, size: 64, color: AppColors.textSecondary),
                  const SizedBox(height: 16),
                  Text('Aucune invitation en attente', style: AppTextStyles.body),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_sponsorInvites.isNotEmpty) ...[
                  Text('INVITATIONS SPONSOR', style: AppTextStyles.labelSmall.copyWith(letterSpacing: 1.2, color: AppColors.primary)),
                  const SizedBox(height: 8),
                  ..._sponsorInvites.map((invite) => Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.workspace_premium_outlined, color: AppColors.primary, size: 22),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      invite.eventName ?? 'Invitation Sponsor',
                                      style: AppTextStyles.h4,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Vous avez été invité(e) en tant que Sponsor. En acceptant, cet événement apparaîtra automatiquement dans votre agenda.',
                                style: AppTextStyles.bodySmall,
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  OutlinedButton(
                                    onPressed: () => _respondSponsor(invite.id, false),
                                    child: const Text('Refuser'),
                                  ),
                                  const SizedBox(width: 12),
                                  ElevatedButton(
                                    onPressed: () => _respondSponsor(invite.id, true),
                                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                                    child: const Text('Accepter'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      )),
                  const SizedBox(height: 20),
                ],
                if (_guestInvites.isNotEmpty) ...[
                  Text('INVITATIONS D\'HONNEUR', style: AppTextStyles.labelSmall.copyWith(letterSpacing: 1.2, color: AppColors.primary)),
                  const SizedBox(height: 8),
                  ..._guestInvites.map((invite) => Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.workspace_premium_rounded, color: AppColors.primary, size: 22),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      invite.eventName ?? 'Invitation Événement',
                                      style: AppTextStyles.h4,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Vous avez été invité(e) en tant qu\'invité d\'honneur. En acceptant, cet événement apparaîtra automatiquement dans votre agenda.',
                                style: AppTextStyles.bodySmall,
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  OutlinedButton(
                                    onPressed: () => _respondGuest(invite.id, false),
                                    child: const Text('Refuser'),
                                  ),
                                  const SizedBox(width: 12),
                                  ElevatedButton(
                                    onPressed: () => _respondGuest(invite.id, true),
                                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                                    child: const Text('Accepter'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      )),
                  const SizedBox(height: 20),
                ],
                if (_coCreatorInvites.isNotEmpty) ...[
                  Text('INVITATIONS CO-CRÉATEUR', style: AppTextStyles.labelSmall.copyWith(letterSpacing: 1.2)),
                  const SizedBox(height: 8),
                  ..._coCreatorInvites.map((invite) => Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Invitation Co-créateur', style: AppTextStyles.h4),
                              const SizedBox(height: 4),
                              Text('Vous avez été invité à co-gérer cet événement.', style: AppTextStyles.bodySmall),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  OutlinedButton(
                                    onPressed: () => _respondCoCreator(invite.id, false),
                                    child: const Text('Refuser'),
                                  ),
                                  const SizedBox(width: 12),
                                  ElevatedButton(
                                    onPressed: () => _respondCoCreator(invite.id, true),
                                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                                    child: const Text('Accepter'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      )),
                  const SizedBox(height: 20),
                ],
                if (_staffInvites.isNotEmpty) ...[
                  Text('INVITATIONS STAFF', style: AppTextStyles.labelSmall.copyWith(letterSpacing: 1.2)),
                  const SizedBox(height: 8),
                  ..._staffInvites.map((invite) => Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Invitation Équipe Staff', style: AppTextStyles.h4),
                              const SizedBox(height: 4),
                              Text('Vous avez été invité à rejoindre l\'équipe staff.', style: AppTextStyles.bodySmall),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  OutlinedButton(
                                    onPressed: () => _respondStaff(invite.id, false),
                                    child: const Text('Refuser'),
                                  ),
                                  const SizedBox(width: 12),
                                  ElevatedButton(
                                    onPressed: () => _respondStaff(invite.id, true),
                                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                                    child: const Text('Accepter'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      )),
                ],
              ],
            ),
    );
  }
}
