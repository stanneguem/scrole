import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/widgets/shared_post_link_screen.dart';

/// Handles incoming Scrole share links such as https://scrole.fun/post/<id>.
/// If the visitor is signed out, the requested post stays queued until login.
class AppDeepLinkService {
  AppDeepLinkService._();

  static final AppDeepLinkService instance = AppDeepLinkService._();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;
  StreamSubscription<AuthState>? _authSubscription;

  String? _pendingPostId;
  String? _pendingCommentId;
  String? _pendingLink;
  String? _lastHandledLink;
  DateTime? _lastHandledAt;
  bool _navigationScheduled = false;
  bool _isOpening = false;
  bool _waitingForAuthentication = false;

  Future<void> initialize() async {
    if (kIsWeb || _subscription != null) return;

    // Start listening before resolving the initial link so a cold-start URL
    // cannot be lost while the initial-link future is being resolved.
    _subscription = _appLinks.uriLinkStream.listen(
      _handleUri,
      onError: (Object error, StackTrace stack) {
        debugPrint('[AppDeepLinkService] Link stream error: $error');
      },
    );

    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) _handleUri(initialUri);
    } catch (error, stack) {
      debugPrint('[AppDeepLinkService] Initial link error: $error\n$stack');
    }
  }

  void _handleUri(Uri uri) {
    if (uri.scheme != 'https' ||
        (uri.host != 'scrole.fun' && uri.host != 'www.scrole.fun')) {
      return;
    }

    final segments = uri.pathSegments;
    if (segments.length != 2 || segments.first != 'post') return;

    final postId = segments[1].trim();
    if (postId.isEmpty || postId.length > 128) return;

    final commentId = uri.queryParameters['comment'] ?? uri.queryParameters['commentId'] ?? uri.queryParameters['comment_id'];
    final canonicalLink = commentId == null || commentId.trim().isEmpty
        ? 'https://scrole.fun/post/$postId'
        : 'https://scrole.fun/post/$postId?comment=${Uri.encodeComponent(commentId.trim())}';
    if (_pendingLink == canonicalLink) return;

    // app_links can emit the same cold-start URL through both the stream and
    // getInitialLink(). Ignore only this short duplicate window.
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

  void _scheduleNavigation() {
    if (_navigationScheduled ||
        _isOpening ||
        _waitingForAuthentication ||
        _pendingPostId == null) {
      return;
    }

    _navigationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigationScheduled = false;
      unawaited(_openPendingPost());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _waitForAuthentication() {
    if (_waitingForAuthentication) return;
    _waitingForAuthentication = true;
    debugPrint(
      '[AppDeepLinkService] User is signed out; waiting to open the shared post after login.',
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

  Future<void> _openPendingPost() async {
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
      if (_pendingPostId != null) _scheduleNavigation();
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _authSubscription?.cancel();
    _subscription = null;
    _authSubscription = null;
  }
}
