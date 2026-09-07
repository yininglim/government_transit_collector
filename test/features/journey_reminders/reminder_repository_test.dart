import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:government_transit_collector/features/journey_reminders/reminder_repository.dart';
import 'journey_reminders_test.dart' show journey, now;

void main() {
  test(
    'Supabase writes authenticated owner, filters reads/deletes and resolves unique conflicts',
    () async {
      final requests = <http.Request>[];
      Map<String, dynamic>? stored;
      var duplicate = false;
      String encode(Map<String, dynamic> value) =>
          base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
      final token =
          '${encode({'alg': 'HS256', 'typ': 'JWT'})}.${encode({'sub': 'owner', 'role': 'authenticated', 'exp': 4102444800})}.signature';
      final client = SupabaseClient(
        'https://example.test',
        'key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          requests.add(request);
          http.Response reply(Object body, [int status = 200]) => http.Response(
            jsonEncode(body),
            status,
            headers: {'content-type': 'application/json'},
            request: request,
          );
          if (request.url.path.contains('/auth/')) {
            return reply({
              'access_token': token,
              'refresh_token': 'refresh',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': {
                'id': 'owner',
                'aud': 'authenticated',
                'role': 'authenticated',
                'email': 'rider@example.test',
                'created_at': '2026-01-01T00:00:00Z',
                'app_metadata': {},
                'user_metadata': {},
              },
            });
          }
          if (request.method == 'POST') {
            if (duplicate) {
              return reply({
                'code': '23505',
                'message': 'unique violation',
                'details': '',
                'hint': '',
              }, 409);
            }
            stored = {
              ...jsonDecode(request.body) as Map<String, dynamic>,
              'reminder_id': 42,
            };
            return reply(stored!, 201);
          }
          if (request.method == 'DELETE') return http.Response('', 204, request: request);
          return reply(
            request.url.queryParameters.containsKey('journey_key')
                ? stored!
                : [stored!],
          );
        }),
      );
      addTearDown(client.dispose);
      await client.auth.signInWithPassword(
        email: 'rider@example.test',
        password: 'password',
      );
      final repository = SupabaseReminderRepository(client);
      final record = await repository.create(journey(), 10, now);
      expect(record.owner, 'owner');
      expect(stored!['user_id'], 'owner');
      expect(stored!['origin_stop_id'], 'larkin');
      expect(stored!['scheduled_departure_seconds'], 57300);
      await repository.load();
      expect(requests.last.url.queryParameters['user_id'], 'eq.owner');
      expect(
        requests.last.url.queryParameters['scheduled_departure_at'],
        startsWith('gt.'),
      );
      duplicate = true;
      final same = await repository.create(journey(), 5, now);
      expect(same.id, 42);
      expect(requests.last.url.queryParameters['user_id'], 'eq.owner');
      expect(
        requests.last.url.queryParameters['journey_key'],
        'eq.${journey().key}',
      );
      await repository.delete(42);
      expect(requests.last.url.queryParameters['user_id'], 'eq.owner');
      expect(requests.last.url.queryParameters['reminder_id'], 'eq.42');
    },
  );

  test(
    'signed-out Supabase repository refuses all reminder operations',
    () async {
      final client = SupabaseClient('https://example.test', 'key');
      addTearDown(client.dispose);
      final repository = SupabaseReminderRepository(client);
      await expectLater(repository.load(), throwsException);
      await expectLater(repository.create(journey(), 10, now), throwsException);
      await expectLater(repository.delete(42), throwsException);
    },
  );
}
