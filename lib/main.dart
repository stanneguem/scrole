import 'dart:async';
import 'dart:io';
import 'package:device_preview/device_preview.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:scrole/app/utils/boot_timing.dart';
import 'package:scrole/modules/module_authentification/centre/services/auth_service.dart';
import 'package:scrole/app/service_global/theme_service.dart';
import 'package:scrole/modules/module_creation_de_compte/centre/services/user_service.dart';
import 'package:scrole/app/repository_global/location_repository.dart';
import 'package:scrole/app/repository_global/centre_interets_repository.dart';
import 'package:scrole/app/service_global/language_service.dart';
import 'package:scrole/app/service_global/notification_service.dart';
import 'package:scrole/app/service_global/app_config_service.dart';
import 'package:scrole/app/service_global/app_deep_link_service.dart';
import 'package:scrole/app/service_global/connectivity_service.dart';
import 'package:scrole/app/service_global/device_service.dart';
import 'package:scrole/app/service_global/media_service.dart';
import 'package:scrole/app/service_global/currency_service.dart';
import 'package:scrole/app/service_global/preferences_service.dart';
import 'package:scrole/app/service_global/privacy_service.dart';
import 'package:scrole/app/service_global/session_service.dart';
import 'package:scrole/app/service_global/presence_service.dart';
import 'package:scrole/app/service_global/supabse_service.dart';
import 'package:scrole/app/service_global/sync_service.dart';
import 'package:scrole/app/service_global/centre_interrets_service.dart';
import 'package:scrole/app_controller.dart';
import 'package:scrole/app/local_storage/fast/fast_cache_service.dart';
import 'package:scrole/app/local_storage/structured/app_cache_database.dart';
import 'package:scrole/app/routes/app_pages.dart';
import 'package:scrole/app/routes/app_routes.dart';
import 'package:scrole/app/theme/app_theme.dart';
import 'package:scrole/app/translation/scrole_translations.dart';
import 'modules/module_activite/centre/services/activity_service.dart';
import 'package:scrole/shared/services/search_history_service.dart';
import 'package:scrole/modules/module_appareils/interne/controllers/device_controller.dart';
import 'package:scrole/modules/module_authentification/interne/controllers/auth_controller.dart';
import 'package:scrole/modules/module_notification/centre/services/notification_db_service.dart';
import 'package:scrole/modules/module_discussion_direct/centre/repositories/messaging_repository.dart';
import 'package:scrole/modules/module_discussion_direct/externe/services/supabase_messaging_service.dart';
import 'package:scrole/modules/module_discussion_direct/externe/services/fcm_notification_service.dart';
import 'package:scrole/modules/module_discussion_direct/centre/services/chat_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  bootLog('WidgetsFlutterBinding.ensureInitialized terminé');

  PlatformDispatcher.instance.onError = (error, stack) {
    if (error is SocketException ||
        error.toString().contains('SocketException') ||
        error.toString().contains('Connection refused')) {
      if (kDebugMode) {
        debugPrint('[Network] Erreur réseau ignorée (hors ligne / connexion refusée).');
      }
      return true;
    }
    if (error.toString().contains('bad_code_verifier') ||
        error.toString().contains('code challenge does not match')) {
      if (kDebugMode) {
        debugPrint(
          '[SupabaseAuth] Code PKCE deeplink expiré ou invalide intercepté avec succès.',
        );
      }
      return true;
    }
    return false;
  };
  if (kIsWeb) {
    FlutterError.onError = (FlutterErrorDetails details) {
      final error = details.exceptionAsString();
      final errorsToIgnore = [
        '_handledContextLostEvent',
        'Noto fonts',
        'widget has been unmounted',
        'setBreakpoints',
        'getWindowWidth',
        'CanvasKit',
        'context lost',
        'FrameService',
      ];
      if (errorsToIgnore.any((e) => error.contains(e))) return;
      FlutterError.dumpErrorToConsole(details);
    };
  }
  _bootstrap();
}

