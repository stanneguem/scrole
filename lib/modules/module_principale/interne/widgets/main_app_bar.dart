import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:scrole/app/utils/boot_timing.dart';
import 'package:scrole/shared/widgets/search_screen.dart';

import '../../../../../app/service_global/connectivity_service.dart';
import '../../../../../shared/widgets/glas_buton.dart';
import '../controllers/main_layout_controller.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final MainLayoutController controller;

  const CustomAppBar({super.key, required this.controller});

  @override
  Size get preferredSize => const Size.fromHeight(72);

  @override
  Widget build(BuildContext context) {
    bootLog('CustomAppBar.build');
    final colorScheme = Theme.of(context).colorScheme;
    final connectivity = Get.find<ConnectivityService>();

    return SafeArea(
      child: Container(
        height: preferredSize.height,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        color: Colors.transparent,
        child: Row(
          children: [
            // ─── GAUCHE : Logo PNG de l'app ouvrant le Drawer + état en ligne/hors ligne ───
            Builder(
              builder: (drawerContext) => GestureDetector(
                onTap: () => Scaffold.of(drawerContext).openDrawer(),
                child: Row(
                  children: [
                    Image.asset(
                      'assets/logos/img.png',
                      width: 38,
                      height: 38,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(width: 10),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Obx(() {
                          final isOnline = connectivity.isConnected.value;
                          return Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: isOnline
                                      ? const Color(0xFF10B981)
                                      : colorScheme.outline,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isOnline ? 'status_online'.tr : 'status_offline'.tr,
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          );
                        }),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const Spacer(),

            // ─── DROITE : Actions principales (Search, Chat, Notifications) ───
            Row(
              children: [
                GlassmorphismButton(
                  icon: SvgPicture.asset(
                    'assets/svg_icons/search.svg',
                    width: 22,
                    height: 22,
                    colorFilter: ColorFilter.mode(
                      colorScheme.onSurface,
                      BlendMode.srcIn,
                    ),
                  ),
                  onTap: () => Get.to(() => const SearchScreen()),
                ),
                const SizedBox(width: 8),
                Obx(() => GlassmorphismButton(
                      icon: SvgPicture.asset(
                        'assets/svg_icons/chat-round-svgrepo-com.svg',
                        width: 22,
                        height: 22,
                        colorFilter: ColorFilter.mode(
                          colorScheme.onSurface,
                          BlendMode.srcIn,
                        ),
                      ),
                      badgeCount: double.tryParse(controller.messageBadge),
                      onTap: controller.openMessages,
                    )),
                const SizedBox(width: 8),
                Obx(() => GlassmorphismButton(
                      icon: SvgPicture.asset(
                        'assets/svg_icons/notification-svgrepo-com.svg',
                        width: 22,
                        height: 22,
                        colorFilter: ColorFilter.mode(
                          colorScheme.onSurface,
                          BlendMode.srcIn,
                        ),
                      ),
                      badgeCount: double.tryParse(controller.notificationBadge),
                      onTap: controller.openNotifications,
                    )),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
