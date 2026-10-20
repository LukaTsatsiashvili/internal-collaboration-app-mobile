import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:excel_community/excel_community.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtex_collab_app/features/drive/data/drive_service.dart';
import 'package:gtex_collab_app/features/drive/data/excel_to_univer.dart';

Uint8List sampleExcel() {
  final workbook = Excel.createExcel();
  final sheet = workbook['Sheet1'];
  sheet.updateCell(CellIndex.indexByString('A1'), TextCellValue('Product'));
  sheet.updateCell(CellIndex.indexByString('B1'), TextCellValue('Price'));
  sheet.updateCell(CellIndex.indexByString('A2'), TextCellValue('Table'));
  sheet.updateCell(CellIndex.indexByString('B2'), DoubleCellValue(12.5));
  sheet.updateCell(
    CellIndex.indexByString('B3'),
    FormulaCellValue('=SUM(B2:B2)'),
  );
  sheet.merge(
    CellIndex.indexByString('D1'),
    CellIndex.indexByString('E1'),
  );
  return Uint8List.fromList(workbook.save()!);
}

Dio stubDio(List<String> requests, {
  bool failSheetSave = false,
  List<Object?>? payloads,
}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api/v1'));
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) {
      requests.add(options.method + ' ' + options.path);
      payloads?.add(options.method == 'GET' ? options.queryParameters : options.data);
      final path = options.path;
      if (path == '/drive/sheets' && options.method == 'POST') {
        handler.resolve(Response(
          requestOptions: options,
          statusCode: 201,
          data: {
            'success': true,
            'data': {'id': 'sheet-123', 'kind': 'FILE', 'name': 'Sales'},
          },
        ));
      } else if (path == '/drive/sheets/sheet-123' &&
          options.method == 'PUT') {
        if (failSheetSave) {
          handler.reject(DioException(
            requestOptions: options,
            response: Response(
              requestOptions: options,
              statusCode: 409,
              data: {
                'success': false,
                'error': {'message': 'Spreadsheet revision conflict'},
              },
            ),
            type: DioExceptionType.badResponse,
          ));
        } else {
          handler.resolve(Response(
            requestOptions: options,
            data: {'success': true, 'data': {'version': 2}},
            statusCode: 200,
          ));
        }
      } else if (path == '/drive/sheet-123' && options.method == 'DELETE') {
        handler.resolve(Response(
          requestOptions: options,
          data: {'success': true},
          statusCode: 200,
        ));
      } else if (path == '/drive' && options.method == 'POST') {
        handler.resolve(Response(
          requestOptions: options,
          statusCode: 201,
          data: {
            'success': true,
            'data': {'id': 'folder-123', 'name': 'Reports', 'kind': 'FOLDER'},
          },
        ));
      } else if (path == '/drive' && options.method == 'GET') {
        handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: {
            'success': true,
            'data': [
              {'id': 'folder-123', 'name': 'Reports', 'kind': 'FOLDER'},
            ],
            'meta': {'usedBytes': 2500},
          },
        ));
      } else {
        handler.reject(DioException(
          requestOptions: options,
          error: 'Unexpected request',
        ));
      }
    },
  ));
  return dio;
}

