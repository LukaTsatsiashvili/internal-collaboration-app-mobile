import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/network/api_client.dart';

class AuthService {
  final ApiClient _apiClient = ApiClient();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  // 1. სისტემაში შესვლა
  Future<Map<String, dynamic>?> login(String email, String password) async {
    try {
      final response = await _apiClient.dio.post(
        '/auth/login',
        data: {'email': email, 'password': password},
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final data = response.data['data'];
        final accessToken = data['accessToken'];
        
        await _secureStorage.write(key: 'access_token', value: accessToken);
        return data['user'];
      }
    } on DioException catch (e) {
      throw Exception(e.response?.data['error']['message'] ?? 'ავტორიზაციის შეცდომა');
    }
    return null;
  }

  // 2. სესიის შემოწმება (იყენებს თუ არა მომხმარებელი არსებულ ვალიდურ ტოკენს)
  Future<bool> checkSession() async {
    try {
      final token = await _secureStorage.read(key: 'access_token');
      if (token == null || token.isEmpty) return false;

      final response = await _apiClient.dio.get('/auth/me');
      if (response.statusCode == 200 && response.data['success'] == true) {
        return true;
      }
    } catch (_) {
      // თუ ტოკენი ვადაგასულია ან სერვერი მიუწვდომელია
    }
    return false;
  }

  // 3. სრული გასვლა (Logout)
  Future<void> logout() async {
    try {
      await _apiClient.dio.post('/auth/logout');
    } catch (_) {
      // თუნდაც ბექენდზე მოთხოვნა ჩავარდეს, ლოკალურად აუცილებლად ვასუფთავებთ
    } finally {
      await _secureStorage.delete(key: 'access_token');
    }
  }
}