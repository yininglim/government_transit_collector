import 'package:supabase_flutter/supabase_flutter.dart';
import 'departure_stop_repository.dart';

class TransferTripEndpoint {
  const TransferTripEndpoint({
    required this.tripId,
    required this.routeId,
    required this.routeShortName,
    required this.routeLongName,
    required this.tripHeadsign,
    required this.endpointSequence,
  });

  final String tripId;
  final String routeId;
  final String? routeShortName;
  final String? routeLongName;
  final String? tripHeadsign;
  final int endpointSequence;
}

class TripStopPosition {
  const TripStopPosition({
    required this.tripId,
    required this.stopId,
    required this.stopName,
    required this.stopSequence,
  });

  final String tripId;
  final String stopId;
  final String stopName;
  final int stopSequence;
}

class TransferJourneyLeg {
  const TransferJourneyLeg({
    required this.routeId,
    required this.routeShortName,
    required this.routeLongName,
    required this.tripId,
    required this.tripHeadsign,
    required this.fromStopId,
    required this.toStopId,
    required this.fromStopSequence,
    required this.toStopSequence,
  });

  final String routeId;
  final String? routeShortName;
  final String? routeLongName;
  final String tripId;
  final String? tripHeadsign;
  final String fromStopId;
  final String toStopId;
  final int fromStopSequence;
  final int toStopSequence;
}

class TransferTripPair {
  const TransferTripPair({
    required this.firstTripId,
    required this.secondTripId,
  });

  final String firstTripId;
  final String secondTripId;
}

class OneTransferJourneyResult {
  const OneTransferJourneyResult({
    required this.firstLeg,
    required this.transferStopId,
    required this.transferStopName,
    required this.secondLeg,
    required this.matchingTripPairs,
  });

  final TransferJourneyLeg firstLeg;
  final String transferStopId;
  final String transferStopName;
  final TransferJourneyLeg secondLeg;
  final List<TransferTripPair> matchingTripPairs;
}

abstract interface class TransferJourneyRepository {
  Future<List<DepartureStop>> reachableDestinations(String originStopId);
  Future<List<OneTransferJourneyResult>> findOneTransferJourneys({
    required String originStopId,
    required String destinationStopId,
  });
}

bool _canTransfer(TransferTripEndpoint first, TransferTripEndpoint second) =>
    first.tripId != second.tripId && first.routeId != second.routeId;

List<DepartureStop> buildReachableDestinations({
  required String originStopId,
  required List<TransferTripEndpoint> originTrips,
  required List<TripStopPosition> firstTripStops,
  required Map<String, List<TransferTripEndpoint>> transferTripsByStop,
  required List<TripStopPosition> secondTripStops,
}) {
  final origins = {for (final trip in originTrips) trip.tripId: trip};
  final secondByTrip = <String, List<TripStopPosition>>{};
  for (final stop in secondTripStops) {
    secondByTrip.putIfAbsent(stop.tripId, () => []).add(stop);
  }
  final destinations = <String, DepartureStop>{};
  for (final stop in firstTripStops) {
    final first = origins[stop.tripId];
    if (first == null ||
        stop.stopId == originStopId ||
        stop.stopSequence <= first.endpointSequence) {
      continue;
    }
    destinations[stop.stopId] = DepartureStop(
      id: stop.stopId,
      name: stop.stopName,
    );
    for (final second
        in transferTripsByStop[stop.stopId] ?? <TransferTripEndpoint>[]) {
      if (!_canTransfer(first, second)) continue;
      for (final destination
          in secondByTrip[second.tripId] ?? <TripStopPosition>[]) {
        if (destination.stopId == originStopId ||
            destination.stopId == stop.stopId ||
            destination.stopSequence <= second.endpointSequence) {
          continue;
        }
        destinations[destination.stopId] = DepartureStop(
          id: destination.stopId,
          name: destination.stopName,
        );
      }
    }
  }
  return destinations.values.toList()..sort((a, b) {
    final name = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return name != 0 ? name : a.id.compareTo(b.id);
  });
}

