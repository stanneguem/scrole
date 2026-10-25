import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:scrole/app/routes/app_pages.dart';
import 'package:scrole/app/theme/app_colors.dart';
import 'package:scrole/app/theme/text_styles.dart';
import 'package:scrole/shared/models/interest_model.dart';
import 'package:scrole/shared/utils/number_formatter.dart';
import 'package:scrole/shared/widgets/app_cached_image.dart';
import 'package:scrole/shared/widgets/profile_post_detail_screen.dart';
import 'package:scrole/modules/module_principale/centre/models/community_post.dart';
import 'package:scrole/shared/widgets/user_certified_badge.dart';
import 'package:scrole/shared/widgets/entity_certified_badge.dart';
import '../../../module_evenement/interne/pages/external_event_itinerary_screen.dart';
import '../controllers/external_profile_controller.dart';


String _formatLastSeen(DateTime value) {
  final local = value.toLocal();
  final languageCode = Get.locale?.languageCode ?? 'fr';
  final pattern = switch (languageCode) {
    'fr' => "d MMMM yyyy 'à' HH:mm",
    'en' => "MMMM d, yyyy 'at' h:mm a",
    'es' => "d 'de' MMMM 'de' yyyy 'a las' HH:mm",
    'de' => "d. MMMM yyyy 'um' HH:mm",
    'it' => "d MMMM yyyy 'alle' HH:mm",
    'pt' => "d 'de' MMMM 'de' yyyy 'às' HH:mm",
    'zh' => "yyyy年M月d日 HH:mm",
    'ja' => "yyyy年M月d日 HH:mm",
    'ru' => "d MMMM yyyy 'в' HH:mm",
    _ => "d MMMM yyyy HH:mm",
  };
  return DateFormat(pattern, languageCode).format(local);
}

class ExternalProfileScreen extends GetView<ExternalProfileController> {
  const ExternalProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Obx(() {
          if (controller.isLoading.value) {
            return Center(
              child: CircularProgressIndicator(color: colors.primary),
            );
          }

          final state = controller.profileState.value;

          if (state == ProfileScreenState.deleted) {
            return const _ProfileDeletedView();
          }

          if (state == ProfileScreenState.notFound) {
            return const _ProfileNotFoundView();
          }

          if (state == ProfileScreenState.error) {
            return _ProfileErrorView(
              message: controller.error.value,
              onRetry: controller.loadProfile,
            );
          }

          final isSuspended = state == ProfileScreenState.suspended;
          final isBanned = state == ProfileScreenState.banned;
          final profile = controller.profile.value;

          Widget backgroundProfileView;
          if (profile != null) {
            backgroundProfileView = ListView(
              padding: EdgeInsets.zero,
              children: [
                const _ReactiveHeader(),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _ReactiveIdentity(),
                      const SizedBox(height: 16),
                      const _ReactiveProfileBody(),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ],
            );
          } else {
            backgroundProfileView = Container(color: colors.surface);
          }

          if (isSuspended || isBanned) {
            return Stack(
              fit: StackFit.expand,
              children: [
                AbsorbPointer(
                  absorbing: true,
                  child: backgroundProfileView,
                ),
                if (isSuspended)
                  _BlockingProfileOverlay(
                    title: 'profile_unavailable_title'.tr,
                    message: 'profile_suspended_message'.tr,
                    icon: Icons.pause_circle_outline_rounded,
                    iconColor: Colors.orange,
                  )
                else if (isBanned)
                  _BlockingProfileOverlay(
                    title: 'profile_unavailable_title'.tr,
                    message: 'profile_banned_message'.tr,
                    icon: Icons.block_rounded,
                    iconColor: Colors.red,
                  ),
              ],
            );
          }

          if (profile == null) return const SizedBox.shrink();
          if (profile.isBlocked) {
            return _PrivateProfile(
              message: 'profile_blocked_msg'.tr,
            );
          }

          return RefreshIndicator(
            onRefresh: controller.loadProfile,
            color: colors.primary,
            child: backgroundProfileView,
          );
        }),
      ),
    );
  }
}

class _ReactiveHeader extends GetView<ExternalProfileController> {
  const _ReactiveHeader();
  @override
  Widget build(BuildContext context) =>
      Obx(() => _Header(profile: controller.profile.value!));
}

