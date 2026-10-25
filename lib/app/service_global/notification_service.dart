import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, kIsWeb, VoidCallback, debugPrintStack;
import 'package:flutter/widgets.dart'
    show WidgetsBinding, WidgetsBindingObserver, Locale;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart' hide Response;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:scrole/app/service_global/connectivity_service.dart';
import 'package:scrole/app/service_global/preferences_service.dart';
import 'package:scrole/app/routes/app_pages.dart';
import 'package:scrole/modules/module_authentification/centre/services/auth_service.dart';
import 'package:scrole/modules/module_notification/centre/services/notification_db_service.dart';
import 'package:scrole/modules/module_notification/centre/services/notification_deep_link_router.dart';
import 'package:scrole/modules/module_notification/externe/repositories/fcm_token_repository.dart';
import 'package:scrole/modules/module_notification/externe/repositories/notification_repository.dart';
import 'package:scrole/modules/module_discussion_direct/centre/repositories/messaging_repository.dart';
import 'package:scrole/modules/module_discussion_direct/centre/models/message.dart'
    as messaging;
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM] Background message received: ${message.messageId}');

  // If it's a data-only message and we are in background, we must show it manually
  if (message.notification == null && message.data.isNotEmpty) {
    final data = message.data;
    final title =
        data['title']?.toString() ??
        data['sender_name']?.toString() ??
        data['subject']?.toString() ??
        'Scrole';
    final body =
        data['body']?.toString() ??
        data['content']?.toString() ??
        data['message']?.toString() ??
        data['text']?.toString() ??
        '';

    if (body.isNotEmpty) {
      final plugin = FlutterLocalNotificationsPlugin();
      // Minimal initialization for the background isolate
      await plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
      );

      // Identifiant stable : le même que celui utilisé par le chemin Realtime
      // et par onMessage, pour que la même notification se remplace au lieu
      // de s'ajouter.
      final notifId = data['notification_id']?.toString() ?? '';

      await plugin.show(
        id: notifId.isNotEmpty
            ? notifId.hashCode.abs()
            : message.hashCode.abs(),
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'scrole_default_channel',
            'Notifications Scrole',
            importance: Importance.high,
            priority: Priority.high,
            onlyAlertOnce: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: jsonEncode(data),
      );
    }
  }
}

/// Détecte les changements de langue de l'appareil.
class _LocaleObserver with WidgetsBindingObserver {
  _LocaleObserver(this.onChange);
  final VoidCallback onChange;

  @override
  void didChangeLocales(List<Locale>? locales) => onChange();
}

class NotificationService {
  NotificationService._internal();
  static final NotificationService instance = NotificationService._internal();
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FcmTokenRepository _tokenRepository = FcmTokenRepository(
    Supabase.instance.client,
  );
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  bool _initialized = false;
  Worker? _authWorker;
  String? _activeConversationId;
  RealtimeChannel? _notificationChannel;
  bool _subscribedOnce = false;
  bool _isProcessingOutbox = false;
  String? _lastSyncedLanguage;

  static const AndroidNotificationChannel _defaultChannel =
      AndroidNotificationChannel(
        'scrole_default_channel',
        'Notifications Scrole',
        description: 'Notifications générales de l\'application',
        importance: Importance.max,
      );
  static const String replyActionId = 'reply_action';
  static const String _replyCategoryId = 'reply_category';

  void setActiveConversation(String? conversationId) =>
      _activeConversationId = conversationId;

  /// Langue à envoyer au serveur (fr, en, es, de ; repli sur fr).
  String _currentLanguageCode() {
    final locale =
        Get.locale ??
        Get.deviceLocale ??
        WidgetsBinding.instance.platformDispatcher.locale;
    const supported = ['fr', 'en', 'es', 'de', 'it', 'pt', 'zh', 'ja', 'ru'];
    return supported.contains(locale.languageCode) ? locale.languageCode : 'fr';
  }

