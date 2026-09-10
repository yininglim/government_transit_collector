import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_network_evidence_models.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_repository.dart';
import 'package:government_transit_collector/features/journey_map/data/shape_segment.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/route_geometry.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/trip_progress_repository.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class RouteTripDataSource {
  Future<List<TripShapeReference>> fetchTrips({
    required String routeId,
    required int offset,
    required int limit,
  });
}

class RouteNetworkStopTimeRecord {
  const RouteNetworkStopTimeRecord({
    required this.tripId,
    required this.stopTime,
  });

  final String tripId;
  final TripStopTimeRecord stopTime;
}

abstract interface class RouteNetworkStopTimeDataSource {
  Future<List<RouteNetworkStopTimeRecord>> fetchStopTimes({
    required List<String> tripIds,
    required int offset,
    required int limit,
  });
}

abstract interface class RouteNetworkEvidenceRepository {
  Future<AiRouteNetworkEvidence> loadRoute(String routeId);
}

class DefaultRouteNetworkEvidenceRepository
    implements RouteNetworkEvidenceRepository {
  DefaultRouteNetworkEvidenceRepository({
    RoutePerformanceRepository? routeRepository,
    RouteTripDataSource? routeTripDataSource,
    JourneyMapDataSource? mapDataSource,
    RouteNetworkStopTimeDataSource? stopTimeDataSource,
  }) : _routeRepository =
           routeRepository ?? DefaultRoutePerformanceRepository(),
       _routeTripDataSource =
           routeTripDataSource ?? SupabaseRouteTripDataSource(),
       _mapDataSource = mapDataSource ?? SupabaseJourneyMapDataSource(),
       _stopTimeDataSource =
           stopTimeDataSource ?? SupabaseRouteNetworkStopTimeDataSource();

  static const pageSize = 1000;
  static const lookupBatchSize = 100;

  final RoutePerformanceRepository _routeRepository;
  final RouteTripDataSource _routeTripDataSource;
  final JourneyMapDataSource _mapDataSource;
  final RouteNetworkStopTimeDataSource _stopTimeDataSource;
  Future<List<RoutePerformanceRoute>>? _routesFuture;
  final Map<String, MapStopRecord> _stopsById = {};
  final Map<String, Future<MapStopRecord?>> _stopLoads = {};
  final Map<String, List<ShapePoint>> _pointsByShapeId = {};
  final Map<String, Future<List<ShapePoint>?>> _shapeLoads = {};

  @override
  Future<AiRouteNetworkEvidence> loadRoute(String routeId) async {
    try {
      final responses = await Future.wait([_loadRoutes(), _loadTrips(routeId)]);
      final routes = responses[0] as List<RoutePerformanceRoute>;
      final route = routes.where((item) => item.routeId == routeId).firstOrNull;
      if (route == null) {
        throw const RouteNetworkEvidenceReadException(
          'The selected route is not available.',
        );
      }
      final tripShapes = responses[1] as List<TripShapeReference>;
      if (tripShapes.isEmpty) {
        return AiRouteNetworkEvidence(route: route, trips: const []);
      }
      final tripIds = tripShapes
          .map((reference) => reference.tripId)
          .toList(growable: false);
      final stopTimesByTrip = await _loadStopTimes(tripIds);
      final stopIds = stopTimesByTrip.values
          .expand((records) => records)
          .map((record) => record.stopId)
          .toSet()
          .toList();
      final shapeByTrip = {
        for (final reference in tripShapes) reference.tripId: reference.shapeId,
      };
      final shapeIds = shapeByTrip.values
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      final details = await Future.wait([
        _loadStops(stopIds),
        _loadShapePoints(shapeIds),
      ]);
      final stopsById = {
        for (final stop in details[0] as List<MapStopRecord>) stop.stopId: stop,
      };
      final pointsByShape = details[1] as Map<String, List<ShapePoint>>;
      final trips = <AiRouteTripEvidence>[];
      for (var index = 0; index < tripIds.length; index++) {
        final tripId = tripIds[index];
        final shapeId = shapeByTrip[tripId];
        final points = shapeId == null
            ? <ShapePoint>[]
            : [...pointsByShape[shapeId] ?? const <ShapePoint>[]];
        points.sort((left, right) => left.sequence.compareTo(right.sequence));
        final coordinates = points
            .map((point) => point.coordinate)
            .toList(growable: false);
        final distances = coordinates.length < 2
            ? const <double>[]
            : cumulativeShapeDistances(coordinates);
        final orderedStopTimes =
            [...stopTimesByTrip[tripId] ?? const <TripStopTimeRecord>[]]..sort(
              (left, right) => left.stopSequence.compareTo(right.stopSequence),
            );
        trips.add(
          AiRouteTripEvidence(
            tripId: tripId,
            shapeId: shapeId,
            stops: [
              for (final stopTime in orderedStopTimes)
                AiRouteStopEvidence(
                  stopId: stopTime.stopId,
                  stopName: stopsById[stopTime.stopId]?.name,
                  stopSequence: stopTime.stopSequence,
                  coordinate: stopsById[stopTime.stopId]?.coordinate,
                  scheduledArrivalSeconds: stopTime.arrivalSeconds,
                  scheduledDepartureSeconds: stopTime.departureSeconds,
                ),
            ],
            shapePoints: points,
            routeDistanceMeters: distances.isEmpty ? null : distances.last,
          ),
        );
      }
      return AiRouteNetworkEvidence(route: route, trips: trips);
    } on RouteNetworkEvidenceReadException {
      rethrow;
    } on Object {
      throw const RouteNetworkEvidenceReadException(
        'Unable to load route network evidence.',
      );
    }
  }

  Future<List<RoutePerformanceRoute>> _loadRoutes() {
    final existing = _routesFuture;
    if (existing != null) return existing;
    final future = _routeRepository.loadRoutes();
    _routesFuture = future;
    future.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {
        if (identical(_routesFuture, future)) _routesFuture = null;
      },
    );
    return future;
  }

  Future<List<TripShapeReference>> _loadTrips(String routeId) async {
    final trips = <TripShapeReference>[];
    for (var offset = 0; ; offset += pageSize) {
      final page = await _routeTripDataSource.fetchTrips(
        routeId: routeId,
        offset: offset,
        limit: pageSize,
      );
      trips.addAll(page);
      if (page.length < pageSize) break;
    }
    return trips;
  }

  Future<Map<String, List<TripStopTimeRecord>>> _loadStopTimes(
    List<String> tripIds,
  ) async {
    final grouped = <String, List<TripStopTimeRecord>>{};
    for (final batch in _batches(tripIds)) {
      for (var offset = 0; ; offset += pageSize) {
        final page = await _stopTimeDataSource.fetchStopTimes(
          tripIds: batch,
          offset: offset,
          limit: pageSize,
        );
        for (final record in page) {
          grouped.putIfAbsent(record.tripId, () => []).add(record.stopTime);
        }
        if (page.length < pageSize) break;
      }
    }
    return grouped;
  }

  Future<List<MapStopRecord>> _loadStops(List<String> stopIds) async {
    final requested = stopIds.toSet().toList(growable: false);
    final missing = requested
        .where(
          (id) => !_stopsById.containsKey(id) && !_stopLoads.containsKey(id),
        )
        .toList(growable: false);
    for (final batch in _batches(missing)) {
      final load = _mapDataSource.loadStops(batch).then((records) {
        return {for (final record in records) record.stopId: record};
      });
      for (final id in batch) {
        late final Future<MapStopRecord?> pending;
        pending = load
            .then((records) {
              final record = records[id];
              if (record != null) _stopsById[id] = record;
              return record;
            })
            .whenComplete(() {
              if (identical(_stopLoads[id], pending)) _stopLoads.remove(id);
            });
        _stopLoads[id] = pending;
      }
    }
    await Future.wait([
      for (final id in requested)
        if (!_stopsById.containsKey(id)) _stopLoads[id]!,
    ]);
    return requested
        .map((id) => _stopsById[id])
        .whereType<MapStopRecord>()
        .toList(growable: false);
  }

  Future<Map<String, List<ShapePoint>>> _loadShapePoints(
    List<String> shapeIds,
  ) async {
    final requested = shapeIds.toSet().toList(growable: false);
    final missing = requested
        .where(
          (id) =>
              !_pointsByShapeId.containsKey(id) && !_shapeLoads.containsKey(id),
        )
        .toList(growable: false);
    for (final batch in _batches(missing)) {
      final load = _mapDataSource.loadShapePoints(batch);
      for (final id in batch) {
        late final Future<List<ShapePoint>?> pending;
        pending = load
            .then((points) {
              final records = points[id];
              if (records != null) _pointsByShapeId[id] = records;
              return records;
            })
            .whenComplete(() {
              if (identical(_shapeLoads[id], pending)) _shapeLoads.remove(id);
            });
        _shapeLoads[id] = pending;
      }
    }
    await Future.wait([
      for (final id in requested)
        if (!_pointsByShapeId.containsKey(id)) _shapeLoads[id]!,
    ]);
    final result = <String, List<ShapePoint>>{};
    for (final id in requested) {
      final points = _pointsByShapeId[id];
      if (points != null) result[id] = points;
    }
    return result;
  }

  Iterable<List<String>> _batches(List<String> values) sync* {
    for (var start = 0; start < values.length; start += lookupBatchSize) {
      final end = (start + lookupBatchSize).clamp(0, values.length);
      yield values.sublist(start, end);
    }
  }
}

