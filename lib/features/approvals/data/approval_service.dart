import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';

class ApprovalService {
  final ApiClient _apiClient = ApiClient();

  // 1. მოთხოვნების სიის წამოღება (GET /approval-requests)
  Future<List<dynamic>> getApprovalRequests({String? status}) async {
    try {
      final queryParameters = <String, dynamic>{};
      if (status != null && status.isNotEmpty) {
        queryParameters['status'] = status;
      }

      final response = await _apiClient.dio.get(
        '/approval-requests',
        queryParameters: queryParameters,
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data['data'] as List<dynamic>;
      }
    } on DioException catch (e) {
      throw Exception(e.response?.data['error']['message'] ?? 'ვერ მოხერხდა მოთხოვნების ჩატვირთვა');
    }
    return [];
  }

  /// Read-only data for the existing personal-group UI. No mutations.
  Future<List<dynamic>> getApprovalGroups() async {
    final response = await _apiClient.dio.get('/approval-groups');
    if (response.data['success'] != true || response.data['data'] is! List) {
      throw StateError('Approval groups could not be loaded');
    }
    return response.data['data'] as List<dynamic>;
  }

  /// Only the signed-in user's group can be renamed or archived.
  Future<Map<String, dynamic>> renameApprovalGroup({
    required String id,
    required String name,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 120) {
      throw ArgumentError('ჯგუფის სახელი უნდა შეიცავდეს 1-120 სიმბოლოს');
    }
    try {
      final response = await _apiClient.dio.patch(
        '/approval-groups/${Uri.encodeComponent(id)}',
        data: <String, dynamic>{'name': trimmed},
      );
      return _approvalData(response.data, 'Group rename failed');
    } on DioException catch (error) {
      throw Exception(_approvalError(error, 'Group rename failed'));
    }
  }

  /// Backend soft-archives the group and moves only this user's layouts
  /// back to Ungrouped; no approval requests are deleted.
  Future<void> deleteApprovalGroup(String id) async {
    try {
      final response = await _apiClient.dio.delete(
        '/approval-groups/${Uri.encodeComponent(id)}',
        // ApiClient sends application/json; Fastify requires a valid JSON
        // document when that content type is present (even on DELETE).
        data: const <String, dynamic>{},
      );
      final body = response.data;
      if (body is! Map || body['success'] != true ||
          body['data'] is! Map || body['data']['id']?.toString() != id) {
        throw StateError('Group deletion was not confirmed');
      }
    } on DioException catch (error) {
      throw Exception(_approvalError(error, 'Group deletion failed'));
    }
  }

  /// Populate all request types in the advanced filter, not only used ones.
  Future<List<dynamic>> getApprovalTypes() async {
    final response = await _apiClient.dio.get('/approval-types');
    if (response.data['success'] != true || response.data['data'] is! List) {
      throw StateError('Approval types could not be loaded');
    }
    return response.data['data'] as List<dynamic>;
  }

  /// Management list contains ACTIVE, INACTIVE and DRAFT records, including
  /// the creator and request count required by the mobile Request Types sheet.
  /// The server enforces approvals.configure permission for this endpoint.
  Future<List<dynamic>> getManagedApprovalTypes() async {
    final response = await _apiClient.dio.get('/approval-types/manage');
    final payload = response.data;
    if (payload is Map && payload['success'] == true &&
        payload['data'] is List) {
      return payload['data'] as List<dynamic>;
    }
    throw StateError('Request types could not be loaded');
  }