Future<T> _timed<T>(String label, Future<T> Function() fn) async {
  final sw = Stopwatch()..start();
  final result = await fn();
  debugPrint('[BootTiming] $label : ${sw.elapsedMilliseconds} ms');
  return result;
}

void _startJankMonitor() {
  if (kDebugMode || kProfileMode) {
    int lastTickMs = bootClock.elapsedMilliseconds;
    final timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final nowMs = bootClock.elapsedMilliseconds;
      final delta = nowMs - lastTickMs;
      if (delta > 250) {
        bootLog('thread UI bloqué ~$delta ms');
      }
      lastTickMs = nowMs;
    });
    Timer(const Duration(seconds: 15), () => timer.cancel());
  }
}

/// Démarrage en deux phases :
///  1. phase critique : uniquement ce qu'il faut pour afficher le premier écran
///  2. phase différée : tout le reste, après le premier frame
Future<void> _bootstrap() async {
  final sw = Stopwatch()..start();
  try {
    await _initCritical();
    debugPrint('[Boot] phase critique : ${sw.elapsedMilliseconds} ms');

    _startJankMonitor();

    bootLog('runApp appelé');
    runApp(DevicePreview(enabled: false, builder: (context) => const MyApp()));

    WidgetsBinding.instance.waitUntilFirstFrameRasterized.then((_) {
      debugPrint('[Boot] premier frame : ${sw.elapsedMilliseconds} ms');
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      bootLog('premier frame terminé');
      unawaited(AppDeepLinkService.instance.initialize());
    });
  } catch (e, st) {
    debugPrint('[Boot] Erreur phase critique : $e');
    debugPrint('$st');
    runApp(const _BootErrorApp());
    return;
  }

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await Future.delayed(const Duration(milliseconds: 300));
    unawaited(_initDeferred());
  });
}

// ───────────────────────── PHASE 1 : critique ─────────────────────────
Future<void> _initCritical() async {
  await _timed('Supabase.initialize', () async {
    await Supabase.initialize(
      url: 'https://djvmxrwfchnqdtzayhwf.supabase.co',
      anonKey: 'sb_publishable_gMk5EZPgW1eoEPN1kU0cKA_aXXGBUNJ',
      realtimeClientOptions: const RealtimeClientOptions(
        timeout: Duration(seconds: 20),
      ),
    );
  });

  final supabaseService = SupabaseService();
  await supabaseService.init();
  Get.put(supabaseService);
  Get.put(AppDatabase(), permanent: true);

  await _timed('FastCacheService.init', () async {
    await Get.putAsync<FastCacheService>(() => FastCacheService().init());
  });

  Get.put(CurrencyService(), permanent: true);

  await _timed('Critical Services Parallel Init', () async {
    await Future.wait([
      Get.putAsync<ConnectivityService>(() => ConnectivityService().init()),
      Get.putAsync<AppConfigService>(() => AppConfigService().init()),
      Get.putAsync<PreferencesService>(() => PreferencesService().init()),
      Get.putAsync<PrivacyService>(() => PrivacyService().init()),
      Get.putAsync<SyncService>(() => SyncService().init()),
      Get.putAsync<SearchHistoryService>(() => SearchHistoryService().init()),
    ]);
  });

  Get.put(DeviceService());
  Get.put(MediaService());

  await _timed('Theme & Locale Init', () async {
    await Future.wait([
      Get.putAsync(() => ThemeService().init()),
      Get.putAsync(() => LocaleService().init()),
    ]);
  });

  Get.put<LocationRepository>(
    CachedLocationRepository(
      SupabaseLocationRepository(Supabase.instance.client),
      Get.find<FastCacheService>(),
    ),
  );
  Get.put(InterestRepository(Supabase.instance.client), permanent: true);
  Get.put(InterestService(Get.find<InterestRepository>()), permanent: true);
  Get.put(AuthService());
  Get.put(UserService());
  Get.put(SessionService());
  Get.put(AppController(), permanent: true);
  Get.put(AuthController(), permanent: true);
  Get.put(DeviceController(), permanent: true);

  Get.lazyPut(() => ActivityService(), fenix: true);
  Get.lazyPut(
    () => SupabaseMessagingService(Supabase.instance.client),
    fenix: true,
  );
  Get.lazyPut(
    () => MessagingRepository(
      Get.find<AppDatabase>(),
      Get.find<SupabaseMessagingService>(),
    ),
    fenix: true,
  );
  Get.lazyPut(
    () => ChatService(Get.find<MessagingRepository>()),
    fenix: true,
  );
  Get.lazyPut(
    () => FcmNotificationService(Get.find<MessagingRepository>()),
    fenix: true,
  );
  Get.lazyPut(
    () => NotificationDbService(Get.find<AppDatabase>()),
    fenix: true,
  );
}

