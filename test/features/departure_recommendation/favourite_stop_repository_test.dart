import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/departure_stop_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/favourite_stop_repository.dart';

void main() {
  test(
    'favourite stops persist, deduplicate and remove only for their owner',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'favourite_stops_test',
      );
      final file = '${directory.path}/favourites.db';
      FavouriteStopRepository repository(String user) =>
          FavouriteStopRepository(
            userId: user,
            factory: databaseFactoryFfi,
            databasePath: file,
          );
      final first = repository('first');
      final second = repository('second');
      const stop = DepartureStop(id: 'gtfs-stop', name: 'Bus Stop');
      try {
        await first.save(stop);
        await first.save(stop);
        expect((await repository('first').load()).single.id, stop.id);
        expect(await second.load(), isEmpty);
        await second.save(stop);
        await first.remove(stop.id);
        expect(await repository('first').load(), isEmpty);
        expect((await second.load()).single.id, stop.id);
      } finally {
        final db = await databaseFactoryFfi.openDatabase(file);
        await db.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