  /// Approval Group creation is separate from task groups and uses its own API.
  /// Sending a JSON body is required by the Fastify server.
  Future<Map<String, dynamic>> createApprovalGroup({required String name}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 120) {
      throw ArgumentError('ჯგუფის სახელი უნდა შეიცავდეს 1-120 სიმბოლოს');
    }
    try {
      final response = await _apiClient.dio.post(
        '/approval-groups',
        data: <String, dynamic>{'name': trimmed},
      );
      final payload = response.data;
      if (payload is Map && payload['success'] == true &&
          payload['data'] is Map) {
        return Map<String, dynamic>.from(payload['data'] as Map);
      }
      throw StateError('ჯგუფის შექმნა ვერ მოხერხდა');
    } on DioException catch (error) {
      final data = error.response?.data;
      final serverError = data is Map ? data['error'] : null;
      final detail = serverError is Map ? serverError['message'] : null;
      throw Exception(detail?.toString() ?? 'ჯგუფის შექმნა ვერ მოხერხდა');
    }
  }

  /// Same read endpoint used by the web Approval Type editor.
  Future<List<dynamic>> getUsersForApprovalSteps() async {
    final response = await _apiClient.dio.get('/users');
    final payload = response.data;
    if (payload is Map && payload['success'] == true &&
        payload['data'] is List) {
      return payload['data'] as List<dynamic>;
    }
    throw StateError('Approvers could not be loaded');
  }

  /// The Fastify/Zod API validates formSchema, step order and permissions.
  /// Keep the payload identical to the web configurator.
  Future<Map<String, dynamic>> createApprovalType(
      Map<String, dynamic> payload) async {
    try {
      final response = await _apiClient.dio.post(
        '/approval-types',
        data: payload,
      );
      final result = response.data;
      if (result is Map && result['success'] == true &&
          result['data'] is Map) {
        return Map<String, dynamic>.from(result['data'] as Map);
      }
      throw StateError('Approval type could not be created');
    } on DioException catch (error) {
      final body = error.response?.data;
      final problem = body is Map ? body['error'] : null;
      final message = problem is Map ? problem['message'] : null;
      throw Exception(
        message?.toString() ?? 'Approval type could not be created',
      );
    }
  }

  /// PATCH creates a new version; the server preserves snapshots used by
  /// existing requests and refuses code changes once a type is in use.
  Future<Map<String, dynamic>> updateApprovalType(
      String id, Map<String, dynamic> payload) async {
    try {
      final response = await _apiClient.dio.patch(
        '/approval-types/${Uri.encodeComponent(id)}',
        data: payload,
      );
      return _approvalData(response.data, 'Request type update failed');
    } on DioException catch (error) {
      throw Exception(_approvalError(error, 'Request type update failed'));
    }
  }

  Future<Map<String, dynamic>> changeApprovalTypeStatus(
      String id, String status) async {
    if (status != 'ACTIVE' && status != 'INACTIVE') {
      throw ArgumentError('Invalid approval type status');
    }
    try {
      final response = await _apiClient.dio.patch(
        '/approval-types/${Uri.encodeComponent(id)}/status',
        data: {'status': status},
      );
      return _approvalData(response.data, 'Status update failed');
    } on DioException catch (error) {
      throw Exception(_approvalError(error, 'Status update failed'));
    }
  }

  /// Mirrors web RequestForm: {approvalTypeId,title,data,submit,attachmentIds}.
  Future<Map<String, dynamic>> createApprovalRequest({
    required String approvalTypeId,
    required String title,
    required Map<String, dynamic> data,
    required bool submit,
    List<String> attachmentIds = const [],
  }) async {
    try {
      final response = await _apiClient.dio.post(
        '/approval-requests',
        data: <String, dynamic>{
          'approvalTypeId': approvalTypeId,
          'title': title.trim(),
          'data': data,
          'submit': submit,
          'attachmentIds': attachmentIds,
        },
      );
      return _approvalData(response.data, 'Approval request could not be saved');
    } on DioException catch (error) {
      throw Exception(_approvalError(error, 'Approval request could not be saved'));
    }
  }

  /// Upload before creating the request, as the web client does. Fastify
  /// expects a multipart POST even though ApiClient defaults to JSON.
  Future<String> uploadApprovalAttachment(
      List<int> bytes, String fileName) async {
    if (bytes.isEmpty) throw ArgumentError('Cannot attach an empty file');
    try {
      final response = await _apiClient.dio.post(
        '/files',
        data: FormData.fromMap({
          'file': MultipartFile.fromBytes(bytes, filename: fileName),
        }),
        options: Options(
          contentType: Headers.multipartFormDataContentType,
          sendTimeout: const Duration(minutes: 2),
          receiveTimeout: const Duration(minutes: 2),
        ),
      );
      final body = response.data;
      if (body is Map && body['success'] == true &&
          body['data'] is Map && body['data']['id'] != null) {
        return body['data']['id'].toString();
      }
      throw StateError('File upload was not confirmed');
    } on DioException catch (error) {
      throw Exception(_approvalError(error, 'File upload failed'));
    }
  }

  Map<String, dynamic> _approvalData(dynamic body, String fallback) {
    if (body is Map && body['success'] == true && body['data'] is Map) {
      return Map<String, dynamic>.from(body['data'] as Map);
    }
    throw StateError(fallback);
  }

  String _approvalError(DioException error, String fallback) {
    final body = error.response?.data;
    final nested = body is Map ? body['error'] : null;
    final message = nested is Map ? nested['message'] : null;
    return message?.toString() ?? fallback;
  }

  /// Used only to display current-user quick filters, as on the web page.
  Future<String> getCurrentUserId() async {
    final response = await _apiClient.dio.get('/auth/me');
    final id = response.data['data']?['id']?.toString();
    if (response.data['success'] != true || id == null || id.isEmpty) {
      throw StateError('Current user is unavailable');
    }
    return id;
  }

  /// Load the live request before every decision; revision protects against
  /// stale decisions from a concurrent web/mobile session.
  Future<Map<String, dynamic>> getApprovalRequest(String id) async {
    try {
      final response = await _apiClient.dio.get(
        '/approval-requests/${Uri.encodeComponent(id)}',
      );
      return _approvalData(response.data, 'Request detail could not be loaded');
    } on DioException catch (error) {
      throw Exception(_approvalError(error, 'Request detail could not be loaded'));
    }
  }

  Future<Map<String, dynamic>> getCurrentApprovalUser() async {
    try {
      final response = await _apiClient.dio.get('/auth/me');
      return _approvalData(response.data, 'Current user could not be loaded');
    } on DioException catch (error) {
      throw Exception(_approvalError(error, 'Current user could not be loaded'));
    }
  }

  /// Same user-specific grouping endpoint as the web RequestDetail component.
  Future<void> setApprovalRequestGroup(String id, String? groupId) async {
    try {
      final response = await _apiClient.dio.put(
        '/approval-requests/${Uri.encodeComponent(id)}/layout',
        data: <String, dynamic>{'groupId': groupId},
      );
      _approvalData(response.data, 'Group change was not saved');
    } on DioException catch (error) {
      throw Exception(_approvalError(error, 'Group change was not saved'));
    }
  }

  /// Decisions must include revision. Only the current assigned approver
  /// may act, and reject/request changes require an explanation.
  Future<void> decideApproval({
    required String id,
    required int revision,
    required String action,
    String comment = '',
  }) async {
    if (!const ['APPROVE', 'REJECT', 'REQUEST_CHANGES'].contains(action)) {
      throw ArgumentError('Unknown review decision');
    }
    if (action != 'APPROVE' && comment.trim().isEmpty) {
      throw ArgumentError('Explain your decision');
    }
    try {
      final response = await _apiClient.dio.post(
        '/approval-requests/${Uri.encodeComponent(id)}/actions',
        data: <String, dynamic>{
          'revision': revision, 'action': action, 'comment': comment.trim(),
        },
      );
      _approvalData(response.data, 'Decision could not be saved');
    } on DioException catch (error) {
      throw Exception(_approvalError(error, 'Decision could not be saved'));
    }
  }

  Future<void> cancelApproval({required String id, required int revision}) async {
    try {
      final response = await _apiClient.dio.post(
        '/approval-requests/${Uri.encodeComponent(id)}/cancel',
        data: <String, dynamic>{'revision': revision},
      );
      if (response.data is! Map || response.data['success'] != true) {
        throw StateError('Cancellation was not confirmed');
      }
    } on DioException catch (error) {
      throw Exception(_approvalError(error, 'Cancellation failed'));
    }
  }

  Future<void> commentOnApproval({
    required String id,
    required String content,
  }) async {
    if (content.trim().isEmpty || content.trim().length > 5000) {
      throw ArgumentError('Comment must contain 1–5000 characters');
    }
    try {
      final response = await _apiClient.dio.post(
        '/approval-requests/${Uri.encodeComponent(id)}/comments',
        data: <String, dynamic>{'content': content.trim()},
      );
      _approvalData(response.data, 'Comment could not be saved');
    } on DioException catch (error) {
      throw Exception(_approvalError(error, 'Comment could not be saved'));
    }
  }

  Future<void> markApprovalNotificationsRead(String id) async {
    await _apiClient.dio.post('/notifications/read-related',
      data: <String, dynamic>{
        'entityType': 'APPROVAL_REQUEST', 'entityId': id,
      },
    );
  }

  /// The existing authenticated Dio interceptor adds the bearer token.
  /// The file endpoint returns binary application/octet-stream.
  Future<List<int>> downloadApprovalAttachment(String fileId) async {
    try {
      final response = await _apiClient.dio.get<List<int>>(
        '/files/${Uri.encodeComponent(fileId)}/download',
        options: Options(responseType: ResponseType.bytes,
          receiveTimeout: const Duration(minutes: 2)),
      );
      if (response.data == null) throw StateError('File is empty');
      return response.data!;
    } on DioException catch (error) {
      throw Exception(_approvalError(error, 'File download failed'));
    }
  }

  /// Edit existing draft/changes-requested request using optimistic revision.
  Future<void> reviseApprovalRequest({
    required String id,
    required int revision,
    required String title,
    required Map<String, dynamic> data,
  }) async {
    try {
      final response = await _apiClient.dio.patch(
        '/approval-requests/${Uri.encodeComponent(id)}',
        data: <String, dynamic>{
          'title': title.trim(), 'data': data, 'revision': revision,
        },
      );
      if (response.data is! Map || response.data['success'] != true) {
        throw StateError('Changes were not saved');
      }
    } on DioException catch (error) {
      throw Exception(_approvalError(error, 'Request update failed'));
    }
  }

  Future<void> submitExistingApproval({
    required String id,
    required int revision,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        '/approval-requests/${Uri.encodeComponent(id)}/submit',
        data: <String, dynamic>{'revision': revision},
      );
      _approvalData(response.data, 'Request submission failed');
    } on DioException catch (error) {
      throw Exception(_approvalError(error, 'Request submission failed'));
    }
  }

  // 2. მოთხოვნაზე მოქმედების შესრულება: დამტკიცება/უარყოფა (POST /approval-requests/:id/actions)
  Future<void> performAction({
    required String requestId,
    required String action, // APPROVE, REJECT, REQUEST_CHANGES
    String? comment,
  }) async {
    try {
      await _apiClient.dio.post(
        '/approval-requests/$requestId/actions',
        data: {
          'action': action,
          'comment': ?comment,
        },
      );
    } on DioException catch (e) {
      throw Exception(e.response?.data['error']['message'] ?? 'მოქმედება ვერ შესრულდა');
    }
  }
}