class _Header extends StatelessWidget {
  const _Header({required this.profile});
  final dynamic profile;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: 185,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SizedBox(
            height: 140,
            width: double.infinity,
            child: profile.coverUrl == null || profile.coverUrl!.isEmpty
                ? Container(color: AppColors.secondary.withValues(alpha: .25))
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      AppCachedImage(
                        imageUrl: profile.coverUrl!,
                        fit: BoxFit.cover,
                      ),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: .30),
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
            child: _HeaderButton(
              icon: Icons.arrow_back_ios_new_rounded,
              onTap: Get.back,
            ),
          ),
          Positioned(
            top: 12,
            right: 16,
            child: _HeaderButton(
              icon: Icons.more_horiz_rounded,
              onTap: () => _showProfileMenu(context),
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
                color: colors.primary,
              ),
              child: ClipOval(
                child: profile.photoUrl == null || profile.photoUrl!.isEmpty
                    ? const Icon(
                        Icons.person_rounded,
                        size: 48,
                        color: Colors.white,
                      )
                    : AppCachedImage(
                        imageUrl: profile.photoUrl!,
                        fit: BoxFit.cover,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showProfileMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .35),
      builder: (_) => const _ProfileMenuSheet(),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
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

class _ReactiveIdentity extends GetView<ExternalProfileController> {
  const _ReactiveIdentity();
  @override
  Widget build(BuildContext context) => Obx(() {
    final p = controller.profile.value!;
    final name = p.displayName.trim();
    final displayName = name.isEmpty
        ? name
        : '${name[0].toUpperCase()}${name.substring(1)}';
    return _Identity(
      profile: p,
      displayName: displayName,
      controller: controller,
    );
  });
}

class _Identity extends StatelessWidget {
  const _Identity({
    required this.profile,
    required this.displayName,
    required this.controller,
  });
  final dynamic profile;
  final String displayName;
  final ExternalProfileController controller;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
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
                      displayName,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.h4.copyWith(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (profile.isCertified) ...[
                    const SizedBox(width: 6),
                    UserCertifiedBadge(size: 20, userId: profile.userId),
                  ],
                ],
              ),
              if ((profile.username ?? '').toString().trim().isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  '@${profile.username}',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              if (profile.age != null || (profile.gender ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (profile.age != null) ...[
                      Text(
                        '${profile.age} ans',
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    if (profile.age != null && (profile.gender ?? '').trim().isNotEmpty)
                      Text(' • ', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
                    if ((profile.gender ?? '').trim().isNotEmpty) ...[
                      Text(
                        profile.gender!,
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              if ((profile.city ?? '').toString().trim().isNotEmpty ||
                  (profile.country ?? '').toString().trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 14,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        [profile.city, profile.country]
                            .where((s) => s != null && s.toString().trim().isNotEmpty)
                            .join(', '),
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              if (profile.isOnline) ...[
                const SizedBox(height: 4),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(color: Color(0xFF34C759), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 5),
                  Text('profile_online'.tr, style: TextStyle(
                    color: colors.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.w600)),
                ]),
              ] else if (profile.lastSeenAt != null) ...[
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'profile_last_seen_label'.tr,
                        style: TextStyle(color: colors.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatLastSeen(profile.lastSeenAt!),
                        style: TextStyle(color: colors.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 10),
        _HeaderStats(profile: profile),
      ],
    );
  }
}

class _ProfileActions extends GetView<ExternalProfileController> {
  const _ProfileActions({required this.controller});
  final ExternalProfileController controller;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Obx(() {
      final p = controller.profile.value!;
      final relationState = p.relationshipState;
      final pending = relationState == 'requested';
      final connected = p.isConnected || relationState == 'friends';
      final busy = controller.isSendingRequest.value;
      if (relationState == 'self') {
        return OutlinedButton(
          onPressed: () => Get.toNamed(AppPages.editmyprofil),
          child: Text('follow_state_self'.tr),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _ConnectionButton(
                  state: relationState,
                  connected: connected,
                  pending: pending,
                  busy: busy,
                  colors: colors,
                  onTap: relationState == 'blocked' || busy || (p.retryAt != null && p.retryAt!.isAfter(DateTime.now())) ? null : controller.handleConnectionTap,
                ),
              ),
              if (p.canMessage) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: _CompactActionButton(
                    iconWidget: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SvgPicture.asset(
                          'assets/svg_icons/chat-round-svgrepo-com.svg',
                          width: 18,
                          height: 18,
                          colorFilter: ColorFilter.mode(colors.onSurface, BlendMode.srcIn),
                        ),
                        const SizedBox(width: 6),
                        Text('Message', style: TextStyle(color: colors.onSurface, fontWeight: FontWeight.w600, fontSize: 13.5)),
                      ],
                    ),
                    foreground: colors.onSurface,
                    background: colors.surfaceContainerHigh,
                    onTap: controller.openConversation,
                  ),
                ),
              ],
            ],
          ),
          if (p.retryAt != null && p.retryAt!.isAfter(DateTime.now())) ...[
            const SizedBox(height: 6),
            Text(
              'follow_retry_at'.trParams({'date': p.retryAt!.toLocal().toString().substring(0, 16)}),
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ],
      );
    });
  }
}

class _ConnectionButton extends StatelessWidget {
  const _ConnectionButton({
    required this.state,
    required this.connected,
    required this.pending,
    required this.busy,
    required this.colors,
    required this.onTap,
  });
  final String state;
  final bool connected, pending, busy;
  final ColorScheme colors;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final isFollowed = state == 'following';
    final isFollowBack = state == 'follow_back';
    final isIncoming = state == 'request_received';
    final isBlocked = state == 'blocked';
    final labeled = pending || connected || isFollowed || isFollowBack || isIncoming || isBlocked;
    final label = switch (state) {
      'friends' => 'follow_state_friends'.tr,
      'following' => 'follow_state_following'.tr,
      'follow_back' => 'follow_state_follow_back'.tr,
      'requested' => 'follow_state_requested'.tr,
      'request_received' => 'follow_state_request_received'.tr,
      'blocked' => connected ? 'follow_state_friends'.tr : 'follow_state_blocked'.tr,
      'self' => 'follow_state_self'.tr,
      _ => 'follow_state_follow'.tr,
    };
    final icon = busy
        ? Icons.hourglass_top_rounded
        : (connected || isFollowed)
            ? Icons.check_rounded
            : (pending || isIncoming)
                ? Icons.hourglass_top_rounded
                : isBlocked && !connected
                    ? Icons.block_rounded
                    : Icons.person_add_alt_1_rounded;
    return Material(
      color: (connected || isFollowed)
          ? colors.primary.withValues(alpha: .15)
          : (pending || isIncoming || (isBlocked && !connected))
              ? colors.surfaceContainerHigh
              : colors.primary,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 38,
          constraints: BoxConstraints(minWidth: labeled ? 110 : 38),
          padding: EdgeInsets.symmetric(horizontal: labeled ? 14 : 0),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: (connected || isFollowed)
                    ? colors.primary
                    : (pending || isIncoming || (isBlocked && !connected))
                        ? colors.onSurfaceVariant
                        : colors.onPrimary,
                size: 16,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: (connected || isFollowed) ? colors.primary : ((pending || isIncoming || (isBlocked && !connected)) ? colors.onSurfaceVariant : colors.onPrimary),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactActionButton extends StatelessWidget {
  const _CompactActionButton({
    this.icon,
    this.iconWidget,
    required this.foreground,
    required this.background,
    required this.onTap,
  });
  final IconData? icon;
  final Widget? iconWidget;
  final Color foreground;
  final Color background;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: background,
    borderRadius: BorderRadius.circular(10),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 38,
        height: 38,
        child: Center(
          child: iconWidget ?? Icon(icon, color: foreground, size: 18),
        ),
      ),
    ),
  );
}

