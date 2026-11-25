import 'dart:convert';
import 'package:http/http.dart' as base;
import 'package:plexus/core/api_config.dart';

// Drop-in replacement for `package:http/http.dart`.
// Use it with the same alias:  import 'package:plexus/core/http_auth.dart' as http;
// http.get / post / put / delete / patch and http.MultipartRequest then send the login
// token automatically, but ONLY to the PLEXUS API (never to another website).
// Everything else (http.Response, http.MultipartFile, http.Client...) is unchanged.
export 'package:http/http.dart'
    hide get, post, put, delete, patch, MultipartRequest;

/// The current login token. AuthProvider keeps it up to date (login, restore, logout).
class AuthToken {
  static String? value;
}

bool _isOurApi(Uri url) {
  final api = Uri.parse(ApiConfig.baseUrl);
  return url.scheme == api.scheme && url.host == api.host && url.port == api.port;
}

Map<String, String> _withAuth(Uri url, Map<String, String>? headers) {
  final h = <String, String>{...?headers};
  final token = AuthToken.value;
  if (token != null && _isOurApi(url) && !h.containsKey('Authorization')) {
    h['Authorization'] = 'Bearer $token';
  }
  return h;
}

Future<base.Response> get(Uri url, {Map<String, String>? headers}) =>
    base.get(url, headers: _withAuth(url, headers));

Future<base.Response> post(Uri url,
    {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
    base.post(url, headers: _withAuth(url, headers), body: body, encoding: encoding);

Future<base.Response> put(Uri url,
    {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
    base.put(url, headers: _withAuth(url, headers), body: body, encoding: encoding);

Future<base.Response> patch(Uri url,
    {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
    base.patch(url, headers: _withAuth(url, headers), body: body, encoding: encoding);

Future<base.Response> delete(Uri url,
    {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
    base.delete(url, headers: _withAuth(url, headers), body: body, encoding: encoding);

/// Same as http.MultipartRequest, with the login token added when the request goes to our API.
class MultipartRequest extends base.MultipartRequest {
  MultipartRequest(super.method, super.url);

  @override
  Future<base.StreamedResponse> send() {
    final token = AuthToken.value;
    if (token != null && _isOurApi(url) && !headers.containsKey('Authorization')) {
      headers['Authorization'] = 'Bearer $token';
    }
    return super.send();
  }
}
