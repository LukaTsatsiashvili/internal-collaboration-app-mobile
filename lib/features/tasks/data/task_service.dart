import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';

class TaskService {
  final ApiClient _apiClient = ApiClient();

  // 1. დავალებების სიის წამოღება
  Future<List<dynamic>> getTasks({String? status}) async {
    try {
      final queryParameters = <String, dynamic>{};
      if (status != null && status.isNotEmpty) {
        queryParameters['status'] = status;
      }

      final response = await _apiClient.dio.get(
        '/tasks',
        queryParameters: queryParameters,
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data['data'] as List<dynamic>;
      }
    } on DioException catch (e) {
      throw Exception(e.response?.data['error']['message'] ?? 'ვერ მოხერხდა დავალებების ჩატვირთვა');
    }
    return [];
  }

  // 2. დეპარტამენტების / ჯგუფების წამოღება
  Future<List<dynamic>> getDepartments() async {
    try {
      final response = await _apiClient.dio.get('/departments');
      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data['data'] as List<dynamic>;
      }
    } on DioException catch (e) {
      throw Exception(e.response?.data['error']['message'] ?? 'ვერ მოხერხდა ჯგუფების ჩატვირთვა');
    }
    return [];
  }

  // 3. ახალი ჯგუფის შექმნა
  Future<void> createDepartment({required String name}) async {
    try {
      await _apiClient.dio.post(
        '/departments',
        data: {
          'name': name,
          'code': name.toUpperCase().replaceAll(' ', '_'),
        },
      );
    } on DioException catch (e) {
      throw Exception(e.response?.data['error']['message'] ?? 'ვერ მოხერხდა ჯგუფის შექმნა');
    }
  }

  // 4. მომხმარებლების (Assignees / Participants) წამოღება
  Future<List<dynamic>> getUsers() async {
    try {
      final response = await _apiClient.dio.get('/users');
      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data['data'] as List<dynamic>;
      }
    } on DioException catch (e) {
      throw Exception(e.response?.data['error']['message'] ?? 'ვერ მოხერხდა მომხმარებლების წამოღება');
    }
    return [];
  }

  // 5. ფაილის ატვირთვა პლატფორმისთვის ნაცნობი მეთოდით
  Future<String?> uploadFileBytes(List<int> bytes, String fileName) async {
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: fileName),
      });

      final response = await _apiClient.dio.post('/files', data: formData);
      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data['data']['id'];
      }
    } on DioException catch (e) {
      throw Exception(e.response?.data['error']['message'] ?? 'ფაილის ატვირთვა ვერ მოხერხდა');
    }
    return null;
  }

  // 6. ახალი დავალების შექმნა
  Future<void> createTask({
    required String title,
    String? description,
    String? assigneeId,
    String? departmentId,
    String? priority,
    String? dueDate,
    List<String>? participantIds,
    List<String>? attachmentIds,
  }) async {
    try {
      await _apiClient.dio.post(
        '/tasks',
        data: {
          'title': title,
          if (description != null && description.isNotEmpty) 'description': description,
          if (assigneeId != null && assigneeId.isNotEmpty) 'assigneeId': assigneeId,
          if (departmentId != null && departmentId.isNotEmpty) 'departmentId': departmentId,
          'priority': ?priority,
          'dueDate': ?dueDate,
          if (participantIds != null && participantIds.isNotEmpty) 'participantIds': participantIds,
          if (attachmentIds != null && attachmentIds.isNotEmpty) 'attachmentIds': attachmentIds,
        },
      );
    } on DioException catch (e) {
      throw Exception(e.response?.data['error']['message'] ?? 'ვერ მოხერხდა დავალების შექმნა');
    }
  }

  // 7. სტატუსის განახლება
  Future<void> updateTaskStatus(String taskId, String newStatus) async {
    try {
      await _apiClient.dio.patch(
        '/tasks/$taskId',
        data: {'status': newStatus},
      );
    } on DioException catch (e) {
      throw Exception(e.response?.data['error']['message'] ?? 'ვერ მოხერხდა სტატუსის განახლება');
    }
  }
}