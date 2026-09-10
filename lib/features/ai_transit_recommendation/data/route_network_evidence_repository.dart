import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_network_evidence_models.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_repository.dart';
import 'package:government_transit_collector/features/journey_map/data/shape_segment.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/route_geometry.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/trip_progress_repository.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class RouteTripDataSource {
  Future<List<String>> fetchTripIds({
    required String routeId,
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
    TripProgressStopTimeDataSource? stopTimeDataSource,
  }) : _routeRepository =
           routeRepository ?? DefaultRoutePerformanceRepository(),
       _routeTripDataSource =
           routeTripDataSource ?? SupabaseRouteTripDataSource(),
       _mapDataSource = mapDataSource ?? SupabaseJourneyMapDataSource(),
       _stopTimeDataSource =
           stopTimeDataSource ?? SupabaseTripProgressStopTimeDataSource();

  static const pageSize = 1000;
  static const lookupBatchSize = 100;

  final RoutePerformanceRepository _routeRepository;
  final RouteTripDataSource _routeTripDataSource;
  final JourneyMapDataSource _mapDataSource;
  final TripProgressStopTimeDataSource _stopTimeDataSource;
  Future<List<RoutePerformanceRoute>>? _routesFuture;

  @override
  Future<AiRouteNetworkEvidence> loadRoute(String routeId) async {
    try {
      final responses = await Future.wait([
        _loadRoutes(),
        _loadTripIds(routeId),
      ]);
      final routes = responses[0] as List<RoutePerformanceRoute>;
      final route = routes.where((item) => item.routeId == routeId).firstOrNull;
      if (route == null) {
        throw const RouteNetworkEvidenceReadException(
          'The selected route is not available.',
        );
      }
      final tripIds = responses[1] as List<String>;
      if (tripIds.isEmpty) {
        return AiRouteNetworkEvidence(route: route, trips: const []);
      }
      final tripShapes = await _loadTripShapes(tripIds);
      final stopTimes = await Future.wait([
        for (final tripId in tripIds) _stopTimeDataSource.loadStopTimes(tripId),
      ]);
      final stopIds = stopTimes
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
        final orderedStopTimes = [...stopTimes[index]]
          ..sort(
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
      onError: (Object _, StackTrace __) {
        if (identical(_routesFuture, future)) _routesFuture = null;
      },
    );
    return future;
  }

  Future<List<String>> _loadTripIds(String routeId) async {
    final tripIds = <String>[];
    for (var offset = 0; ; offset += pageSize) {
      final page = await _routeTripDataSource.fetchTripIds(
        routeId: routeId,
        offset: offset,
        limit: pageSize,
      );
      tripIds.addAll(page);
      if (page.length < pageSize) break;
    }
    return tripIds;
  }

  Future<List<TripShapeReference>> _loadTripShapes(List<String> tripIds) async {
    final references = <TripShapeReference>[];
    for (final batch in _batches(tripIds)) {
      references.addAll(await _mapDataSource.loadTripShapes(batch));
    }
    return references;
  }

  Future<List<MapStopRecord>> _loadStops(List<String> stopIds) async {
    final stops = <MapStopRecord>[];
    for (final batch in _batches(stopIds)) {
      stops.addAll(await _mapDataSource.loadStops(batch));
    }
    return stops;
  }

  Future<Map<String, List<ShapePoint>>> _loadShapePoints(
    List<String> shapeIds,
  ) async {
    final result = <String, List<ShapePoint>>{};
    for (final batch in _batches(shapeIds)) {
      final points = await _mapDataSource.loadShapePoints(batch);
      for (final entry in points.entries) {
        result.putIfAbsent(entry.key, () => []).addAll(entry.value);
      }
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
  Future<List<String>> fetchTripIds({
    required String routeId,
    required int offset,
    required int limit,
  }) async {
    final rows = await _client
        .from('gtfs_trips')
        .select('trip_id')
        .eq('route_id', routeId)
        .order('trip_id')
        .range(offset, offset + limit - 1);
    return rows.map((row) => row['trip_id'] as String).toList(growable: false);
  }
}

class RouteNetworkEvidenceReadException implements Exception {
  const RouteNetworkEvidenceReadException(this.message);

  final String message;

  @override
  String toString() => message;
}