List<OneTransferJourneyResult> buildOneTransferJourneys({
  required String originStopId,
  required String destinationStopId,
  required List<TransferTripEndpoint> originTrips,
  required List<TransferTripEndpoint> destinationTrips,
  required List<TripStopPosition> firstTripStops,
  required List<TripStopPosition> secondTripStops,
  int limit = 5,
}) {
  if (limit <= 0) return const [];
  final originByTrip = {for (final trip in originTrips) trip.tripId: trip};
  final destinationByTrip = {
    for (final trip in destinationTrips) trip.tripId: trip,
  };
  final downstreamByStop = <String, List<TripStopPosition>>{};
  for (final stop in firstTripStops) {
    final trip = originByTrip[stop.tripId];
    if (trip == null ||
        stop.stopId == originStopId ||
        stop.stopId == destinationStopId ||
        stop.stopSequence <= trip.endpointSequence) {
      continue;
    }
    downstreamByStop.putIfAbsent(stop.stopId, () => []).add(stop);
  }

  final upstreamByStop = <String, List<TripStopPosition>>{};
  for (final stop in secondTripStops) {
    final trip = destinationByTrip[stop.tripId];
    if (trip == null ||
        stop.stopId == originStopId ||
        stop.stopId == destinationStopId ||
        stop.stopSequence >= trip.endpointSequence) {
      continue;
    }
    upstreamByStop.putIfAbsent(stop.stopId, () => []).add(stop);
  }

  final grouped = <String, _TransferGroup>{};
  for (final entry in downstreamByStop.entries) {
    final secondStops = upstreamByStop[entry.key];
    if (secondStops == null) continue;
    for (final firstStop in entry.value) {
      final firstTrip = originByTrip[firstStop.tripId]!;
      for (final secondStop in secondStops) {
        final secondTrip = destinationByTrip[secondStop.tripId]!;
        if (!_canTransfer(firstTrip, secondTrip)) {
          continue;
        }
        final key = '${firstTrip.routeId}|${entry.key}|${secondTrip.routeId}';
        final group = grouped.putIfAbsent(
          key,
          () => _TransferGroup(
            firstTrip: firstTrip,
            firstStop: firstStop,
            secondTrip: secondTrip,
            secondStop: secondStop,
          ),
        );
        group.addPair(firstTrip.tripId, secondTrip.tripId);
      }
    }
  }

  final results = grouped.values.map((group) {
    return OneTransferJourneyResult(
      firstLeg: TransferJourneyLeg(
        routeId: group.firstTrip.routeId,
        routeShortName: group.firstTrip.routeShortName,
        routeLongName: group.firstTrip.routeLongName,
        tripId: group.firstTrip.tripId,
        tripHeadsign: group.firstTrip.tripHeadsign,
        fromStopId: originStopId,
        toStopId: group.firstStop.stopId,
        fromStopSequence: group.firstTrip.endpointSequence,
        toStopSequence: group.firstStop.stopSequence,
      ),
      transferStopId: group.firstStop.stopId,
      transferStopName: group.firstStop.stopName,
      secondLeg: TransferJourneyLeg(
        routeId: group.secondTrip.routeId,
        routeShortName: group.secondTrip.routeShortName,
        routeLongName: group.secondTrip.routeLongName,
        tripId: group.secondTrip.tripId,
        tripHeadsign: group.secondTrip.tripHeadsign,
        fromStopId: group.secondStop.stopId,
        toStopId: destinationStopId,
        fromStopSequence: group.secondStop.stopSequence,
        toStopSequence: group.secondTrip.endpointSequence,
      ),
      matchingTripPairs: group.pairs.toList(growable: false),
    );
  }).toList();
  results.sort((left, right) {
    final byStop = left.transferStopName.toLowerCase().compareTo(
      right.transferStopName.toLowerCase(),
    );
    if (byStop != 0) return byStop;
    final leftFirst = left.firstLeg.routeShortName ?? left.firstLeg.routeId;
    final rightFirst = right.firstLeg.routeShortName ?? right.firstLeg.routeId;
    final byFirst = leftFirst.toLowerCase().compareTo(rightFirst.toLowerCase());
    if (byFirst != 0) return byFirst;
    final leftSecond = left.secondLeg.routeShortName ?? left.secondLeg.routeId;
    final rightSecond =
        right.secondLeg.routeShortName ?? right.secondLeg.routeId;
    return leftSecond.toLowerCase().compareTo(rightSecond.toLowerCase());
  });
  return results.take(limit).toList(growable: false);
}

