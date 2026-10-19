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