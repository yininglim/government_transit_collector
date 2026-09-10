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

  test('batches stop times by 100 trip IDs in deterministic order', () async {
    final trips = ManyTripsDataSource(205);
    final stopTimes = RecordingStopTimeDataSource();

    final result = await repository(
      routeTripDataSource: trips,
      stopTimeDataSource: stopTimes,
      mapDataSource: GeneratedMapDataSource(),
    ).loadRoute('J15');

    expect(stopTimes.batchSizes, [100, 100, 5]);
    expect(stopTimes.offsets, [0, 0, 0]);
    expect(result.trips.map((trip) => trip.tripId), trips.tripIds);
    expect(
      result.trips.every((trip) => trip.stops.first.stopSequence == 1),
      isTrue,
    );
  });

  test('paginates within a stop-time batch beyond 1000 rows', () async {
    final stopTimes = PaginatedStopTimeDataSource();

    final result = await repository(
      routeTripDataSource: ManyTripsDataSource(2),
      stopTimeDataSource: stopTimes,
      mapDataSource: GeneratedMapDataSource(),
    ).loadRoute('J15');

    expect(stopTimes.offsets, [0, 1000]);
    expect(result.trips.first.stops, hasLength(600));
    expect(result.trips.last.stops, hasLength(401));
    expect(result.trips.first.stops.first.stopSequence, 1);
    expect(result.trips.first.stops.last.stopSequence, 600);
  });

  test(
    'deduplicates shared stop and shape loads across concurrent routes',
    () async {
      final maps = CountingSharedMapDataSource();
      final network = repository(mapDataSource: maps);

      final results = await Future.wait([
        network.loadRoute('J15'),
        network.loadRoute('J16'),
      ]);

      expect(results.map((result) => result.trips.length), [2, 2]);
      expect(maps.stopRequests, [
        containsAll(['stop-a', 'stop-b']),
      ]);
      expect(maps.shapeRequests, [
        containsAll(['shape-a', 'shape-b']),
      ]);
      expect(results.last.trips.first.stops.map((stop) => stop.stopSequence), [
        1,
        2,
      ]);
      expect(
        results.last.trips.first.shapePoints.map((point) => point.sequence),
        [1, 2],
      );
    },
  );

  test('a new static-cache context loads shared entities again', () async {
    final maps = CountingSharedMapDataSource();

    await repository(mapDataSource: maps).loadRoute('J15');
    await repository(mapDataSource: maps).loadRoute('J15');

    expect(maps.stopRequests, hasLength(2));
    expect(maps.shapeRequests, hasLength(2));
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
        routeTripDataSource: MissingShapeTripDataSource(),
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
  RouteNetworkStopTimeDataSource? stopTimeDataSource,
}) {
  return DefaultRouteNetworkEvidenceRepository(
    routeRepository: FakeRouteRepository(),
    routeTripDataSource: routeTripDataSource ?? FakeRouteTripDataSource(),
    mapDataSource: mapDataSource ?? FakeMapDataSource(),
    stopTimeDataSource: stopTimeDataSource ?? FakeStopTimeDataSource(),
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
    RoutePerformanceRoute(
      routeId: 'J16',
      shortName: 'J16',
      longName: 'Second Johor route',
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
  Future<List<TripShapeReference>> fetchTrips({
    required String routeId,
    required int offset,
    required int limit,
  }) async {
    routeIds.add(routeId);
    offsets.add(offset);
    return offset == 0
        ? const [
            TripShapeReference(tripId: 'trip-a', shapeId: 'shape-a'),
            TripShapeReference(tripId: 'trip-b', shapeId: 'shape-b'),
          ]
        : const [];
  }
}

class MissingShapeTripDataSource implements RouteTripDataSource {
  @override
  Future<List<TripShapeReference>> fetchTrips({
    required String routeId,
    required int offset,
    required int limit,
  }) async => offset == 0
      ? const [
          TripShapeReference(tripId: 'trip-a', shapeId: null),
          TripShapeReference(tripId: 'trip-b', shapeId: null),
        ]
      : const [];
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

class CountingSharedMapDataSource extends FakeMapDataSource {
  final stopRequests = <List<String>>[];
  final shapeRequests = <List<String>>[];

  @override
  Future<List<MapStopRecord>> loadStops(List<String> stopIds) async {
    stopRequests.add([...stopIds]);
    await Future<void>.delayed(Duration.zero);
    return super.loadStops(stopIds);
  }

  @override
  Future<Map<String, List<ShapePoint>>> loadShapePoints(
    List<String> shapeIds,
  ) async {
    shapeRequests.add([...shapeIds]);
    await Future<void>.delayed(Duration.zero);
    return super.loadShapePoints(shapeIds);
  }
}

class FakeStopTimeDataSource implements RouteNetworkStopTimeDataSource {
  @override
  Future<List<RouteNetworkStopTimeRecord>> fetchStopTimes({
    required List<String> tripIds,
    required int offset,
    required int limit,
  }) async {
    if (offset > 0) return const [];
    return [
      for (final tripId in tripIds) ...[
        RouteNetworkStopTimeRecord(
          tripId: tripId,
          stopTime: const TripStopTimeRecord(
            stopId: 'stop-b',
            stopSequence: 2,
            arrivalSeconds: 8 * 3600 + 30 * 60,
            departureSeconds: 8 * 3600 + 30 * 60,
          ),
        ),
        RouteNetworkStopTimeRecord(
          tripId: tripId,
          stopTime: const TripStopTimeRecord(
            stopId: 'stop-a',
            stopSequence: 1,
            arrivalSeconds: 8 * 3600,
            departureSeconds: 8 * 3600,
          ),
        ),
      ],
    ];
  }
}

class ManyTripsDataSource implements RouteTripDataSource {
  ManyTripsDataSource(int count)
    : tripIds = List.generate(
        count,
        (index) => 'trip-${index.toString().padLeft(3, '0')}',
      );

  final List<String> tripIds;

  @override
  Future<List<TripShapeReference>> fetchTrips({
    required String routeId,
    required int offset,
    required int limit,
  }) async => [
    for (final tripId in tripIds.skip(offset).take(limit))
      TripShapeReference(tripId: tripId, shapeId: 'shape-$tripId'),
  ];
}

class RecordingStopTimeDataSource implements RouteNetworkStopTimeDataSource {
  final batchSizes = <int>[];
  final offsets = <int>[];

  @override
  Future<List<RouteNetworkStopTimeRecord>> fetchStopTimes({
    required List<String> tripIds,
    required int offset,
    required int limit,
  }) async {
    batchSizes.add(tripIds.length);
    offsets.add(offset);
    return [
      for (final tripId in tripIds)
        RouteNetworkStopTimeRecord(
          tripId: tripId,
          stopTime: TripStopTimeRecord(
            stopId: 'stop-$tripId',
            stopSequence: 1,
            arrivalSeconds: null,
            departureSeconds: null,
          ),
        ),
    ];
  }
}

class PaginatedStopTimeDataSource implements RouteNetworkStopTimeDataSource {
  final offsets = <int>[];

  @override
  Future<List<RouteNetworkStopTimeRecord>> fetchStopTimes({
    required List<String> tripIds,
    required int offset,
    required int limit,
  }) async {
    offsets.add(offset);
    if (offset > 0) {
      return [
        RouteNetworkStopTimeRecord(
          tripId: tripIds.last,
          stopTime: const TripStopTimeRecord(
            stopId: 'last-stop',
            stopSequence: 401,
            arrivalSeconds: null,
            departureSeconds: null,
          ),
        ),
      ];
    }
    return List.generate(1000, (index) {
      final firstTrip = index < 600;
      return RouteNetworkStopTimeRecord(
        tripId: firstTrip ? tripIds.first : tripIds.last,
        stopTime: TripStopTimeRecord(
          stopId: 'stop-$index',
          stopSequence: firstTrip ? index + 1 : index - 599,
          arrivalSeconds: null,
          departureSeconds: null,
        ),
      );
    });
  }
}

class GeneratedMapDataSource implements JourneyMapDataSource {
  @override
  Future<List<TripShapeReference>> loadTripShapes(List<String> tripIds) async =>
      throw UnimplementedError();

  @override
  Future<List<MapStopRecord>> loadStops(List<String> stopIds) async => const [];

  @override
  Future<Map<String, List<ShapePoint>>> loadShapePoints(
    List<String> shapeIds,
  ) async => const {};
}