class SupabaseTransferJourneyRepository implements TransferJourneyRepository {
  SupabaseTransferJourneyRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  static const int resultLimit = 5;
  static const int _pageSize = 1000;
  static const int _tripBatchSize = 50;

  final SupabaseClient _client;

  @override
  Future<List<DepartureStop>> reachableDestinations(String originStopId) async {
    try {
      final origins = await _loadTripEndpoints(
        originStopId,
        useEarliestSequence: true,
      );
      final firstStops = await _loadStopsForTrips(
        origins.map((t) => t.tripId).toList(),
      );
      final direct = buildReachableDestinations(
        originStopId: originStopId,
        originTrips: origins,
        firstTripStops: firstStops,
        transferTripsByStop: const {},
        secondTripStops: const [],
      );
      final transferTrips = <String, List<TransferTripEndpoint>>{};
      final ids = direct.map((s) => s.id).toList();
      for (var start = 0; start < ids.length; start += _tripBatchSize) {
        final batch = ids.sublist(
          start,
          (start + _tripBatchSize).clamp(0, ids.length),
        );
        for (var offset = 0; ; offset += _pageSize) {
          final rows = await _client
              .from('gtfs_stop_times')
              .select(
                'stop_id, trip_id, stop_sequence, gtfs_trips!inner(route_id, trip_headsign, gtfs_routes!inner(route_id, route_short_name, route_long_name))',
              )
              .inFilter('stop_id', batch)
              .order('trip_id')
              .order('stop_sequence')
              .range(offset, offset + _pageSize - 1);
          for (final row in rows) {
            transferTrips
                .putIfAbsent(row['stop_id'] as String, () => [])
                .add(_endpointFromSupabase(row));
          }
          if (rows.length < _pageSize) break;
        }
      }
      final secondIds = transferTrips.values
          .expand((trips) => trips)
          .map((t) => t.tripId)
          .toSet()
          .toList();
      final secondStops = await _loadStopsForTrips(secondIds);
      return buildReachableDestinations(
        originStopId: originStopId,
        originTrips: origins,
        firstTripStops: firstStops,
        transferTripsByStop: transferTrips,
        secondTripStops: secondStops,
      );
    } on Object {
      throw const TransferJourneyReadException(
        'Unable to load reachable destinations. Please retry.',
      );
    }
  }

  @override
  Future<List<OneTransferJourneyResult>> findOneTransferJourneys({
    required String originStopId,
    required String destinationStopId,
  }) async {
    try {
      final endpoints = await Future.wait([
        _loadTripEndpoints(originStopId, useEarliestSequence: true),
        _loadTripEndpoints(destinationStopId, useEarliestSequence: false),
      ]);
      final originTrips = endpoints[0];
      final destinationTrips = endpoints[1];
      if (originTrips.isEmpty || destinationTrips.isEmpty) return const [];

      final stopGroups = await Future.wait([
        _loadStopsForTrips(originTrips.map((trip) => trip.tripId).toList()),
        _loadStopsForTrips(
          destinationTrips.map((trip) => trip.tripId).toList(),
        ),
      ]);
      return buildOneTransferJourneys(
        originStopId: originStopId,
        destinationStopId: destinationStopId,
        originTrips: originTrips,
        destinationTrips: destinationTrips,
        firstTripStops: stopGroups[0],
        secondTripStops: stopGroups[1],
        limit: resultLimit,
      );
    } on PostgrestException catch (error) {
      throw TransferJourneyReadException(
        error.message.isEmpty
            ? 'Unable to find one-transfer routes.'
            : error.message,
      );
    } on TransferJourneyReadException {
      rethrow;
    } on Object {
      throw const TransferJourneyReadException(
        'Unable to find one-transfer routes.',
      );
    }
  }