class _ReactiveProfileBody extends GetView<ExternalProfileController> {
  const _ReactiveProfileBody();
  @override
  Widget build(BuildContext context) => Obx(() {
    final p = controller.profile.value!;
    if (p.isPrivate) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Keep relationship/message actions first; explain profile privacy
          // directly underneath the follow/message controls.
          _ProfileActions(controller: controller),
          const SizedBox(height: 10),
          _PrivateProfile(message: 'profile_private_msg'.tr),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if ((p.bio ?? '').isNotEmpty) ...[
          _ExpandableBio(bio: p.bio!),
          const SizedBox(height: 14),
        ],
        if (!p.isPrivate) ...[
          _ProfileActions(controller: controller),
          const SizedBox(height: 16),
        ],
        if (p.activities.isNotEmpty) ...[
          const SizedBox(height: 16),
          _ProfileActivitiesSection(activities: p.activities),
        ],
        if ((p.slogan ?? '').isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(p.slogan!, style: const TextStyle(fontStyle: FontStyle.italic)),
        ],
        const SizedBox(height: 20),
        _buildTabsAndContent(context),
      ],
    );
  });

  Widget _buildTabsAndContent(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Obx(() {
          final tab = controller.selectedTab.value;
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildTabButton(0, Icons.grid_on_rounded, 'Publications', tab == 0, colorScheme),
              _buildTabButton(1, Icons.event_rounded, 'Événements', tab == 1, colorScheme),
              _buildTabButton(2, Icons.favorite_border_rounded, 'J’aime récents', tab == 2, colorScheme),
            ],
          );
        }),
        const SizedBox(height: 4),
        Obx(() {
          switch (controller.selectedTab.value) {
            case 0:
              return _buildUserPostsGrid(colorScheme);
            case 1:
              return _buildUserEventsList(colorScheme);
            case 2:
              return _buildSavedPostsGrid(colorScheme);
            default:
              return const SizedBox.shrink();
          }
        }),
      ],
    );
  }

  Widget _buildTabButton(int index, IconData icon, String label, bool isSelected, ColorScheme colorScheme) {
    return Expanded(
      child: GestureDetector(
        onTap: () => controller.selectProfileTab(index),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? colorScheme.onSurface : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Icon(
            icon,
            size: 24,
            color: isSelected ? colorScheme.onSurface : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }


  Widget _buildUserPostsGrid(ColorScheme colorScheme) =>
      _buildMediaGrid(colorScheme, tabIndex: 0);

  Widget _buildSavedPostsGrid(ColorScheme colorScheme) =>
      _buildMediaGrid(colorScheme, tabIndex: 2);

  Widget _buildMediaGrid(ColorScheme colorScheme, {required int tabIndex}) {
    return Obx(() {
      final loading = controller.loadingProfileTabs.contains(tabIndex);
      final error = controller.profileTabErrors[tabIndex];
      final items = controller.profileTabItems[tabIndex] ?? const <Map<String, dynamic>>[];

      if (loading && items.isEmpty) {
        return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
      }
      if (error != null && items.isEmpty) {
        return Padding(
          padding: const EdgeInsets.all(28),
          child: Column(children: [
            Text(error, textAlign: TextAlign.center, style: TextStyle(color: colorScheme.onSurfaceVariant)),
            const SizedBox(height: 10),
            TextButton(onPressed: () => controller.loadProfileTab(tabIndex, forceRefresh: true), child: const Text('Réessayer')),
          ]),
        );
      }
      if (items.isEmpty) {
        return Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Text(
              tabIndex == 0 ? 'Aucune publication pour le moment' : 'Aucun J’aime récent',
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ),
        );
      }

      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 3,
          mainAxisSpacing: 3,
          childAspectRatio: 0.92,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          final imageUrl = _profilePostImage(item);
          return GestureDetector(
            onTap: () => _openProfilePost(context, item),
            child: Stack(fit: StackFit.expand, children: [
              if (imageUrl != null && imageUrl.isNotEmpty)
                AppCachedImage(imageUrl: imageUrl, fit: BoxFit.cover)
              else
                Container(
                  color: colorScheme.surfaceContainerHigh,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    item['video_url'] != null ? Icons.play_circle_outline_rounded : Icons.article_outlined,
                    color: colorScheme.onSurfaceVariant,
                    size: 30,
                  ),
                ),
              if (_profilePostMediaCount(item) > 1)
                const Positioned(right: 6, top: 6, child: Icon(Icons.collections_rounded, color: Colors.white, size: 18, shadows: [Shadow(blurRadius: 5)])),
              if ((item['video_url'] ?? '').toString().isNotEmpty)
                const Positioned(left: 6, top: 6, child: Icon(Icons.play_arrow_rounded, color: Colors.white, shadows: [Shadow(blurRadius: 5)])),
              if (tabIndex == 2)
                const Positioned(right: 6, bottom: 6, child: Icon(Icons.favorite_rounded, color: Colors.white, size: 17, shadows: [Shadow(blurRadius: 5)])),
            ]),
          );
        },
      );
    });
  }

  int _profilePostMediaCount(Map<String, dynamic> item) {
    final media = item['media'];
    if (media is List && media.isNotEmpty) return media.length;
    final photos = item['photos'];
    if (photos is List && photos.isNotEmpty) return photos.length;
    return (item['photo'] ?? '').toString().isNotEmpty ? 1 : 0;
  }

  void _openProfilePost(BuildContext context, Map<String, dynamic> item) {
    final normalized = Map<String, dynamic>.from(item);
    if (normalized['media'] is! List || (normalized['media'] as List).isEmpty) {
      final photos = normalized['photos'];
      if (photos is List && photos.isNotEmpty) {
        normalized['media'] = photos.map((value) => {'type': 'photo', 'url': value.toString()}).toList();
      } else {
        final photo = (normalized['photo'] ?? normalized['video_thumbnail_url'] ?? '').toString();
        if (photo.isNotEmpty) normalized['media'] = [{'type': 'photo', 'url': photo}];
      }
    }
    Get.to(() => ProfilePostDetailScreen(post: CommunityPost.fromMap(normalized)));
  }

  String? _profilePostImage(Map<String, dynamic> item) {
    final media = item['media'];
    if (media is List) {
      for (final entry in media) {
        if (entry is Map) {
          final type = (entry['type'] ?? entry['media_type'] ?? 'photo').toString().toLowerCase();
          final url = (entry['thumbnail_url'] ?? entry['thumbnail'] ?? entry['url'] ?? entry['media_url'] ?? '').toString();
          if (url.isNotEmpty && (type.contains('photo') || type.contains('image') || type.contains('video'))) return url;
        } else if (entry is String && entry.isNotEmpty) {
          return entry;
        }
      }
    }
    final photos = item['photos'];
    if (photos is List && photos.isNotEmpty && photos.first.toString().isNotEmpty) return photos.first.toString();
    final photo = (item['photo'] ?? '').toString();
    if (photo.isNotEmpty) return photo;
    final thumbnail = (item['video_thumbnail_url'] ?? '').toString();
    if (thumbnail.isNotEmpty) return thumbnail;
    return null;
  }

  void _showProfilePostImage(BuildContext context, String imageUrl) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(alignment: Alignment.topRight, children: [
          InteractiveViewer(child: AppCachedImage(imageUrl: imageUrl, fit: BoxFit.contain)),
          IconButton(onPressed: () => Navigator.of(dialogContext).pop(), icon: const Icon(Icons.close_rounded, color: Colors.white)),
        ]),
      ),
    );
  }

  Widget _buildUserEventsList(ColorScheme colorScheme) {
    return Obx(() {
      const tabIndex = 1;
      final loading = controller.loadingProfileTabs.contains(tabIndex);
      final error = controller.profileTabErrors[tabIndex];
      final events = controller.profileTabItems[tabIndex] ?? const <Map<String, dynamic>>[];

      if (loading && events.isEmpty) {
        return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
      }
      if (error != null && events.isEmpty) {
        return Padding(
          padding: const EdgeInsets.all(28),
          child: Column(children: [
            Text(error, textAlign: TextAlign.center, style: TextStyle(color: colorScheme.onSurfaceVariant)),
            const SizedBox(height: 10),
            TextButton(onPressed: () => controller.loadProfileTab(tabIndex, forceRefresh: true), child: const Text('Réessayer')),
          ]),
        );
      }
      if (events.isEmpty) {
        return Padding(
          padding: const EdgeInsets.all(32),
          child: Center(child: Text('Aucun événement à afficher', textAlign: TextAlign.center, style: TextStyle(color: colorScheme.onSurfaceVariant))),
        );
      }

      return ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: events.length,
        itemBuilder: (context, index) {
          final event = events[index];
          final photo = (event['photo'] ?? '').toString();
          final start = DateTime.tryParse((event['starts_at'] ?? '').toString());
          final date = start == null ? '' : '${start.day.toString().padLeft(2, '0')}/${start.month.toString().padLeft(2, '0')}/${start.year}';
          final location = [event['city'], event['country']].where((value) => value != null && value.toString().trim().isNotEmpty).join(', ');
          final role = (event['role'] ?? '').toString().replaceAll('_', ' ');
          return GestureDetector(
            onTap: () {
              final eventId = (event['id'] ?? '').toString();
              if (eventId.isNotEmpty) Get.toNamed(AppPages.eventPreviewPath(eventId));
            },
            child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.25)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (photo.isNotEmpty)
                SizedBox(height: 150, width: double.infinity, child: AppCachedImage(imageUrl: photo, fit: BoxFit.cover)),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text((event['name'] ?? 'Événement').toString(),
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                    EntityCertifiedBadge(entityType: 'event', entityId: (event['id'] ?? '').toString(), size: 16),
                    if (role.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: colorScheme.primaryContainer, borderRadius: BorderRadius.circular(20)),
                        child: Text(role, style: TextStyle(fontSize: 10, color: colorScheme.onPrimaryContainer)),
                      ),
                  ]),
                  if (date.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(children: [
                      Icon(Icons.calendar_month_outlined, size: 15, color: colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(date, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                    ]),
                  ],
                  if (location.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(children: [
                      Icon(Icons.location_on_outlined, size: 15, color: colorScheme.primary),
                      const SizedBox(width: 6),
                      Expanded(child: Text(location, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ]),
                  ],
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        final eventId = (event['id'] ?? '').toString();
                        if (eventId.isEmpty) return;
                        Get.to(() => ExternalEventItineraryScreen(
                          userId: controller.userId,
                          eventId: eventId,
                          eventName: (event['name'] ?? 'Événement').toString(),
                        ));
                      },
                      icon: const Icon(Icons.route_rounded, size: 17),
                      label: Text('external_event_itinerary_button'.tr),
                    ),
                  ),
                ]),
              ),
            ]),
            ),
          );
        },
      );
    });
  }

}

