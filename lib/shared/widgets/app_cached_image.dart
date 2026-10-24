import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'shimmer.dart';

class AppCachedImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? placeholder;
  final Widget? errorWidget;
  final bool progressive;
  final int? lowResolutionWidth;
  final int? highResolutionWidth;
  final int imageQuality;

  const AppCachedImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholder,
    this.errorWidget,
    this.progressive = false,
    this.lowResolutionWidth,
    this.highResolutionWidth,
    this.imageQuality = 80,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) return _buildErrorWidget();
    // Private R2 object keys must be exchanged for short-lived signed URLs.
    if (!imageUrl.startsWith('http://') && !imageUrl.startsWith('https://') &&
        (imageUrl.startsWith('private/') || imageUrl.startsWith('messages/') ||
         imageUrl.startsWith('stories/') || imageUrl.startsWith('bug-reports/') ||
         imageUrl.startsWith('comments/') || imageUrl.startsWith('communities/') ||
         imageUrl.startsWith('posts/') || imageUrl.startsWith('profiles/') ||
         imageUrl.startsWith('events/'))) {
      return _R2SignedImage(
        objectKey: imageUrl, width: width, height: height, fit: fit,
        borderRadius: borderRadius, placeholder: placeholder, errorWidget: errorWidget,
      );
    }
    // Storage object keys (e.g. `{uid}/chat/media/file.jpg`) are not files.
    if (!imageUrl.startsWith('http://') && !imageUrl.startsWith('https://')) {
      final absolute = imageUrl.startsWith('file://')
          ? Uri.parse(imageUrl).toFilePath()
          : imageUrl;
      if (!absolute.startsWith('/')) {
        return errorWidget ?? _buildErrorWidget();
      }
      final file = File(absolute);
      if (!file.existsSync()) return errorWidget ?? _buildErrorWidget();
      return ClipRRect(
        borderRadius: borderRadius ?? BorderRadius.zero,
        child: Image.file(
          file,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, __, ___) => errorWidget ?? _buildErrorWidget(),
        ),
      );
    }

    if (!progressive || lowResolutionWidth == null)
      return _buildImage(imageUrl);

    final lowUrl = _buildSupabaseTransformUrl(
      imageUrl,
      width: lowResolutionWidth!,
    );
    final highUrl = highResolutionWidth != null
        ? _buildSupabaseTransformUrl(imageUrl, width: highResolutionWidth!)
        : imageUrl;
    if (lowUrl == imageUrl) return _buildImage(imageUrl);

    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          CachedNetworkImage(
            imageUrl: lowUrl,
            width: width,
            height: height,
            fit: fit,
            memCacheWidth: lowResolutionWidth,
            fadeInDuration: const Duration(milliseconds: 120),
            placeholder: (context, url) => placeholder ?? _buildPlaceholder(),
            errorWidget: (context, url, error) => const SizedBox.shrink(),
          ),
          if (highUrl != lowUrl)
            _ProgressiveHighImage(
              imageUrl: highUrl,
              width: width,
              height: height,
              fit: fit,
              highResolutionWidth: highResolutionWidth,
            ),
        ],
      ),
    );
  }

  Widget _buildImage(String url) {
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: CachedNetworkImage(
        imageUrl: url,
        width: width,
        height: height,
        fit: fit,
        placeholder: (context, url) => placeholder ?? _buildPlaceholder(),
        errorWidget: (context, url, error) =>
            errorWidget ?? _buildErrorWidget(),
      ),
    );
  }

  String _buildSupabaseTransformUrl(String url, {required int width}) {
    const marker = '/storage/v1/object/public/';
    final markerIndex = url.indexOf(marker);
    if (markerIndex == -1 || width < 1) return url;
    final base = url.substring(0, markerIndex);
    final objectPath = url.substring(markerIndex + marker.length);
    if (objectPath.isEmpty) return url;
    final encodedPath = objectPath
        .split('/')
        .map(Uri.encodeComponent)
        .join('/');
    return '$base/storage/v1/render/image/public/$encodedPath?width=$width&quality=$imageQuality';
  }

  Widget _buildPlaceholder() => SkeletonShimmer(
    width: width ?? double.infinity,
    height: height ?? double.infinity,
    borderRadius: borderRadius?.topLeft.x ?? 0,
  );
  Widget _buildErrorWidget() => Container(
    width: width,
    height: height,
    color: Colors.grey[200],
    child: const Icon(Icons.broken_image_outlined, color: Colors.grey),
  );
}

