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