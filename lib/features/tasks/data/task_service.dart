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
  Future<Map<String, dynamic>> moveTaskToGroup(
    String taskId, String? groupId,
  ) async {
    try {
      final response = await _apiClient.dio.put(
        '/tasks/$taskId/layout',
        data: {'groupId': groupId},
      );
      if (response.data['success'] != true ||
          response.data['data'] is! Map) {
        throw Exception('დავალების ჯგუფის შეცვლა ვერ მოხერხდა');
      }
      final saved = Map<String, dynamic>.from(response.data['data'] as Map);
      // Never present a group as saved until the server confirms its ID.
      if (saved['groupId']?.toString() != groupId) {
        throw Exception('სერვერმა არჩეული ჯგუფი ვერ დაადასტურა');
      }
      return saved;
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
    if (bytes.isEmpty) throw Exception('ცარიელი ფაილის ატვირთვა შეუძლებელია');
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: fileName),
      });

      // Explicit multipart body: ApiClient defaults to application/json.
      final response = await _apiClient.dio.post(
        '/files',
        data: formData,
        options: Options(
          contentType: Headers.multipartFormDataContentType,
          sendTimeout: const Duration(minutes: 2),
          receiveTimeout: const Duration(minutes: 2),
        ),
      );
      if ((response.statusCode == 200 || response.statusCode == 201) &&
          response.data['success'] == true &&
          response.data['data']?['id'] != null) {
        return response.data['data']['id'].toString();
      }
      throw Exception('სერვერმა ატვირთვა ვერ დაადასტურა');
    } on DioException catch (e) {
      final payload = e.response?.data;
      final error = payload is Map ? payload['error'] : null;
      throw Exception(
        (error is Map ? error['message'] : null)?.toString() ??
            'ფაილის ატვირთვა ვერ მოხერხდა: ' + (e.message ?? 'network error'),
      );
    }
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

  // Task attachment update is separate from adding an attachment to a
  // comment. Preserve existing attachment IDs when appending a new file.
  Future<void> attachFileToTask(
    String taskId, {
    required List<String> existingIds,
    required String newFileId,
  }) async {
    final allIds = {...existingIds, newFileId}.toList();
    final response = await _apiClient.dio.patch('/tasks/$taskId', data: {
      'attachmentIds': allIds,
    });
    if (response.data['success'] != true) {
      throw Exception('ფაილის დავალებასთან დაკავშირება ვერ მოხერხდა');
    }
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
