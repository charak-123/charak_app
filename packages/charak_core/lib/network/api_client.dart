import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:shared_preferences/shared_preferences.dart';

const String _kBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000',  // Android emulator → host localhost
);

class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  /// Called once when the server rejects our credentials (401), after the
  /// stored session has been cleared. Apps wire this to send the user back to
  /// the login screen — without it a token that has expired, or that was
  /// signed with a rotated `JWT_SECRET`, leaves every screen stuck on an
  /// "Invalid or expired token" error with no way out.
  static void Function()? onUnauthorized;

  /// Guards against a burst of concurrent 401s each firing the callback.
  static bool _handlingUnauthorized = false;

  Future<void> _clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('user_id');
    await prefs.remove('user_name');
  }

  Future<String?> _token() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  Future<Map<String, String>> _headers() async {
    final token = await _token();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<dynamic> get(String path) async {
    final res = await http.get(
      Uri.parse('$_kBaseUrl$path'),
      headers: await _headers(),
    );
    return _handle(res);
  }

  Future<dynamic> post(String path, Map<String, dynamic> body) async {
    final res = await http.post(
      Uri.parse('$_kBaseUrl$path'),
      headers: await _headers(),
      body: jsonEncode(body),
    );
    return _handle(res);
  }

  Future<dynamic> patch(String path, Map<String, dynamic> body) async {
    final res = await http.patch(
      Uri.parse('$_kBaseUrl$path'),
      headers: await _headers(),
      body: jsonEncode(body),
    );
    return _handle(res);
  }

  Future<dynamic> put(String path, dynamic body) async {
    final res = await http.put(
      Uri.parse('$_kBaseUrl$path'),
      headers: await _headers(),
      body: jsonEncode(body),
    );
    return _handle(res);
  }

  /// Multipart upload for the `/uploads/*` endpoints.
  ///
  /// These take a real file, not JSON — client-side Storage writes are rejected
  /// because these apps authenticate with a FastAPI JWT rather than a Supabase
  /// auth session, so every file goes through the backend.
  Future<dynamic> postFile(
    String path, {
    required List<int> bytes,
    required String filename,
    String field = 'file',
    String? contentType,
    Map<String, String> fields = const {},
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse('$_kBaseUrl$path'));
    final token = await _token();
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.fields.addAll(fields);
    request.files.add(http.MultipartFile.fromBytes(
      field,
      bytes,
      filename: filename,
      contentType: contentType == null ? null : MediaType.parse(contentType),
    ));
    final streamed = await request.send();
    return _handle(await http.Response.fromStream(streamed));
  }

  Future<void> delete(String path) async {
    final res = await http.delete(
      Uri.parse('$_kBaseUrl$path'),
      headers: await _headers(),
    );
    _handle(res);
  }

  /// Turns an error body into something a human can read.
  ///
  /// FastAPI reports its own `AppError`s as a plain `detail` string, but
  /// *validation* failures (422) return `detail` as a list of
  /// `{loc, msg, type}` objects. Blindly casting that to String threw
  /// "List<dynamic> is not a subtype of String", which hid the actual
  /// validation message behind a type error.
  static String _message(dynamic body, int statusCode) {
    final fallback = 'Request failed ($statusCode)';
    if (body is! Map) return fallback;

    final raw = body['error'] ?? body['detail'];
    if (raw == null) return fallback;
    if (raw is String) return raw;

    if (raw is List) {
      final parts = <String>[];
      for (final item in raw) {
        if (item is Map) {
          final field = (item['loc'] is List)
              // drop the leading "body"/"query" scope segment
              ? (item['loc'] as List).skip(1).join('.')
              : null;
          final detail = item['msg']?.toString() ?? 'invalid';
          parts.add(field == null || field.isEmpty ? detail : '$field: $detail');
        } else {
          parts.add(item.toString());
        }
      }
      if (parts.isNotEmpty) return parts.join('\n');
    }

    return raw.toString();
  }

  dynamic _handle(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.body.isEmpty) return null;
      try {
        return jsonDecode(res.body);
      } on FormatException {
        // A 2xx that is not JSON is still a broken response, but it must
        // arrive as an ApiException like everything else — every call site
        // catches only that.
        throw ApiException('Unexpected response from the server', res.statusCode);
      }
    }

    // Error bodies are not always JSON: a proxy 502/504 or an HTML error page
    // would throw FormatException here, escaping the ApiException contract
    // every screen is written against and surfacing as a red screen instead of
    // a readable message.
    dynamic body = const {};
    if (res.body.isNotEmpty) {
      try {
        body = jsonDecode(res.body);
      } on FormatException {
        body = const {};
      }
    }
    final msg = _message(body, res.statusCode);

    if (res.statusCode == 401 && !_handlingUnauthorized) {
      _handlingUnauthorized = true;
      // Fire-and-forget: drop the dead credentials, then let the app redirect.
      _clearSession().whenComplete(() {
        try {
          onUnauthorized?.call();
        } finally {
          _handlingUnauthorized = false;
        }
      });
    }

    throw ApiException(msg, res.statusCode);
  }
}

class ApiException implements Exception {
  final String message;
  final int statusCode;
  const ApiException(this.message, this.statusCode);
  @override
  String toString() => 'ApiException($statusCode): $message';
}
