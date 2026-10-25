import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lottie/lottie.dart';
import 'package:scrole/shared/widgets/app_cached_image.dart';
import 'package:scrole/shared/widgets/entity_certified_badge.dart';
import '../controllers/community/community_controller.dart';
import 'create_community_screen.dart';
import 'community_feed_screen.dart';

class CommunityScreen extends StatelessWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final CommunityController controller = Get.put(CommunityController());

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        title: Text(
          'community_my_communities'.tr,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.add_rounded, color: colorScheme.primary, size: 28),
            onPressed: () {
              Get.to(() => const CreateCommunityScreen())?.then((_) {
                controller.loadCommunities();
              });
            },
            tooltip: 'create_community_title'.tr,
          ),
        ],
      ),
      body: Obx(() {
        debugPrint('[COMMUNITY_SYNC] UI build stats: totalCommunities=${controller.communities.length}, pending=${controller.communities.where((c) => c.status == 'pending').length}, confirmed=${controller.communities.where((c) => c.status == 'confirmed').length}');
        if (controller.isLoading.value && controller.communities.isEmpty) {
          return Center(
            child: Lottie.asset(
              'assets/lotties/Animation - 1791582964132.json',
              width: 140,
              height: 140,
            ),
          );
        }

        if (controller.communities.isEmpty) {
          return RefreshIndicator(
            color: Colors.transparent,
            backgroundColor: Colors.transparent,
            elevation: 0,
            onRefresh: () => controller.loadCommunities(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.7,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.groups_outlined, size: 64, color: colorScheme.outline),
                          const SizedBox(height: 16),
                          Text(
                            'community_empty_title'.tr,
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'community_empty_subtitle'.tr,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: () {
                              Get.to(() => const CreateCommunityScreen())?.then((_) {
                                controller.loadCommunities();
                              });
                            },
                            icon: const Icon(Icons.add_rounded),
                            label: Text('community_create_button'.tr),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          color: Colors.transparent,
          backgroundColor: Colors.transparent,
          elevation: 0,
          onRefresh: () => controller.loadCommunities(),
          child: GridView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1,
            ),
            itemCount: controller.communities.length,
            itemBuilder: (context, index) {
              final community = controller.communities[index];
              final isPending = community.status == 'pending';

              return Opacity(
                opacity: isPending ? 0.78 : 1.0,
                child: _MyCommunityTile(
                  community: community,
                  isPending: isPending,
                  onTap: isPending
                      ? () {
                          Get.snackbar(
                            'community_creation_in_progress'.tr,
                            'community_creation_pending_message'.tr,
                            snackPosition: SnackPosition.BOTTOM,
                          );
                        }
                      : () {
                          Get.to(() => CommunityFeedScreen(
                                communityId: community.id,
                                communityName: community.name,
                              ))?.then((_) {
                                controller.loadCommunities();
                              });
                        },
                ),
              );
            },
          ),
        );
      }),
    );
  }
}

class _MyCommunityTile extends StatelessWidget {
  final dynamic community;
  final bool isPending;
  final VoidCallback onTap;

  const _MyCommunityTile({
    required this.community,
    required this.isPending,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final initial = community.name.isNotEmpty ? community.name[0].toUpperCase() : 'C';
    final avatarUrl = community.avatarUrl?.toString() ?? '';
    final coverUrl = community.bannerUrl?.toString() ?? '';
    final hasCover = coverUrl.isNotEmpty;
    final hasAvatar = avatarUrl.isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasCover)
                AppCachedImage(
                  imageUrl: coverUrl,
                  fit: BoxFit.cover,
                  errorWidget: _communityImageFallback(colorScheme, initial),
                )
              else
                _communityImageFallback(colorScheme, initial),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x16000000),
                      Color(0x25000000),
                      Color(0xE6000000),
                    ],
                    stops: [0, 0.35, 1],
                  ),
                ),
              ),
              if (isPending)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.42),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.schedule_rounded,
                      size: 15,
                      color: Color(0xFFFFD180),
                    ),
                  ),
                ),
              Positioned(
                left: 8,
                right: 7,
                bottom: 10,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 43,
                      height: 43,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black38,
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: hasAvatar
                            ? AppCachedImage(
                                imageUrl: avatarUrl,
                                fit: BoxFit.cover,
                                errorWidget: _communityAvatarFallback(colorScheme, initial),
                              )
                            : _communityAvatarFallback(colorScheme, initial),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            community.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              height: 1.12,
                              fontWeight: FontWeight.w800,
                              shadows: [
                                Shadow(color: Colors.black54, blurRadius: 7),
                              ],
                            ),
                          ),
                          const SizedBox(height: 3),
                          EntityCertifiedBadge(
                            entityType: 'community',
                            entityId: community.id,
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _communityImageFallback(ColorScheme colors, String initial) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.primaryContainer, colors.tertiaryContainer],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: colors.onPrimaryContainer,
          fontSize: 56,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _communityAvatarFallback(ColorScheme colors, String initial) {
    return Container(
      color: colors.primaryContainer,
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: colors.onPrimaryContainer,
          fontSize: 23,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
