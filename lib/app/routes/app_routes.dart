import 'package:get/get.dart';
import '../../modules/module_activite/interne/pages/create_activity_screen.dart';
import '../../modules/module_activite/interne/pages/my_activities_screen.dart';
import '../../modules/module_activite/centre/services/activity_service.dart';
import '../../modules/module_authentification/centre/bindings/auth_binding.dart';
import '../../modules/module_authentification/interne/pages/auth_screen.dart';
import '../../modules/module_activite/centre/bindings/create_activite_binding.dart';
import '../../modules/module_discussion_direct/interne/pages/direct_conversation_screen.dart';
import '../../modules/module_discussion_direct/interne/pages/contacts_screen.dart';
import '../../modules/module_discussion_direct/interne/controllers/contacts_controller.dart';
import '../../modules/module_discussion_direct/interne/pages/direct_messages_screen.dart';
import '../../modules/module_discussion_direct/interne/messaging_binding.dart';
import '../../modules/module_creation_de_compte/interne/pages/create_account_screen.dart';
import '../../modules/module_creation_de_compte/centre/bindings/create_user_account_binding.dart';
import '../../modules/module_notification/interne/controllers/notification_controller.dart';
import '../../modules/module_notification/interne/pages/notification_screen.dart';
import '../../modules/module_parametre/interne/pages/settings_screen.dart';
import '../../modules/module_parametre/interne/pages/scanner_screen.dart';
import '../../modules/module_profil/centre/bindings/edit_profil_binding.dart';
import '../../modules/module_profil/centre/bindings/profil_binding.dart';
import '../../modules/module_profil/interne/pages/edit_profile_screen.dart';
import '../../modules/module_profil/interne/pages/profile_screen.dart';
import '../../modules/module_profil/interne/pages/profile_contacts_screen.dart';
import '../../modules/module_profil/interne/pages/follow_lists_screen.dart';
import '../../modules/module_profil/interne/pages/follow_requests_screen.dart';
import '../../modules/module_profil/interne/pages/user_qr_identity_screen.dart';
import '../../modules/module_profil/interne/pages/share_profile_screen.dart';
import '../../modules/module_profil/interne/pages/interest_selection_screen.dart';
import '../../modules/module_decouverte/interne/controllers/external_profile_controller.dart';
import '../../modules/module_decouverte/interne/pages/external_profile_screen.dart';
import '../../modules/module_evenement/centre/bindings/create_event_binding.dart';
import '../../modules/module_evenement/centre/bindings/main_event_binding.dart';
import '../../modules/module_evenement/interne/pages/event_creation_screen.dart';
import '../../modules/module_evenement/interne/pages/my_events_screen.dart';
import '../../modules/module_evenement/interne/pages/event_preview_screen.dart';
import '../../modules/module_evenement/interne/pages/edit_event_screen.dart';
import '../../modules/module_evenement/interne/pages/event_settings_screen.dart';
import '../../modules/module_evenement/interne/pages/event_visibility_screen.dart';
import '../../modules/module_evenement/interne/pages/co_creators_management_screen.dart';
import '../../modules/module_evenement/interne/pages/staff_management_screen.dart';
import '../../modules/module_evenement/interne/pages/ticket_management_screen.dart';
import '../../modules/module_evenement/interne/pages/create_ticket_screen.dart';
import '../../modules/module_evenement/interne/pages/activity_management_screen.dart';
import '../../modules/module_evenement/interne/pages/add_activity_screen.dart';
import '../../modules/module_evenement/interne/pages/user_agenda_screen.dart';
import '../../modules/module_evenement/interne/pages/qr_scan_screen.dart';
import '../../modules/module_evenement/interne/pages/event_budget_calculator_screen.dart';
import '../../modules/module_evenement/interne/pages/transfer_ownership_screen.dart';
import '../../modules/module_evenement/interne/pages/event_pricing_screen.dart';
import '../../modules/module_evenement/interne/pages/event_stats_dashboard_screen.dart';
import '../../modules/module_evenement/interne/pages/event_interests_screen.dart';
import '../../modules/module_evenement/interne/pages/user_invitations_screen.dart';
import '../../modules/module_evenement/interne/pages/event_admin_moderation_screen.dart';
import '../../modules/module_evenement/interne/pages/checkin_tree_screen.dart';
import '../../modules/module_evenement/interne/controllers/event_budget_controller.dart';
import '../../modules/module_evenement/centre/bindings/staff_binding.dart';
import '../../modules/module_evenement/centre/bindings/ticket_binding.dart';
import '../../modules/module_evenement/centre/bindings/event_activity_binding.dart';
import '../../modules/module_evenement/centre/bindings/user_agenda_binding.dart';
import '../../modules/module_evenement/centre/bindings/qr_scan_binding.dart';
import '../../modules/module_evenement/centre/bindings/edit_event_binding.dart';
import '../../modules/module_evenement/centre/bindings/transfer_ownership_binding.dart';
import '../../shared/widgets/creation_selection_screen.dart';
import '../../shared/widgets/my_content_screen.dart';
import '../../root_page.dart';
import 'app_pages.dart';

