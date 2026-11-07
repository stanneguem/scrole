import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:scrole/app/utils/boot_timing.dart';
import 'package:scrole/shared/widgets/search_screen.dart';

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

    return SafeArea(
      child: Container(
        height: preferredSize.height,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        color: Colors.transparent,
        child: Row(
          children: [
            // ─── GAUCHE : Scrole wordmark ───
            Builder(
              builder: (drawerContext) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Scaffold.of(drawerContext).openDrawer(),
                child: Obx(() {
                  final isOnline = Get.find<ConnectivityService>().isConnected.value;
                  return AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeInOut,
                    style: GoogleFonts.grandHotel(
                      fontSize: 39,
                      fontWeight: FontWeight.w400,
                      height: 1.05,
                      letterSpacing: 0.15,
                      color: isOnline
                          ? colorScheme.onSurface
                          : colorScheme.onSurfaceVariant.withValues(alpha: 0.58),
                    ),
                    child: const Text('Scrole'),
                  );
                }),
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
