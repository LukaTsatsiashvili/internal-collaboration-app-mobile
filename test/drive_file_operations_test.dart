import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:excel_community/excel_community.dart';
import 'package:gtex_collab_app/features/drive/data/univer_excel_export.dart';
import 'package:gtex_collab_app/core/theme/app_theme.dart';
import 'package:gtex_collab_app/features/drive/data/drive_service.dart';
import 'package:gtex_collab_app/screens/drive_screen.dart';
import 'package:gtex_collab_app/screens/drive_move_dialog.dart';
import 'package:gtex_collab_app/screens/drive_permissions_dialog.dart';

Dio mockDio(List<String> requests, List<dynamic> payloads) {
  final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api/v1'));
  dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
    requests.add('${options.method} ${options.path}');
    payloads.add(options.data ?? options.queryParameters);
    dynamic result;
    switch ('${options.method} ${options.path}') {
      case 'PATCH /drive/item-1':
      case 'DELETE /drive/item-1':
      case 'PUT /drive/item-1/shares':
        result = {'success': true, 'data': null};
      case 'GET /drive/item-1/shares':
        result = {
          'success': true,
          'data': [
            {'userId': 'person-1', 'access': 'VIEWER', 'scope': 'ITEM_ONLY'},
          ],
          'meta': {'permissionMode': 'CUSTOM', 'spaceType': 'PERSONAL'},
        };
      case 'GET /users':
        result = {
          'success': true,
          'data': [
            {'id':'owner', 'displayName':'Owner', 'status':'ACTIVE'},
            {'id':'person-1','displayName':'Luka','status':'ACTIVE'},
            {'id':'inactive','displayName':'Inactive','status':'INACTIVE'},
          ],
        };
      case 'GET /departments':
        result = {
          'success': true,
          'data': [{'id':'dept-1','name':'Retail'}],
        };
      case 'GET /drive':
        final parent = options.queryParameters['parentId'];
        result = {
          'success': true,
          'data': parent == null
              ? [
                  {'id':'folder-2', 'name':'Reports', 'kind':'FOLDER',
                    'access':'OWNER'},
                ]
              : <dynamic>[],
          'meta': {
            'usedBytes': 0,
            'breadcrumbs': parent == null
                ? <dynamic>[] : [
                    {'id':parent,'name':'Reports'},
                  ],
          },
        };
      case 'GET /drive/sheets/item-1':
        result = {'success': true, 'data': {
          'id': 'item-1', 'snapshot': {'sheetOrder':[], 'sheets':{}},
        }};
      default:
        handler.reject(DioException(
          requestOptions: options, error:'Unexpected request',
        ));
        return;
    }
    handler.resolve(Response(
      requestOptions: options,
      statusCode: 200,
      data: result,
    ));
  }));
  return dio;
}

Map<String, dynamic> fileItem() => {
  'id': 'item-1',
  'name': 'Sample.pdf',
  'kind': 'FILE',
  'access': 'OWNER',
  'ownerId': 'owner',
  'parentId': null,
  'file': {
    'id': 'file-1', 'mimeType':'application/pdf', 'sizeBytes':120,
  },
  'owner': {'displayName': 'Owner'},
};

Map<String, dynamic> folderItem() => {
  ...fileItem(),
  'name': 'Folder',
  'kind': 'FOLDER',
  'file': null,
};

