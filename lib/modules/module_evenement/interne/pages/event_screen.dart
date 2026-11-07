import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../../app/theme/app_colors.dart';
import '../../../../../app/theme/text_styles.dart';
import '../../../module_principale/interne/controllers/main_layout_controller.dart';
import '../controllers/event_controller.dart';
import 'event_calendar_tab.dart';
import 'event_suggestion_tab.dart';

import 'package:scrole/app/utils/boot_timing.dart';

class EventScreen extends StatefulWidget {
  const EventScreen({super.key});

  @override
  State<EventScreen> createState() => _EventScreenState();
}

class _EventScreenState extends State<EventScreen> {
  int _currentIndex = 0;
  final _pageController = PageController();
  Worker? _suggestionsNavigationWorker;
  int _lastSuggestionsNavigationRequest = 0;

  @override
  void initState() {
    super.initState();
    bootLog('EventScreen.initState');
    // Les deux onglets utilisent le même contrôleur. L'enregistrer avant
    // que le PageView ne construise SuggestionTab et CalendarTab.
    if (!Get.isRegistered<EventController>()) {
      Get.put<EventController>(EventController(), permanent: true);
    }
    if (Get.isRegistered<MainLayoutController>()) {
      final layoutController = Get.find<MainLayoutController>();
      _lastSuggestionsNavigationRequest = layoutController.eventSuggestionsNavigationRequest.value;
      _suggestionsNavigationWorker = ever<int>(
        layoutController.eventSuggestionsNavigationRequest,
        (request) {
          if (request <= _lastSuggestionsNavigationRequest) return;
          _lastSuggestionsNavigationRequest = request;
          if (!mounted) return;
          setState(() => _currentIndex = 0);
          if (_pageController.hasClients) {
            _pageController.jumpToPage(0);
          }
        },
      );
    }
  }

  @override
  void dispose() {
    _suggestionsNavigationWorker?.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bootLog('EventScreen.build');
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.background,
      body: Column(
        children: [
          const SizedBox(height: 8),
          // ===== PILLS TABS =====
          Center(
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTabChip(0, 'events_tab_suggestion'.tr),
                  _buildTabChip(1, 'events_tab_calendar'.tr),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // ===== CONTENT =====
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (i) => setState(() => _currentIndex = i),
              children: const [
                SuggestionTab(),
                CalendarTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabChip(int index, String label) {
    final isActive = _currentIndex == index;
    final colorScheme = Theme.of(context).colorScheme;
    
    return GestureDetector(
      onTap: () {
        setState(() => _currentIndex = index);
        _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? colorScheme.surfaceContainerHigh : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: AppTextStyles.labelLarge.copyWith(
            color: isActive ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
