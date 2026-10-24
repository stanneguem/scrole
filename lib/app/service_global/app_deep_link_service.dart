import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../shared/widgets/shared_post_link_screen.dart';

/// Handles incoming Scrole share links such as https://scrole.fun/post/<id>.
class AppDeepLinkService {
  AppDeepLinkService._();

  static final AppDeepLinkService instance = AppDeepLinkService._();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;

  String? _pendingPostId;
  String? _pendingLink;
  String? _lastHandledLink;
  DateTime? _lastHandledAt;
  bool _navigationScheduled = false;
  bool _isOpening = false;

  Future<void> initialize() async {
    if (kIsWeb || _subscription != null) return;

    // Listen first so a link received during startup is not lost while the
    // initial-link future is being resolved.
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

    final canonicalLink = 'https://scrole.fun/post/$postId';
    if (_pendingLink == canonicalLink) return;

    // app_links may emit the same cold-start URL through both the stream and
    // getInitialLink(). Ignore only this short duplicate window, so tapping
    // the same post again later still opens it.
    final lastHandledAt = _lastHandledAt;
    if (_lastHandledLink == canonicalLink &&
        lastHandledAt != null &&
        DateTime.now().difference(lastHandledAt) < const Duration(seconds: 2)) {
      return;
    }

    debugPrint('[AppDeepLinkService] Post link received: $canonicalLink');
    _pendingPostId = postId;
    _pendingLink = canonicalLink;
    _scheduleNavigation();
  }

  void _scheduleNavigation() {
    if (_navigationScheduled || _isOpening || _pendingPostId == null) return;

    _navigationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigationScheduled = false;
      unawaited(_openPendingPost());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _openPendingPost() async {
    final postId = _pendingPostId;
    final link = _pendingLink;
    if (postId == null || link == null || _isOpening) return;

    // A link can arrive while Flutter is still mounting GetMaterialApp. Keep
    // it queued and retry instead of marking it handled and dropping it.
    final navigator = Get.key.currentState;
    if (navigator == null || !navigator.mounted || Get.context == null) {
      debugPrint('[AppDeepLinkService] Navigator not ready; retrying post navigation.');
      await Future<void>.delayed(const Duration(milliseconds: 250));
      _scheduleNavigation();
      return;
    }

    _isOpening = true;
    _pendingPostId = null;
    _pendingLink = null;
    try {
      debugPrint('[AppDeepLinkService] Opening post detail: $postId');
      await Get.to<void>(
        () => SharedPostLinkScreen(postId: postId),
        preventDuplicates: true,
      );
      _lastHandledLink = link;
      _lastHandledAt = DateTime.now();
    } catch (error, stack) {
      // Do not mark the URL handled if navigation fails; retain it for retry.
      _pendingPostId = postId;
      _pendingLink = link;
      debugPrint('[AppDeepLinkService] Could not open post $postId: $error\n$stack');
    } finally {
      _isOpening = false;
      if (_pendingPostId != null) _scheduleNavigation();
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
