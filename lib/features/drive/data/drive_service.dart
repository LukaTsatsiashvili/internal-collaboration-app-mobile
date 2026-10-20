import 'dart:typed_data';

import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';
import 'excel_to_univer.dart';

/// Personal Drive data returned by GET /drive, including real storage usage.
/// The file list contains DriveItem records, not raw uploaded FileObjects.
class PersonalDriveListing {
  const PersonalDriveListing({
    required this.items,
    required this.usedBytes,
    this.breadcrumbs = const [],
  });

  final List<Map<String, dynamic>> items;
  final int usedBytes;
  final List<Map<String, dynamic>> breadcrumbs;
}

class DriveService {
  DriveService({Dio? dio}) : _dio = dio ?? ApiClient().dio;

  final Dio _dio;

  /// Fetch the signed-in user's Personal space only. The backend expects
  /// parentId (not folderId) and returns kind, file, owner and timestamps.
  Future<PersonalDriveListing> getPersonalListing({String? parentId}) async {
    try {
      final response = await _dio.get(
        '/drive',
        queryParameters: {
          'view': 'personal',
          if (parentId != null) 'parentId': parentId,
        },
      );
      final body = response.data;
      if (response.statusCode == 200 &&
          body is Map &&
          body['success'] == true &&
          body['data'] is List) {
        final items = (body['data'] as List)
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false);
        final meta = body['meta'];
        final usedBytes = meta is Map && meta['usedBytes'] is num
            ? (meta['usedBytes'] as num).toInt()
            : 0;
        return PersonalDriveListing(
          items: items,
          usedBytes: usedBytes,
          breadcrumbs: meta is Map && meta['breadcrumbs'] is List
              ? (meta['breadcrumbs'] as List).whereType<Map>()
                  .map((crumb) => Map<String, dynamic>.from(crumb)).toList()
              : const [],
        );
      }
      throw StateError('Drive returned an unexpected response');
    } on DioException catch (e) {
      final data = e.response?.data;
      final error = data is Map ? data['error'] : null;
      throw Exception(
        error is Map && error['message'] != null
            ? error['message'].toString()
            : 'ფაილების ჩატვირთვა ვერ მოხერხდა',
      );
    }
  }

  /// Backwards-compatible list accessor used by older Drive UI callers.
  Future<List<dynamic>> getDriveItems({String? folderId}) async {
    return (await getPersonalListing(parentId: folderId)).items;
  }


  /// Creates a real Personal Drive folder. Without fileId, /drive creates
  /// kind=FOLDER. This is the same endpoint used by the web interface.
  Future<Map<String, dynamic>> createFolder(String name, {String? parentId}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty ||
        trimmed.length > 200 ||
        trimmed == '.' ||
        trimmed == '..' ||
        RegExp(r'[\x00-\x1f/\\]').hasMatch(trimmed)) {
      throw const FormatException('Enter a valid folder name (max. 200 characters)');
    }

    try {
      final response = await _dio.post(
        '/drive',
        data: {'name': trimmed, 'parentId': parentId},
      );
      final data = response.data;
      if (data is Map && data['success'] == true &&
          data['data'] is Map && data['data']['kind'] == 'FOLDER') {
        return Map<String, dynamic>.from(data['data'] as Map);
      }
      throw StateError('The server did not confirm folder creation');
    } on DioException catch (error) {
      throw Exception(_serverError(error, 'Folder creation failed'));
    }
  }

  /// Imports the workbook into a live Univer spreadsheet, not a raw Drive
  /// attachment: the web app uses POST /drive/sheets then PUT the snapshot.
  /// A failed save cleans up the newly created (empty) Drive item best-effort.
  Future<Map<String, dynamic>> importExcel(
    Uint8List bytes, {
    required String filename,
    String? parentId,
  }) async {
    final name = ExcelToUniver.spreadsheetName(filename);
    final snapshot = await ExcelToUniver.convert(bytes, name: name);

    String? createdId;
    try {
      final created = await _dio.post(
        '/drive/sheets',
        data: {'name': name, 'parentId': parentId},
      );
      final createdBody = created.data;
      if (createdBody is! Map ||
          createdBody['success'] != true ||
          createdBody['data'] is! Map) {
        throw StateError('The server did not confirm spreadsheet creation');
      }

      final sheet = Map<String, dynamic>.from(createdBody['data'] as Map);
      final id = sheet['id']?.toString();
      if (id == null || id.isEmpty) {
        throw StateError('The new spreadsheet has no ID');
      }
      createdId = id;

      final saved = await _dio.put(
        '/drive/sheets/$id',
        data: {'snapshot': snapshot, 'version': 1},
      );
      final savedBody = saved.data;
      if (savedBody is! Map || savedBody['success'] != true) {
        throw StateError('The imported spreadsheet was not saved');
      }
      return sheet;
    } catch (error) {
      if (createdId != null) {
        try {
          // Only remove the incomplete item from the Personal listing.
          // The server implements deletion through Drive Trash.
          await _dio.delete('/drive/$createdId');
        } catch (_) {}
      }
      if (error is DioException) {
        throw Exception(_serverError(error, 'Excel import failed'));
      }
      rethrow;
    }
  }


  static const sheetMime = 'application/vnd.gtex.univer-sheet+json';

  /// Same Drive actions and access checks used by the React app.
  Future<void> renameItem(String itemId, String name) async {
    _checkName(name);
    await _changeItem(itemId, {'name': name.trim()});
  }

  Future<void> moveItem(String itemId, String? parentId) async {
    await _changeItem(itemId, {'parentId': parentId});
  }

  Future<void> _changeItem(String itemId, Map<String, dynamic> change) async {
    try {
      final response = await _dio.patch(
        '/drive/${Uri.encodeComponent(itemId)}',
        data: change,
      );
      _requireSuccess(response, 'Drive update failed');
    } on DioException catch (error) {
      throw Exception(_serverError(error, 'Drive update failed'));
    }
  }

  Future<void> trashItem(String itemId) async {
    try {
      final response = await _dio.delete(
        '/drive/${Uri.encodeComponent(itemId)}',
      );
      _requireSuccess(response, 'Could not move item to Trash');
    } on DioException catch (error) {
      throw Exception(_serverError(error, 'Could not move item to Trash'));
    }
  }

  Future<List<Map<String, dynamic>>> getPeople() async => _loadRows('/users');
  Future<List<Map<String, dynamic>>> getDepartments() async =>
      _loadRows('/departments');

  Future<List<Map<String, dynamic>>> _loadRows(String path) async {
    try {
      final response = await _dio.get(path);
      if (response.data is Map &&
          response.data['success'] == true &&
          response.data['data'] is List) {
        return (response.data['data'] as List).whereType<Map>()
            .map((value) => Map<String, dynamic>.from(value)).toList();
      }
      throw StateError('Invalid directory response');
    } on DioException catch (error) {
      throw Exception(_serverError(error, 'Could not load directory'));
    }
  }

  Future<DriveShares> getShares(String itemId) async {
    try {
      final response = await _dio.get(
        '/drive/${Uri.encodeComponent(itemId)}/shares',
      );
      if (response.data is Map &&
          response.data['success'] == true &&
          response.data['data'] is List) {
        final meta = response.data['meta'];
        return DriveShares(
          grants: (response.data['data'] as List).whereType<Map>()
              .map((value) => Map<String, dynamic>.from(value)).toList(),
          permissionMode: meta is Map
              ? (meta['permissionMode'] ?? 'CUSTOM').toString() : 'CUSTOM',
        );
      }
      throw StateError('Invalid permission response');
    } on DioException catch (error) {
      throw Exception(_serverError(error, 'Could not load permissions'));
    }
  }

  Future<void> setShares(
    String itemId, {
    required List<Map<String, dynamic>> grants,
    String? permissionMode,
  }) async {
    try {
      final response = await _dio.put(
        '/drive/${Uri.encodeComponent(itemId)}/shares',
        data: {
          'grants': grants,
          if (permissionMode != null) 'permissionMode': permissionMode,
        },
      );
      _requireSuccess(response, 'Could not save permissions');
    } on DioException catch (error) {
      throw Exception(_serverError(error, 'Could not save permissions'));
    }
  }

  /// The /files/:id/download endpoint returns actual file bytes and checks
  /// the requesting user's permissions on the backend.
  Future<Uint8List> downloadFile(String fileId) async {
    try {
      final response = await _dio.get<List<int>>(
        '/files/${Uri.encodeComponent(fileId)}/download',
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data;
      if (bytes == null) throw StateError('No file data received');
      return Uint8List.fromList(bytes);
    } on DioException catch (error) {
      throw Exception(_serverError(error, 'Download failed'));
    }
  }

  /// Univer spreadsheet FileObjects are virtual; download their JSON snapshot
  /// to export real Excel bytes (equivalent to the Web app's export path).
  Future<Map<String, dynamic>> getSpreadsheet(String driveItemId) async {
    try {
      final response = await _dio.get(
        '/drive/sheets/${Uri.encodeComponent(driveItemId)}',
      );
      if (response.data is Map &&
          response.data['success'] == true &&
          response.data['data'] is Map) {
        return Map<String, dynamic>.from(response.data['data'] as Map);
      }
      throw StateError('Invalid spreadsheet response');
    } on DioException catch (error) {
      throw Exception(_serverError(error, 'Could not load spreadsheet'));
    }
  }

  static void _checkName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 200 ||
        trimmed == '.' || trimmed == '..' ||
        RegExp(r'[\x00-\x1f/\\]').hasMatch(trimmed)) {
      throw const FormatException('Use a valid name (maximum 200 characters)');
    }
  }

  void _requireSuccess(Response<dynamic> response, String fallback) {
    if (response.data is! Map || response.data['success'] != true) {
      throw StateError(fallback);
    }
  }

  String _serverError(DioException error, String fallback) {
    final body = error.response?.data;
    final issue = body is Map ? body['error'] : null;
    if (issue is Map && issue['message'] != null) {
      return issue['message'].toString();
    }
    return fallback;
  }

  // Existing upload method is retained for the later functional phase.
  // Uploading to /files alone does not create a Drive item: linking is separate.
  Future<void> uploadFile(String filePath, String fileName) async {
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
      });

      await _dio.post('/files', data: formData);
    } on DioException catch (e) {
      final data = e.response?.data;
      final error = data is Map ? data['error'] : null;
      throw Exception(
        error is Map && error['message'] != null
            ? error['message'].toString()
            : 'ფაილის ატვირთვა ვერ მოხერხდა',
      );
    }
  }
}

class DriveShares {
  const DriveShares({required this.grants, required this.permissionMode});
  final List<Map<String, dynamic>> grants;
  final String permissionMode;
}
