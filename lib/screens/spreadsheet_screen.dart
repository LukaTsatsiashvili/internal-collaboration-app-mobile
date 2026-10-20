import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/network/api_client.dart';

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
  /// The editor and REST API must use the same origin. This defaults to
  /// collaboration.gtexshop.ge; optional API URL overrides automatically
  /// update the editor too, preventing cross-environment mismatches.
  static Uri editorUri(String id) {
    final api = Uri.parse(ApiClient.baseUrl);
    if (api.scheme != 'https' || api.host.isEmpty) {
      throw StateError('Spreadsheet editor requires an HTTPS API origin.');
    }
    return api.replace(
      pathSegments: ['mobile', 'sheets', id],
      query: null,
      fragment: null,
    );
  }
  static const _storage = FlutterSecureStorage();

  late final WebViewController _webView;
  bool _pageLoading = true;
  String? _error;
  bool _authSent = false;
  bool _requestingClose = false;

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
          // Only the exact first-party workbook page may receive the
          // in-memory token. Never allow a cross-origin redirect.
          if (!request.isMainFrame) return NavigationDecision.navigate;
          final uri = Uri.tryParse(request.url);
          final allowed = editorUri(widget.id);
          if (uri?.origin == allowed.origin && uri?.path == allowed.path &&
              uri?.query.isEmpty == true && uri?.fragment.isEmpty == true) {
            return NavigationDecision.navigate;
          }
          return NavigationDecision.prevent;
        },
        onPageStarted: (_) {
          _authSent = false;
          if (mounted) {
            setState(() {
              _pageLoading = true;
              _error = null;
            });
          }
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
      ..loadRequest(editorUri(widget.id));
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

  /// Android system back and predictive-back gestures must take the same
  /// save/conflict path as the editor's own Back button. Never silently pop
  /// a live workbook before the JavaScript editor has persisted its changes.
  Future<void> _requestSafeClose() async {
    if (_requestingClose) return;
    _requestingClose = true;
    try {
      if (_error == null && _authSent) {
        final clicked = await _webView.runJavaScriptReturningResult("""
          (() => {
            const back = document.querySelector(
              'button[title="Back to Flutter Drive"]'
            );
            if (!back) return false;
            back.click();
            return true;
          })()
        """);
        if (!mounted) return;
        if (clicked == true || clicked.toString() == 'true') {
          // JS will post {type:"close"} ONLY after the editor has saved.
          return;
        }
      }

      if (!mounted) return;
      final leave = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Close spreadsheet?'),
          content: const Text(
            'The editor cannot confirm that all changes were saved. '
            'Closing now may discard unsaved changes.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Close anyway'),
            ),
          ],
        ),
      );
      if (mounted && leave == true) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot request a safe close. Try again.'),
          ),
        );
      }
    } finally {
      _requestingClose = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestSafeClose();
      },
      child: Scaffold(
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
                          onPressed: _requestSafeClose,
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
    ),
    );
  }
}
