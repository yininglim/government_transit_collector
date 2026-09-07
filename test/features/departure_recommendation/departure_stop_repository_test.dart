import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/departure_stop_repository.dart';

void main() {
  test(
    'exact ID lookup bypasses name search and handles removed or missing stops',
    () async {
      final queries = <Map<String, String>>[];
      final client = SupabaseClient(
        'https://example.test',
        'key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          queries.add(request.url.queryParameters);
          final id = request.url.queryParameters['stop_id'];
          return http.Response(
            jsonEncode(
              id == 'eq.Exact-ID'
                  ? [
                      {'stop_id': 'Exact-ID', 'stop_name': 'Current name'},
                    ]
                  : [],
            ),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      final repository = SupabaseDepartureStopRepository(client: client);
      final stop = await repository.getStopById('Exact-ID');
      expect(stop?.id, 'Exact-ID');
      expect(stop?.name, 'Current name');
      expect(queries.single['stop_id'], 'eq.Exact-ID');
      expect(queries.single.containsKey('stop_name'), isFalse);
      expect(await repository.getStopById('removed'), isNull);
      expect(await repository.getStopById(' '), isNull);
      expect(queries, hasLength(2));
    },
  );

  test(
    'normalizes search and applies the result limit after filtering',
    () async {
      final allStops = [
        for (var index = 0; index < 80; index++)
          DepartureStop(id: 'early-$index', name: 'Alpha Stop $index'),
        const DepartureStop(id: 'late-987', name: 'ZY Motorsport'),
      ];
      String? observedQuery;
      int? observedLimit;
      var queryCount = 0;
      final repository = SupabaseDepartureStopRepository(
        query: (query, limit) async {
          queryCount++;
          observedQuery = query;
          observedLimit = limit;
          return allStops
              .where((stop) => stop.name.toLowerCase().contains(query))
              .take(limit)
              .toList();
        },
      );

      final result = await repository.searchStops('  Zy MoToR  ');

      expect(result.single.id, 'late-987');
      expect(observedQuery, 'zy motor');
      expect(observedLimit, SupabaseDepartureStopRepository.resultLimit);

      final cached = await repository.searchStops('ZY MOTOR');
      expect(cached.single.id, 'late-987');
      expect(queryCount, 1);
    },
  );

  test('result limit is respected', () async {
    final repository = SupabaseDepartureStopRepository(
      query: (_, limit) async => List.generate(
        limit,
        (index) => DepartureStop(id: '$index', name: 'Stop $index'),
      ),
    );

    final result = await repository.searchStops('stop');

    expect(result, hasLength(SupabaseDepartureStopRepository.resultLimit));
  });

  test('different stop IDs are never collapsed by duplicate name', () async {
    final repository = SupabaseDepartureStopRepository(
      query: (_, _) async => const [
        DepartureStop(id: 'a', name: 'Shared Stop'),
        DepartureStop(id: 'b', name: 'Shared Stop'),
      ],
    );

    final result = await repository.searchStops('shared');

    expect(result.map((stop) => stop.id), ['a', 'b']);
  });
}
