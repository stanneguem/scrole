import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/widgets/shared_post_link_screen.dart';
import '../routes/app_pages.dart';
import '../../app_controller.dart';
import '../../modules/module_authentification/interne/enums/auth_statut.dart';
import 'app_config_service.dart';

/// Handles incoming Scrole share links such as https://scrole.fun/post/<id>.
/// If the visitor is signed out, the requested post stays queued until login.
class AppDeepLinkService {
  AppDeepLinkService._();

  static final AppDeepLinkService instance = AppDeepLinkService._();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;
  StreamSubscription<AuthState>? _authSubscription;

  String? _pendingPostId;
  String? _pendingEventId;
  String? _pendingEventLink;
  String? _pendingProfileId;
  String? _pendingProfileLink;
  String? _pendingCommentId;
  String? _pendingLink;
  String? _lastHandledLink;
  DateTime? _lastHandledAt;
  bool _navigationScheduled = false;
  bool _isOpening = false;
  bool _waitingForAuthentication = false;

  bool _priorityScreenActive = false;

  /// A share URL must never navigate over a mandatory app-level screen.
  /// This is checked before queuing links as well as immediately before
  /// navigation, including when the visitor is signed out.
  Future<bool> _isNavigationBlocked() async {
    // Route-level check is important because the app may already be displaying
    // a mandatory gate before its controller status has finished synchronizing.
    final route = Get.currentRoute.toLowerCase();
    if (route.contains('update') ||
        route.contains('maintenance') ||
        route.contains('banned') ||
        route.contains('blocked') ||
        route.contains('account-suspended')) {
      _priorityScreenActive = true;
      _discardPendingLinks();
      debugPrint('[AppDeepLinkService] Link blocked while priority route is active: $route');
      return true;
    }

    // main() subscribes to app_links before Supabase/config/controllers finish
    // booting. Wait for the policy services instead of treating their absence
    // as permission to navigate.
    try {
      var attempts = 0;
      while (!Get.isRegistered<AppConfigService>() && attempts < 80) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        attempts++;
      }
      if (!Get.isRegistered<AppConfigService>()) {
        debugPrint('[AppDeepLinkService] Config service not ready; blocking link.');
        _priorityScreenActive = true;
        return true;
      }

      final config = Get.find<AppConfigService>();
      await config.checkConfig();
      if (config.isMaintenance.value || config.needsUpdate.value) {
        _priorityScreenActive = true;
        _discardPendingLinks();
        return true;
      }

      attempts = 0;
      while (!Get.isRegistered<AppController>() && attempts < 80) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        attempts++;
      }
      if (!Get.isRegistered<AppController>()) {
        debugPrint('[AppDeepLinkService] App controller not ready; blocking link.');
        _priorityScreenActive = true;
        return true;
      }

