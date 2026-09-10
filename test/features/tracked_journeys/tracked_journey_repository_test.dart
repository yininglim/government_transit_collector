import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:government_transit_collector/features/tracked_journeys/tracked_journey_repository.dart';
import 'tracked_journey_lifecycle_test.dart' show snapshot;

void main() {
  test(
    'repository scopes reads to signed-in owner and completed status; lifecycle uses atomic RPCs',
    () async {
      final requests = <http.Request>[];
      String encode(Map<String, dynamic> value) =>
          base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
      final token =
          '${encode({'alg': 'HS256'})}.${encode({'sub': 'owner', 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.signature';
      final client = SupabaseClient(
        'https://example.test',
        'key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          requests.add(request);
          final body = request.url.path.contains('/auth/')
              ? jsonEncode({
                  'access_token': token,
                  'refresh_token': 'refresh',
                  'token_type': 'bearer',
                  'expires_in': 3600,
                  'user': {
                    'id': 'owner',
                    'aud': 'authenticated',
                    'role': 'authenticated',
                    'email': 'owner@example.test',
                    'created_at': '2026-01-01T00:00:00Z',
                    'app_metadata': {},
                    'user_metadata': {},
                  },
                })
              : request.method == 'GET'
              ? jsonEncode([
                  {
                    'tracking_session_id': 'tracked',
                    'user_id': 'owner',
                    'status':
                        request.url.queryParameters['status'] == 'eq.completed'
                        ? 'completed'
                        : 'active',
                    'started_at': '2026-09-10T07:00:00Z',
                    'completed_at': '2026-09-10T09:00:00Z',
                    'journey_snapshot': snapshot(transfer: true).toJson(),
                  },
                ])
              : 'null';
          return http.Response(
            body,
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      await client.auth.signInWithPassword(
        email: 'owner@example.test',
        password: 'password',
      );
      final repository = SupabaseTrackedJourneyRepository(
        userId: 'owner',
        supabaseClient: client,
      );
      expect((await repository.active())!.snapshot.tracking.legs.length, 2);
      expect((await repository.completed()).single.status, 'completed');
      final reads = requests.where((r) => r.method == 'GET').toList();
      expect(
        reads.every((r) => r.url.queryParameters['user_id'] == 'eq.owner'),
        isTrue,
      );
      expect(reads.last.url.queryParameters['status'], 'eq.completed');
      await repository.start(snapshot(), replaceId: 'tracked');
      expect(requests.last.url.path, endsWith('/rpc/start_passenger_journey'));
      expect(jsonDecode(requests.last.body), {
        'p_snapshot': snapshot().toJson(),
        'p_replace_id': 'tracked',
      });
      await repository.finish('tracked', completed: true);
      expect(jsonDecode(requests.last.body), {
        'p_id': 'tracked',
        'p_completed': true,
      });
      await repository.finish('tracked', completed: false);
      expect(jsonDecode(requests.last.body), {
        'p_id': 'tracked',
        'p_completed': false,
      });
      final count = requests.length;
      final other = SupabaseTrackedJourneyRepository(
        userId: 'other',
        supabaseClient: client,
      );
      await expectLater(other.completed(), throwsStateError);
      await expectLater(other.start(snapshot()), throwsStateError);
      expect(requests.length, count);
    },
  );
}
