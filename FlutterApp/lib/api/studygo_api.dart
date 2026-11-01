import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

class ApiException implements Exception {
  ApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;
  @override
  String toString() => message;
}

class StudyGoApi {
  StudyGoApi({required this.baseUrl});
  final String baseUrl;
  final _storage = const FlutterSecureStorage();
  String? _accessToken;
  String? _refreshToken;
  Map<String, dynamic>? user;

  Future<void> restore() async {
    _accessToken = await _storage.read(key: 'access_token');
    _refreshToken = await _storage.read(key: 'refresh_token');
  }

  Future<void> resume() async {
    if (_accessToken == null && _refreshToken == null) return;
    try {
      final result = await _request('GET', '/api/v1/auth/me');
      user = (result['user'] as Map?)?.cast<String, dynamic>();
    } catch (_) {
      user = null;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
    bool retry = true,
  }) async {
    Future<http.Response> send() async {
      final headers = <String, String>{'Accept': 'application/json', 'X-Device-Label': 'StudyGo Flutter'};
      if (body != null) headers['Content-Type'] = 'application/json';
      if (auth && _accessToken != null) headers['Authorization'] = 'Bearer $_accessToken';
      final uri = Uri.parse('$baseUrl$path');
      switch (method) {
        case 'POST': return http.post(uri, headers: headers, body: jsonEncode(body ?? {}));
        case 'PATCH': return http.patch(uri, headers: headers, body: jsonEncode(body ?? {}));
        case 'DELETE': return http.delete(uri, headers: headers);
        default: return http.get(uri, headers: headers);
      }
    }

    var response = await send();
    if (response.statusCode == 401 && auth && retry && _refreshToken != null) {
      await refresh();
      response = await send();
    }
    final decoded = response.body.isEmpty ? <String, dynamic>{} :
        (jsonDecode(response.body) as Map).cast<String, dynamic>();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, decoded['error']?.toString() ?? 'request_failed');
    }
    return decoded;
  }

  Future<void> login(String email, String password) async {
    final result = await _request('POST', '/api/v1/auth/login',
        auth: false, body: {'email': email, 'password': password});
    await _saveTokens(result);
    user = (result['user'] as Map?)?.cast<String, dynamic>();
  }

  Future<void> register(String name, String email, String password) async {
    await _request('POST', '/api/v1/auth/register', auth: false,
        body: {'displayName': name, 'email': email, 'password': password});
  }

  Future<void> refresh() async {
    if (_refreshToken == null) throw ApiException(401, 'session_expired');
    final result = await _request('POST', '/api/v1/auth/refresh', auth: false,
        retry: false, body: {'refreshToken': _refreshToken});
    await _saveTokens(result);
    user = (result['user'] as Map?)?.cast<String, dynamic>();
  }

  Future<void> _saveTokens(Map<String, dynamic> result) async {
    _accessToken = result['accessToken']?.toString();
    _refreshToken = result['refreshToken']?.toString();
    if (_accessToken == null || _refreshToken == null) throw ApiException(500, 'invalid_token_response');
    await _storage.write(key: 'access_token', value: _accessToken);
    await _storage.write(key: 'refresh_token', value: _refreshToken);
  }

  Future<void> logout() async {
    try {
      await _request('POST', '/api/v1/auth/logout', body: {'refreshToken': _refreshToken});
    } finally {
      _accessToken = null; _refreshToken = null; user = null;
      await _storage.delete(key: 'access_token'); await _storage.delete(key: 'refresh_token');
    }
  }

  Future<List<dynamic>> subjects() async => (await _request('GET', '/api/v1/subjects'))['subjects'] as List<dynamic>;
  Future<Map<String, dynamic>> quota() => _request('GET', '/api/v1/ai/quota');
  Future<String> ask(String question) async {
    final result = await _request('POST', '/api/v1/ai/tutor',
        body: {'question': question, 'requestId': const Uuid().v4()});
    return result['answer'].toString();
  }
  Future<List<dynamic>> tasks() async => (await _request('GET', '/api/v1/planner/tasks'))['tasks'] as List<dynamic>;
  Future<Map<String, dynamic>> createTask(String title, {String priority = 'normal'}) async =>
      (await _request('POST', '/api/v1/planner/tasks', body: {'title': title, 'priority': priority}))['task'] as Map<String, dynamic>;
  Future<List<dynamic>> materials() async => (await _request('GET', '/api/v1/materials'))['materials'] as List<dynamic>;
  Future<void> uploadMaterial(PlatformFile file, {String? title}) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/api/v1/materials'));
    request.headers['Authorization'] = 'Bearer $_accessToken';
    if (title != null) request.fields['title'] = title;
    if (file.path != null) {
      request.files.add(await http.MultipartFile.fromPath('file', file.path!));
    } else if (file.bytes != null) {
      request.files.add(http.MultipartFile.fromBytes('file', file.bytes!, filename: file.name));
    } else {
      throw ApiException(400, 'file_not_available');
    }
    var streamed = await request.send();
    if (streamed.statusCode == 401 && _refreshToken != null) {
      await refresh();
      request.headers['Authorization'] = 'Bearer $_accessToken';
      streamed = await request.send();
    }
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw ApiException(streamed.statusCode, 'upload_failed');
    }
  }
  Future<List<dynamic>> notifications() async => (await _request('GET', '/api/v1/notifications'))['notifications'] as List<dynamic>;
  Future<void> markNotificationRead(int id) async => _request('POST', '/api/v1/notifications/$id/read');
  Future<List<dynamic>> sessions() async => (await _request('GET', '/api/v1/auth/sessions'))['sessions'] as List<dynamic>;
  Future<void> revokeSession(String id) async => _request('DELETE', '/api/v1/auth/sessions/$id');
  Future<String> solveImage(File file, String mimeType) async {
    final bytes = await file.readAsBytes();
    final result = await _request('POST', '/api/v1/ai/solve-image', body: {
      'imageBase64': base64Encode(bytes), 'mimeType': mimeType,
      'requestId': const Uuid().v4(),
      'question': 'Baca dan selesaikan soal dalam gambar. Jelaskan langkahnya.'
    });
    return result['answer'].toString();
  }
}
