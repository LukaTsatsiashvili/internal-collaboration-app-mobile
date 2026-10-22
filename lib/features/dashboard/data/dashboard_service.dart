import '../../../core/network/api_client.dart';

class DashboardService {
  final ApiClient _apiClient = ApiClient();

  // 1. მომხმარებლის პროფილის წამოღება
  Future<Map<String, dynamic>?> getUserProfile() async {
    try {
      final response = await _apiClient.dio.get('/auth/me');
      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data['data'];
      }
    } catch (_) {}
    return null;
  }

  // 2. დაშბორდის სტატისტიკა / მეტრიკები
  Future<Map<String, dynamic>> getDashboardMetrics() async {
    try {
      // პარალელურად ვქაჩავთ დავალებებს და მოთხოვნებს, რომ დავთვალოთ რაოდენობები
      final tasksResponse = await _apiClient.dio.get('/tasks');
      final approvalsResponse = await _apiClient.dio.get('/approval-requests');

      int activeTasks = 0;
      int pendingApprovals = 0;

      if (tasksResponse.statusCode == 200 && tasksResponse.data['success'] == true) {
        final List tasks = tasksResponse.data['data'];
        activeTasks = tasks.where((t) => t['status'] == 'IN_PROGRESS' || t['status'] == 'OPEN').length;
      }

      if (approvalsResponse.statusCode == 200 && approvalsResponse.data['success'] == true) {
        final List approvals = approvalsResponse.data['data'];
        pendingApprovals = approvals.where((a) => a['status'] == 'PENDING').length;
      }

      return {
        'activeTasks': activeTasks.toString(),
        'pendingApprovals': pendingApprovals.toString(),
      };
    } catch (_) {
      // An unavailable API is not evidence of zero active tasks or approvals.
      rethrow;
    }
  }
}