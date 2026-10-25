import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Affiche une page web dans Scrole, sans quitter l'application.
class ExternalWebViewScreen extends StatefulWidget {
  const ExternalWebViewScreen({
    required this.url,
    this.title,
    super.key,
  });

  final String url;
  final String? title;

  @override
  State<ExternalWebViewScreen> createState() => _ExternalWebViewScreenState();
}

class _ExternalWebViewScreenState extends State<ExternalWebViewScreen> {
  late final WebViewController _controller;
  int _progress = 0;
  bool _hasError = false;
  String? _pageTitle;

  Uri? get _initialUri => Uri.tryParse(widget.url);

  @override
  void initState() {
    super.initState();
    final uri = _initialUri;
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty) {
      _hasError = true;
      return;
    }

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFFFFFF))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onPageStarted: (_) {
            if (mounted) {
              setState(() {
                _hasError = false;
                _progress = 0;
              });
            }
          },
          onPageFinished: (_) async {
            final title = await _controller.getTitle();
            if (mounted) {
              setState(() {
                _pageTitle = title;
                _progress = 100;
              });
            }
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && mounted) {
              setState(() => _hasError = true);
            }
          },
          onNavigationRequest: (request) async {
            final target = Uri.tryParse(request.url);
            if (target == null) return NavigationDecision.prevent;
            if (target.scheme == 'http' || target.scheme == 'https') {
              return NavigationDecision.navigate;
            }
            if (await canLaunchUrl(target)) {
              await launchUrl(target, mode: LaunchMode.externalApplication);
            }
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(uri);
  }

  Future<void> _reload() async {
    if (_initialUri == null ||
        (_initialUri!.scheme != 'https' && _initialUri!.scheme != 'http')) {
      return;
    }
    setState(() {
      _hasError = false;
      _progress = 0;
    });
    await _controller.reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final uri = _initialUri;
    final host = uri?.host.replaceFirst(RegExp(r'^www\\.'), '') ?? '';
    final title = widget.title ?? _pageTitle ?? 'Page web';

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(76),
        child: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: colors.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          titleSpacing: 0,
          title: Padding(
            padding: const EdgeInsets.only(left: 16, right: 12),
            child: Row(
              children: [
                _ToolbarButton(
                  icon: Icons.close_rounded,
                  tooltip: 'Fermer',
                  onPressed: () => Get.back(),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.25,
                          color: colors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.lock_rounded,
                            size: 12,
                            color: colors.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              host.isEmpty ? 'Page intégrée à Scrole' : host,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colors.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _ToolbarButton(
                  icon: Icons.refresh_rounded,
                  tooltip: 'Actualiser',
                  onPressed: _reload,
                ),
              ],
            ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_progress < 100 && !_hasError)
                  LinearProgressIndicator(
                    value: _progress == 0 ? null : _progress / 100,
                    minHeight: 2,
                    backgroundColor: colors.surfaceContainerHighest,
                    color: colors.primary,
                  )
                else
                  const SizedBox(height: 2),
                Divider(height: 1, thickness: 1, color: colors.outlineVariant.withValues(alpha: 0.45)),
              ],
            ),
          ),
        ),
      ),
      body: _hasError
          ? _WebViewErrorState(onRetry: _reload)
          : ClipRect(
              child: WebViewWidget(controller: _controller),
            ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.72),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(icon, size: 21, color: colors.onSurface),
          ),
        ),
      ),
    );
  }
}

class _WebViewErrorState extends StatelessWidget {
  const _WebViewErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: colors.errorContainer,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Icon(
                  Icons.wifi_off_rounded,
                  size: 38,
                  color: colors.onErrorContainer,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Impossible de charger cette page',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Vérifiez votre connexion Internet puis réessayez. '
                'La page restera ouverte dans Scrole.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 19),
                label: const Text('Réessayer'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
