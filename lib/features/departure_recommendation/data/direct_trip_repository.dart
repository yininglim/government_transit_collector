import 'package:supabase_flutter/supabase_flutter.dart';

class DirectTripMatch {
  const DirectTripMatch({
    required this.tripId,
    required this.routeId,
    required this.routeShortName,
    required this.routeLongName,
    required this.tripHeadsign,
    required this.directionId,
    required this.originStopSequence,
    required this.destinationStopSequence,
  });

  final String tripId;
  final String routeId;
  final String? routeShortName;
  final String? routeLongName;
  final String? tripHeadsign;
  final int? directionId;
  final int originStopSequence;
  final int destinationStopSequence;
}

class DirectRouteResult {
  const DirectRouteResult({
    required this.routeId,
    required this.routeShortName,
    required this.routeLongName,
    required this.tripHeadsign,
    required this.matchingTripIds,
  });

  final String routeId;
  final String? routeShortName;
  final String? routeLongName;
  final String? tripHeadsign;
  final List<String> matchingTripIds;

  int get matchingTripCount => matchingTripIds.length;
}

abstract interface class DirectTripRepository {
  Future<List<DirectRouteResult>> findDirectRoutes({
    required String originStopId,
    required String destinationStopId,
  });
}

List<DirectTripMatch> matchTripsInTravelOrder({
  required List<DirectTripMatch> candidates,
}) {
  return candidates
      .where((trip) => trip.originStopSequence < trip.destinationStopSequence)
      .toList(growable: false);
}

List<DirectRouteResult> groupDirectTripsByRoute(List<DirectTripMatch> matches) {
  final grouped = <String, List<DirectTripMatch>>{};
  for (final match in matches) {
    grouped.putIfAbsent(match.routeId, () => []).add(match);
  }
  final results = grouped.values.map((trips) {
    final first = trips.first;
    final headsign = trips
        .map((trip) => trip.tripHeadsign?.trim())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .firstOrNull;
    return DirectRouteResult(
      routeId: first.routeId,
      routeShortName: first.routeShortName,
      routeLongName: first.routeLongName,
      tripHeadsign: headsign,
      matchingTripIds: trips.map((trip) => trip.tripId).toList(growable: false),
    );
  }).toList();
  results.sort((left, right) {
    final leftName = left.routeShortName ?? left.routeLongName ?? left.routeId;
    final rightName =
        right.routeShortName ?? right.routeLongName ?? right.routeId;
    return leftName.toLowerCase().compareTo(rightName.toLowerCase());
  });
  return results;
}

class SupabaseDirectTripRepository implements DirectTripRepository {
  SupabaseDirectTripRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  static const int _pageSize = 1000;
  static const int _tripIdBatchSize = 100;

  final SupabaseClient _client;

  @override
  Future<List<DirectRouteResult>> findDirectRoutes({
    required String originStopId,
    required String destinationStopId,
  }) async {
    try {
      final originRows = await _loadOriginRows(originStopId);
      if (originRows.isEmpty) return const [];

      final destinationSequences = await _loadDestinationSequences(
        destinationStopId,
        originRows.map((row) => row.tripId).toList(growable: false),
      );
      final candidates = <DirectTripMatch>[];
      for (final origin in originRows) {
        final destinationSequence = destinationSequences[origin.tripId];
        if (destinationSequence == null) continue;
        candidates.add(
          DirectTripMatch(
            tripId: origin.tripId,
            routeId: origin.routeId,
            routeShortName: origin.routeShortName,
            routeLongName: origin.routeLongName,
            tripHeadsign: origin.tripHeadsign,
            directionId: origin.directionId,
            originStopSequence: origin.originStopSequence,
            destinationStopSequence: destinationSequence,
          ),
        );
      }
      return groupDirectTripsByRoute(
        matchTripsInTravelOrder(candidates: candidates),
      );
    } on PostgrestException catch (error) {
      throw DirectTripReadException(
        error.message.isEmpty ? 'Unable to find direct routes.' : error.message,
      );
    } on DirectTripReadException {
      rethrow;
    } on Object {
      throw const DirectTripReadException('Unable to find direct routes.');
    }
  }

  Future<List<_OriginTripRow>> _loadOriginRows(String stopId) async {
    final rows = <_OriginTripRow>[];
    var start = 0;
    while (true) {
      final data = await _client
          .from('gtfs_stop_times')
          .select(
            'trip_id, stop_sequence, '
            'gtfs_trips!inner('
            'trip_id, route_id, trip_headsign, direction_id, '
            'gtfs_routes!inner(route_id, route_short_name, route_long_name)'
            ')',
          )
          .eq('stop_id', stopId)
          .order('trip_id')
          .range(start, start + _pageSize - 1);
      rows.addAll(data.map(_OriginTripRow.fromSupabase));
      if (data.length < _pageSize) break;
      start += _pageSize;
    }
    final earliestByTrip = <String, _OriginTripRow>{};
    for (final row in rows) {
      final current = earliestByTrip[row.tripId];
      if (current == null ||
          row.originStopSequence < current.originStopSequence) {
        earliestByTrip[row.tripId] = row;
      }
    }
    return earliestByTrip.values.toList(growable: false);
  }

  Future<Map<String, int>> _loadDestinationSequences(
    String stopId,
    List<String> tripIds,
  ) async {
    final sequences = <String, int>{};
    for (var start = 0; start < tripIds.length; start += _tripIdBatchSize) {
      final end = (start + _tripIdBatchSize).clamp(0, tripIds.length);
      final batch = tripIds.sublist(start, end);
      final data = await _client
          .from('gtfs_stop_times')
          .select('trip_id, stop_sequence')
          .eq('stop_id', stopId)
          .inFilter('trip_id', batch);
      for (final row in data) {
        final tripId = row['trip_id'] as String;
        final sequence = row['stop_sequence'] as int;
        final current = sequences[tripId];
        if (current == null || sequence > current) {
          sequences[tripId] = sequence;
        }
      }
    }
    return sequences;
  }
}

class _OriginTripRow {
  const _OriginTripRow({
    required this.tripId,
    required this.routeId,
    required this.routeShortName,
    required this.routeLongName,
    required this.tripHeadsign,
    required this.directionId,
    required this.originStopSequence,
  });

  factory _OriginTripRow.fromSupabase(Map<String, dynamic> row) {
    final trip = row['gtfs_trips'] as Map<String, dynamic>;
    final route = trip['gtfs_routes'] as Map<String, dynamic>;
    return _OriginTripRow(
      tripId: row['trip_id'] as String,
      routeId: trip['route_id'] as String,
      routeShortName: route['route_short_name'] as String?,
      routeLongName: route['route_long_name'] as String?,
      tripHeadsign: trip['trip_headsign'] as String?,
      directionId: trip['direction_id'] as int?,
      originStopSequence: row['stop_sequence'] as int,
    );
  }

  final String tripId;
  final String routeId;
  final String? routeShortName;
  final String? routeLongName;
  final String? tripHeadsign;
  final int? directionId;
  final int originStopSequence;
}

class DirectTripReadException implements Exception {
  const DirectTripReadException(this.message);

  final String message;

  @override
  String toString() => message;
}
