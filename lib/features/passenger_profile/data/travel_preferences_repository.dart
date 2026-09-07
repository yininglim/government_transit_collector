import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

abstract interface class TravelPreferencesRepository {
  Future<int> loadRadius();
  Future<void> saveRadius(int radius);
}

class SqliteTravelPreferencesRepository implements TravelPreferencesRepository {
  SqliteTravelPreferencesRepository({
    required this.userId,
    DatabaseFactory? factory,
    this.databasePath,
  }) : _factory = factory ?? databaseFactory;
  final String userId;
  final DatabaseFactory _factory;
  final String? databasePath;
  Future<Database>? _database;
  Future<Database> get _db async {
    try {
      return await (_database ??= _open());
    } on Object {
      _database = null;
      rethrow;
    }
  }

  Future<Database> _open() async => _factory.openDatabase(
    databasePath ??
        path.join(await _factory.getDatabasesPath(), 'travel_preferences.db'),
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, _) async {
        await db.execute(
          'CREATE TABLE travel_preferences (user_id TEXT PRIMARY KEY, radius INTEGER NOT NULL CHECK (radius IN (500, 1000, 2000)))',
        );
      },
    ),
  );
  @override
  Future<int> loadRadius() async {
    final rows = await (await _db).query(
      'travel_preferences',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    return rows.isEmpty ? 1000 : rows.first['radius'] as int;
  }

  @override
  Future<void> saveRadius(int radius) async {
    if (![500, 1000, 2000].contains(radius)) throw ArgumentError.value(radius);
    await (await _db).insert('travel_preferences', {
      'user_id': userId,
      'radius': radius,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
