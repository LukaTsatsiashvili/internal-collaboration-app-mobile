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