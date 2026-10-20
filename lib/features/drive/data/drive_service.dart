import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';

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
