import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:scrole/app/utils/boot_timing.dart';
import 'package:scrole/app/routes/app_pages.dart';
import 'package:scrole/app/theme/app_colors.dart';
import 'package:scrole/shared/widgets/app_cached_image.dart';
import 'package:scrole/shared/widgets/user_certified_badge.dart';
import 'package:scrole/shared/widgets/search_screen.dart';
import 'package:scrole/shared/constantes/image_path.dart';
import 'package:scrole/shared/widgets/external_web_view_screen.dart';
import '../../../module_evenement/interne/pages/event_screen.dart';
import '../../../module_communautes/interne/pages/community_screen.dart';
import '../../../module_communautes/interne/controllers/community/community_controller.dart';
import '../../../module_communautes/interne/pages/create_community_post_screen.dart';
import '../pages/home_feed_screen.dart';
import '../../../../app_controller.dart';
import '../../../module_authentification/centre/services/auth_service.dart';
import '../controllers/main_layout_controller.dart';
import '../widgets/main_app_bar.dart';

class MainLayoutPage extends StatefulWidget {
  const MainLayoutPage({super.key});

  @override
  State<MainLayoutPage> createState() => _MainLayoutPageState();
}

class _MainLayoutPageState extends State<MainLayoutPage> {
  int _currentIndex = 0;
  final List<bool> _visited = [true, false, false]; // Home, Community, Events
  bool _isBottomNavVisible = true;

  @override
  void initState() {
    super.initState();
    if (Get.isRegistered<MainLayoutController>()) {
      ever(Get.find<MainLayoutController>().currentTab, (idx) {
        int navIdx = idx;
        int stackIdx = 0;
        if (navIdx == 1) stackIdx = 1;
        else if (navIdx == 3) stackIdx = 2;
        else stackIdx = 0;
        if (mounted && _currentIndex != stackIdx) {
          setState(() {
            _currentIndex = stackIdx;
            _visited[stackIdx] = true;
            _isBottomNavVisible = true;
          });
        }
      });
    }
  }

  final List<Widget> _pages = const [
    HomeFeedScreen(),     // 0. Accueil
    CommunityScreen(),    // 1. Communautés
    EventScreen(),        // 2. Événements
  ];

