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
      throw Exception(
        e.response?.data['error']['message'] ??
            'ვერ მოხერხდა დავალებების ჩატვირთვა',
      );
    }
    return [];
  }

  // Use the authenticated session, not a display name/role, for personal tabs.
  Future<String> getCurrentUserId() async {
    try {
      final response = await _apiClient.dio.get('/auth/me');
      if (response.statusCode == 200 && response.data['success'] == true) {
        final id = response.data['data']?['id']?.toString();
        if (id != null && id.isNotEmpty) return id;
      }
    } on DioException catch (e) {
      throw Exception(
        e.response?.data?['error']?['message'] ??
            'ვერ მოხერხდა მომხმარებლის იდენტიფიცირება',
      );
    }
    throw Exception('ვერ მოხერხდა მომხმარებლის იდენტიფიცირება');
  }

  // Personal task groups belong to the signed-in user, not a department.
  Future<List<dynamic>> getTaskGroups() async {
    try {
      final response = await _apiClient.dio.get('/tasks/groups');
      if (response.data['success'] == true) {
        return response.data['data'] as List<dynamic>;
      }
      throw Exception('დავალებების ჯგუფები ვერ ჩაიტვირთა');
    } on DioException catch (e) {
      throw Exception(
        e.response?.data?['error']?['message'] ??
            'დავალებების ჯგუფები ვერ ჩაიტვირთა',
      );
    }
  }

  Future<void> createTaskGroup({required String name}) async {
    try {
      final response = await _apiClient.dio.post(
        '/tasks/groups',
        data: {'name': name.trim()},
      );
      if (response.data['success'] != true) {
        throw Exception('ჯგუფის შექმნა ვერ მოხერხდა');
      }
    } on DioException catch (e) {
      throw Exception(
        e.response?.data?['error']?['message'] ?? 'ჯგუფის შექმნა ვერ მოხერხდა',
      );
    }
  }

  // Changing a personal layout never changes the task's department.
  Future<void> moveTaskToGroup(String taskId, String? groupId) async {
    try {
      final response = await _apiClient.dio.put(
        '/tasks/$taskId/layout',
        data: {'groupId': groupId},
      );
      if (response.data['success'] != true) {
        throw Exception('დავალების ჯგუფის შეცვლა ვერ მოხერხდა');
      }
    } on DioException catch (e) {
      throw Exception(
        e.response?.data?['error']?['message'] ??
            'დავალების ჯგუფის შეცვლა ვერ მოხერხდა',
      );
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
      throw Exception(
        e.response?.data['error']['message'] ??
            'ვერ მოხერხდა მომხმარებლების წამოღება',
      );
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
      if ((response.statusCode == 200 || response.statusCode == 201) &&
          response.data['success'] == true) {
        return response.data['data']['id'];
      }
    } on DioException catch (e) {
      throw Exception(
        e.response?.data['error']['message'] ?? 'ფაილის ატვირთვა ვერ მოხერხდა',
      );
    }
    return null;
  }

  // 6. ახალი დავალების შექმნა
  Future<void> createTask({
    required String title,
    String? description,
    String? assigneeId,
    String? groupId,
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
          if (description != null && description.isNotEmpty)
            'description': description,
          if (assigneeId != null && assigneeId.isNotEmpty)
            'assigneeId': assigneeId,
          if (groupId != null && groupId.isNotEmpty) 'groupId': groupId,
          'priority': ?priority,
          'dueDate': ?dueDate,
          if (participantIds != null && participantIds.isNotEmpty)
            'participantIds': participantIds,
          if (attachmentIds != null && attachmentIds.isNotEmpty)
            'attachmentIds': attachmentIds,
        },
      );
    } on DioException catch (e) {
      throw Exception(
        e.response?.data['error']['message'] ?? 'ვერ მოხერხდა დავალების შექმნა',
      );
    }
  }

  // Full task includes participants, subtasks, comments, history, attachments.
  Future<Map<String, dynamic>> getTaskDetails(String taskId) async {
    final response = await _apiClient.dio.get('/tasks/$taskId');
    if (response.data['success'] != true) {
      throw Exception('დავალების დეტალების ჩატვირთვა ვერ მოხერხდა');
    }
    return Map<String, dynamic>.from(response.data['data'] as Map);
  }

  // The backend validates comment text and checks that attached files
  // were uploaded by the current authenticated user.
  Future<void> addTaskComment(
    String taskId, {
    required String content,
    List<String> attachmentIds = const [],
  }) async {
    await _apiClient.dio.post('/tasks/$taskId/comments', data: {
      'content': content.trim(),
      'attachmentIds': attachmentIds,
    });
  }

  // Authenticated Dio client uses the same token and refresh interceptor as
  // task requests. Store only in a temporary path; the system file picker
  // chooses the final destination.
  Future<void> downloadFileToPath(String fileId, String path) async {
    await _apiClient.dio.download('/files/$fileId/download', path);
  }

  // 7. სტატუსის განახლება
  Future<void> updateTaskStatus(String taskId, String newStatus) async {
    try {
      await _apiClient.dio.patch('/tasks/$taskId', data: {'status': newStatus});
    } on DioException catch (e) {
      throw Exception(
        e.response?.data['error']['message'] ??
            'ვერ მოხერხდა სტატუსის განახლება',
      );
    }
  }
}
