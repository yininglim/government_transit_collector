import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/timetable_recommendation_repository.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_models.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_repository.dart';
import 'package:government_transit_collector/features/journey_map/data/shape_segment.dart';

const direct = DirectJourneyRecommendation(
  tripId: 'direct-trip',
  routeId: 'route-1',
  routeShortName: 'J10',
  originStopId: 'origin',
  destinationStopId: 'destination',
  serviceId: 'weekday',
  originStopSequence: 1,
  destinationStopSequence: 9,
  departureSeconds: 3600,
  arrivalSeconds: 5400,
);

const transfer = TransferJourneyRecommendation(
  firstTripId: 'first-trip',
  secondTripId: 'second-trip',
  firstRouteId: 'route-1',
  firstRouteShortName: 'J10',
  secondRouteId: 'route-2',
  secondRouteShortName: 'J15',
  originStopId: 'origin',
  transferStopId: 'transfer',
  transferStopName: 'City Square',
  destinationStopId: 'destination',
  firstServiceId: 'weekday',
  secondServiceId: 'weekday',
  originStopSequence: 1,
  firstTransferStopSequence: 5,
  secondTransferStopSequence: 2,
  destinationStopSequence: 9,
  departureSeconds: 3600,
  transferArrivalSeconds: 4200,
  secondDepartureSeconds: 4500,
  arrivalSeconds: 5400,
);

class FakeMapDataSource implements JourneyMapDataSource {
  List<String>? requestedTripIds;
  List<String>? requestedStopIds;
  List<String>? requestedShapeIds;

  @override
  Future<List<TripShapeReference>> loadTripShapes(List<String> tripIds) async {
    requestedTripIds = tripIds;
    return [
      for (final tripId in tripIds)
        TripShapeReference(tripId: tripId, shapeId: 'shape-$tripId'),
    ];
  }

  @override
  Future<List<MapStopRecord>> loadStops(List<String> stopIds) async {
    requestedStopIds = stopIds;
    const coordinates = {
      'origin': MapCoordinate(1.450, 103.750),
      'transfer': MapCoordinate(1.455, 103.755),
      'destination': MapCoordinate(1.460, 103.760),
    };
    return [
      for (final stopId in stopIds)
        MapStopRecord(
          stopId: stopId,
          name: stopId,
          coordinate: coordinates[stopId],
        ),
    ];
  }

  @override
  Future<Map<String, List<ShapePoint>>> loadShapePoints(
    List<String> shapeIds,
  ) async {
    requestedShapeIds = shapeIds;
    return {
      for (final shapeId in shapeIds)
        shapeId: [
          const ShapePoint(
            sequence: 1,
            coordinate: MapCoordinate(1.450, 103.750),
          ),
          const ShapePoint(
            sequence: 2,
            coordinate: MapCoordinate(1.455, 103.755),
          ),
          const ShapePoint(
            sequence: 3,
            coordinate: MapCoordinate(1.460, 103.760),
          ),
        ],
    };
  }
}

void main() {
  test('direct recommendation loads exactly its one trip shape', () async {
    final source = FakeMapDataSource();
    final result = await GtfsJourneyMapRepository(
      dataSource: source,
    ).loadJourney(direct);

    expect(source.requestedTripIds, ['direct-trip']);
    expect(source.requestedShapeIds, ['shape-direct-trip']);
    expect(result.legs, hasLength(1));
    expect(result.stops, hasLength(2));
  });

  test('transfer recommendation loads both exact trip shapes', () async {
    final source = FakeMapDataSource();
    final result = await GtfsJourneyMapRepository(
      dataSource: source,
    ).loadJourney(transfer);

    expect(source.requestedTripIds, ['first-trip', 'second-trip']);
    expect(source.requestedShapeIds, ['shape-first-trip', 'shape-second-trip']);
    expect(result.legs, hasLength(2));
    expect(result.stops, hasLength(3));
  });

  test('shape segmentation orders points and keeps the journey direction', () {
    final segment = segmentShape(
      shapePoints: const [
        ShapePoint(sequence: 30, coordinate: MapCoordinate(1.003, 103)),
        ShapePoint(sequence: 10, coordinate: MapCoordinate(1.001, 103)),
        ShapePoint(sequence: 20, coordinate: MapCoordinate(1.002, 103)),
      ],
      boarding: const MapCoordinate(1.001, 103),
      alighting: const MapCoordinate(1.003, 103),
    );

    expect(segment.usedFullShapeFallback, isFalse);
    expect(segment.points.map((point) => point.latitude), [
      1.001,
      1.002,
      1.003,
    ]);
  });

  test(
    'shape segmentation falls back to full shape when order is unreliable',
    () {
      final segment = segmentShape(
        shapePoints: const [
          ShapePoint(sequence: 1, coordinate: MapCoordinate(1.001, 103)),
          ShapePoint(sequence: 2, coordinate: MapCoordinate(1.002, 103)),
        ],
        boarding: const MapCoordinate(1.002, 103),
        alighting: const MapCoordinate(1.001, 103),
      );

      expect(segment.usedFullShapeFallback, isTrue);
      expect(segment.points, hasLength(2));
    },
  );
}
