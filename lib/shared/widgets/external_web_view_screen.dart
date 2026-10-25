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

  @override
  void initState() {
    super.initState();
    final uri = Uri.tryParse(widget.url);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      _hasError = true;
      return;
    }

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(ThemeData().colorScheme.surface)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onPageStarted: (_) {
            if (mounted) setState(() {
              _hasError = false;
              _progress = 0;
            });
          },
          onPageFinished: (_) async {
            final title = await _controller.getTitle();
            if (mounted) setState(() {
              _pageTitle = title;
              _progress = 100;
            });
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
    setState(() {
      _hasError = false;
      _progress = 0;
    });
    await _controller.reload();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final title = widget.title ?? _pageTitle ?? 'Page web';

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        leading: IconButton(
          tooltip: 'Fermer',
          icon: const Icon(Icons.close),
          onPressed: () => Get.back(),
        ),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
        bottom: _progress < 100 && !_hasError
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                  value: _progress == 0 ? null : _progress / 100,
                  minHeight: 2,
                ),
              )
            : null,
      ),
      body: _hasError
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.wifi_off_rounded, size: 44, color: colors.error),
                    const SizedBox(height: 16),
                    const Text(
                      'Cette page ne peut pas être chargée. Vérifiez votre connexion puis réessayez.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
            )
          : WebViewWidget(controller: _controller),
    );
  }
}