class _ExpandableBio extends StatefulWidget {
  final String bio;
  const _ExpandableBio({required this.bio});

  @override
  State<_ExpandableBio> createState() => _ExpandableBioState();
}

class _ExpandableBioState extends State<_ExpandableBio> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final span = TextSpan(
          text: widget.bio,
          style: TextStyle(color: colors.onSurface, fontSize: 14),
        );
        final tp = TextPainter(
          text: span,
          maxLines: 2,
          textDirection: Directionality.of(context),
        );
        tp.layout(maxWidth: constraints.maxWidth);
        final exceeds = tp.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.bio,
              style: TextStyle(color: colors.onSurface, fontSize: 14, height: 1.4),
              maxLines: _expanded ? null : 2,
              overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            ),
            if (exceeds) ...[
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Text(
                  _expanded ? 'see_less'.tr : 'see_more'.tr,
                  style: TextStyle(
                    color: colors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ProfileInterests extends StatelessWidget {
  const _ProfileInterests({required this.interests});
  final List<Interest> interests;
  @override
  Widget build(BuildContext context) {
    if (interests.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final visibleInterests = interests.take(3).toList();
    final additionalCount = interests.length - 3;

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        ...visibleInterests.map(
          (i) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: colors.outlineVariant.withValues(alpha: .45),
              ),
            ),
            child: Text(
              '#${i.name}',
              style: TextStyle(
                color: colors.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        if (additionalCount > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: colors.outlineVariant.withValues(alpha: .6),
              ),
            ),
            child: Text(
              '+$additionalCount',
              style: TextStyle(
                color: colors.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }
}

class _ProfileStats extends StatelessWidget {
  const _ProfileStats({required this.profile});
  final dynamic profile;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Row(
        children: [
          Expanded(child: _StatItem(
            value: NumberFormatter.formatCount(profile.followersCount),
            label: 'profile_stat_followers'.tr,
          )),
          Expanded(child: _StatItem(
            value: NumberFormatter.formatCount(profile.followingCount),
            label: 'profile_stat_following'.tr,
          )),
          Expanded(child: _StatItem(
            value: _formatReputation(profile.rating),
            label: 'profile_stat_reputation'.tr,
          )),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.value,
    required this.label,
  });
  final String value, label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: colors.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: colors.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _ProfileActivitiesSection extends StatelessWidget {
  const _ProfileActivitiesSection({required this.activities});
  final List<Map<String, dynamic>> activities;
  @override
  Widget build(BuildContext context) {
    if (activities.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Activités',
          style: AppTextStyles.h6.copyWith(color: colors.onSurface, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: activities.length,
            itemBuilder: (context, index) {
              final act = activities[index];
              return Container(
                width: 140,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.3)),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      act['name']?.toString() ?? '',
                      style: TextStyle(color: colors.onSurface, fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PrivateProfile extends StatelessWidget {
  const _PrivateProfile({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final explanation = message.trim().isNotEmpty && message != 'profile_blocked_msg'.tr
        ? message
        : 'profile_blocked_explanation'.tr;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: colors.outlineVariant.withValues(alpha: .65),
              ),
              boxShadow: [
                BoxShadow(
                  color: colors.shadow.withValues(alpha: .07),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: colors.errorContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.lock_person_rounded,
                    size: 36,
                    color: colors.onErrorContainer,
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'Profil indisponible',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  explanation,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 14,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 22),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest.withValues(alpha: .7),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 19, color: colors.onSurfaceVariant),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'profile_blocked_actions_disabled'.tr,
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 12.5,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    label: Text('profile_action_back'.tr),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileMenuSheet extends StatelessWidget {
  const _ProfileMenuSheet();

  @override
  Widget build(BuildContext context) {
    final profile = Get.find<ExternalProfileController>().profile.value;
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: colors.outlineVariant.withValues(alpha: .45)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .18), blurRadius: 24, offset: const Offset(0, -5))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38, height: 4,
              decoration: BoxDecoration(color: colors.onSurfaceVariant.withValues(alpha: .35), borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(height: 18),
            Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: colors.primary.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)),
                child: Icon(Icons.manage_accounts_rounded, color: colors.primary, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('profile_actions_title'.tr, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: colors.onSurface)),
                Text('profile_actions_subtitle'.tr, style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
              ])),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
            ]),
            const SizedBox(height: 18),
            _ProfileMenuAction(
              icon: Icons.share_rounded,
              title: 'profile_share_action'.tr,
              subtitle: 'profile_share_description'.tr,
              color: colors.primary,
              onTap: () async {
                Navigator.pop(context);
                if (profile == null) return;
                final link = 'scrole://user-profile/${profile.userId}';
                await SharePlus.instance.share(ShareParams(
                  text: 'profile_share_message'.trParams({'name': profile.displayName, 'link': link}),
                  subject: 'profile_share_subject'.trParams({'name': profile.displayName}),
                ));
              },
            ),
            const SizedBox(height: 10),
            _ProfileMenuAction(
              icon: Icons.flag_rounded,
              title: 'profile_report_action'.tr,
              subtitle: 'profile_report_description'.tr,
              color: colors.error,
              onTap: () {
                Navigator.pop(context);
                if (profile != null) {
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    backgroundColor: Colors.transparent,
                    barrierColor: Colors.black.withValues(alpha: .48),
                    builder: (_) => _ProfileReportSheet(profile: profile),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileMenuAction extends StatelessWidget {
  const _ProfileMenuAction({
    required this.icon, required this.title, required this.subtitle,
    required this.color, required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 13),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(color: colors.onSurface, fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 3),
              Text(subtitle, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
            ])),
            Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }
}

class _ProfileReportSheet extends StatefulWidget {
  const _ProfileReportSheet({required this.profile});
  final dynamic profile;

  @override
  State<_ProfileReportSheet> createState() => _ProfileReportSheetState();
}

class _ProfileReportSheetState extends State<_ProfileReportSheet> {
  String? _reason;
  final TextEditingController _details = TextEditingController();
  bool _sending = false;

  static const _reasons = <(String, String, IconData)>[
    ('spam', 'report_reason_spam', Icons.campaign_outlined),
    ('fake_profile', 'report_reason_fake_profile', Icons.person_off_outlined),
    ('harassment', 'report_reason_harassment', Icons.mood_bad_outlined),
    ('inappropriate', 'report_reason_inappropriate', Icons.visibility_off_outlined),
    ('other', 'report_reason_other', Icons.more_horiz_rounded),
  ];

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + MediaQuery.viewInsetsOf(context).bottom),
        child: Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .82),
          decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(28)),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: colors.onSurfaceVariant.withValues(alpha: .35), borderRadius: BorderRadius.circular(4)))),
              const SizedBox(height: 20),
              Row(children: [
                Container(width: 46, height: 46, decoration: BoxDecoration(color: colors.error.withValues(alpha: .12), borderRadius: BorderRadius.circular(15)), child: Icon(Icons.flag_rounded, color: colors.error)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('profile_report_title'.tr, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: colors.onSurface)),
                  Text(widget.profile.displayName, style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant)),
                ])),
              ]),
              const SizedBox(height: 8),
              Text('profile_report_hint'.tr, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13)),
              const SizedBox(height: 18),
              ..._reasons.map((entry) {
                final selected = _reason == entry.$1;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: selected ? colors.error.withValues(alpha: .08) : colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(15),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(15),
                      onTap: () => setState(() => _reason = entry.$1),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                        child: Row(children: [
                          Icon(entry.$3, color: selected ? colors.error : colors.onSurfaceVariant, size: 21),
                          const SizedBox(width: 12),
                          Expanded(child: Text(entry.$2.tr, style: TextStyle(color: colors.onSurface, fontWeight: selected ? FontWeight.w700 : FontWeight.w500))),
                          Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: selected ? colors.error : colors.onSurfaceVariant),
                        ]),
                      ),
                    ),
                  ),
                );
              }),
              if (_reason == 'other') ...[
                const SizedBox(height: 4),
                TextField(controller: _details, maxLines: 3, decoration: InputDecoration(hintText: 'profile_report_details_hint'.tr, filled: true, fillColor: colors.surfaceContainerLow, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none))),
              ],
              const SizedBox(height: 14),
              SizedBox(width: double.infinity, height: 50, child: FilledButton(
                onPressed: _reason == null || _sending ? null : _submit,
                style: FilledButton.styleFrom(backgroundColor: colors.error, foregroundColor: colors.onError, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                child: _sending ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text('profile_report_submit'.tr, style: const TextStyle(fontWeight: FontWeight.w700)),
              )),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_reason == null || _sending) return;
    setState(() => _sending = true);
    try {
      await Supabase.instance.client.rpc('report_user_profile', params: {
        'p_reported_user_id': widget.profile.userId,
        'p_reason': _reason,
        'p_details': _details.text.trim().isEmpty ? null : _details.text.trim(),
      });
      if (!mounted) return;
      Navigator.of(context).pop();
      Get.snackbar('success_title'.tr, 'profile_report_success'.tr, snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      Get.snackbar('error_title'.tr, 'profile_report_error'.tr, snackPosition: SnackPosition.BOTTOM);
    }
  }
}