void main() {
  test('Excel extensions match the Web importer', () {
    expect(ExcelToUniver.supportsFilename('report.XLSX'), isTrue);
    expect(ExcelToUniver.supportsFilename('macro.xlsm'), isTrue);
    expect(ExcelToUniver.supportsFilename('old.xls'), isTrue);
    expect(ExcelToUniver.supportsFilename('report.pdf'), isFalse);
    expect(ExcelToUniver.spreadsheetName('Q4 2026.XLSX'), 'Q4 2026');
    expect(
      () => ExcelToUniver.spreadsheetName('invalid.pdf'),
      throwsFormatException,
    );
  });

  test('converts cells, formula and merge into Web Univer format', () async {
    final snapshot =
        await ExcelToUniver.convert(sampleExcel(), name: 'Sales');
    expect(snapshot['name'], 'Sales');
    expect(snapshot['appVersion'], '1.0.2');
    final id = (snapshot['sheetOrder'] as List).first.toString();
    final sheet = (snapshot['sheets'] as Map)[id] as Map;
    expect(sheet['name'], 'Sheet1');
    expect(sheet['rowCount'], greaterThanOrEqualTo(1000));
    expect(sheet['columnCount'], greaterThanOrEqualTo(20));
    final cells = sheet['cellData'] as Map;
    expect((cells['0'] as Map)['0']['v'], 'Product');
    expect((cells['1'] as Map)['1']['v'], 12.5);
    expect((cells['2'] as Map)['1']['f'], '=SUM(B2:B2)');
    expect(sheet['mergeData'], contains({
      'startRow': 0, 'startColumn': 3, 'endRow': 0, 'endColumn': 4,
    }));
  });

  test('creates Personal folder and reads Personal listing', () async {
    final requests = <String>[];
    final payloads = <Object?>[];
    final service = DriveService(
      dio: stubDio(requests, payloads: payloads),
    );
    final created = await service.createFolder(' Reports ');
    expect(created['kind'], 'FOLDER');
    expect(payloads.first, {'name': 'Reports', 'parentId': null});
    final listing = await service.getPersonalListing();
    expect(listing.items.single['name'], 'Reports');
    expect(listing.usedBytes, 2500);
    expect(requests, ['POST /drive', 'GET /drive']);
    expect((payloads.last as Map)['view'], 'personal');
  });

  test('New Spreadsheet creates a Drive-backed workbook in the chosen folder', () async {
    final requests = <String>[];
    final payloads = <Object?>[];
    final service = DriveService(dio: stubDio(requests, payloads: payloads));
    final created = await service.createSpreadsheet(' Weekly report ',
        parentId: 'folder-123', spaceId: 'group-space-1');
    expect(created['id'], 'sheet-123');
    expect(requests, ['POST /drive/sheets']);
    expect(payloads.single, {
      'name': 'Weekly report',
      'parentId': 'folder-123',
      'spaceId': 'group-space-1',
    });
    // Creating a new blank workbook must not perform an extra PUT.
    // The Univer editor initializes the empty snapshot on first open.
  });

  test('invalid spreadsheet names never call the backend', () async {
    final requests = <String>[];
    final service = DriveService(dio: stubDio(requests));
    await expectLater(
      service.createSpreadsheet('Bad/Name'),
      throwsA(isA<FormatException>()),
    );
    expect(requests, isEmpty);
  });

  test('imports Excel through POST sheet then PUT snapshot', () async {
    final requests = <String>[];
    final payloads = <Object?>[];
    final service = DriveService(
      dio: stubDio(requests, payloads: payloads),
    );
    final created =
        await service.importExcel(sampleExcel(), filename: 'Sales.xlsx');
    expect(created['id'], 'sheet-123');
    expect(requests, ['POST /drive/sheets', 'PUT /drive/sheets/sheet-123']);
    expect(payloads.first, {'name': 'Sales', 'parentId': null});
    final put = payloads.last as Map;
    expect(put['version'], 1);
    expect((put['snapshot'] as Map)['name'], 'Sales');
  });

  test('failed snapshot persistence trashes incomplete sheet', () async {
    final requests = <String>[];
    final service = DriveService(
      dio: stubDio(requests, failSheetSave: true),
    );
    await expectLater(
      service.importExcel(sampleExcel(), filename: 'Sales.xlsx'),
      throwsA(isA<Exception>()),
    );
    expect(requests, [
      'POST /drive/sheets',
      'PUT /drive/sheets/sheet-123',
      'DELETE /drive/sheet-123',
    ]);
  });

  test('damaged Excel is rejected before any POST', () async {
    final requests = <String>[];
    final service = DriveService(dio: stubDio(requests));
    await expectLater(
      service.importExcel(Uint8List.fromList([1, 2, 3]),
          filename: 'corrupt.xlsx'),
      throwsA(isA<FormatException>()),
    );
    expect(requests, isEmpty);
  });
}
