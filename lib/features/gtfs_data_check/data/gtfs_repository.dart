import 'package:supabase_flutter/supabase_flutter.dart';

class GtfsRoute {
  const GtfsRoute({
    required this.id,
    required this.shortName,
    required this.longName,
  });

  final String id;
  final String? shortName;
  final String? longName;

  String get displayName {
    final short = shortName?.trim() ?? '';
    final long = longName?.trim() ?? '';
    if (short.isNotEmpty && long.isNotEmpty) return '$short - $long';
    if (short.isNotEmpty) return short;
    if (long.isNotEmpty) return long;
    return id;
  }

  bool matches(String query) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return true;
    return id.toLowerCase().contains(normalizedQuery) ||
        (shortName?.toLowerCase().contains(normalizedQuery) ?? false) ||
        (longName?.toLowerCase().contains(normalizedQuery) ?? false);
  }
}

class GtfsStop {
  const GtfsStop({
    required this.id,
    required this.name,
    required this.sequence,
  });

  final String id;
  final String name;
  final int sequence;
}

class GtfsRepository {
  GtfsRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  static const int displayedStopLimit = 24;
  static const int _stopCandidateLimit = 200;

  final SupabaseClient _client;

  Future<List<GtfsRoute>> fetchRoutes() async {
    try {
      final data = await _client
          .from('gtfs_routes')
          .select('route_id, route_short_name, route_long_name')
          .order('route_short_name')
          .order('route_long_name');

      return data
          .map(
            (row) => GtfsRoute(
              id: row['route_id'] as String,
              shortName: row['route_short_name'] as String?,
              longName: row['route_long_name'] as String?,
            ),
          )
          .toList(growable: false);
    } on PostgrestException catch (error) {
      throw GtfsReadException(
        error.message.isEmpty ? 'Unable to load routes.' : error.message,
      );
    } on Object {
      throw const GtfsReadException('Unable to load routes.');
    }
  }

  Future<List<GtfsStop>> fetchStopsForRoute(String routeId) async {
    try {
      final data = await _client
          .from('gtfs_stop_times')
          .select(
            'trip_id, stop_sequence, '
            'gtfs_trips!inner(route_id), '
            'gtfs_stops!inner(stop_id, stop_name)',
          )
          .eq('gtfs_trips.route_id', routeId)
          .order('trip_id')
          .order('stop_sequence')
          .limit(_stopCandidateLimit);

      final uniqueStops = <String, GtfsStop>{};
      for (final row in data) {
        final stop = row['gtfs_stops'];
        if (stop is! Map<String, dynamic>) continue;
        final stopId = stop['stop_id'];
        final stopName = stop['stop_name'];
        final sequence = row['stop_sequence'];
        if (stopId is! String || stopName is! String || sequence is! int) {
          continue;
        }
        uniqueStops.putIfAbsent(
          stopId,
          () => GtfsStop(id: stopId, name: stopName, sequence: sequence),
        );
        if (uniqueStops.length == displayedStopLimit) break;
      }
      return uniqueStops.values.toList(growable: false);
    } on PostgrestException catch (error) {
      throw GtfsReadException(
        error.message.isEmpty
            ? 'Unable to load stops for this route.'
            : error.message,
      );
    } on Object {
      throw const GtfsReadException('Unable to load stops for this route.');
    }
  }
}

class GtfsReadException implements Exception {
  const GtfsReadException(this.message);

  final String message;

  @override
  String toString() => message;
}