  /// Synchronise la langue de l'appareil/de l'app avec `user_preferences.language`.
  /// Le serveur s'en sert pour traduire les notifications (table + push).
  /// À rappeler aussi après un changement de langue dans l'app
  /// (ex. après `Get.updateLocale(...)`) avec `force: true`.
  Future<void> syncLanguage({bool force = false}) async {
    if (kIsWeb || Get.find<AuthService>().userId == null) return;
    final code = _currentLanguageCode();
    if (!force && code == _lastSyncedLanguage) return;
    try {
      await Supabase.instance.client.rpc(
        'set_app_language',
        params: {'p_language': code},
      );
      _lastSyncedLanguage = code;
    } catch (e) {
      debugPrint('[FCM] Échec synchro langue: $e');
    }
  }

  void _openMessageConversation(Map<String, dynamic> data) {
    final conversationId = data['conversation_id']?.toString();
    if (conversationId == null || conversationId.isEmpty) return;
    Get.toNamed(
      AppPages.conversation,
      parameters: {'chatId': conversationId},
      arguments: {
        'userId': data['sender_id']?.toString() ?? '',
        'name': data['sender_name']?.toString() ?? 'Ami',
        'avatar': data['sender_photo_url']?.toString(),
      },
    );
  }

  Future<void> _handleReplyAction(NotificationResponse response) async {
    if (response.actionId != replyActionId) return;
    final text = response.input?.trim();
    if (text == null ||
        text.isEmpty ||
        response.payload == null ||
        response.payload!.isEmpty)
      return;
    try {
      final data = Map<String, dynamic>.from(
        jsonDecode(response.payload!) as Map,
      );
      final conversationId = data['conversation_id']?.toString();
      final senderId = Get.find<AuthService>().userId;
      if (conversationId == null || conversationId.isEmpty || senderId == null)
        return;
      final repository = Get.find<MessagingRepository>();
      final localId = repository.generateLocalId();
      final message = messaging.Message(
        id: localId,
        localId: localId,
        conversationId: conversationId,
        senderId: senderId,
        content: text,
        type: messaging.MessageType.text,
        sentAt: DateTime.now().toUtc(),
        status: messaging.MessageStatus.pending,
      );
      final result = await repository.sendMessage(message);
      if (!result.success)
        throw Exception(result.message ?? "Échec de l'envoi");
      final senderName =
          data['sender_name']?.toString() ?? data['title']?.toString() ?? 'Ami';
      final originalMessage = data['body']?.toString() ?? '';
      await showNotification(
        id: response.id ?? DateTime.now().millisecondsSinceEpoch,
        title: senderName,
        body: originalMessage.isEmpty
            ? '✅ Répondu'
            : '✅ Répondu : $originalMessage',
        payload: response.payload,
      );
      debugPrint('[FCM] Réponse rapide envoyée dans $conversationId');
    } catch (e) {
      debugPrint('[FCM] Échec réponse rapide: $e');
    }
  }

