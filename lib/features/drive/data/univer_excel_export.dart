import 'dart:typed_data';

import 'package:excel_community/excel_community.dart';

/// Export the same Univer snapshot shape as the Web xlsx.js exporter.
/// Virtual Drive Sheets cannot be downloaded from the raw /files endpoint.
class UniverExcelExport {
  UniverExcelExport._();

  static Uint8List export(Map<String, dynamic> snapshot) {
    final sheetOrder = snapshot['sheetOrder'];
    final sheets = snapshot['sheets'];
    if (sheetOrder is! List || sheets is! Map || sheetOrder.isEmpty) {
      throw const FormatException('Spreadsheet has no worksheets');
    }
    final workbook = Excel.createExcel();
    var first = true;
    final used = <String>{};
    for (final sheetId in sheetOrder) {
      final data = sheets[sheetId.toString()];
      if (data is! Map) continue;
      final name = _safeSheetName((data['name'] ?? 'Sheet').toString(), used);
      if (first) {
        workbook.rename('Sheet1', name);
        first = false;
      }
      final output = workbook[name];

      final cells = data['cellData'];
      if (cells is Map) {
        for (final row in cells.entries) {
          final rowIndex = int.tryParse(row.key.toString());
          if (rowIndex == null || rowIndex < 0 || row.value is! Map) continue;
          for (final col in (row.value as Map).entries) {
            final columnIndex = int.tryParse(col.key.toString());
            if (columnIndex == null ||
                columnIndex < 0 || col.value is! Map) continue;
            final cell = col.value as Map;
            final raw = cell['v'];
            final formula = cell['f'];
            CellValue? value;
            if (formula is String && formula.isNotEmpty) {
              value = FormulaCellValue(
                formula.startsWith('=') ? formula : '=$formula',
              );
            } else if (raw is bool) {
              value = BoolCellValue(raw);
            } else if (raw is int) {
              value = IntCellValue(raw);
            } else if (raw is num) {
              value = DoubleCellValue(raw.toDouble());
            } else if (raw != null) {
              value = TextCellValue(raw.toString());
            }
            if (value == null) continue;
            output.updateCell(
              CellIndex.indexByColumnRow(
                  columnIndex: columnIndex, rowIndex: rowIndex),
              value,
            );
          }
        }
      }

      final merges = data['mergeData'];
      if (merges is List) {
        for (final range in merges.whereType<Map>()) {
          final sr = (range['startRow'] as num?)?.toInt();
          final sc = (range['startColumn'] as num?)?.toInt();
          final er = (range['endRow'] as num?)?.toInt();
          final ec = (range['endColumn'] as num?)?.toInt();
          if (sr == null || sc == null || er == null || ec == null ||
              sr < 0 || sc < 0 || er < sr || ec < sc) continue;
          output.merge(
            CellIndex.indexByColumnRow(columnIndex: sc, rowIndex: sr),
            CellIndex.indexByColumnRow(columnIndex: ec, rowIndex: er),
          );
        }
      }
    }
    if (first) {
      throw const FormatException('Spreadsheet has no valid worksheets');
    }
    final encoded = workbook.save();
    if (encoded == null || encoded.isEmpty) {
      throw StateError('Could not create Excel file');
    }
    return Uint8List.fromList(encoded);
  }

  static String _safeSheetName(String raw, Set<String> used) {
    var base = raw.replaceAll(RegExp(r'[\\/?*\[\]:]'), ' ').trim();
    if (base.isEmpty) base = 'Sheet';
    if (base.length > 31) base = base.substring(0, 31);
    var candidate = base;
    var number = 2;
    while (!used.add(candidate.toLowerCase())) {
      final suffix = ' $number';
      final maxLength = 31 - suffix.length;
      candidate = (base.length > maxLength
              ? base.substring(0, maxLength)
              : base) + suffix;
      number++;
    }
    return candidate;
  }
}
