import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';

/// The People directory uses exactly the search/filter contract of prod.
class PeopleService {
  PeopleService({Dio? dio}) : _dio = dio ?? ApiClient().dio;

  final Dio _dio;

  Future<List<Map<String, dynamic>>> getPeople({
    String query = '',
    String? departmentId,
    String? role,
    String? status = 'ACTIVE',
  }) async {
    final params = <String, dynamic>{};
    if (query.trim().isNotEmpty) params['q'] = query.trim();
    if (departmentId != null && departmentId.isNotEmpty) {
      params['departmentId'] = departmentId;
    }
    if (role != null && role.isNotEmpty) params['role'] = role;
    if (status != null && status.isNotEmpty) params['status'] = status;
    final response = await _dio.get<Map<String, dynamic>>(
      '/users',
      queryParameters: params,
    );
    return _extractList(response.data);
  }

  Future<List<Map<String, dynamic>>> getDepartments() async {
    final response = await _dio.get<Map<String, dynamic>>('/departments');
    return _extractList(response.data);
  }

  static List<Map<String, dynamic>> _extractList(
    Map<String, dynamic>? body,
  ) {
    if (body?['success'] != true || body?['data'] is! List) {
      throw const FormatException('Invalid directory response');
    }
    return (body!['data'] as List)
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }
}
