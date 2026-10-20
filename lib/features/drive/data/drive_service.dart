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
  });

  final List<Map<String, dynamic>> items;
  final int usedBytes;
}

class DriveService {
  final ApiClient _apiClient = ApiClient();

  /// Fetch the signed-in user's Personal space only. The backend expects
  /// parentId (not folderId) and returns kind, file, owner and timestamps.
  Future<PersonalDriveListing> getPersonalListing({String? parentId}) async {
    try {
      final response = await _apiClient.dio.get(
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
        return PersonalDriveListing(items: items, usedBytes: usedBytes);
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
  Future<Map<String, dynamic>> createFolder(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty ||
        trimmed.length > 200 ||
        trimmed == '.' ||
        trimmed == '..' ||
        RegExp(r'[\x00-\x1f/\\]').hasMatch(trimmed)) {
      throw const FormatException('Enter a valid folder name (max. 200 characters)');
    }

    try {
      final response = await _apiClient.dio.post(
        '/drive',
        data: {'name': trimmed, 'parentId': null},
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
  }) async {
    final name = ExcelToUniver.spreadsheetName(filename);
    final snapshot = await ExcelToUniver.convert(bytes, name: name);

    String? createdId;
    try {
      final created = await _apiClient.dio.post(
        '/drive/sheets',
        data: {'name': name, 'parentId': null},
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

      final saved = await _apiClient.dio.put(
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
          await _apiClient.dio.delete('/drive/$createdId');
        } catch (_) {}
      }
      if (error is DioException) {
        throw Exception(_serverError(error, 'Excel import failed'));
      }
      rethrow;
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

      await _apiClient.dio.post('/files', data: formData);
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
