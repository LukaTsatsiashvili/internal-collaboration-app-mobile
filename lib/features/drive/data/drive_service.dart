import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';

class DriveService {
  final ApiClient _apiClient = ApiClient();

  // 1. ფაილებისა და საქაღალდეების სიის წამოღება (GET /drive ან /files)
  Future<List<dynamic>> getDriveItems({String? folderId}) async {
    try {
      final response = await _apiClient.dio.get(
        '/drive',
        queryParameters: {'folderId': ?folderId},
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data['data'] as List<dynamic>;
      }
    } on DioException catch (e) {
      throw Exception(e.response?.data['error']['message'] ?? 'ფაილების ჩატვირთვა ვერ მოხერხდა');
    }
    return [];
  }

  // 2. ფაილის ატვირთვა სერვერზე (POST /files)
  Future<void> uploadFile(String filePath, String fileName) async {
    try {
      String fileName = filePath.split('/').last;
      FormData formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
      });

      await _apiClient.dio.post('/files', data: formData);
    } on DioException catch (e) {
      throw Exception(e.response?.data['error']['message'] ?? 'ფაილის ატვირთვა ვერ მოხერხდა');
    }
  }
}