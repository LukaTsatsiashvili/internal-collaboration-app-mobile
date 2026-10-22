import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/network/api_client.dart';

/// The deployed prod web app exposes /drive/sheets/:id, not /mobile/sheets/:id.
/// It owns an independent, cookie-backed browser session inside the WebView.
/// Native access/refresh tokens must never enter the WebView or its URLs.
class SpreadsheetScreen extends StatefulWidget {
  const SpreadsheetScreen({super.key, required this.id, required this.name});

  final String id;
  final String name;

  static Uri editorUri(String id) =>
      editorUriForBaseUrl(id, ApiClient.baseUrl);

  static Uri editorUriForBaseUrl(String id, String baseUrl) {
    final uri = Uri.parse(baseUrl);
    if (uri.scheme != 'https' || uri.host.isEmpty ||
        uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      throw StateError('Spreadsheet editor requires the production HTTPS origin.');
    }
    return uri.replace(
      pathSegments: ['drive', 'sheets', id],
      query: null,
      fragment: null,
    );
  }

  @override
  State<SpreadsheetScreen> createState() => _SpreadsheetScreenState();
}

class _SpreadsheetScreenState extends State<SpreadsheetScreen> {
  late final WebViewController _webView;
  bool _pageLoading = true;
  bool _awaitingWebLogin = false;
  bool _redirectingToSheet = false;
  bool _closing = false;
  String? _error;

  Uri get _editor => SpreadsheetScreen.editorUri(widget.id);

  @override
  void initState() {
    super.initState();
    _webView = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          if (!request.isMainFrame) return NavigationDecision.navigate;
          final uri = Uri.tryParse(request.url);
          // Never navigate a top-level embedded browser to a third party.
          final editor = _editor;
          if (uri?.scheme == 'https' &&
              uri?.host == editor.host &&
              uri?.port == editor.port) {
            return NavigationDecision.navigate;
          }
          return NavigationDecision.prevent;
        },
        onUrlChange: (change) {
          final uri = Uri.tryParse(change.url ?? '');
          if (uri?.origin != _editor.origin) return;
          if (uri?.path == '/login') {
            _awaitingWebLogin = true;
            return;
          }
          // Prod web sign-in redirects to /dashboard. Return to the
          // spreadsheet after that browser login; cookies stay in the WebView.
          if (_awaitingWebLogin && !_redirectingToSheet &&
              uri?.path == '/dashboard') {
            _awaitingWebLogin = false;
            _redirectingToSheet = true;
            _webView.loadRequest(_editor);
          }
          if (uri?.path == _editor.path) _redirectingToSheet = false;
        },
        onPageStarted: (_) {
          if (!mounted) return;
          setState(() {
            _pageLoading = true;
            _error = null;
          });
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _pageLoading = false);
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == true && mounted) {
            setState(() {
              _pageLoading = false;
              _error = 'ცხრილის გვერდი ვერ ჩაიტვირთა: ${error.description}';
            });
          }
        },
      ))
      ..loadRequest(_editor);
  }

  Future<void> _requestSafeClose() async {
    if (_closing) return;
    _closing = true;
    try {
      final leave = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('ცხრილის დახურვა'),
          content: const Text(
            'დარწმუნდით, რომ ცხრილში ცვლილებები შენახულია '
            'ვებრედაქტორის Save ღილაკით. გსურთ დახურვა?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('გაგრძელება'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('დახურვა'),
            ),
          ],
        ),
      );
      if (mounted && leave == true) Navigator.of(context).pop();
    } finally {
      _closing = false;
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _requestSafeClose();
        },
        child: Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            title: Text(widget.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: _requestSafeClose,
              tooltip: 'ცხრილის დახურვა',
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.table_chart_outlined),
                tooltip: 'ცხრილზე დაბრუნება',
                onPressed: () async {
                  final current = Uri.tryParse(await _webView.currentUrl() ?? '');
                  if (!mounted || current?.path == _editor.path) return;
                  await _webView.loadRequest(_editor);
                },
              ),
            ],
          ),
          body: Stack(
            children: [
              WebViewWidget(controller: _webView),
              if (_pageLoading)
                const Center(child: CircularProgressIndicator()),
              if (_error != null)
                ColoredBox(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline_rounded, size: 34),
                          const SizedBox(height: 14),
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 14),
                          FilledButton(
                            onPressed: () => _webView.loadRequest(_editor),
                            child: const Text('ხელახლა ცდა'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
}
