import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MemoryAuthStorage extends GotrueAsyncStorage {
  final values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    values.remove(key);
  }
}

// Synthetic fixtures only. No live credentials or auth requests.
class AuthBackend {
  final requests = <http.Request>[];
  final storage = MemoryAuthStorage();
  String role = 'passenger';
  bool google = true;
  String sessionMethod = 'password';
  bool emailIdentity = false;
  bool obfuscatedSignup = false;
  String? signupErrorCode;
  String? loginErrorCode;
  String? updateErrorCode;
  String? recoveryErrorCode;
  bool missingProfile = false;
  bool failProfile = false;
  bool failExchange = false;
  bool failRecovery = false;
  int updateStatus = 200;
  late final SupabaseClient client = SupabaseClient(
    'https://auth.example.test',
    'test-key',
    authOptions: AuthClientOptions(
      autoRefreshToken: false,
      authFlowType: AuthFlowType.pkce,
      pkceAsyncStorage: storage,
    ),
    httpClient: MockClient(_respond),
  );

  Map<String, dynamic> get user => {
    'id': 'authenticated-owner',
    'aud': 'authenticated',
    'email': 'owner@example.test',
    'role': 'authenticated',
    'created_at': '2026-01-01T00:00:00Z',
    'app_metadata': {'provider': google ? 'google' : 'email'},
    'user_metadata': {'full_name': 'Google Name', 'role': 'admin'},
    'identities': [
      if (!google || emailIdentity)
        {
          'id': 'authenticated-owner',
          'identity_id': 'email-identity',
          'user_id': 'authenticated-owner',
          'provider': 'email',
          'created_at': '2026-01-01T00:00:00Z',
        },
      if (google)
        {
          'id': 'google-subject',
          'identity_id': 'identity',
          'user_id': 'authenticated-owner',
          'provider': 'google',
          'created_at': '2026-01-01T00:00:00Z',
        },
    ],
  };

  Map<String, dynamic> get session {
    String encode(Object data) =>
        base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
    final token =
        '${encode({'alg': 'HS256'})}.${encode({
          'sub': 'authenticated-owner',
          'role': 'authenticated',
          'amr': [
            {'method': sessionMethod, 'timestamp': 1},
          ],
          'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
        })}.test-signature';
    return {
      'access_token': token,
      'refresh_token': 'test-refresh',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': user,
    };
  }

  Future<http.Response> _respond(http.Request request) async {
    requests.add(request);
    http.Response reply(Object? data, [int status = 200]) => http.Response(
      jsonEncode(data),
      status,
      request: request,
      headers: {
        'content-type': 'application/json',
        'x-supabase-api-version': '2024-01-01',
      },
    );
    switch (request.url.path) {
      case '/auth/v1/token':
        if (loginErrorCode != null) {
          return reply({
            'code': loginErrorCode,
            'message': 'private server details',
          }, 400);
        }
        if (failExchange) {
          return reply({'message': 'sensitive backend error'}, 400);
        }
        return reply(session);
      case '/auth/v1/signup':
        if (signupErrorCode != null) {
          return reply({
            'code': signupErrorCode,
            'message': 'private server details',
          }, 422);
        }
        if (obfuscatedSignup) return reply({...user, 'identities': []});
        return reply(session);
      case '/auth/v1/recover':
        if (recoveryErrorCode != null) {
          return reply({
            'code': recoveryErrorCode,
            'message': 'private server details',
          }, 422);
        }
        return failRecovery
            ? reply({'message': 'email does not exist'}, 400)
            : reply({});
      case '/auth/v1/user':
        if (updateErrorCode != null) {
          return reply({
            'code': updateErrorCode,
            'message': 'private server details',
          }, 422);
        }
        return updateStatus == 200
            ? reply(user)
            : reply({'message': 'expired secret'}, updateStatus);
      case '/auth/v1/logout':
        return reply({});
      case '/rest/v1/profiles':
        if (failProfile) {
          return reply({'message': 'sensitive database details'}, 403);
        }
        return reply(
          missingProfile
              ? null
              : {
                  'user_id': 'authenticated-owner',
                  'full_name': 'Existing Name',
                  'role': role,
                },
        );
      case '/rest/v1/rpc/ensure_current_google_profile':
        missingProfile = false;
        role = 'passenger';
        return reply(null);
      default:
        throw StateError('Unexpected test request: ${request.url.path}');
    }
  }

  Future<void> signIn() async {
    await client.auth.signInWithPassword(
      email: 'owner@example.test',
      password: 'password123',
    );
    requests.clear();
  }
}