class _HeaderStats extends StatelessWidget {
  const _HeaderStats({required this.profile});
  final dynamic profile;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => Get.toNamed(AppPages.followLists, arguments: {'userId': profile.userId, 'initialTab': 0}),
          child: _buildStatCol(NumberFormatter.formatCount(profile.followersCount), 'follow_tab_followers'.tr, colors),
        ),
        const SizedBox(width: 10),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => Get.toNamed(AppPages.followLists, arguments: {'userId': profile.userId, 'initialTab': 1}),
          child: _buildStatCol(NumberFormatter.formatCount(profile.followingCount), 'follow_tab_following'.tr, colors),
        ),
        const SizedBox(width: 10),
        _buildStatCol(_formatReputation(profile.rating), 'profile_stat_reputation'.tr, colors),
      ],
    );
  }

  Widget _buildStatCol(String value, String label, ColorScheme colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: colors.onSurface,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: colors.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _ProfileDeletedView extends StatelessWidget {
  const _ProfileDeletedView();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: colors.error.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.person_off_rounded, size: 40, color: colors.error),
            ),
            const SizedBox(height: 20),
            Text(
              'profile_deleted_title'.tr,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: colors.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'profile_deleted_message'.tr,
              style: TextStyle(
                fontSize: 14,
                color: colors.onSurfaceVariant,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: Text('profile_action_back'.tr, style: const TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileNotFoundView extends StatelessWidget {
  const _ProfileNotFoundView();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.search_off_rounded, size: 40, color: colors.primary),
            ),
            const SizedBox(height: 20),
            Text(
              'profile_not_found_title'.tr,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: colors.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'profile_not_found_message'.tr,
              style: TextStyle(
                fontSize: 14,
                color: colors.onSurfaceVariant,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('Retour', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ProfileErrorView({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: colors.error.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.cloud_off_rounded, size: 40, color: colors.error),
            ),
            const SizedBox(height: 20),
            Text(
              'profile_load_error_title'.tr,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: colors.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              message.isNotEmpty ? message : 'profile_load_error_message'.tr,
              style: TextStyle(
                fontSize: 14,
                color: colors.onSurfaceVariant,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('Retour'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text('profile_action_retry'.tr, style: const TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: colors.onPrimary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _formatReputation(num value) {
  final rounded = (value.clamp(0, 5) * 10).round() / 10;
  return rounded.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
}

class _BlockingProfileOverlay extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;
  final Color iconColor;

  const _BlockingProfileOverlay({
    required this.title,
    required this.message,
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          Navigator.of(context).pop();
        }
      },
      child: Container(
        color: Colors.black.withValues(alpha: 0.65),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, 8)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 34, color: iconColor),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: colors.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: colors.onSurfaceVariant,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('Retour', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: colors.onPrimary,
                    minimumSize: const Size(double.infinity, 46),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
