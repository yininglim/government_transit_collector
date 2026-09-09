import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:government_transit_collector/features/authentication/data/auth_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/saved_journey_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/departure_stop_repository.dart';

Future<SupabaseClient> signedClient(List<http.Request> requests) async {
  String encode(Map<String, dynamic> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final token =
      '${encode({'alg': 'HS256', 'typ': 'JWT'})}.${encode({'sub': 'owner', 'role': 'authenticated', 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.test-signature';
  final client = SupabaseClient(
    'https://example.test',
    'test-key',
    httpClient: MockClient((request) async {
      http.Response reply(String body, int status) => http.Response(
        body,
        status,
        request: request,
        headers: {'content-type': 'application/json'},
      );
      requests.add(request);
      if (request.url.path.contains('/auth/')) {
        return reply(
          jsonEncode({
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
          }),
          200,
        );
      }
      if (request.url.path.endsWith('/profiles')) {
        return reply(
          jsonEncode({
            'user_id': 'owner',
            'full_name': 'New Name',
            'role': 'passenger',
          }),
          200,
        );
      }
      if (request.method == 'GET') {
        return reply(
          jsonEncode([
            {
              'search_id': 'saved',
              'saved_name': 'College',
              'origin': {'stop_id': 'a', 'stop_name': 'A'},
              'destination': {'stop_id': 'b', 'stop_name': 'B'},
            },
          ]),
          200,
        );
      }
      return reply('', 204);
    }),
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  await client.auth.signInWithPassword(
    email: 'rider@example.test',
    password: 'test-password',
  );
  return client;
}

void main() {
  test(
    'same authenticated user ID reads identical saved journeys after provider change',
    () async {
      final requests = <http.Request>[];
      final client = await signedClient(requests);
      addTearDown(client.dispose);
      final first = await SupabaseSavedJourneyRepository(client: client).load();
      final session = client.auth.currentSession!.toJson();
      final user = Map<String, dynamic>.from(session['user'] as Map);
      user['app_metadata'] = {
        'provider': 'google',
        'providers': ['email', 'google'],
      };
      session['user'] = user;
      await client.auth.recoverSession(jsonEncode(session));
      final linked = await SupabaseSavedJourneyRepository(
        client: client,
      ).load();
      expect(client.auth.currentUser!.id, 'owner');
      expect(linked.map((j) => j.id), first.map((j) => j.id));
      final reads = requests.where(
        (r) => r.url.path.endsWith('/journey_searches'),
      );
      expect(reads.length, 2);
      expect(
        reads.every((r) => r.url.queryParameters['user_id'] == 'eq.owner'),
        isTrue,
      );
      expect(
        reads.every((r) => !r.url.queryParameters.containsKey('email')),
        isTrue,
      );
    },
  );
  test(
    'name update changes only full_name for the authenticated profile',
    () async {
      final requests = <http.Request>[];
      final client = await signedClient(requests);
      addTearDown(client.dispose);
      final profile = await AuthRepository(
        client: client,
      ).updateFullName(' New Name ');
      expect(profile.fullName, 'New Name');
      expect(profile.email, 'rider@example.test');
      expect(requests.last.method, 'PATCH');
      expect(jsonDecode(requests.last.body), {'full_name': 'New Name'});
      expect(requests.last.url.queryParameters['user_id'], 'eq.owner');
    },
  );
  test(
    'save, load and delete use authenticated owner and existing schema',
    () async {
      final requests = <http.Request>[];
      final client = await signedClient(requests);
      addTearDown(client.dispose);
      final repository = SupabaseSavedJourneyRepository(client: client);
      await repository.save(
        ' College ',
        const DepartureStop(id: 'a', name: 'A'),
        const DepartureStop(id: 'b', name: 'B'),
      );
      final body = jsonDecode(requests.last.body) as Map;
      expect(body['user_id'], 'owner');
      expect(body['saved_name'], 'College');
      expect(body['is_saved'], true);
      expect(body['requested_departure_at'], isNotEmpty);
      expect(body.containsKey('origin_lat'), false);
      final journeys = await repository.load();
      expect(journeys.single.usable, true);
      expect(journeys.single.origin!.id, 'a');
      expect(requests.last.url.queryParameters['user_id'], 'eq.owner');
      expect(requests.last.url.queryParameters['is_saved'], 'eq.true');
      await repository.delete('saved');
      expect(requests.last.method, 'DELETE');
      expect(requests.last.url.queryParameters['user_id'], 'eq.owner');
      expect(requests.last.url.queryParameters['search_id'], 'eq.saved');
    },
  );
  test('signed-out operations are rejected before network access', () async {
    final client = SupabaseClient('https://example.test', 'test-key');
    addTearDown(client.dispose);
    final repository = SupabaseSavedJourneyRepository(client: client);
    await expectLater(repository.load(), throwsA(isA<SavedJourneyException>()));
    await expectLater(
      repository.delete('other'),
      throwsA(isA<SavedJourneyException>()),
    );
    await expectLater(
      repository.save(
        'Name',
        const DepartureStop(id: 'a', name: 'A'),
        const DepartureStop(id: 'b', name: 'B'),
      ),
      throwsA(isA<SavedJourneyException>()),
    );
  });
}
