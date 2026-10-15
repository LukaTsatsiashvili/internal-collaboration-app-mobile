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