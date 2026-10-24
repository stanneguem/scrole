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
  String? _lastHandledLink;

  Future<void> initialize() async {
    if (kIsWeb || _subscription != null) return;

    _subscription = _appLinks.uriLinkStream.listen(
      _handleUri,
      onError: (Object error, StackTrace stack) {
        debugPrint('[AppDeepLinkService] Link stream error: $error');
      },
    );

    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        // Wait for GetMaterialApp to mount its navigator before navigating.
        WidgetsBinding.instance.addPostFrameCallback((_) => _handleUri(initialUri));
      }
    } catch (error) {
      debugPrint('[AppDeepLinkService] Initial link error: $error');
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
    if (_lastHandledLink == canonicalLink) return;
    _lastHandledLink = canonicalLink;

    if (Get.context == null) {
      // The app may still be booting; retry once the first frame is mounted.
      WidgetsBinding.instance.addPostFrameCallback((_) => _openPost(postId));
      return;
    }
    _openPost(postId);
  }

  void _openPost(String postId) {
    if (Get.context == null) return;
    Get.to(() => SharedPostLinkScreen(postId: postId), preventDuplicates: true);
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