  Future<List<TransferTripEndpoint>> _loadTripEndpoints(
    String stopId, {
    required bool useEarliestSequence,
  }) async {
    final rows = <TransferTripEndpoint>[];
    var start = 0;
    while (true) {
      final data = await _client
          .from('gtfs_stop_times')
          .select(
            'trip_id, stop_sequence, '
            'gtfs_trips!inner('
            'route_id, trip_headsign, '
            'gtfs_routes!inner(route_id, route_short_name, route_long_name)'
            ')',
          )
          .eq('stop_id', stopId)
          .order('trip_id')
          .range(start, start + _pageSize - 1);
      rows.addAll(data.map(_endpointFromSupabase));
      if (data.length < _pageSize) break;
      start += _pageSize;
    }
    final selectedByTrip = <String, TransferTripEndpoint>{};
    for (final row in rows) {
      final current = selectedByTrip[row.tripId];
      if (current == null ||
          (useEarliestSequence
              ? row.endpointSequence < current.endpointSequence
              : row.endpointSequence > current.endpointSequence)) {
        selectedByTrip[row.tripId] = row;
      }
    }
    return selectedByTrip.values.toList(growable: false);
  }

  Future<List<TripStopPosition>> _loadStopsForTrips(
    List<String> tripIds,
  ) async {
    final stops = <TripStopPosition>[];
    for (
      var batchStart = 0;
      batchStart < tripIds.length;
      batchStart += _tripBatchSize
    ) {
      final batchEnd = (batchStart + _tripBatchSize).clamp(0, tripIds.length);
      final batch = tripIds.sublist(batchStart, batchEnd);
      var rangeStart = 0;
      while (true) {
        final data = await _client
            .from('gtfs_stop_times')
            .select(
              'trip_id, stop_id, stop_sequence, '
              'gtfs_stops!inner(stop_id, stop_name)',
            )
            .inFilter('trip_id', batch)
            .order('trip_id')
            .order('stop_sequence')
            .range(rangeStart, rangeStart + _pageSize - 1);
        stops.addAll(data.map(_stopFromSupabase));
        if (data.length < _pageSize) break;
        rangeStart += _pageSize;
      }
    }
    return stops;
  }

  TransferTripEndpoint _endpointFromSupabase(Map<String, dynamic> row) {
    final trip = row['gtfs_trips'] as Map<String, dynamic>;
    final route = trip['gtfs_routes'] as Map<String, dynamic>;
    return TransferTripEndpoint(
      tripId: row['trip_id'] as String,
      routeId: trip['route_id'] as String,
      routeShortName: route['route_short_name'] as String?,
      routeLongName: route['route_long_name'] as String?,
      tripHeadsign: trip['trip_headsign'] as String?,
      endpointSequence: row['stop_sequence'] as int,
    );
  }

  TripStopPosition _stopFromSupabase(Map<String, dynamic> row) {
    final stop = row['gtfs_stops'] as Map<String, dynamic>;
    return TripStopPosition(
      tripId: row['trip_id'] as String,
      stopId: row['stop_id'] as String,
      stopName: stop['stop_name'] as String,
      stopSequence: row['stop_sequence'] as int,
    );
  }
}

class _TransferGroup {
  _TransferGroup({
    required this.firstTrip,
    required this.firstStop,
    required this.secondTrip,
    required this.secondStop,
  });

  final TransferTripEndpoint firstTrip;
  final TripStopPosition firstStop;
  final TransferTripEndpoint secondTrip;
  final TripStopPosition secondStop;
  final Set<TransferTripPair> pairs = {};
  final Set<String> _pairKeys = {};

  void addPair(String firstTripId, String secondTripId) {
    final key = '$firstTripId|$secondTripId';
    if (_pairKeys.add(key)) {
      pairs.add(
        TransferTripPair(firstTripId: firstTripId, secondTripId: secondTripId),
      );
    }
  }
}

class TransferJourneyReadException implements Exception {
  const TransferJourneyReadException(this.message);

  final String message;

  @override
  String toString() => message;
}
