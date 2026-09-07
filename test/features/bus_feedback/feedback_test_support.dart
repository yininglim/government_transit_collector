import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

http.Response jsonResponse(Object? body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Future<SupabaseClient> feedbackClient(
  Future<http.Response> Function(http.Request) handle, {
  String owner = 'owner',
  bool signIn = true,
}) async {
  String encode(Map<String, dynamic> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final token =
      '${encode({'alg': 'HS256', 'typ': 'JWT'})}.${encode({'sub': owner, 'role': 'authenticated', 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.signature';
  final client = SupabaseClient(
    'https://example.test',
    'test-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient((request) async {
      if (request.url.path.contains('/auth/')) {
        return jsonResponse({
          'access_token': token,
          'refresh_token': 'refresh',
          'token_type': 'bearer',
          'expires_in': 3600,
          'user': {
            'id': owner,
            'aud': 'authenticated',
            'role': 'authenticated',
            'email': 'rider@example.test',
            'created_at': '2026-01-01T00:00:00Z',
            'app_metadata': {},
            'user_metadata': {},
          },
        });
      }
      final response = await handle(request);
      return http.Response.bytes(
        response.bodyBytes,
        response.statusCode,
        headers: response.headers,
        request: request,
      );
    }),
  );
  if (signIn) {
    await client.auth.signInWithPassword(
      email: 'rider@example.test',
      password: 'test-password',
    );
  }
  return client;
}