// ───────────────────────── PHASE 2 : différée ─────────────────────────
Future<void> _initDeferred() async {
  try {
    unawaited(Get.find<AppConfigService>().checkConfig());

    Get.find<ActivityService>();
    Get.find<NotificationDbService>();
    Get.find<ChatService>();

    await Get.find<MessagingRepository>().initialize();

    // Retarder l'initialisation lourde de Firebase & FCM de 3 secondes après le premier rendu
    await Future.delayed(const Duration(seconds: 3));

    await Firebase.initializeApp();
    unawaited(Get.find<FcmNotificationService>().initialize());

    await NotificationService.instance.initialize(
      onNotificationTap: (response) {
        if (kDebugMode) {
          debugPrint('Notification tapée, payload: ${response.payload}');
        }
      },
    );

    // Maintient une présence en ligne basée sur l'activité réelle au premier plan.
    Get.put(PresenceService(), permanent: true);
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('[Boot] Erreur phase différée : $e');
      debugPrint('$st');
    }
  }
}

class _BootErrorApp extends StatelessWidget {
  const _BootErrorApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Impossible de démarrer Scrole.\n'
              'Vérifie ta connexion puis relance l\'application.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    bootLog('MyApp.build start');
    final localeService = Get.find<LocaleService>();
    final themeMode = Get.find<ThemeService>().themeMode;
    final lightTheme = bootMeasure('AppTheme.lightTheme', () => AppTheme.lightTheme);
    final darkTheme = bootMeasure('AppTheme.darkTheme', () => AppTheme.darkTheme);
    final translations = bootMeasure('ScroleTranslations()', () => ScroleTranslations());

    final widget = Obx(
      () => GetMaterialApp(
        title: 'Scrole',
        debugShowCheckedModeBanner: false,
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: themeMode,
        translations: translations,
        locale: localeService.locale,
        fallbackLocale: const Locale('en'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('fr'),
          Locale('en'),
          Locale('es'),
          Locale('de'),
          Locale('it'),
          Locale('pt'),
          Locale('zh'),
          Locale('ja'),
          Locale('ru'),
        ],
        initialRoute: AppPages.root,
        getPages: AppRoutes.routes,
        builder: (context, child) {
          bootLog('GetMaterialApp.builder start');
          final result = DevicePreview.appBuilder(
            context,
            bootMeasure('ResponsiveBreakpoints.builder', () => ResponsiveBreakpoints.builder(
              breakpoints: [
                const Breakpoint(start: 0, end: 559, name: MOBILE),
                const Breakpoint(start: 560, end: 1050, name: TABLET),
                const Breakpoint(
                  start: 1051,
                  end: double.infinity,
                  name: DESKTOP,
                ),
              ],
              child: child!,
            )),
          );
          bootLog('GetMaterialApp.builder end');
          return result;
        },
      ),
    );
    bootLog('MyApp.build end');
    return widget;
  }
}
