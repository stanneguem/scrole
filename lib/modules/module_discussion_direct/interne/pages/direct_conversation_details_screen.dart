import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../app/routes/app_pages.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../../../../shared/widgets/user_certified_badge.dart';
import '../../../module_decouverte/centre/models/external_profile_model.dart';
import '../../../module_decouverte/externe/repositories/external_profile_repository.dart';
import '../controllers/direct_conversation_controller.dart';
import 'chat_wallpaper_selection_screen.dart';

class DirectConversationDetailsScreen extends StatefulWidget {
  const DirectConversationDetailsScreen({
    super.key,
    required this.userId,
    required this.userName,
    required this.userColor,
    this.userAvatar,
  });

  final String userId;
  final String userName;
  final Color userColor;
  final String? userAvatar;

  @override
  State<DirectConversationDetailsScreen> createState() =>
      _DirectConversationDetailsScreenState();
}

class _DirectConversationDetailsScreenState
    extends State<DirectConversationDetailsScreen> {
  final ExternalProfileRepository _profileRepository =
      ExternalProfileRepository();

  bool _notificationsEnabled = true;
  bool _mediaVisibilityEnabled = true;
  bool _savingPreferences = false;
  ExternalProfileModel? _profile;

  String get _displayName {
    final name = (_profile?.username ?? widget.userName).trim();
    if (name.isEmpty) return name;
    return name[0].toUpperCase() + name.substring(1);
  }

  String get _username => _profile?.username ?? '';

  String? get _avatarUrl {
    final value = _profile?.photoUrl ?? widget.userAvatar;
    return value == null || value.trim().isEmpty ? null : value;
  }

  String? get _coverUrl {
    final value = _profile?.photoUrl;
    return value == null || value.trim().isEmpty ? null : value;
  }

  bool get _isVerified => _profile?.isCertified ?? false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadConversationPreferences();
  }

  Future<void> _loadConversationPreferences() async {
    final controller = Get.isRegistered<DirectConversationController>()
        ? Get.find<DirectConversationController>()
        : null;
    if (controller == null) return;
    await controller.loadConversationPreferences();
    if (!mounted) return;
    setState(() {
      _notificationsEnabled = controller.conversationNotificationsEnabled.value;
      _mediaVisibilityEnabled = controller.saveIncomingMediaToGallery.value;
    });
  }

  Future<void> _updatePreference({
    bool? notificationsEnabled,
    bool? mediaVisibilityEnabled,
  }) async {
    if (_savingPreferences) return;
    final controller = Get.find<DirectConversationController>();
    final previousNotifications = _notificationsEnabled;
    final previousMedia = _mediaVisibilityEnabled;
    setState(() {
      _savingPreferences = true;
      if (notificationsEnabled != null) _notificationsEnabled = notificationsEnabled;
      if (mediaVisibilityEnabled != null) _mediaVisibilityEnabled = mediaVisibilityEnabled;
    });
    try {
      await controller.updateConversationPreference(
        notificationsEnabled: notificationsEnabled,
        saveMediaToGallery: mediaVisibilityEnabled,
      );
      if (!mounted) return;
      Get.snackbar(
        'chats_title'.tr,
        'Préférences de discussion enregistrées.',
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(12),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _notificationsEnabled = previousNotifications;
        _mediaVisibilityEnabled = previousMedia;
      });
      Get.snackbar(
        'Erreur',
        'Impossible d’enregistrer ce réglage. Réessaie.',
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(12),
      );
    } finally {
      if (mounted) setState(() => _savingPreferences = false);
    }
  }

  Future<void> _loadProfile() async {
    if (widget.userId.trim().isEmpty) return;
    try {
      final profile = await _profileRepository.getProfile(widget.userId);
      if (!mounted) return;
      setState(() => _profile = profile);
    } catch (_) {
      // The chat-provided identity remains available if the profile request fails.
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadProfile,
          color: colors.primary,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _buildHeader(colors),
              const SizedBox(height: 12),
              _buildIdentity(colors),
              const SizedBox(height: 24),
              _buildSettingsSection(colors),
              const SizedBox(height: 16),
              _buildWallpaperSection(colors),
              const SizedBox(height: 16),
              _buildDangerSection(colors),
              const SizedBox(height: 16),
              _buildReportSection(colors),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme colors) {
    return SizedBox(
      height: 185,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SizedBox(
            height: 140,
            width: double.infinity,
            child: _coverUrl == null
                ? Container(color: AppColors.secondary.withValues(alpha: .25))
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      AppCachedImage(imageUrl: _coverUrl!, fit: BoxFit.cover),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: .28),
                              Colors.transparent,
                              colors.surface.withValues(alpha: .35),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          Positioned(
            top: 12,
            left: 16,
            child: _headerButton(
              icon: Icons.arrow_back_ios_new_rounded,
              onTap: Get.back,
            ),
          ),
          Positioned(
            top: 12,
            right: 16,
            child: _headerButton(
              icon: Icons.more_horiz_rounded,
              onTap: () => _comingSoon('direct_details_more_action'.tr),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 20,
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: colors.surface, width: 5),
                color: widget.userColor.withValues(alpha: .12),
              ),
              child: ClipOval(
                child: _avatarUrl == null
                    ? Center(
                        child: Text(
                          _displayName.isEmpty
                              ? '?'
                              : _displayName.characters.first.toUpperCase(),
                          style: TextStyle(
                            color: widget.userColor,
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      )
                    : AppCachedImage(imageUrl: _avatarUrl!, fit: BoxFit.cover),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.black.withValues(alpha: .42),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  Widget _buildIdentity(ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _displayName,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.h4.copyWith(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (_isVerified) ...[
                      const SizedBox(width: 5),
                      UserCertifiedBadge(
                        userId: widget.userId,
                        size: 20,
                      ),
                    ],
                  ],
                ),
                if (_username.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    '@$_username',
                    style: AppTextStyles.body.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: SizedBox(
              width: 46,
              height: 46,
              child: Material(
                color: colors.surfaceContainerHighest.withValues(alpha: .55),
                borderRadius: BorderRadius.circular(13),
                child: InkWell(
                  onTap: () => Get.toNamed(
                    AppPages.externalProfilePath(widget.userId),
                  ),
                  borderRadius: BorderRadius.circular(13),
                  child: Icon(
                    Icons.person_outline_rounded,
                    size: 21,
                    color: colors.onSurface,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSection(ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _section(
        colors,
        children: [
          _switchTile(
            icon: Icons.notifications_none_rounded,
            title: 'direct_details_notifications'.tr,
            value: _notificationsEnabled,
            onChanged: (value) => _updatePreference(notificationsEnabled: value),
          ),
          _switchTile(
            icon: Icons.photo_library_outlined,
            title: 'direct_details_media_visibility'.tr,
            subtitle: 'direct_details_media_visibility_subtitle'.tr,
            value: _mediaVisibilityEnabled,
            onChanged: (value) => _updatePreference(mediaVisibilityEnabled: value),
          ),
        ],
      ),
    );
  }

  Widget _buildWallpaperSection(ColorScheme colors) {
    final controller = Get.isRegistered<DirectConversationController>()
        ? Get.find<DirectConversationController>()
        : null;

    if (controller == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _section(
        colors,
        children: [
          _actionTile(
            icon: Icons.wallpaper_rounded,
            title: 'direct_details_wallpaper'.tr,
            subtitle: 'Personnalise le fond de cette discussion sur ton appareil.',
            onTap: () {
              Get.to(
                () => ChatWallpaperSelectionScreen(
                  initialWallpaper: controller.selectedWallpaper.value,
                  userName: _displayName,
                  userColor: widget.userColor,
                  userAvatar: _avatarUrl,
                  onApply: (wallpaperKey) =>
                      controller.setWallpaper(wallpaperKey),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDangerSection(ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _section(
        colors,
        children: [
          _actionTile(
            icon: Icons.history_rounded,
            title: 'direct_details_clear'.tr,
            destructive: true,
            onTap: _confirmClearConversation,
          ),
          Obx(() {
            final blocked = Get.find<DirectConversationController>().blockedByMe.value;
            return _actionTile(
              icon: blocked ? Icons.lock_open_rounded : Icons.block_rounded,
              title: blocked
                  ? 'Débloquer $_displayName'
                  : 'direct_details_block'.trParams({'name': _displayName}),
              destructive: !blocked,
              onTap: _confirmBlock,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildReportSection(ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _section(
        colors,
        children: [
          _actionTile(
            icon: Icons.flag_outlined,
            title: 'direct_details_report'.trParams({'name': _displayName}),
            destructive: true,
            onTap: _showReportDialog,
          ),
        ],
      ),
    );
  }

  Widget _section(ColorScheme colors, {required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: .28),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outline.withValues(alpha: .08)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    final color = destructive ? AppColors.error : colors.onSurface;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Row(
            children: [
              Icon(icon, color: color, size: 21),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(color: color, fontWeight: FontWeight.w600),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: colors.onSurfaceVariant.withValues(alpha: .6),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _switchTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
        child: Row(
          children: [
            Icon(icon, size: 21, color: colors.onSurfaceVariant),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            CupertinoSwitch(
              value: value,
              onChanged: onChanged,
              activeTrackColor: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }

  void _confirmClearConversation() {
    Get.dialog(
      AlertDialog(
        title: Text('direct_details_clear'.tr),
        content: const Text(
          'Cette action efface la discussion de votre messagerie. Elle ne supprime pas les messages chez l’autre personne.',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text('cancel'.tr),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () async {
              Get.back();
              try {
                await Get.find<DirectConversationController>()
                    .clearConversationForMe();
                if (!mounted) return;
                Get.back();
                Get.snackbar(
                  'chats_title'.tr,
                  'Discussion effacée de votre messagerie.',
                  snackPosition: SnackPosition.BOTTOM,
                  margin: const EdgeInsets.all(12),
                );
              } catch (e) {
                Get.snackbar(
                  'chats_title'.tr,
                  'Impossible d’effacer la discussion : $e',
                  snackPosition: SnackPosition.BOTTOM,
                  margin: const EdgeInsets.all(12),
                );
              }
            },
            child: const Text('Effacer'),
          ),
        ],
      ),
    );
  }

  void _confirmBlock() {
    final controller = Get.find<DirectConversationController>();
    final isBlocked = controller.blockedByMe.value;
    final action = isBlocked ? 'Débloquer' : 'Bloquer';
    Get.dialog(
      AlertDialog(
        title: Text('$action $_displayName ?'),
        content: Text(isBlocked
            ? 'Cette personne pourra de nouveau vous envoyer des messages.'
            : 'Cette personne ne pourra plus vous envoyer de messages.'),
        actions: [
          TextButton(onPressed: Get.back, child: Text('cancel'.tr)),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: isBlocked ? AppColors.primary : AppColors.error,
            ),
            onPressed: () async {
              Get.back();
              try {
                await controller.toggleBlockOtherUser();
                if (!mounted) return;
                Get.back();
                Get.snackbar(
                  'chats_title'.tr,
                  controller.blockedByMe.value
                      ? '$_displayName a été bloqué.'
                      : '$_displayName a été débloqué.',
                  snackPosition: SnackPosition.BOTTOM,
                  margin: const EdgeInsets.all(12),
                );
              } catch (e) {
                Get.snackbar(
                  'chats_title'.tr,
                  'Impossible de ${isBlocked ? 'débloquer' : 'bloquer'} cet utilisateur : $e',
                  snackPosition: SnackPosition.BOTTOM,
                  margin: const EdgeInsets.all(12),
                );
              }
            },
            child: Text(action),
          ),
        ],
      ),
    );
  }

  Future<void> _showReportDialog() async {
    final detailsController = TextEditingController();
    String reason = 'Harcèlement ou intimidation';
    const reasons = <String>[
      'Harcèlement ou intimidation',
      'Contenu haineux',
      'Usurpation d’identité',
      'Spam ou arnaque',
      'Contenu inapproprié',
      'Autre',
    ];
    final confirmed = await Get.dialog<bool>(
      Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: StatefulBuilder(
          builder: (context, setDialogState) {
            final colors = Theme.of(context).colorScheme;
            return Padding(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: Container(
                      width: 52, height: 52,
                      decoration: BoxDecoration(color: colors.errorContainer, shape: BoxShape.circle),
                      child: Icon(CupertinoIcons.flag_fill, color: colors.onErrorContainer, size: 22),
                    )),
                    const SizedBox(height: 14),
                    Text('Signaler $_displayName', textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text('Pourquoi souhaitez-vous signaler cette personne ? Votre signalement sera transmis à notre équipe pour examen.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant, height: 1.35)),
                    const SizedBox(height: 20),
                    Text('MOTIF', style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant, letterSpacing: 1.1, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(color: colors.surfaceContainerHighest.withValues(alpha: .55), borderRadius: BorderRadius.circular(16)),
                      child: Column(children: [
                        for (var i = 0; i < reasons.length; i++) ...[
                          InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => setDialogState(() => reason = reasons[i]),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              child: Row(children: [
                                Expanded(child: Text(reasons[i], style: Theme.of(context).textTheme.bodyMedium)),
                                if (reason == reasons[i]) Icon(CupertinoIcons.checkmark_circle_fill, color: colors.primary, size: 20),
                              ]),
                            ),
                          ),
                          if (i < reasons.length - 1) Divider(height: 1, indent: 12, color: colors.outlineVariant.withValues(alpha: .45)),
                        ],
                      ]),
                    ),
                    const SizedBox(height: 18),
                    Text('DÉTAILS (FACULTATIF)', style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant, letterSpacing: 1.1, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: detailsController, maxLines: 3, maxLength: 2000,
                      decoration: InputDecoration(
                        hintText: 'Ajoutez des précisions utiles…', filled: true,
                        fillColor: colors.surfaceContainerHighest.withValues(alpha: .45),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: colors.primary, width: 1)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: OutlinedButton(
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                        onPressed: () => Get.back(result: false), child: Text('Annuler', style: TextStyle(color: colors.onSurface)))),
                      const SizedBox(width: 10),
                      Expanded(child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: colors.error, foregroundColor: colors.onError, minimumSize: const Size.fromHeight(46), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                        onPressed: () => Get.back(result: true), child: const Text('Envoyer'))),
                    ]),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
    if (confirmed != true) {
      detailsController.dispose();
      return;
    }
    try {
      final controller = Get.find<DirectConversationController>();
      await controller.reportOtherUser(reason, detailsController.text.trim().isEmpty ? null : detailsController.text.trim());
      Get.snackbar('Signalement envoyé', 'Merci. Votre signalement a été transmis pour examen.',
        snackPosition: SnackPosition.BOTTOM, margin: const EdgeInsets.all(12));
    } catch (e) {
      Get.snackbar('chats_title'.tr, 'Impossible d’envoyer le signalement : $e',
        snackPosition: SnackPosition.BOTTOM, margin: const EdgeInsets.all(12));
    } finally {
      detailsController.dispose();
    }
  }

  void _comingSoon(String feature) {
    Get.snackbar(
      'chats_title'.tr,
      'direct_details_coming_soon'.trParams({'feature': feature}),
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(12),
      duration: const Duration(seconds: 2),
    );
  }
}
