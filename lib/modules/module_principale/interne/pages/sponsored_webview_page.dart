import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Opens external destinations inside Scrole, while handing app links to the OS.
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
  String? _currentUrl;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _handleNavigationRequest,
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onPageStarted: (url) {
            if (mounted) {
              setState(() {
                _currentUrl = url;
                _loadError = null;
                _progress = 0;
              });
            }
          },
          onPageFinished: (url) {
            if (mounted) {
              setState(() {
                _currentUrl = url;
                _progress = 100;
              });
            }
          },
          onWebResourceError: (error) {
            // Ignore failed sub-resources (ads, trackers, fonts, etc.).
            if (error.isForMainFrame == true && mounted) {
              setState(() => _loadError = error.description);
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  bool _isWhatsAppUrl(Uri uri) {
    final host = uri.host.toLowerCase();
    return host == 'wa.me' ||
        host.endsWith('.whatsapp.com') ||
        host == 'whatsapp.com';
  }

  Future<NavigationDecision> _handleNavigationRequest(
    NavigationRequest request,
  ) async {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.prevent;

    // WhatsApp universal links should be handed to Android/iOS so the
    // installed WhatsApp app can claim them. Other non-web schemes (tel,
    // mailto, sms, intent, etc.) must never be loaded as web pages.
    final isWeb = uri.scheme == 'http' || uri.scheme == 'https';
    if (!isWeb || _isWhatsAppUrl(uri)) {
      await _launchExternal(uri);
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  Future<void> _launchExternal(Uri uri) async {
    try {
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Aucune application ne peut ouvrir ce lien."),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Impossible d'ouvrir ce lien.")),
        );
      }
    }
  }

  Future<Uri?> _activeUri() async {
    final raw = await _controller.currentUrl() ?? _currentUrl;
    if (raw == null) return null;
    return Uri.tryParse(raw);
  }

  Future<void> _copyCurrentLink() async {
    final uri = await _activeUri();
    if (uri == null) return;
    await Clipboard.setData(ClipboardData(text: uri.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lien copié.')),
      );
    }
  }

  Future<void> _openCurrentInBrowser() async {
    final uri = await _activeUri();
    if (uri != null) await _launchExternal(uri);
  }

  Future<void> _shareCurrentLink() async {
    final uri = await _activeUri();
    if (uri == null) return;
    await SharePlus.instance.share(ShareParams(uri: uri));
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
            tooltip: 'Retour',
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
            PopupMenuButton<String>(
              tooltip: 'Options du navigateur',
              icon: const Icon(Icons.more_vert),
              onSelected: (value) async {
                switch (value) {
                  case 'browser':
                    await _openCurrentInBrowser();
                    break;
                  case 'copy':
                    await _copyCurrentLink();
                    break;
                  case 'share':
                    await _shareCurrentLink();
                    break;
                  case 'back':
                    if (await _controller.canGoBack()) {
                      await _controller.goBack();
                    }
                    break;
                  case 'forward':
                    if (await _controller.canGoForward()) {
                      await _controller.goForward();
                    }
                    break;
                  case 'reload':
                    await _controller.reload();
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'browser',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.open_in_browser),
                    title: Text('Ouvrir dans un navigateur externe'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'copy',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.copy),
                    title: Text('Copier le lien'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'share',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.share),
                    title: Text('Partager le lien'),
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'back',
                  child: const ListTile(
                    dense: true,
                    leading: Icon(Icons.arrow_back),
                    title: Text('Page précédente'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'forward',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.arrow_forward),
                    title: Text('Page suivante'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'reload',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.refresh),
                    title: Text('Actualiser la page'),
                  ),
                ),
              ],
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
