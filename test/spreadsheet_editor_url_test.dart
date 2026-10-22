import 'package:flutter_test/flutter_test.dart';
import 'package:gtex_collab_app/core/network/api_client.dart';
import 'package:gtex_collab_app/screens/spreadsheet_screen.dart';

void main() {
  test('WebView uses the existing prod HTTPS spreadsheet route', () {
    final api = Uri.parse(ApiClient.baseUrl);
    final editor = SpreadsheetScreen.editorUri('sheet-123');
    expect(api.scheme, 'https');
    expect(editor.origin, api.origin);
    expect(editor.path, '/drive/sheets/sheet-123');
    expect(editor.query, isEmpty);
    expect(editor.fragment, isEmpty);
  });

  test('insecure HTTP is not accepted for the embedded editor', () {
    expect(
      () => SpreadsheetScreen.editorUriForBaseUrl(
        'sheet-123', 'http://example.com/api/v1',
      ),
      throwsStateError,
    );
  });

  test('unexpected user-info and query parameters are rejected', () {
    expect(
      () => SpreadsheetScreen.editorUriForBaseUrl(
        'sheet-123', 'https://test@example.com/api/v1',
      ),
      throwsStateError,
    );
    expect(
      () => SpreadsheetScreen.editorUriForBaseUrl(
        'sheet-123', 'https://example.com/api/v1?token=secret',
      ),
      throwsStateError,
    );
  });

  test('workbook IDs remain one escaped URL path segment', () {
    const unsafeId = 'special/id?fragment#value';
    final editor = SpreadsheetScreen.editorUri(unsafeId);
    expect(editor.pathSegments, ['drive', 'sheets', unsafeId]);
    expect(editor.query, isEmpty);
    expect(editor.fragment, isEmpty);
    expect(editor.toString(), contains('%2F'));
  });
}
