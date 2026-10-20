import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiClient {
  late final Dio dio;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  // შეცვალეთ თქვენი ბექენდის რეალური URL-ით (მაგ: ადგილობრივი სერვერი ან დომენი)
  static const String baseUrl = 'https://collaboration.gtexshop.ge/api/v1'; 

  ApiClient() {
    dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    // Interceptor - ავტომატურად ამატებს ტოკენტს და მართავს შეცდომებს
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Fastify rejects an empty request labeled application/json.
          // DELETE /drive/:id has no body, just like the Web request.
          // Keep JSON headers for requests that actually send JSON.
          omitContentTypeForBodylessDelete(options);
        // მახსოვრობიდან/სექიური საწყობიდან ტოკენის წამოღება
          String? token = await _secureStorage.read(key: 'access_token');
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (DioException e, handler) async {
          // თუ ტოკენს ვადა გაუვიდა (401), ვცდილობთ refresh ენდპოინტით განახლებას
          if (e.response?.statusCode == 401) {
            bool refreshed = await _refreshToken();
            if (refreshed) {
              // თავიდან გავიმეოროთ წარუმატებელი მოთხოვნა
              return handler.resolve(await _retry(e.requestOptions));
            }
          }
          return handler.next(e);
        },
      ),
    );
  }

  /// Delete endpoints have no JSON request body. This is also reapplied
  /// during token-refresh retries by the request interceptor.
  static void omitContentTypeForBodylessDelete(RequestOptions options) {
    if (options.method.toUpperCase() != 'DELETE' || options.data != null) {
      return;
    }
    options.headers.removeWhere(
      (key, _) => key.toLowerCase() == Headers.contentTypeHeader,
    );
    options.contentType = null;
  }

  // ტოკენის განახლების მექანიზმი HttpOnly cookie-ს გამოყენებით
  Future<bool> _refreshToken() async {
    try {
      final response = await dio.post('/auth/refresh');
      if (response.statusCode == 200 && response.data['success'] == true) {
        final newToken = response.data['data']['accessToken'];
        await _secureStorage.write(key: 'access_token', value: newToken);
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<Response<dynamic>> _retry(RequestOptions requestOptions) async {
    final options = Options(
      method: requestOptions.method,
      headers: requestOptions.headers,
    );
    return dio.request<dynamic>(
      requestOptions.path,
      data: requestOptions.data,
      queryParameters: requestOptions.queryParameters,
      options: options,
    );
  }
}