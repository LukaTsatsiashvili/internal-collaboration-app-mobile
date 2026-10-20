import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiClient {
  late final Dio dio;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  // Flutter API and the Univer WebView use this same HTTPS server.
  // The default works when the server runs the web/API dev-luka branch on
  // collaboration.gtexshop.ge. Override only for a different test server.
  static const String baseUrl = String.fromEnvironment(
    'COLLAB_API_BASE_URL',
    defaultValue: 'https://collaboration.gtexshop.ge/api/v1',
  ); 

  ApiClient() {
    // Dio sets application/json for Map bodies and multipart for FormData.
    // Do not force JSON on bodyless requests (notably DELETE /drive/:id).
    dio = Dio(defaultOptions());

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

  /// Match the Web client: Content-Type is selected from the request body.
  /// Keeping this separate also lets regression tests assert the defaults.
  static BaseOptions defaultOptions() => BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      );

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
    // A multipart stream can be sent once. On token refresh clone the form
    // before retrying, otherwise Dio throws "Cannot finalize" after 401.
    final originalData = requestOptions.data;
    final retryData = originalData is FormData
        ? originalData.clone()
        : originalData;
    final headers = Map<String, dynamic>.from(requestOptions.headers);
    if (retryData is FormData) {
      // The cloned form has its own multipart boundary.
      headers.removeWhere(
        (key, _) => key.toLowerCase() == Headers.contentTypeHeader,
      );
    }
    final options = Options(
      method: requestOptions.method,
      headers: headers,
      sendTimeout: requestOptions.sendTimeout,
      receiveTimeout: requestOptions.receiveTimeout,
      responseType: requestOptions.responseType,
    );
    return dio.request<dynamic>(
      requestOptions.path,
      data: retryData,
      queryParameters: requestOptions.queryParameters,
      options: options,
    );
  }
}