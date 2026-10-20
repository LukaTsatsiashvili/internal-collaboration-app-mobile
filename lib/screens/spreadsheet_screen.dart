import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// The actual workbook, formula engine, autosave and conflict handling are
/// shared with the web app. This screen contains only native navigation and
/// the origin-restricted Flutter <-> Univer bridge.
class SpreadsheetScreen extends StatefulWidget {
  const SpreadsheetScreen({super.key, required this.id, required this.name});

  final String id;
  final String name;

  @override
  State<SpreadsheetScreen> createState() => _SpreadsheetScreenState();
}

class _SpreadsheetScreenState extends State<SpreadsheetScreen> {
  static const _origin = 'https://collaboration.gtexshop.ge';
  static const _storage = FlutterSecureStorage();

  late final WebViewController _webView;
  bool _pageLoading = true;
  String? _error;
  bool _authSent = false;

  @override
  void initState() {
    super.initState();
    _webView = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..addJavaScriptChannel(
        'CollaborationFlutter',
        onMessageReceived: _onBridgeMessage,
      )
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          // A bearer token is injected only into the page hosted by our own
          // HTTPS domain; prevent top-level navigation to untrusted sites.
          if (!request.isMainFrame) return NavigationDecision.navigate;
          final uri = Uri.tryParse(request.url);
          if (uri?.scheme == 'https' &&
              uri?.host == 'collaboration.gtexshop.ge' &&
              uri!.path.startsWith('/mobile/sheets/')) {
            return NavigationDecision.navigate;
          }
          return NavigationDecision.prevent;
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _pageLoading = false);
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == true && mounted) {
            setState(() {
              _pageLoading = false;
              _error = 'Spreadsheet page could not load: ${error.description}';
            });
          }
        },
      ))
      ..loadRequest(
        Uri.parse('$_origin/mobile/sheets/${Uri.encodeComponent(widget.id)}'),
      );
  }

  Future<void> _onBridgeMessage(JavaScriptMessage message) async {
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(message.message);
      if (decoded is! Map) return;
      data = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return;
    }

    switch (data['type']) {
      case 'ready':
        if (_authSent) return;
        _authSent = true;
        final token = await _storage.read(key: 'access_token');
        if (!mounted) return;
        if (token == null || token.isEmpty) {
          setState(() => _error = 'Sign in to open this spreadsheet.');
          return;
        }
        // jsonEncode ensures the token cannot escape into executable JS.
        // Never put this token in a URL, cookie or localStorage.
        await _webView.runJavaScript(
          'window.dispatchEvent(new CustomEvent("collab-mobile-session", '
          '{ detail: { token: ${jsonEncode(token)} } }));',
        );
      case 'close':
        if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
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
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Back to Drive'),
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
}
