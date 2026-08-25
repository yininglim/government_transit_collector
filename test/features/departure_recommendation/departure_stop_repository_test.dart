import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/departure_stop_repository.dart';

void main() {
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
