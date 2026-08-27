import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_network_evidence_repository.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_models.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_repository.dart';
import 'package:government_transit_collector/features/journey_map/data/shape_segment.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/route_geometry.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/trip_progress_repository.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_repository.dart';

void main() {
  test('passes the selected route to the paged trip lookup', () async {
    final trips = FakeRouteTripDataSource();

    await repository(routeTripDataSource: trips).loadRoute('J15');

    expect(trips.routeIds, ['J15']);
    expect(trips.offsets, [0]);
  });

  test('preserves ordered stops, identities, and coordinates', () async {
    final result = await repository().loadRoute('J15');
    final stops = result.trips.first.stops;

    expect(stops.map((stop) => stop.stopSequence), [1, 2]);
    expect(stops.map((stop) => stop.stopId), ['stop-a', 'stop-b']);
    expect(stops.map((stop) => stop.stopName), ['Stop A', 'Stop B']);
    expect(stops.first.coordinate, const MapCoordinate(1.45, 103.75));
    expect(stops.last.coordinate, const MapCoordinate(1.46, 103.76));
    expect(stops.first.scheduledDepartureSeconds, 8 * 3600);
    expect(stops.last.scheduledArrivalSeconds, 8 * 3600 + 30 * 60);
  });

  test(
    'preserves every trip and shape without choosing a canonical shape',
    () async {
      final result = await repository().loadRoute('J15');

      expect(result.trips.map((trip) => trip.tripId), ['trip-a', 'trip-b']);
      expect(result.trips.map((trip) => trip.shapeId), ['shape-a', 'shape-b']);
      expect(result.trips.first.shapePoints.map((point) => point.sequence), [
        1,
        2,
      ]);
      expect(result.trips.last.shapePoints.map((point) => point.sequence), [
        1,
        2,
      ]);
    },
  );

  test('uses existing cumulative shape distance calculation', () async {
    final result = await repository().loadRoute('J15');
    final trip = result.trips.first;
    final expected = cumulativeShapeDistances(
      trip.shapePoints.map((point) => point.coordinate).toList(),
    ).last;

    expect(trip.routeDistanceMeters, expected);
  });

  test(
    'keeps missing stop and shape details visible as null or empty',
    () async {
      final result = await repository(
        mapDataSource: IncompleteMapDataSource(),
      ).loadRoute('J15');
      final trip = result.trips.first;

      expect(trip.shapeId, isNull);
      expect(trip.shapePoints, isEmpty);
      expect(trip.routeDistanceMeters, isNull);
      expect(trip.stops.first.stopId, 'stop-a');
      expect(trip.stops.first.stopName, isNull);
      expect(trip.stops.first.coordinate, isNull);
    },
  );
}

DefaultRouteNetworkEvidenceRepository repository({
  RouteTripDataSource? routeTripDataSource,
  JourneyMapDataSource? mapDataSource,
}) {
  return DefaultRouteNetworkEvidenceRepository(
    routeRepository: FakeRouteRepository(),
    routeTripDataSource: routeTripDataSource ?? FakeRouteTripDataSource(),
    mapDataSource: mapDataSource ?? FakeMapDataSource(),
    stopTimeDataSource: FakeStopTimeDataSource(),
  );
}

class FakeRouteRepository implements RoutePerformanceRepository {
  @override
  Future<List<RoutePerformanceRoute>> loadRoutes() async => const [
    RoutePerformanceRoute(
      routeId: 'J15',
      shortName: 'J15',
      longName: 'Johor route',
    ),
  ];

  @override
  Future<RoutePerformanceData> loadRoutePerformance({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) {
    throw UnimplementedError();
  }
}

class FakeRouteTripDataSource implements RouteTripDataSource {
  final routeIds = <String>[];
  final offsets = <int>[];

  @override
  Future<List<String>> fetchTripIds({
    required String routeId,
    required int offset,
    required int limit,
  }) async {
    routeIds.add(routeId);
    offsets.add(offset);
    return offset == 0 ? ['trip-a', 'trip-b'] : const [];
  }
}

class FakeMapDataSource implements JourneyMapDataSource {
  @override
  Future<List<TripShapeReference>> loadTripShapes(List<String> tripIds) async {
    return [
      const TripShapeReference(tripId: 'trip-a', shapeId: 'shape-a'),
      const TripShapeReference(tripId: 'trip-b', shapeId: 'shape-b'),
    ];
  }

  @override
  Future<List<MapStopRecord>> loadStops(List<String> stopIds) async {
    return const [
      MapStopRecord(
        stopId: 'stop-a',
        name: 'Stop A',
        coordinate: MapCoordinate(1.45, 103.75),
      ),
      MapStopRecord(
        stopId: 'stop-b',
        name: 'Stop B',
        coordinate: MapCoordinate(1.46, 103.76),
      ),
    ];
  }

  @override
  Future<Map<String, List<ShapePoint>>> loadShapePoints(
    List<String> shapeIds,
  ) async {
    return {
      'shape-a': const [
        ShapePoint(sequence: 2, coordinate: MapCoordinate(1.46, 103.76)),
        ShapePoint(sequence: 1, coordinate: MapCoordinate(1.45, 103.75)),
      ],
      'shape-b': const [
        ShapePoint(sequence: 1, coordinate: MapCoordinate(1.46, 103.76)),
        ShapePoint(sequence: 2, coordinate: MapCoordinate(1.47, 103.77)),
      ],
    };
  }
}

class IncompleteMapDataSource implements JourneyMapDataSource {
  @override
  Future<List<TripShapeReference>> loadTripShapes(List<String> tripIds) async {
    return [
      for (final tripId in tripIds)
        TripShapeReference(tripId: tripId, shapeId: null),
    ];
  }

  @override
  Future<List<MapStopRecord>> loadStops(List<String> stopIds) async => const [];

  @override
  Future<Map<String, List<ShapePoint>>> loadShapePoints(
    List<String> shapeIds,
  ) async => const {};
}

class FakeStopTimeDataSource implements TripProgressStopTimeDataSource {
  @override
  Future<List<TripStopTimeRecord>> loadStopTimes(String tripId) async {
    return const [
      TripStopTimeRecord(
        stopId: 'stop-b',
        stopSequence: 2,
        arrivalSeconds: 8 * 3600 + 30 * 60,
        departureSeconds: 8 * 3600 + 30 * 60,
      ),
      TripStopTimeRecord(
        stopId: 'stop-a',
        stopSequence: 1,
        arrivalSeconds: 8 * 3600,
        departureSeconds: 8 * 3600,
      ),
    ];
  }
}