class AppRoutes {
  static final routes = [
    GetPage(name: AppPages.root, page: () => const RootPage()),
    GetPage(name: AppPages.authentificationscreen, page: () => AuthScreen(), binding: AuthBinding()),
    GetPage(name: AppPages.creercompte, page: () => CreateAccountScreen(), binding: CreateUserAccountBinding()),
    GetPage(name: AppPages.myprofil, page: () => ProfileScreen(), binding: ProfilBinding()),
    GetPage(name: AppPages.externalProfile, page: () => const ExternalProfileScreen(), binding: BindingsBuilder(() => Get.lazyPut(() => ExternalProfileController()))),
    GetPage(name: AppPages.setting, page: () => SettingsScreen()),
    GetPage(
      name: AppPages.notification,
      page: () => const NotificationScreen(),
      binding: BindingsBuilder(() {
        Get.lazyPut<NotificationController>(() => NotificationController());
      }),
    ),
    GetPage(name: AppPages.scanner, page: () => ScannerScreen()),
    GetPage(name: AppPages.createactivite, page: () => CreateActivityScreen(), binding: CreateActiviteBinding()),
    GetPage(
      name: AppPages.myActivities,
      page: () => const MyActivitiesScreen(),
      binding: BindingsBuilder(() {
        if (!Get.isRegistered<ActivityService>()) {
          Get.lazyPut(() => ActivityService());
        }
      }),
    ),
    GetPage(name: AppPages.createEvent, page: () => const EventCreationScreen(), binding: CreateEventBinding()),
    GetPage(name: AppPages.myEvents, page: () => const MyEventsScreen(), binding: MainEventBinding()),
    GetPage(name: AppPages.eventPreview, page: () => const EventPreviewScreen()),
    GetPage(name: AppPages.eventEdit, page: () => const EditEventScreen(), binding: EditEventBinding()),
    GetPage(name: AppPages.eventSettings, page: () => const EventSettingsScreen()),
    GetPage(name: AppPages.eventVisibility, page: () => const EventVisibilityScreen()),
    GetPage(name: AppPages.eventCoCreators, page: () => const CoCreatorsManagementScreen(), binding: StaffBinding()),
    GetPage(name: AppPages.eventStaff, page: () => const StaffManagementScreen(), binding: StaffBinding()),
    GetPage(name: AppPages.eventTickets, page: () => const TicketManagementScreen(), binding: TicketBinding()),
    GetPage(name: AppPages.eventTicketCreate, page: () => const CreateTicketScreen(), binding: TicketBinding()),
    GetPage(name: AppPages.eventActivities, page: () => const ActivityManagementScreen(), binding: EventActivityBinding()),
    GetPage(name: AppPages.eventActivityAdd, page: () => const AddActivityScreen(), binding: EventActivityBinding()),
    GetPage(name: AppPages.userAgenda, page: () => const UserAgendaScreen(), binding: UserAgendaBinding()),
    GetPage(name: AppPages.eventScan, page: () => const QrScanScreen(), binding: QrScanBinding()),
    GetPage(
      name: AppPages.eventBudget,
      page: () => const EventBudgetCalculatorScreen(),
      binding: BindingsBuilder(() {
        Get.lazyPut(() => EventBudgetController());
      }),
    ),
    GetPage(name: AppPages.eventTransfer, page: () => const TransferOwnershipScreen(), binding: TransferOwnershipBinding()),
    GetPage(name: AppPages.eventPricing, page: () => const EventPricingScreen()),
    GetPage(name: AppPages.eventStatistics, page: () => const EventStatsDashboardScreen()),
    GetPage(name: AppPages.eventInterests, page: () => const EventInterestsScreen()),
    GetPage(name: AppPages.eventInvitations, page: () => const UserInvitationsScreen()),
    GetPage(name: AppPages.eventAdminModeration, page: () => const EventAdminModerationScreen()),
    GetPage(name: AppPages.eventCheckinTree, page: () => CheckinTreeScreen(eventId: Get.parameters['id'] ?? '')),
    GetPage(name: AppPages.discussion, page: () => const DirectMessagesScreen(), binding: MessagingBinding()),
    GetPage(name: AppPages.conversation, page: () => const DirectConversationScreen(), binding: ConversationBinding()),
    GetPage(name: AppPages.contacts, page: () => const ContactsScreen(), binding: BindingsBuilder(() => Get.lazyPut(() => ContactsController()))),
    GetPage(name: AppPages.editmyprofil, page: () => const EditProfileScreen(), binding: EditProfilBinding()),
    GetPage(name: AppPages.myContacts, page: () => const FollowListsScreen()),
    GetPage(name: AppPages.followLists, page: () => const FollowListsScreen()),
    GetPage(name: AppPages.followRequests, page: () => const FollowRequestsScreen()),
    GetPage(name: AppPages.userQrCode, page: () => const UserQrIdentityScreen()),
    GetPage(name: AppPages.shareMyProfile, page: () => const ShareProfileScreen()),
    GetPage(name: AppPages.interestSelection, page: () => const InterestSelectionScreen()),
    GetPage(name: AppPages.creationSelection, page: () => const CreationSelectionScreen()),
    GetPage(name: AppPages.myContent, page: () => const MyContentScreen()),
  ];
}
