import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:image_picker/image_picker.dart';
import 'package:scrole/app/routes/app_pages.dart';
import 'package:scrole/app/theme/app_colors.dart';
import 'package:scrole/app/theme/text_styles.dart';
import 'package:scrole/shared/widgets/app_cached_image.dart';
import 'package:scrole/shared/widgets/image_source_sheet.dart';
import 'package:scrole/shared/widgets/user_certified_badge.dart';
import 'package:scrole/shared/widgets/entity_certified_badge.dart';
import 'package:scrole/modules/module_principale/centre/models/community_post.dart';
import 'package:scrole/shared/widgets/profile_post_detail_screen.dart';
import 'package:scrole/modules/module_profil/interne/controllers/profile_controller.dart';
import 'package:scrole/modules/module_profil/interne/widgets/circle_button_widget.dart';

String _formatReputation(num value) {
  final rounded = (value.clamp(0, 5) * 10).round() / 10;
  return rounded.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
}

class ProfileScreen extends GetView<ProfileController> {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Stack(
          children: [
            RefreshIndicator(
              onRefresh: controller.refreshProfile,
              color: colorScheme.primary,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context, colorScheme),
                    const SizedBox(height: 10),
                    _buildNameAndUsername(colorScheme),
                    const SizedBox(height: 12),
                    _buildFollowStats(colorScheme),
                    const SizedBox(height: 12),
                    _buildBio(colorScheme),
                    const SizedBox(height: 20),
                    _buildTabsAndContent(context, colorScheme),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
            
            // Chargement plein écran discret
            Obx(() => controller.isLoading.value
                ? Container(
                    color: Colors.black.withValues(alpha: 0.3),
                    child: Center(
                      child: CircularProgressIndicator(color: colorScheme.primary),
                    ),
                  )
                : const SizedBox.shrink()),
          ],
        ),
      ),
    );
  }

  // ============================================
  // HEADER
  // ============================================
  Widget _buildHeader(BuildContext context, ColorScheme colorScheme) {
    return SizedBox(
      height: 185, // 140 (cover) + 45 (avatar overlap)
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SizedBox(
            height: 140,
            width: double.infinity,
            child: Obx(() {
              final coverUrl = controller.coverImageUrl.value;
              if (coverUrl.isEmpty) {
                return Container(color: AppColors.secondary.withValues(alpha: 0.25));
              }
              return Stack(
                fit: StackFit.expand,
                children: [
                  AppCachedImage(
                    imageUrl: coverUrl,
                    fit: BoxFit.cover,
                    errorWidget: Container(color: AppColors.secondary.withValues(alpha: 0.25)),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.35),
                          Colors.black.withValues(alpha: 0.05),
                          colorScheme.surface.withValues(alpha: 0.55),
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),

          Positioned(
            bottom: 8,
            right: 12,
            child: GestureDetector(
              onTap: () => showImageSourceSheet(
                context,
                onCamera: () => controller.pickCoverImage(ImageSource.camera),
                onGallery: () => controller.pickCoverImage(ImageSource.gallery),
              ),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                child: Obx(
                  () => controller.isUploadingCover.value
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 16),
                ),
              ),
            ),
          ),

          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CircleButtonWidget(
                  icon: Icons.arrow_back_ios_rounded,
                  onTap: () => Get.back(),
                ),
                Row(
                  children: [
                    CircleButtonWidget(
                      icon: Icons.calendar_today_outlined,
                      onTap: () => Get.toNamed(AppPages.userAgenda),
                    ),
                    const SizedBox(width: 8),
                    CircleButtonWidget(
                      icon: Icons.qr_code_rounded,
                      onTap: () => Get.toNamed(AppPages.userQrCode),
                    ),
                    const SizedBox(width: 8),
                    CircleButtonWidget(
                      icon: Icons.share_rounded,
                      onTap: () => Get.toNamed(AppPages.shareMyProfile),
                    ),
                  ],
                ),
              ],
            ),
          ),

          Positioned(
            bottom: 0,
            left: 20,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Obx(() {
                  final avatarUrl = controller.profileImageUrl.value;
                  return Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: colorScheme.surface, width: 5),
                      color: colorScheme.primary,
                    ),
                    child: avatarUrl.isEmpty
                        ? Center(
                            child: Text(
                              controller.initials,
                              style: AppTextStyles.h3.copyWith(color: Colors.white),
                            ),
                          )
                        : AppCachedImage(
                            imageUrl: avatarUrl,
                            width: 90,
                            height: 90,
                            borderRadius: BorderRadius.circular(45),
                            fit: BoxFit.cover,
                          ),
                  );
                }),
                Positioned(
                  bottom: 2,
                  right: 2,
                  child: GestureDetector(
                    onTap: () => showImageSourceSheet(
                      context,
                      onCamera: () => controller.pickProfileImage(ImageSource.camera),
                      onGallery: () => controller.pickProfileImage(ImageSource.gallery),
                    ),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colorScheme.primary,
                        border: Border.all(color: colorScheme.surface, width: 3),
                      ),
                      child: Obx(
                        () => controller.isUploadingProfileImage.value
                            ? const Padding(
                                padding: EdgeInsets.all(5),
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================
  // NAME & USERNAME + bouton d'édition
  // ============================================
  Widget _buildNameAndUsername(ColorScheme colorScheme) {
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
                      child: Obx(
                        () => Text(
                          controller.displayName,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.h4.copyWith(color: colorScheme.onSurface),
                        ),
                      ),
                    ),
                    Obx(() {
                      if (!controller.isVerified.value) return const SizedBox.shrink();
                      final level = controller.certificationLevel.value;
                      final badgeType = switch (level) {
                        'premium' => CertificationBadgeType.premium,
                        'pro' => CertificationBadgeType.pro,
                        'basique' => CertificationBadgeType.basic,
                        _ => null,
                      };
                      if (badgeType == null) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: UserCertifiedBadge(size: 20, type: badgeType),
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 4),
                Obx(
                  () => Text(
                    '@${controller.username.value}',
                    style: AppTextStyles.body.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: () => Get.toNamed(AppPages.editmyprofil),
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: Text('profile_edit_button'.tr, style: AppTextStyles.buttonSmall),
            style: OutlinedButton.styleFrom(
              foregroundColor: colorScheme.primary,
              side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFollowStats(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Obx(() => Row(
        children: [
          Expanded(
            child: _followStat(
              controller.followersCount.value.toString(),
              'follow_tab_followers'.tr,
              colorScheme,
              () => Get.toNamed(AppPages.followLists, arguments: {'userId': controller.userId.value, 'initialTab': 0}),
            ),
          ),
          Expanded(
            child: _followStat(
              controller.followingCount.value.toString(),
              'follow_tab_following'.tr,
              colorScheme,
              () => Get.toNamed(AppPages.followLists, arguments: {'userId': controller.userId.value, 'initialTab': 1}),
            ),
          ),
          Expanded(
            child: _engagementStat(
              _formatReputation(controller.reputation.value),
              'profile_stat_reputation'.tr,
              colorScheme,
            ),
          ),
        ],
      )),
    );
  }

  Widget _buildEngagementStats(ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Obx(() => Wrap(
        alignment: WrapAlignment.spaceAround,
        runAlignment: WrapAlignment.center,
        spacing: 18,
        runSpacing: 12,
        children: [
          _engagementStat(controller.postsCount.value.toString(), 'profile_stat_posts'.tr, colors),
          _engagementStat(_formatReputation(controller.reputation.value), 'profile_stat_reputation'.tr, colors),
        ],
      )),
    );
  }

  Widget _engagementStat(String value, String label, ColorScheme colors) {
    return SizedBox(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: AppTextStyles.bodyLarge.copyWith(
            color: colors.onSurface,
            fontWeight: FontWeight.w800,
          )),
          const SizedBox(height: 2),
          Text(label, textAlign: TextAlign.center, style: AppTextStyles.bodySmall.copyWith(
            color: colors.onSurfaceVariant,
            fontSize: 10,
          )),
        ],
      ),
    );
  }

  Widget _followStat(String count, String label, ColorScheme colors, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            Text(count, style: AppTextStyles.bodyLarge.copyWith(color: colors.onSurface, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(label, style: AppTextStyles.bodySmall.copyWith(color: colors.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  // ============================================
  // BIO
  // ============================================
  Widget _buildBio(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Obx(
        () => Text(
          controller.displayBio,
          style: AppTextStyles.body.copyWith(
            color: controller.bio.value.isEmpty
                ? colorScheme.onSurfaceVariant
                : colorScheme.onSurface.withValues(alpha: 0.85),
            fontStyle: controller.bio.value.isEmpty ? FontStyle.italic : FontStyle.normal,
          ),
        ),
      ),
    );
  }

  // ============================================
  // INSTAGRAM-STYLE TABS & CONTENT
  // ============================================
  Widget _buildTabsAndContent(BuildContext context, ColorScheme colorScheme) {
    return Column(
      children: [
        Obx(() {
          final tab = controller.selectedTab.value;
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildTabButton(0, Icons.grid_on_rounded, 'profile_tab_posts'.tr, tab == 0, colorScheme),
              _buildTabButton(1, Icons.event_rounded, 'profile_tab_events'.tr, tab == 1, colorScheme),
              _buildTabButton(2, Icons.favorite_border_rounded, 'profile_tab_liked_posts'.tr, tab == 2, colorScheme),
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 22,
                color: isSelected ? colorScheme.onSurface : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall.copyWith(
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? colorScheme.onSurface : colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildUserPostsGrid(ColorScheme colorScheme) =>
      _buildPostGrid(controller.userPosts, colorScheme, tabIndex: 0);

  Widget _buildSavedPostsGrid(ColorScheme colorScheme) =>
      _buildPostGrid(controller.savedPosts, colorScheme, tabIndex: 2);

  Widget _buildPostGrid(List<CommunityPost> posts, ColorScheme colorScheme, {required int tabIndex}) {
    return Obx(() {
      final loading = controller.loadingProfileTabs.contains(tabIndex);
      final error = controller.profileTabErrors[tabIndex];
      if (loading && posts.isEmpty) {
        return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
      }
      if (error != null && posts.isEmpty) {
        return Padding(
          padding: const EdgeInsets.all(28),
          child: Column(children: [
            Text(error, textAlign: TextAlign.center, style: TextStyle(color: colorScheme.onSurfaceVariant)),
            const SizedBox(height: 10),
            TextButton(onPressed: () => controller.refreshProfileTab(tabIndex), child: Text('profile_tab_retry'.tr)),
          ]),
        );
      }
      if (posts.isEmpty) {
        return Padding(
          padding: const EdgeInsets.all(40),
          child: Center(
            child: Text(
              tabIndex == 0 ? 'profile_tab_posts_empty'.tr : 'profile_tab_liked_empty'.tr,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ),
        );
      }
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 2,
          mainAxisSpacing: 2,
        ),
        itemCount: posts.length,
        itemBuilder: (context, index) {
          final post = posts[index];
          final imageUrl = post.media.isNotEmpty ? (post.media.first.isVideo ? (post.media.first.thumbnailUrl ?? '') : post.media.first.url) : '';
          return GestureDetector(
            onTap: () async {
              final deleted = await Get.to<bool>(() => ProfilePostDetailScreen(post: post));
              if (deleted == true) {
                await controller.refreshProfile();
              }
            },
            child: Stack(fit: StackFit.expand, children: [
              Container(
                color: colorScheme.surfaceContainerHighest,
                child: imageUrl.isNotEmpty
                    ? AppCachedImage(imageUrl: imageUrl, fit: BoxFit.cover)
                    : Center(
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Text(post.content, maxLines: 3, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 10, color: colorScheme.onSurface), textAlign: TextAlign.center),
                        ),
                      ),
              ),
              if (post.media.length > 1)
                const Positioned(right: 5, top: 5, child: Icon(Icons.collections_rounded, color: Colors.white, size: 18, shadows: [Shadow(blurRadius: 5)])),
              if (post.media.any((m) => (m.type).toLowerCase().contains('video')))
                const Positioned(left: 5, top: 5, child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 18, shadows: [Shadow(blurRadius: 5)])),
              if (tabIndex == 2)
                const Positioned(right: 5, bottom: 5, child: Icon(Icons.favorite_rounded, color: Colors.white, size: 17, shadows: [Shadow(blurRadius: 5)])),
            ]),
          );
        },
      );
    });
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
      final events = controller.userEvents;
      if (loading && events.isEmpty) {
        return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
      }
      if (error != null && events.isEmpty) {
        return Padding(
          padding: const EdgeInsets.all(28),
          child: Column(children: [
            Text(error, textAlign: TextAlign.center, style: TextStyle(color: colorScheme.onSurfaceVariant)),
            const SizedBox(height: 10),
            TextButton(onPressed: () => controller.refreshProfileTab(tabIndex), child: const Text('Réessayer')),
          ]),
        );
      }
      if (events.isEmpty) {
        return Padding(
          padding: const EdgeInsets.all(40),
          child: Center(child: Text('profile_tab_events_empty'.tr, style: TextStyle(color: colorScheme.onSurfaceVariant))),
        );
      }
      return ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: events.length,
        itemBuilder: (context, index) {
          final ev = Map<String, dynamic>.from(events[index] as Map);
          final image = (ev['photo'] ?? '').toString();
          final start = DateTime.tryParse((ev['starts_at'] ?? '').toString());
          final date = start == null ? '' : '${start.day.toString().padLeft(2, '0')}/${start.month.toString().padLeft(2, '0')}/${start.year}';
          final location = [ev['city'], ev['country']].where((v) => v != null && v.toString().trim().isNotEmpty).join(', ');
          final role = (ev['role'] ?? '').toString().replaceAll('_', ' ');
          return GestureDetector(
            onTap: () {
              final eventId = (ev['id'] ?? '').toString();
              if (eventId.isNotEmpty) Get.toNamed(AppPages.eventPreviewPath(eventId));
            },
            child: Container(
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.25)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (image.isNotEmpty) SizedBox(height: 130, width: double.infinity, child: AppCachedImage(imageUrl: image, fit: BoxFit.cover)),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 5,
                    runSpacing: 3,
                    children: [
                      Text(
                        (ev['name'] ?? 'profile_tab_event_fallback'.tr).toString(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                      ),
                      EntityCertifiedBadge(entityType: 'event', entityId: (ev['id'] ?? '').toString(), size: 16),
                      if (role.isNotEmpty)
                        Text(role, style: TextStyle(fontSize: 11, color: colorScheme.primary)),
                    ],
                  ),
                  if (date.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(children: [Icon(Icons.calendar_month_outlined, size: 15, color: colorScheme.primary), const SizedBox(width: 6),
                      Text(date, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant))]),
                  ],
                  if (location.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(children: [Icon(Icons.location_on_outlined, size: 15, color: colorScheme.primary), const SizedBox(width: 6),
                      Expanded(child: Text(location, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)))]),
                  ],
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
