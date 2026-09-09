import 'package:government_transit_collector/features/departure_recommendation/data/recent_journey_search.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart' as sqflite;

abstract interface class RecentSearchRepository {
  Future<List<RecentJourneySearch>> getRecentSearches();
  Future<void> saveRecentSearch(RecentJourneySearch search);
  Future<void> deleteRecentSearch(int id);
  Future<void> clearRecentSearches();
}

class SqliteRecentSearchRepository implements RecentSearchRepository {
  SqliteRecentSearchRepository({
    sqflite.DatabaseFactory? databaseFactory,
    this.databasePath,
    this.userId,
  }) : _databaseFactory = databaseFactory ?? sqflite.databaseFactory;

  static const String _table = 'recent_journey_searches';
  static const int historyLimit = 10;

  final sqflite.DatabaseFactory _databaseFactory;
  final String? databasePath;
  final String? userId;
  sqflite.Database? _database;

  Future<sqflite.Database> get _db async {
    final existing = _database;
    if (existing != null) return existing;
    final resolvedDatabasePath =
        databasePath ??
        path.join(
          await _databaseFactory.getDatabasesPath(),
          userId == null
              ? 'government_transit_local.db'
              : 'government_transit_${Uri.encodeComponent(userId!)}.db',
        );
    return _database = await _databaseFactory.openDatabase(
      resolvedDatabasePath,
      options: sqflite.OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE $_table (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              origin_stop_id TEXT NOT NULL,
              origin_stop_name TEXT NOT NULL,
              destination_stop_id TEXT NOT NULL,
              destination_stop_name TEXT NOT NULL,
              searched_at TEXT NOT NULL
            )
          ''');
        },
      ),
    );
  }

  @override
  Future<List<RecentJourneySearch>> getRecentSearches() async {
    final db = await _db;
    final rows = await db.query(
      _table,
      orderBy: 'searched_at DESC, id DESC',
      limit: historyLimit,
    );
    return rows.map(RecentJourneySearch.fromMap).toList(growable: false);
  }

  @override
  Future<void> saveRecentSearch(RecentJourneySearch search) async {
    final db = await _db;
    await db.transaction((transaction) async {
      await transaction.delete(
        _table,
        where: 'origin_stop_id = ? AND destination_stop_id = ?',
        whereArgs: [search.originStopId, search.destinationStopId],
      );
      await transaction.insert(_table, search.toMap());
      await transaction.rawDelete('''
        DELETE FROM $_table
        WHERE id NOT IN (
          SELECT id FROM $_table
          ORDER BY searched_at DESC, id DESC
          LIMIT $historyLimit
        )
      ''');
    });
  }

  @override
  Future<void> clearRecentSearches() async {
    final db = await _db;
    await db.delete(_table);
  }

  @override
  Future<void> deleteRecentSearch(int id) async {
    final db = await _db;
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }
}