      final controller = Get.find<AppController>();
      // Do not decide while account status is still being resolved; otherwise
      // a banned user can race the deep-link stream during startup.
      attempts = 0;
      while (controller.status.value == AppStatus.loading && attempts < 100) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        attempts++;
      }
      if (controller.status.value == AppStatus.loading) {
        debugPrint('[AppDeepLinkService] Account status unresolved; blocking link.');
        _priorityScreenActive = true;
        return true;
      }

      final status = controller.status.value;
      if (status == AppStatus.banned ||
          status == AppStatus.maintenance ||
          status == AppStatus.updateRequired) {
        _priorityScreenActive = true;
        _discardPendingLinks();
        return true;
      }
    } catch (error) {
      debugPrint('[AppDeepLinkService] Priority-screen guard check failed: $error');
      _priorityScreenActive = true;
      return true;
    }

    _priorityScreenActive = false;
    return false;
  }

  void _discardPendingLinks() {
    _pendingPostId = null;
    _pendingCommentId = null;
    _pendingLink = null;
    _pendingEventId = null;
    _pendingEventLink = null;
    _pendingProfileId = null;
    _pendingProfileLink = null;
    _waitingForAuthentication = false;
    unawaited(_authSubscription?.cancel());
    _authSubscription = null;
  }


  Future<void> initialize() async {
    if (kIsWeb || _subscription != null) return;

    // Use the link stream as the single source of incoming URLs.
    // app_links can expose the Android launch intent again through
    // getInitialLink() when Dart is hot-restarted, which would reopen the same
    // SharedPostLinkScreen even though the user did not tap the link again.
    // The stream delivers cold-start links as well as links received while the
    // app is running, so do not also read the cached initial intent.
    _subscription = _appLinks.uriLinkStream.listen(
      _handleUri,
      onError: (Object error, StackTrace stack) {
        debugPrint('[AppDeepLinkService] Link stream error: $error');
      },
    );
  }

  void _handleUri(Uri uri) {
    if (_priorityScreenActive) return;
    unawaited(_acceptUriWhenAllowed(uri));
  }

  Future<void> _acceptUriWhenAllowed(Uri uri) async {
    if (await _isNavigationBlocked()) {
      debugPrint('[AppDeepLinkService] Deep link blocked by app priority screen: $uri');
      return;
    }
    _handleUriUnchecked(uri);
  }

  void _handleUriUnchecked(Uri uri) {
    // Keep supporting old custom-scheme profile links while sharing canonical
    // HTTPS links so they also have a web fallback and can be verified as App Links.
    if (uri.scheme == 'scrole' && uri.host == 'user-profile') {
      final segments = uri.pathSegments;
      if (segments.length == 1) _queueProfileLink(segments.first);
      return;
    }

    if (uri.scheme != 'https' ||
        (uri.host != 'scrole.fun' && uri.host != 'www.scrole.fun')) {
      return;
    }

    final segments = uri.pathSegments;
    if (segments.length != 2) return;

    if (segments.first == 'user-profile') {
      _queueProfileLink(segments[1]);
      return;
    }

    if (segments.first == 'event' || segments.first == 'events') {
      final eventId = segments[1].trim();
      if (eventId.isEmpty || eventId.length > 128) return;
      final canonicalLink = 'https://scrole.fun/event/$eventId';
      if (_pendingEventLink == canonicalLink || _pendingLink == canonicalLink ||
          _pendingProfileLink == canonicalLink) return;
      final lastHandledAt = _lastHandledAt;
      if (_lastHandledLink == canonicalLink &&
          lastHandledAt != null &&
          DateTime.now().difference(lastHandledAt) < const Duration(seconds: 2)) {
        return;
      }
      debugPrint('[AppDeepLinkService] Event link received: $canonicalLink');
      _pendingEventId = eventId;
      _pendingEventLink = canonicalLink;
      _scheduleNavigation();
      return;
    }

    if (segments.first != 'post') return;

    final postId = segments[1].trim();
    if (postId.isEmpty || postId.length > 128) return;

    final commentId = uri.queryParameters['comment'] ?? uri.queryParameters['commentId'] ?? uri.queryParameters['comment_id'];
    final canonicalLink = commentId == null || commentId.trim().isEmpty
        ? 'https://scrole.fun/post/$postId'
        : 'https://scrole.fun/post/$postId?comment=${Uri.encodeComponent(commentId.trim())}';
    if (_pendingLink == canonicalLink) return;

    final lastHandledAt = _lastHandledAt;
    if (_lastHandledLink == canonicalLink &&
        lastHandledAt != null &&
        DateTime.now().difference(lastHandledAt) < const Duration(seconds: 2)) {
      return;
    }

    debugPrint('[AppDeepLinkService] Post link received: $canonicalLink');
    _pendingPostId = postId;
    _pendingCommentId = commentId?.trim().isEmpty == true ? null : commentId?.trim();
    _pendingLink = canonicalLink;
    _scheduleNavigation();
  }

  void _queueProfileLink(String rawProfileId) {
    final profileId = rawProfileId.trim();
    if (profileId.isEmpty || profileId.length > 128) return;
    final canonicalLink = 'https://scrole.fun/user-profile/$profileId';
    if (_pendingProfileLink == canonicalLink) return;

    final lastHandledAt = _lastHandledAt;
    if (_lastHandledLink == canonicalLink &&
        lastHandledAt != null &&
        DateTime.now().difference(lastHandledAt) < const Duration(seconds: 2)) {
      return;
    }

    debugPrint('[AppDeepLinkService] Profile link received: $canonicalLink');
    _pendingProfileId = profileId;
    _pendingProfileLink = canonicalLink;
    _scheduleNavigation();
  }

  void _scheduleNavigation() {
    if (_navigationScheduled ||
        _isOpening ||
        _waitingForAuthentication ||
        (_pendingPostId == null && _pendingEventId == null && _pendingProfileId == null)) {
      return;
    }

    _navigationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigationScheduled = false;
      if (_pendingEventId != null) {
        unawaited(_openPendingEvent());
      } else if (_pendingPostId != null) {
        unawaited(_openPendingPost());
      } else {
        unawaited(_openPendingProfile());
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _waitForAuthentication() {
    if (_waitingForAuthentication) return;
    _waitingForAuthentication = true;
    debugPrint(
      '[AppDeepLinkService] User is signed out; waiting to open the shared link after login.',
    );

    // The auth stream is attached only after Supabase and the app navigator
    // are ready. Keep the post ID/link intact while the login screen is shown.
    _authSubscription ??= Supabase.instance.client.auth.onAuthStateChange.listen(
      (data) {
        if (data.session == null) return;
        debugPrint('[AppDeepLinkService] Login completed; resuming shared post link.');
        _waitingForAuthentication = false;
        unawaited(_authSubscription?.cancel());
        _authSubscription = null;
        _scheduleNavigation();
      },
      onError: (Object error, StackTrace stack) {
        debugPrint('[AppDeepLinkService] Auth stream error: $error');
      },
    );
  }

  Future<void> _openPendingEvent() async {
    if (await _isNavigationBlocked()) return;
    final eventId = _pendingEventId;
    final link = _pendingEventLink;
    if (eventId == null || link == null || _isOpening) return;

    final navigator = Get.key.currentState;
    if (navigator == null || !navigator.mounted || Get.context == null) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      _scheduleNavigation();
      return;
    }

    try {
      if (Supabase.instance.client.auth.currentSession == null) {
        _waitForAuthentication();
        return;
      }
    } catch (error) {
      debugPrint('[AppDeepLinkService] Could not inspect auth session for event: $error');
      _waitForAuthentication();
      return;
    }

    _isOpening = true;
    _pendingEventId = null;
    _pendingEventLink = null;
    try {
      debugPrint('[AppDeepLinkService] Opening shared event: $eventId');
      await Get.toNamed<void>(
        AppPages.eventPreviewPath(eventId),
        arguments: {'id': eventId, 'context': 'shared_link'},
        preventDuplicates: true,
      );
      _lastHandledLink = link;
      _lastHandledAt = DateTime.now();
    } catch (error, stack) {
      _pendingEventId = eventId;
      _pendingEventLink = link;
      debugPrint('[AppDeepLinkService] Could not open event $eventId: $error\\n$stack');
    } finally {
      _isOpening = false;
      if (_pendingPostId != null || _pendingEventId != null || _pendingProfileId != null) _scheduleNavigation();
    }
  }

  Future<void> _openPendingProfile() async {
    if (await _isNavigationBlocked()) return;
    final profileId = _pendingProfileId;
    final link = _pendingProfileLink;
    if (profileId == null || link == null || _isOpening) return;

    final navigator = Get.key.currentState;
    if (navigator == null || !navigator.mounted || Get.context == null) {
      debugPrint('[AppDeepLinkService] Navigator not ready; retrying profile navigation.');
      await Future<void>.delayed(const Duration(milliseconds: 250));
      _scheduleNavigation();
      return;
    }

    try {
      if (Supabase.instance.client.auth.currentSession == null) {
        _waitForAuthentication();
        return;
      }
    } catch (error) {
      debugPrint('[AppDeepLinkService] Could not inspect auth session for profile: $error');
      _waitForAuthentication();
      return;
    }

    _isOpening = true;
    _pendingProfileId = null;
    _pendingProfileLink = null;
    try {
      debugPrint('[AppDeepLinkService] Opening shared profile: $profileId');
      await Get.toNamed<void>(
        AppPages.externalProfilePath(profileId),
        arguments: {'userId': profileId, 'context': 'shared_link'},
        preventDuplicates: true,
      );
      _lastHandledLink = link;
      _lastHandledAt = DateTime.now();
    } catch (error, stack) {
      _pendingProfileId = profileId;
      _pendingProfileLink = link;
      debugPrint('[AppDeepLinkService] Could not open profile $profileId: $error\\n$stack');
    } finally {
      _isOpening = false;
      if (_pendingPostId != null || _pendingEventId != null || _pendingProfileId != null) {
        _scheduleNavigation();
      }
    }
  }

  Future<void> _openPendingPost() async {
    if (await _isNavigationBlocked()) return;
    final postId = _pendingPostId;
    final commentId = _pendingCommentId;
    final link = _pendingLink;
    if (postId == null || link == null || _isOpening) return;

    // Wait for GetMaterialApp to mount before trying to navigate.
    final navigator = Get.key.currentState;
    if (navigator == null || !navigator.mounted || Get.context == null) {
      debugPrint('[AppDeepLinkService] Navigator not ready; retrying post navigation.');
      await Future<void>.delayed(const Duration(milliseconds: 250));
      _scheduleNavigation();
      return;
    }

    // Do not send signed-out visitors to a post screen that will fail to load.
    // The root route already presents the login screen; retain the pending URL
    // and resume automatically when Supabase emits a successful sign-in.
    try {
      if (Supabase.instance.client.auth.currentSession == null) {
        _waitForAuthentication();
        return;
      }
    } catch (error) {
      debugPrint('[AppDeepLinkService] Could not inspect auth session: $error');
      _waitForAuthentication();
      return;
    }

    _isOpening = true;
    _pendingPostId = null;
    _pendingCommentId = null;
    _pendingLink = null;
    try {
      debugPrint('[AppDeepLinkService] Opening post detail: $postId');
      await Get.to<void>(
        () => SharedPostLinkScreen(postId: postId, commentId: commentId),
        preventDuplicates: true,
      );
      _lastHandledLink = link;
      _lastHandledAt = DateTime.now();
    } catch (error, stack) {
      // Retain the URL if navigation fails, so it can be retried.
      _pendingPostId = postId;
      _pendingCommentId = commentId;
      _pendingLink = link;
      debugPrint('[AppDeepLinkService] Could not open post $postId: $error\n$stack');
    } finally {
      _isOpening = false;
      if (_pendingPostId != null || _pendingEventId != null || _pendingProfileId != null) _scheduleNavigation();
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _authSubscription?.cancel();
    _subscription = null;
    _authSubscription = null;
  }
}