class _ProgressiveHighImage extends StatefulWidget {
  const _ProgressiveHighImage({
    required this.imageUrl,
    this.width,
    this.height,
    required this.fit,
    this.highResolutionWidth,
  });
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final int? highResolutionWidth;

  @override
  State<_ProgressiveHighImage> createState() => _ProgressiveHighImageState();
}

class _ProgressiveHighImageState extends State<_ProgressiveHighImage> {
  bool _loaded = false;
  bool _failed = false;

  @override
  Widget build(BuildContext context) {
    if (_failed) return const SizedBox.shrink();
    return Stack(
      fit: StackFit.passthrough,
      children: [
        AnimatedOpacity(
          opacity: _loaded ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          child: CachedNetworkImage(
            imageUrl: widget.imageUrl,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            memCacheWidth: widget.highResolutionWidth,
            fadeInDuration: const Duration(milliseconds: 180),
            placeholder: (context, url) => const SizedBox.shrink(),
            errorWidget: (context, url, error) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _failed = true);
              });
              return const SizedBox.shrink();
            },
            imageBuilder: (context, provider) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !_loaded) setState(() => _loaded = true);
              });
              return Image(
                image: provider,
                width: widget.width,
                height: widget.height,
                fit: widget.fit,
              );
            },
          ),
        ),
        if (!_loaded)
          Positioned.fill(
            child: Center(
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .45),
                  shape: BoxShape.circle,
                ),
                child: const Padding(
                  padding: EdgeInsets.all(7),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}


class _R2SignedImage extends StatefulWidget {
  const _R2SignedImage({
    required this.objectKey,
    this.width,
    this.height,
    required this.fit,
    this.borderRadius,
    this.placeholder,
    this.errorWidget,
  });

  final String objectKey;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? placeholder;
  final Widget? errorWidget;

  @override
  State<_R2SignedImage> createState() => _R2SignedImageState();
}

class _R2SignedImageState extends State<_R2SignedImage> {
  late Future<String> _urlFuture;

  @override
  void initState() {
    super.initState();
    _urlFuture = _resolveUrl();
  }

  Future<String> _resolveUrl() async {
    final response = await Supabase.instance.client.functions.invoke(
      'r2-media-upload',
      body: {'action': 'create-download-url', 'object_key': widget.objectKey},
    );
    if (response.status < 200 || response.status >= 300 || response.data is! Map) {
      throw StateError('Impossible de résoudre le média privé Cloudflare R2.');
    }
    final data = Map<String, dynamic>.from(response.data as Map);
    final url = data['url']?.toString();
    if (url == null || url.isEmpty) throw StateError('URL de lecture R2 absente.');
    return url;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _urlFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return widget.errorWidget ?? Container(
            width: widget.width, height: widget.height, color: Colors.grey[200],
            child: const Icon(Icons.broken_image_outlined, color: Colors.grey),
          );
        }
        if (!snapshot.hasData) {
          return widget.placeholder ?? SkeletonShimmer(
            width: widget.width ?? double.infinity,
            height: widget.height ?? double.infinity,
            borderRadius: widget.borderRadius?.topLeft.x ?? 0,
          );
        }
        return AppCachedImage(
          imageUrl: snapshot.data!, width: widget.width, height: widget.height,
          fit: widget.fit, borderRadius: widget.borderRadius,
          placeholder: widget.placeholder, errorWidget: widget.errorWidget,
        );
      },
    );
  }
}
