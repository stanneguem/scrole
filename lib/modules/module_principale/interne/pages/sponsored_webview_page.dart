import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Opens sponsored external destinations inside the Scrole application.
class SponsoredWebViewPage extends StatefulWidget {
  final String url;

  const SponsoredWebViewPage({super.key, required this.url});

  @override
  State<SponsoredWebViewPage> createState() => _SponsoredWebViewPageState();
}

class _SponsoredWebViewPageState extends State<SponsoredWebViewPage> {
  late final WebViewController _controller;
  int _progress = 0;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onPageStarted: (_) {
            if (mounted) setState(() {
              _loadError = null;
              _progress = 0;
            });
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _progress = 100);
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && mounted) {
              setState(() => _loadError = error.description);
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<bool> _handleBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop && await _handleBack() && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Page web'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              if (await _controller.canGoBack()) {
                await _controller.goBack();
              } else if (mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
          actions: [
            IconButton(
              tooltip: 'Actualiser',
              onPressed: () => _controller.reload(),
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: _progress < 100 && _loadError == null
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(2),
                  child: LinearProgressIndicator(
                    value: _progress / 100,
                    minHeight: 2,
                  ),
                )
              : null,
        ),
        body: _loadError == null
            ? WebViewWidget(controller: _controller)
            : Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.wifi_off_rounded,
                          size: 42, color: theme.colorScheme.error),
                      const SizedBox(height: 12),
                      const Text(
                        'Impossible de charger cette page.',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Text(_loadError!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () {
                          setState(() => _loadError = null);
                          _controller.reload();
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Réessayer'),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