  Future<void> initialize({
    void Function(NotificationResponse response)? onNotificationTap,
  }) async {
    if (_initialized || kIsWeb) {
      if (kIsWeb) _initialized = true;
      return;
    }
    tz.initializeTimeZones();
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    final iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      notificationCategories: [
        DarwinNotificationCategory(
          _replyCategoryId,
          actions: [
            DarwinNotificationAction.text(
              'reply_action',
              'Répondre',
              buttonTitle: 'Envoyer',
              placeholder: 'Votre message',
            ),
          ],
        ),
      ],
    );
    await _plugin.initialize(
      settings: InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
      onDidReceiveNotificationResponse: (response) async {
        if (response.actionId == replyActionId) {
          await _handleReplyAction(response);
          return;
        }
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          try {
            final data = Map<String, dynamic>.from(jsonDecode(payload) as Map);
            if (data['type'] == 'message_received') {
              _openMessageConversation(data);
            } else {
              unawaited(NotificationDeepLinkRouter.open(data));
            }
          } catch (e) {
            debugPrint('[FCM] Unable to parse local notification payload: $e');
          }
        }
        onNotificationTap?.call(response);
      },
    );

    // Request permissions for Android 13+ and FCM
    await requestPermissions();

    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_defaultChannel);
    await _setupFirebaseMessaging();
    await _setupRealtimeNotifications();
    unawaited(_routeInitialLocalNotification());

    // Process pending outbox actions (deletions, etc.)
    unawaited(processOutbox());

    // Écouter le retour de connexion pour synchroniser l'outbox
    Get.find<ConnectivityService>().onStatusChange.listen((status) {
      if (status == InternetStatus.connected) unawaited(processOutbox());
    });

    // Écouter le refresh spontané du token
    _fcm.onTokenRefresh.listen((token) async {
      debugPrint('[FCM] Token refreshed spontaneously');
      await _registerToken(token);
    });

    final authService = Get.find<AuthService>();
    _authWorker = ever(authService.currentUser, (user) async {
      if (user != null) {
        // Réutiliser le token stable : le backend compare last_seen_at pour
        // ne rattraper que les notifications reçues pendant l'absence.
        // Supprimer le token à chaque session faisait perdre ce checkpoint et
        // rejouait tout l'historique des notifications non lues.
        await ensureCurrentDeviceRegistered();
        await syncLanguage(force: true);
      }
    });

    // Synchronisation de la langue : au démarrage et à chaque changement
    // de langue de l'appareil.
    WidgetsBinding.instance.addObserver(
      _LocaleObserver(() => unawaited(syncLanguage())),
    );
    unawaited(syncLanguage(force: true));

    _initialized = true;
  }

  /// Force la suppression de l'ancien token FCM et en génère un nouveau.
  /// Utile lors d'un changement de compte pour éviter les mélanges de notifications.
  Future<void> rotateToken() async {
    if (kIsWeb) return;
    try {
      debugPrint('[FCM] Rotating token for account isolation...');
      await _fcm.deleteToken();
      final newToken = await _fcm.getToken();
      if (newToken != null) {
        await _registerToken(newToken);
      }
    } catch (e) {
      debugPrint('[FCM] Erreur lors de la rotation du token: $e');
      // Repli : tenter d'enregistrer le token actuel si deleteToken échoue
      final currentToken = await _fcm.getToken();
      if (currentToken != null) await _registerToken(currentToken);
    }
  }

  Future<void> requestPermissions() async {
    if (kIsWeb) return;

    if (Platform.isIOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } else if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    }

    await _fcm.requestPermission(alert: true, badge: true, sound: true);
  }

  Future<void> _registerCurrentDeviceToken() async {
    if (Get.find<AuthService>().userId == null) return;
    final token = await getDeviceToken();
    if (token != null) await _registerToken(token);
  }

  /// Enregistre l'appareil courant sans forcer une rotation du token FCM.
  Future<void> ensureCurrentDeviceRegistered() => _registerCurrentDeviceToken();

  Future<void> _registerToken(String token) async {
    if (Get.find<AuthService>().userId == null) return;
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      String? osVersion, deviceBrand, deviceModel;
      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        osVersion = info.version.release;
        deviceBrand = info.brand;
        deviceModel = info.model;
      } else if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        osVersion = info.systemVersion;
        deviceBrand = 'Apple';
        deviceModel = info.utsname.machine;
      }
      final missed = await _tokenRepository.registerToken(
        token: token,
        platform: Platform.isIOS ? 'ios' : 'android',
        osVersion: osVersion,
        appVersion: packageInfo.version,
        deviceBrand: deviceBrand,
        deviceModel: deviceModel,
      );
      await _replayMissedNotifications(missed);
    } catch (e) {
      if (e.toString().contains('23505') ||
          e.toString().contains('already exists')) {
        debugPrint(
          '[FCM] Token already registered for this user, ignoring duplicate error.',
        );
        return;
      }
      debugPrint('[FCM] Échec enregistrement token/appareil: $e');
    }
  }

  Future<void> _replayMissedNotifications(
    List<Map<String, dynamic>> missed,
  ) async {
    final userId = Get.find<AuthService>().userId;
    if (userId == null || missed.isEmpty) return;
    final db = Get.find<NotificationDbService>();
    for (final notification in missed) {
      final type = notification['type']?.toString() ?? 'info';
      if (type == 'message_received') continue;
      final id = notification['id']?.toString();
      if (id == null || id.isEmpty) continue;
      await db.saveNotification(
        id: id,
        userId: userId,
        title: notification['title']?.toString() ?? 'Scrole',
        message: notification['body']?.toString() ?? '',
        type: type,
        payload: jsonEncode({
          if (notification['data'] is Map)
            ...Map<String, dynamic>.from(notification['data'] as Map),
          'type': type,
          'notification_id': id,
          if (notification['actor_id'] != null)
            'actor_id': notification['actor_id'],
        }),
      );
    }
  }

  Future<void> _setupRealtimeNotifications() async {
    final userId = Get.find<AuthService>().userId;
    if (userId == null || kIsWeb) return;

    final client = Supabase.instance.client;
    final db = Get.find<NotificationDbService>();

    _notificationChannel?.unsubscribe();
    _notificationChannel = client.channel('notifications_utilisateur')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'notifications',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: userId,
        ),
        callback: (payload) async {
          final row = payload.newRecord;
          await _processIncomingNotification(row);
        },
      ).subscribe((status, error) async {
        if (status == RealtimeSubscribeStatus.subscribed) {
          if (_subscribedOnce) {
            // RECONNEXION : Rattrapage ciblé pour combler les "trous"
            debugPrint(
              '[Sync] Notification channel reconnected, catching up...',
            );
            final lastSeen = await db.getLatestNotificationTimestamp(userId);

            // On récupère tout ce qui est arrivé depuis le dernier checkpoint local
            final query = client
                .from('notifications')
                .select()
                .eq('user_id', userId);
            if (lastSeen != null) {
              // Inclure l'égalité : plusieurs notifications peuvent partager
              // le même timestamp. L'insert local est idempotent par ID.
              query.gte('created_at', lastSeen.toUtc().toIso8601String());
            }

            try {
              final missed = await query.order('created_at');
              for (final n in missed) {
                await _processIncomingNotification(n);
              }
              debugPrint(
                '[Sync] Notification catch-up completed: ${missed.length} missed notifications processed.',
              );
            } catch (e) {
              debugPrint('[Error] Notification catch-up failed: $e');
            }
          }
          _subscribedOnce = true;
        }
      });
  }

  Future<void> processOutbox() async {
    final userId = Get.find<AuthService>().userId;
    if (userId == null || _isProcessingOutbox) return;

    _isProcessingOutbox = true;
    try {
      final db = Get.find<NotificationDbService>();
      final repo = NotificationRepository(); // Ou via Get.find si enregistré

      final pending = await db.getPendingOutbox(userId);
      for (final item in pending) {
        final nid = item['notification_id'].toString();
        final type = item['action_type'].toString();

        try {
          if (type == 'delete') {
            await repo.deleteNotification(nid);
          } else if (type == 'mark_read') {
            await repo.markAsRead(nid);
          }
          await db.removeFromOutbox(userId, nid, type);
        } catch (e) {
          debugPrint('[FCM] Outbox item $nid ($type) failed: $e');
          await db.markOutboxAttempt(userId, nid, type);
        }
      }
    } finally {
      _isProcessingOutbox = false;
    }
  }

  Future<void> _processIncomingNotification(Map<String, dynamic> data) async {
    final userId = Get.find<AuthService>().userId;
    if (userId == null) return;

    final id =
        data['id']?.toString() ??
        DateTime.now().millisecondsSinceEpoch.toString();
    final title = data['title']?.toString() ?? 'Scrole';
    final body = data['body']?.toString() ?? '';
    final type = data['type']?.toString() ?? 'info';
    final rawPayloadData = data['data'];
    final payload = jsonEncode({
      if (rawPayloadData is Map) ...Map<String, dynamic>.from(rawPayloadData),
      'type': type,
      'notification_id': id,
      if (data['actor_id'] != null) 'actor_id': data['actor_id'],
    });

    final dbService = Get.find<NotificationDbService>();

    // Récupération de l'horodatage réel du serveur si disponible
    DateTime? createdAt;
    if (data['created_at'] != null) {
      createdAt = DateTime.tryParse(data['created_at'].toString());
    }

    // 1. Sauvegarde en DB locale (met à jour le checkpoint pour le rattrapage)
    final saved = await dbService.saveNotification(
      id: id,
      userId: userId,
      title: title,
      message: body,
      type: type,
      payload: payload,
      createdAt: createdAt,
      // Le rattrapage Realtime doit respecter l'état serveur, sinon une
      // notification déjà lue revient comme non lue après reconnexion.
      isRead: data['read_at'] != null,
    );

    // 2. Affichage local si la notification est nouvelle et le corps non vide
    if (saved && body.isNotEmpty) {
      debugPrint('[FCM] Showing local notification: $title - $body');
      await showNotification(
        id: id.hashCode.abs(),
        title: title,
        body: body,
        payload: payload,
      );
    }
  }

  Future<void> _setupFirebaseMessaging() async {
    // En premier plan, on laisse FlutterLocalNotifications gérer l'affichage.
    // Si iOS affiche aussi le payload FCM natif, la même notification apparaît
    // deux fois (bannière FCM + notification locale).
    await _fcm.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: true,
      sound: false,
    );

    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      debugPrint('[FCM] Foreground message: ${message.data}');
      if (message.notification != null) {
        debugPrint(
          '[FCM] Notification: ${message.notification!.title} / ${message.notification!.body}',
        );
      }

      final data = Map<String, dynamic>.from(message.data);
      final type = data['type']?.toString() ?? 'info';
      final title =
          message.notification?.title ??
          data['title']?.toString() ??
          data['sender_name']?.toString() ??
          data['subject']?.toString() ??
          'Scrole';
      final body =
          message.notification?.body ??
          data['body']?.toString() ??
          data['content']?.toString() ??
          data['message']?.toString() ??
          data['text']?.toString() ??
          '';

      if (type == 'message_received') {
        final conversationId = data['conversation_id']?.toString();
        if (Get.isRegistered<MessagingRepository>()) {
          unawaited(
            Get.find<MessagingRepository>().handlePushWake(conversationId),
          );
        }
        if (conversationId != null && conversationId == _activeConversationId)
          return;

        await showReplyableNotification(
          id: message.hashCode.abs(),
          senderName: title,
          message: body,
          payload: jsonEncode(data),
        );
        return;
      }

      // Même identifiant que le chemin Realtime (`id` de la ligne = `notification_id`)
      final notifId =
          data['notification_id']?.toString() ??
          message.messageId ??
          DateTime.now().millisecondsSinceEpoch.toString();

      final userId = Get.find<AuthService>().userId;
      var saved = true;
      if (userId != null) {
        try {
          saved = await Get.find<NotificationDbService>().saveNotification(
            id: notifId,
            userId: userId,
            title: title,
            message: body,
            type: type,
            payload: jsonEncode(data),
          );
        } catch (e) {
          debugPrint('[FCM] Erreur sauvegarde notification: $e');
        }
      }

      // Si la notification a déjà été sauvegardée (et donc affichée) par le
      // chemin Realtime, on ne l'affiche pas une deuxième fois.
      if (saved && body.isNotEmpty) {
        debugPrint('[FCM] Showing local notification: $title - $body');
        await showNotification(
          id: notifId.hashCode.abs(),
          title: title,
          body: body,
          payload: data.isNotEmpty ? jsonEncode(data) : null,
        );
      } else if (!saved) {
        debugPrint('[FCM] Notification déjà traitée, affichage ignoré');
      } else {
        debugPrint('[FCM] Body is empty, not showing notification');
      }
    });
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final data = Map<String, dynamic>.from(message.data);
      if (data['type'] == 'message_received') {
        _openMessageConversation(data);
      } else {
        unawaited(NotificationDeepLinkRouter.open(data));
      }
    });

    // When Android/iOS launches the app from a terminated state via an FCM tap.
    unawaited(_routeInitialFirebaseMessage());
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  Future<void> _routeInitialLocalNotification() async {
    try {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final response = launch?.notificationResponse;
      final payload = response?.payload;
      if (launch?.didNotificationLaunchApp != true ||
          payload == null ||
          payload.isEmpty)
        return;
      await Future<void>.delayed(const Duration(milliseconds: 700));
      final data = Map<String, dynamic>.from(jsonDecode(payload) as Map);
      if (data['type'] == 'message_received') {
        _openMessageConversation(data);
      } else {
        await NotificationDeepLinkRouter.open(data);
      }
    } catch (e, st) {
      debugPrint(
        '[Notifications] Failed to route local notification launch: $e',
      );
      debugPrintStack(stackTrace: st);
    }
  }

  Future<void> _routeInitialFirebaseMessage() async {
    try {
      final initial = await _fcm.getInitialMessage();
      if (initial == null || initial.data.isEmpty) return;
      // Wait until GetX routes and the initial app frame are available.
      await Future<void>.delayed(const Duration(milliseconds: 700));
      final data = Map<String, dynamic>.from(initial.data);
      if (data['type'] == 'message_received') {
        _openMessageConversation(data);
      } else {
        await NotificationDeepLinkRouter.open(data);
      }
    } catch (e, st) {
      debugPrint('[FCM] Failed to route initial notification: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  bool _notificationAllowed(String? payload) {
    try {
      if (!Get.isRegistered<PreferencesService>()) return true;
      final prefs = Get.find<PreferencesService>().preferences.value;
      if (!prefs.notificationsEnabled || !prefs.notifPush) return false;
      if (payload == null || payload.isEmpty) return true;
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return true;
      final type = (decoded['type'] ?? '').toString().toLowerCase();
      if (type.isEmpty) return true;
      if (type.contains('message')) return prefs.notifMessages;
      if (type.contains('event') || type.contains('evenement')) return prefs.notifEvenements;
      if (type.contains('community') || type.contains('communaute')) return prefs.notifCommunautes;
      return prefs.notifSocial;
    } catch (_) {
      // A malformed payload must not prevent normal notifications from working.
      return true;
    }
  }

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_notificationAllowed(payload)) {
      debugPrint('[FCM] Notification suppressed by user preferences');
      return;
    }
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'scrole_default_channel',
        'Notifications Scrole',
        importance: Importance.max,
        priority: Priority.high,
        showWhen: true,
        channelShowBadge: true,
        enableVibration: true,
        onlyAlertOnce: true,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }

  Future<void> showReplyableNotification({
    required int id,
    required String senderName,
    required String message,
    required String payload,
  }) async {
    if (!_notificationAllowed(payload)) {
      debugPrint('[FCM] Replyable message notification suppressed by user preferences');
      return;
    }
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'scrole_default_channel',
        'Notifications Scrole',
        importance: Importance.max,
        priority: Priority.high,
        showWhen: true,
        channelShowBadge: true,
        enableVibration: true,
        icon: '@mipmap/ic_launcher',
        actions: [
          AndroidNotificationAction(
            replyActionId,
            'Répondre',
            inputs: [
              const AndroidNotificationActionInput(label: 'Votre message'),
            ],
          ),
        ],
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        categoryIdentifier: _replyCategoryId,
      ),
    );
    await _plugin.show(
      id: id,
      title: senderName,
      body: message,
      notificationDetails: details,
      payload: payload,
    );
  }

  Future<String?> getDeviceToken() async {
    if (kIsWeb) return FirebaseMessaging.instance.getToken();
    try {
      return await _fcm.getToken();
    } catch (_) {
      return null;
    }
  }
}
