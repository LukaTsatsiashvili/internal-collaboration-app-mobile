import 'package:flutter_test/flutter_test.dart';
import 'package:gtex_collab_app/core/network/api_client.dart';
import 'package:gtex_collab_app/screens/spreadsheet_screen.dart';

void main() {
  test('Univer WebView shares the exact HTTPS origin with the REST API', () {
    final api = Uri.parse(ApiClient.baseUrl);
    final editor = SpreadsheetScreen.editorUri('sheet-123');

    expect(api.scheme, 'https');
    expect(editor.scheme, api.scheme);
    expect(editor.host, api.host);
    expect(editor.port, api.port);
    expect(editor.path, '/mobile/sheets/sheet-123');
    expect(editor.query, isEmpty);
    expect(editor.fragment, isEmpty);
  });

  test('local ADB WebView route uses the same HTTP loopback origin', () {
    final editor = SpreadsheetScreen.editorUriForBaseUrl(
      'sheet-123',
      'http://127.0.0.1:5173/api/v1',
      allowDebugLoopbackHttp: true,
    );

    expect(editor.toString(), 'http://127.0.0.1:5173/mobile/sheets/sheet-123');
  });

  test('local HTTP editor is not permitted outside debug mode', () {
    expect(
      () => SpreadsheetScreen.editorUriForBaseUrl(
        'sheet-123',
        'http://127.0.0.1:5173/api/v1',
        allowDebugLoopbackHttp: false,
      ),
      throwsStateError,
    );
  });

  test('non-local HTTP editor is never permitted', () {
    expect(
      () => SpreadsheetScreen.editorUriForBaseUrl(
        'sheet-123',
        'http://192.168.1.25:5173/api/v1',
        allowDebugLoopbackHttp: true,
      ),
      throwsStateError,
    );
  });

  test('Workbook IDs remain a single escaped URL path segment', () {
    const unsafeId = 'special/id?fragment#value';
    final editor = SpreadsheetScreen.editorUri(unsafeId);
    expect(editor.pathSegments, ['mobile', 'sheets', unsafeId]);
    expect(editor.query, isEmpty);
    expect(editor.fragment, isEmpty);
    expect(editor.toString(), contains('%2F'));
  });
}
