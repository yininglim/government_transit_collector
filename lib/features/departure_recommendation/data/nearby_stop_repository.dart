import 'dart:math' as math;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/departure_stop_repository.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_models.dart';
import 'package:government_transit_collector/features/passenger_location/data/passenger_location.dart';
import 'package:government_transit_collector/features/passenger_location/data/boarding_stop_distance.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/route_geometry.dart'
    show earthRadiusMeters;

bool validCoordinates(double latitude, double longitude) =>
    latitude.isFinite &&
    longitude.isFinite &&
    latitude.abs() <= 90 &&
    longitude.abs() <= 180;

class NearbyStop {
  const NearbyStop(this.stop, this.distanceMeters);
  final DepartureStop stop;
  final double distanceMeters;
}

abstract interface class NearbyStopRepository {
  Future<List<NearbyStop>> findNearby(
    PassengerLocation location,
    int radiusMeters,
  );
}

typedef NearbyStopPageQuery =
    Future<List<Map<String, dynamic>>> Function(
      double minLatitude,
      double maxLatitude,
      int offset,
      int limit,
    );

class SupabaseNearbyStopRepository implements NearbyStopRepository {
  SupabaseNearbyStopRepository({this._client, this._query});
  final SupabaseClient? _client;
  final NearbyStopPageQuery? _query;
  static const pageSize = 500;

  @override
  Future<List<NearbyStop>> findNearby(
    PassengerLocation location,
    int radiusMeters,
  ) async {
    if (!validCoordinates(location.latitude, location.longitude) ||
        ![500, 1000, 2000].contains(radiusMeters)) {
      throw const DepartureStopReadException(
        'Invalid location or search radius.',
      );
    }
    // A latitude band is a conservative spherical bound, including at poles and
    // across the date line. Page the complete band before distance filtering.
    final delta = radiusMeters / earthRadiusMeters * 180 / math.pi;
    final minLat = math.max(-90.0, location.latitude - delta);
    final maxLat = math.min(90.0, location.latitude + delta);
    final results = <String, NearbyStop>{};
    try {
      for (var offset = 0; ; offset += pageSize) {
        final rows = _query != null
            ? await _query(minLat, maxLat, offset, pageSize)
            : await (_client ?? Supabase.instance.client)
                  .from('gtfs_stops')
                  .select('stop_id, stop_name, stop_lat, stop_lon')
                  .eq('location_type', 0)
                  .gte('stop_lat', minLat)
                  .lte('stop_lat', maxLat)
                  .order('stop_id')
                  .range(offset, offset + pageSize - 1);
        for (final row in rows) {
          final lat = row['stop_lat'] is num
              ? (row['stop_lat'] as num).toDouble()
              : null;
          final lon = row['stop_lon'] is num
              ? (row['stop_lon'] as num).toDouble()
              : null;
          final id = row['stop_id'];
          final name = row['stop_name'];
          if (lat == null ||
              lon == null ||
              !validCoordinates(lat, lon) ||
              id is! String ||
              name is! String) {
            continue;
          }
          final distance = passengerDistanceToStopMeters(
            location,
            MapCoordinate(lat, lon),
          );
          if (distance <= radiusMeters) {
            results[id] = NearbyStop(
              DepartureStop(id: id, name: name),
              distance,
            );
          }
        }
        if (rows.length < pageSize) break;
      }
      return results.values.toList()..sort((a, b) {
        final distance = a.distanceMeters.compareTo(b.distanceMeters);
        return distance != 0 ? distance : a.stop.id.compareTo(b.stop.id);
      });
    } on Object {
      throw const DepartureStopReadException(
        'Unable to load nearby stops. Check your connection and try again.',
      );
    }
  }
}
