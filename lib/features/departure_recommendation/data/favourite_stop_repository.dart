import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'departure_stop_repository.dart';

class FavouriteStopRepository {
  FavouriteStopRepository({
    required this.userId,
    DatabaseFactory? factory,
    this.databasePath,
  }) : _factory = factory ?? databaseFactory;

  final String userId;
  final DatabaseFactory _factory;
  final String? databasePath;
  Future<Database>? _database;
  static final _revisions = <String, ValueNotifier<int>>{};
  ValueNotifier<int> get changes =>
      _revisions.putIfAbsent(userId, () => ValueNotifier(0));

  static FavouriteStopRepository? currentUser() {
    try {
      final id = Supabase.instance.client.auth.currentUser?.id;
      return id == null ? null : FavouriteStopRepository(userId: id);
    } on Object {
      return null;
    }
  }

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
        path.join(await _factory.getDatabasesPath(), 'favourite_bus_stops.db'),
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, _) async {
        await db.execute(
          'CREATE TABLE favourite_stops (user_id TEXT NOT NULL, stop_id TEXT NOT NULL, stop_name TEXT NOT NULL, PRIMARY KEY (user_id, stop_id))',
        );
      },
    ),
  );

  Future<List<DepartureStop>> load() async {
    final rows = await (await _db).query(
      'favourite_stops',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'stop_name COLLATE NOCASE, stop_id',
    );
    return rows
        .map(
          (row) => DepartureStop(
            id: row['stop_id'] as String,
            name: row['stop_name'] as String,
          ),
        )
        .toList();
  }

  Future<void> save(DepartureStop stop) async {
    await (await _db).insert('favourite_stops', {
      'user_id': userId,
      'stop_id': stop.id,
      'stop_name': stop.name,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    changes.value++;
  }

  Future<void> remove(String stopId) async {
    await (await _db).delete(
      'favourite_stops',
      where: 'user_id = ? AND stop_id = ?',
      whereArgs: [userId, stopId],
    );
    changes.value++;
  }
}