class SupabaseRouteTripDataSource implements RouteTripDataSource {
  SupabaseRouteTripDataSource({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<List<TripShapeReference>> fetchTrips({
    required String routeId,
    required int offset,
    required int limit,
  }) async {
    final rows = await _client
        .from('gtfs_trips')
        .select('trip_id, shape_id')
        .eq('route_id', routeId)
        .order('trip_id')
        .range(offset, offset + limit - 1);
    return rows
        .map(
          (row) => TripShapeReference(
            tripId: row['trip_id'] as String,
            shapeId: row['shape_id'] as String?,
          ),
        )
        .toList(growable: false);
  }
}

class SupabaseRouteNetworkStopTimeDataSource
    implements RouteNetworkStopTimeDataSource {
  SupabaseRouteNetworkStopTimeDataSource({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<List<RouteNetworkStopTimeRecord>> fetchStopTimes({
    required List<String> tripIds,
    required int offset,
    required int limit,
  }) async {
    final rows = await _client
        .from('gtfs_stop_times')
        .select(
          'trip_id, stop_id, stop_sequence, arrival_seconds, departure_seconds',
        )
        .inFilter('trip_id', tripIds)
        .order('trip_id')
        .order('stop_sequence')
        .range(offset, offset + limit - 1);
    return rows
        .map(
          (row) => RouteNetworkStopTimeRecord(
            tripId: row['trip_id'] as String,
            stopTime: TripStopTimeRecord(
              stopId: row['stop_id'] as String,
              stopSequence: (row['stop_sequence'] as num).toInt(),
              arrivalSeconds: (row['arrival_seconds'] as num?)?.toInt(),
              departureSeconds: (row['departure_seconds'] as num?)?.toInt(),
            ),
          ),
        )
        .toList(growable: false);
  }
}

class RouteNetworkEvidenceReadException implements Exception {
  const RouteNetworkEvidenceReadException(this.message);

  final String message;

  @override
  String toString() => message;
}
