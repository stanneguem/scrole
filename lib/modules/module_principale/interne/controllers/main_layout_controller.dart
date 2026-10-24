import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:scrole/app/utils/boot_timing.dart';
import 'package:scrole/app_controller.dart';
import 'package:scrole/app/routes/app_pages.dart';
import '../../../module_activite/interne/controllers/create_activity_controller.dart';
import '../../../module_notification/centre/services/notification_db_service.dart';
import '../../../module_evenement/centre/bindings/main_event_binding.dart';
import '../../../module_profil/interne/controllers/profile_controller.dart';
import '../../../module_discussion_direct/centre/repositories/messaging_repository.dart';

class MainLayoutController extends GetxController
    with GetSingleTickerProviderStateMixin {
  final NotificationDbService _notificationService = Get.find<NotificationDbService>();
  final MessagingRepository _messagingRepository = Get.find<MessagingRepository>();
  
  // Navigation
  final RxInt currentTab = 0.obs;
  int get selectedNavIndex => currentTab.value;

  // Add Menu
  final RxBool isAddMenuOpen = false.obs;

  // User Data
  final RxBool isLoading = true.obs;
  final RxString userFirstName = ''.obs;
  final RxString userAvatarUrl = ''.obs;
  final RxBool isVerified = false.obs;
  final RxInt unreadNotifications = 0.obs;
  final RxInt unreadMessages = 0.obs;

  late final AppController _appController;
  Worker? _profileWorker;

  late AnimationController fadeController;
  late Animation<double> fadeAnimation;

  @override
  void onInit() {
    bootLog('MainLayoutController.onInit start');
    super.onInit();

    MainEventBinding().dependencies();
    Get.lazyPut(() => ProfileController(), fenix: true);
    Get.lazyPut(() => CreateActivityController(), fenix: true);

    fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    fadeAnimation = CurvedAnimation(
      parent: fadeController,
      curve: Curves.easeInOut,
    );

    _appController = Get.find<AppController>();
    _bindUserData();
    bootLog('MainLayoutController.onInit end');
  }

  @override
  void onReady() {
    bootLog('MainLayoutController.onReady start');
    super.onReady();
    bootLog('MainLayoutController.onReady end');
  }

  @override
  void onClose() {
    _profileWorker?.dispose();
    fadeController.dispose();
    super.onClose();
  }

  void _bindUserData() {
    isLoading.value = true;

    _applyProfileOrDefaults(_appController.profile.value);
    _profileWorker = ever(_appController.profile, _applyProfileOrDefaults);

    final userId = _appController.authUser.value?.id;
    if (userId != null) {
      unreadNotifications.bindStream(_notificationService.watchUnreadCount(userId));
      unreadMessages.bindStream(_messagingRepository.watchGlobalUnreadCount());
    }

    isLoading.value = false;
    fadeController.forward();
  }

  void _applyProfileOrDefaults(Map<String, dynamic>? data) {
    if (data == null) {
      userFirstName.value = 'Utilisateur';
      userAvatarUrl.value = '';
      return;
    }

    final prenom = data['prenom']?.toString() ?? '';
    final username = data['username']?.toString() ?? '';
    userFirstName.value = prenom.isNotEmpty ? prenom : (username.isNotEmpty ? username : 'Utilisateur');
    userAvatarUrl.value = data['photo_url']?.toString() ?? '';
    isVerified.value = data['is_verified'] == true;
  }

  void changeTab(int navIndex) {
    if (isAddMenuOpen.value) {
      closeAddMenu();
    }
    if (currentTab.value != navIndex) {
      currentTab.value = navIndex;
    }
  }

  final RxInt eventSuggestionsNavigationRequest = 0.obs;

  void goToEventsTab() {
    closeAddMenu();
    changeTab(3);
  }

  void goToEventSuggestionsTab() {
    closeAddMenu();
    eventSuggestionsNavigationRequest.value++;
    changeTab(3);
  }

  void goToProfilScreen() {
    closeAddMenu();
    Get.toNamed(AppPages.myprofil);
  }

  void toggleAddMenu() {
    isAddMenuOpen.toggle();
  }

  void closeAddMenu() {
    isAddMenuOpen.value = false;
  }

  void openAddMenu() {
    isAddMenuOpen.value = true;
  }

  void onCreateEvent() {
    closeAddMenu();
    Get.toNamed(AppPages.createEvent);
  }

  void onCreateActivity() {
    closeAddMenu();
    Get.toNamed(AppPages.createactivite);
  }

  void onCreatePost() {
    closeAddMenu();
  }

  void openNotifications() {
    closeAddMenu();
    Get.toNamed(AppPages.notification);
  }

  void openSetting() {
    closeAddMenu();
    Get.toNamed(AppPages.setting);
  }

  void openScan() {
    closeAddMenu();
    Get.toNamed(AppPages.scanner);
  }

  void openMessages() {
    closeAddMenu();
    Get.toNamed(AppPages.discussion);
  }

  void openSearch() {
    closeAddMenu();
  }

  bool get hasNotifications => unreadNotifications.value > 0;
  bool get hasMessages => unreadMessages.value > 0;
  String get displayName => userFirstName.value.isNotEmpty
      ? userFirstName.value
      : 'Utilisateur';
  String get avatarUrl => userAvatarUrl.value;

  String get notificationBadge => unreadNotifications.value > 0
      ? unreadNotifications.value.toString()
      : '';
  String get messageBadge => unreadMessages.value > 0
      ? unreadMessages.value.toString()
      : '';
}
