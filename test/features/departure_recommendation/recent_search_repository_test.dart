import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/recent_journey_search.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/recent_search_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late SqliteRecentSearchRepository repository;

  setUpAll(sqfliteFfiInit);

  setUp(() {
    repository = SqliteRecentSearchRepository(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
  });

  RecentJourneySearch search({
    String originId = 'origin',
    String destinationId = 'destination',
    DateTime? searchedAt,
  }) {
    return RecentJourneySearch(
      originStopId: originId,
      originStopName: 'Origin $originId',
      destinationStopId: destinationId,
      destinationStopName: 'Destination $destinationId',
      searchedAt: searchedAt ?? DateTime.utc(2026, 8, 21),
    );
  }

  test('recent search maps to and from SQLite values', () {
    final original = search();
    final mapped = RecentJourneySearch.fromMap({'id': 7, ...original.toMap()});

    expect(mapped.id, 7);
    expect(mapped.originStopId, original.originStopId);
    expect(mapped.destinationStopName, original.destinationStopName);
    expect(mapped.searchedAt, original.searchedAt);
  });

  test('retrieves newest searches and deduplicates the same journey', () async {
    await repository.saveRecentSearch(
      search(searchedAt: DateTime.utc(2026, 8, 20)),
    );
    await repository.saveRecentSearch(
      search(searchedAt: DateTime.utc(2026, 8, 21)),
    );
    await repository.saveRecentSearch(
      search(originId: 'other', searchedAt: DateTime.utc(2026, 8, 22)),
    );

    final searches = await repository.getRecentSearches();
    expect(searches, hasLength(2));
    expect(searches.first.originStopId, 'other');
    expect(searches.last.searchedAt, DateTime.utc(2026, 8, 21));
  });

  test('clears recent searches', () async {
    await repository.saveRecentSearch(search());
    await repository.clearRecentSearches();

    expect(await repository.getRecentSearches(), isEmpty);
  });
}