void main() {
  test('rename, move and delete use exactly the Web Drive endpoints',
      () async {
    final requests = <String>[];
    final payloads = <dynamic>[];
    final api = DriveService(dio: mockDio(requests, payloads));
    await api.renameItem('item-1', 'Renamed.pdf');
    await api.moveItem('item-1', 'folder-2');
    await api.trashItem('item-1');
    expect(requests, [
      'PATCH /drive/item-1',
      'PATCH /drive/item-1',
      'DELETE /drive/item-1',
    ]);
    expect(payloads[0], {'name': 'Renamed.pdf'});
    expect(payloads[1], {'parentId': 'folder-2'});
    expect(() => api.renameItem('item-1', 'Bad/Name'),
        throwsFormatException);
  });

  test('permission APIs preserve role levels and descendant scope', () async {
    final requests = <String>[];
    final payloads = <dynamic>[];
    final api = DriveService(dio: mockDio(requests, payloads));
    final shares = await api.getShares('item-1');
    expect(shares.grants.single['access'], 'VIEWER');
    await api.setShares('item-1', grants: [
      {'userId': 'person-1', 'access': 'EDITOR_DELETE',
       'scope': 'DESCENDANTS'},
    ]);
    expect(requests, [
      'GET /drive/item-1/shares',
      'PUT /drive/item-1/shares',
    ]);
    final sent = payloads.last as Map;
    expect((sent['grants'] as List).single['access'], 'EDITOR_DELETE');
    expect((sent['grants'] as List).single['scope'], 'DESCENDANTS');
  });


  test('Univer download exports a valid multi-sheet Excel workbook', () {
    final snapshot = {
      'sheetOrder': ['sheet-1','sheet-2'],
      'sheets': {
        'sheet-1': {
          'name': 'Financials',
          'cellData': {
            '0': {
              '0': {'v': 'Revenue'},
              '1': {'v': 12.5, 's': {'n': {'pattern':'#,##0.00'}}},
            },
            '1': {
              '1': {'f': '=SUM(B1:B1)'},
            },
          },
          'mergeData': [
            {'startRow':2,'startColumn':0,'endRow':2,'endColumn':1},
          ],
          'rowData': {'0': {'h': 30}},
          'columnData': {'0': {'w': 120}},
        },
        'sheet-2': {
          'name': 'Notes',
          'cellData': {'0': {'0': {'v': 'Next year'}}},
          'mergeData': <dynamic>[],
        },
      },
    };
    final bytes = UniverExcelExport.export(snapshot);
    expect(bytes.sublist(0, 2), [80, 75]); // ZIP-based XLSX signature
    final reopened = Excel.decodeBytes(bytes.toList());
    expect(reopened.tables.keys, containsAll(['Financials','Notes']));
    expect(reopened['Financials']
        .cell(CellIndex.indexByString('A1')).value, TextCellValue('Revenue'));
    expect(reopened['Financials']
        .cell(CellIndex.indexByString('B1')).value, DoubleCellValue(12.5));
    expect(reopened['Notes']
        .cell(CellIndex.indexByString('A1')).value, TextCellValue('Next year'));
  });

  testWidgets('Personal Permissions reads users, departments and grants',
      (tester) async {
    final requests = <String>[];
    final payloads = <dynamic>[];
    final service = DriveService(dio: mockDio(requests, payloads));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: Builder(builder: (context) => ElevatedButton(
        onPressed: () => showDialog<bool>(
          context: context,
          builder: (_) => DrivePermissionsDialog(
            item: folderItem(), service: service,
          ),
        ),
        child: const Text('Open permissions'),
      ))),
    ));
    await tester.tap(find.text('Open permissions'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Permissions · Folder'), findsOneWidget);
    expect(find.text('Luka'), findsOneWidget);
    expect(find.text('Retail'), findsOneWidget);
    expect(find.text('Owner'), findsNothing);
    expect(find.text('Inactive'), findsNothing);
    expect(find.text('Include current and future contents'), findsOneWidget);
    expect(find.text('All Edit/Delete'), findsOneWidget);
    await tester.tap(find.text('All Edit/Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save permissions'));
    await tester.pumpAndSettle();
    final sent = payloads.last as Map;
    expect((sent['grants'] as List).length, 2);
    expect((sent['grants'] as List).every((grant) =>
        grant['access'] == 'EDITOR_DELETE'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Move modal lists real folders and sends selected destination',
      (tester) async {
    final requests = <String>[];
    final payloads = <dynamic>[];
    final service = DriveService(dio: mockDio(requests, payloads));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: Builder(builder: (context) => ElevatedButton(
        onPressed: () => showDialog<bool>(
          context: context,
          builder: (_) => DriveMoveDialog(item: fileItem(), service: service),
        ),
        child: const Text('Open move'),
      ))),
    ));
    await tester.tap(find.text('Open move'));
    await tester.pumpAndSettle();
    expect(find.text('Reports'), findsOneWidget);
    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move here'));
    await tester.pumpAndSettle();
    expect(requests, contains('PATCH /drive/item-1'));
    expect(payloads.last, {'parentId': 'folder-2'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('file cards show five actions and folders four', (tester) async {
    final service = _FakeListing([fileItem(), folderItem()]);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: DriveScreen(service: service),
    ));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Download'), findsOneWidget);
    expect(find.byTooltip('Rename'), findsNWidgets(2));
    expect(find.byTooltip('Permissions'), findsNWidgets(2));
    expect(find.byTooltip('Move'), findsNWidgets(2));
    expect(find.byTooltip('Delete'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}

class _FakeListing extends DriveService {
  _FakeListing(this.items);
  final List<Map<String, dynamic>> items;

  @override
  Future<PersonalDriveListing> getPersonalListing({String? parentId}) async =>
      PersonalDriveListing(items: items, usedBytes: 0);
}