  void _onTabChanged(int index) {
    if (index == 2) {
      // Center Create button (+) -> Opens CreateCommunityPostScreen
      Get.to(() => const CreateCommunityPostScreen(communityName: 'Fil d\'actualité général'));
      return;
    }
    if (index == 4) {
      // Profile avatar
      Get.toNamed(AppPages.myprofil);
      return;
    }
    int stackIndex = 0;
    if (index == 1) {
      stackIndex = 1;
    } else if (index == 3) {
      stackIndex = 2;
    } else {
      stackIndex = 0;
    }

    setState(() {
      _currentIndex = stackIndex;
      _visited[stackIndex] = true;
      _isBottomNavVisible = true;
    });

    if (Get.isRegistered<MainLayoutController>()) {
      Get.find<MainLayoutController>().currentTab.value = index;
    }

    // The community tab is kept alive in the page stack, so onInit alone
    // does not run again when the user returns to it.
    if (stackIndex == 1 && Get.isRegistered<CommunityController>()) {
      Get.find<CommunityController>().loadCommunities();
    }
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification) {
      if (notification.metrics.axis == Axis.horizontal) {
        return false;
      }
      if (notification.scrollDelta! > 10 && _isBottomNavVisible) {
        setState(() => _isBottomNavVisible = false);
      } else if (notification.scrollDelta! < -10 && !_isBottomNavVisible) {
        setState(() => _isBottomNavVisible = true);
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    bootLog('MainNavigationScreen.build');
    if (!Get.isRegistered<MainLayoutController>()) {
      Get.put(MainLayoutController());
    }

    final controller = Get.find<MainLayoutController>();
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: CustomAppBar(controller: controller),
      drawer: const AppDrawer(),
      body: Stack(
        children: [
          Positioned.fill(
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScrollNotification,
              child: IndexedStack(
                index: _currentIndex,
                children: List.generate(_pages.length, (index) {
                  if (!_visited[index]) {
                    return const SizedBox.shrink();
                  }
                  return _pages[index];
                }),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 250),
              offset: _isBottomNavVisible ? Offset.zero : const Offset(0, 1),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: _isBottomNavVisible ? 1.0 : 0.0,
                child: NavigationBar(
                  selectedIndex: _currentIndex == 2 ? 3 : _currentIndex,
                  onDestinationSelected: _onTabChanged,
                  labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
                  destinations: [
                    NavigationDestination(
                      icon: SvgPicture.asset(
                        'assets/svg_icons/japan-svgrepo-com.svg',
                        width: 24,
                        height: 24,
                        colorFilter: ColorFilter.mode(
                          colorScheme.onSurfaceVariant,
                          BlendMode.srcIn,
                        ),
                      ),
                      selectedIcon: SvgPicture.asset(
                        'assets/svg_icons/japan-svgrepo-com.svg',
                        width: 24,
                        height: 24,
                        colorFilter: ColorFilter.mode(
                          colorScheme.primary,
                          BlendMode.srcIn,
                        ),
                      ),
                      label: 'nav_home'.tr,
                    ),
                    NavigationDestination(
                      icon: SvgPicture.asset(
                        'assets/svg_icons/group-svgrepo-com.svg',
                        width: 24,
                        height: 24,
                        colorFilter: ColorFilter.mode(
                          colorScheme.onSurfaceVariant,
                          BlendMode.srcIn,
                        ),
                      ),
                      selectedIcon: SvgPicture.asset(
                        'assets/svg_icons/group-svgrepo-com.svg',
                        width: 24,
                        height: 24,
                        colorFilter: ColorFilter.mode(
                          colorScheme.primary,
                          BlendMode.srcIn,
                        ),
                      ),
                      label: 'Communautés',
                    ),
                    NavigationDestination(
                      icon: SvgPicture.asset(
                        'assets/svg_icons/add-circle-1-svgrepo-com.svg',
                        width: 38,
                        height: 38,
                      ),
                      selectedIcon: SvgPicture.asset(
                        'assets/svg_icons/add-circle-1-svgrepo-com.svg',
                        width: 38,
                        height: 38,
                      ),
                      label: 'nav_create'.tr,
                    ),
                    NavigationDestination(
                      icon: SvgPicture.asset(
                        'assets/svg_icons/event-svgrepo-com.svg',
                        width: 24,
                        height: 24,
                        colorFilter: ColorFilter.mode(
                          colorScheme.onSurfaceVariant,
                          BlendMode.srcIn,
                        ),
                      ),
                      selectedIcon: SvgPicture.asset(
                        'assets/svg_icons/event-svgrepo-com.svg',
                        width: 24,
                        height: 24,
                        colorFilter: ColorFilter.mode(
                          colorScheme.primary,
                          BlendMode.srcIn,
                        ),
                      ),
                      label: 'nav_events'.tr,
                    ),
                    NavigationDestination(
                      icon: const _BottomNavProfileIcon(isSelected: false),
                      selectedIcon: const _BottomNavProfileIcon(isSelected: true),
                      label: 'nav_profile'.tr,
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
}

class _BottomNavProfileIcon extends StatelessWidget {
  const _BottomNavProfileIcon({required this.isSelected});
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appController = Get.find<AppController>();

    return Obx(() {
      final profile = appController.profile.value;
      final avatar = profile?['photo_url']?.toString() ?? '';

      return Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? colorScheme.primary : colorScheme.outline,
            width: isSelected ? 2 : 1.5,
          ),
        ),
        child: ClipOval(
          child: avatar.isNotEmpty
              ? AppCachedImage(
                  imageUrl: avatar,
                  width: 28,
                  height: 28,
                  fit: BoxFit.cover,
                )
              : Container(
                  color: colorScheme.surfaceContainerHigh,
                  child: Icon(
                    Icons.person_rounded,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
        ),
      );
    });
  }
}

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Drawer(
      backgroundColor: colorScheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              height: 80,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Image.asset(
                    ImagePath.logoApp,
                    height: 32,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Scrole',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.folder_copy_outlined, color: colorScheme.tertiary),
              title: Text('drawer_my_content'.tr, style: const TextStyle(fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.of(context).pop();
                Get.toNamed(AppPages.myContent);
              },
            ),
            ListTile(
              leading: Icon(Icons.add_circle_outline_rounded, color: colorScheme.secondary),
              title: Text('drawer_creation'.tr, style: const TextStyle(fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.of(context).pop();
                Get.toNamed(AppPages.creationSelection);
              },
            ),
            ListTile(
              leading: Icon(Icons.info_outline_rounded, color: colorScheme.primary),
              title: Text('drawer_about'.tr, style: const TextStyle(fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.of(context).pop();
                Get.to(() => ExternalWebViewScreen(
                  url: 'https://about.scrole.fun',
                  title: 'webview_about_title'.tr,
                ));
              },
            ),
            ListTile(
              leading: Icon(Icons.settings_outlined, color: colorScheme.onSurfaceVariant),
              title: Text('drawer_settings'.tr, style: const TextStyle(fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.of(context).pop();
                Get.toNamed(AppPages.setting);
              },
            ),
            const Spacer(),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
