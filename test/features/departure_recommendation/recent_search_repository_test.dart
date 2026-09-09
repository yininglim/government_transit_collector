import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'package:government_transit_collector/features/departure_recommendation/data/recent_journey_search.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/recent_search_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late SqliteRecentSearchRepository repository;

  setUpAll(sqfliteFfiInit);

  test(
    'account files isolate new history and preserve legacy history',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'account_history_test',
      );
      final oldPath = await databaseFactoryFfi.getDatabasesPath();
      await databaseFactoryFfi.setDatabasesPath(directory.path);
      try {
        final first = SqliteRecentSearchRepository(
          databaseFactory: databaseFactoryFfi,
          userId: 'first',
        );
        final second = SqliteRecentSearchRepository(
          databaseFactory: databaseFactoryFfi,
          userId: 'second',
        );
        final legacy = SqliteRecentSearchRepository(
          databaseFactory: databaseFactoryFfi,
        );
        final item = RecentJourneySearch(
          originStopId: 'a',
          originStopName: 'A',
          destinationStopId: 'b',
          destinationStopName: 'B',
          searchedAt: DateTime.utc(2026),
        );
        await legacy.saveRecentSearch(item);
        expect(await first.getRecentSearches(), isEmpty);
        await first.saveRecentSearch(item);
        final linkedLogin = SqliteRecentSearchRepository(
          databaseFactory: databaseFactoryFfi,
          userId: 'first',
        );
        expect(
          (await linkedLogin.getRecentSearches()).single.originStopId,
          'a',
        );
        expect(await second.getRecentSearches(), isEmpty);
        await second.clearRecentSearches();
        expect(await first.getRecentSearches(), hasLength(1));
        expect(await legacy.getRecentSearches(), hasLength(1));
      } finally {
        await databaseFactoryFfi.setDatabasesPath(oldPath);
        for (final file in directory.listSync().whereType<File>()) {
          await databaseFactoryFfi.deleteDatabase(file.path);
        }
        await directory.delete();
      }
    },
  );

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

  test(
    'historical missing IDs map safely without inventing IDs from names',
    () {
      final row = search().toMap()
        ..remove('origin_stop_id')
        ..remove('destination_stop_id');
      final mapped = RecentJourneySearch.fromMap(row);
      expect(mapped.originStopId, '');
      expect(mapped.destinationStopId, '');
    },
  );

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
