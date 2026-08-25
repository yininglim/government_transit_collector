import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_models.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_repository.dart';
import 'package:government_transit_collector/features/journey_map/data/shape_segment.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/trip_progress_repository.dart';

class FakeMapSource implements JourneyMapDataSource {
  List<String>? requestedTrips;
  List<String>? requestedStops;
  List<String>? requestedShapes;

  @override
  Future<List<TripShapeReference>> loadTripShapes(List<String> tripIds) async {
    requestedTrips = tripIds;
    return const [TripShapeReference(tripId: 'exact-trip', shapeId: 'shape-1')];
  }

  @override
  Future<List<MapStopRecord>> loadStops(List<String> stopIds) async {
    requestedStops = stopIds;
    return const [
      MapStopRecord(
        stopId: 'a',
        name: 'Stop A',
        coordinate: MapCoordinate(1, 103),
      ),
      MapStopRecord(stopId: 'b', name: 'Stop B', coordinate: null),
    ];
  }

  @override
  Future<Map<String, List<ShapePoint>>> loadShapePoints(
    List<String> shapeIds,
  ) async {
    requestedShapes = shapeIds;
    return const {
      'shape-1': [
        ShapePoint(sequence: 2, coordinate: MapCoordinate(1.1, 103.1)),
        ShapePoint(sequence: 1, coordinate: MapCoordinate(1, 103)),
      ],
    };
  }
}

class FakeStopTimeSource implements TripProgressStopTimeDataSource {
  String? requestedTrip;

  @override
  Future<List<TripStopTimeRecord>> loadStopTimes(String tripId) async {
    requestedTrip = tripId;
    return const [
      TripStopTimeRecord(
        stopId: 'b',
        stopSequence: 20,
        arrivalSeconds: 200,
        departureSeconds: 210,
      ),
      TripStopTimeRecord(
        stopId: 'a',
        stopSequence: 10,
        arrivalSeconds: 100,
        departureSeconds: 110,
      ),
    ];
  }
}

void main() {
  test(
    'loads only the exact trip and reuses map shape/stop infrastructure',
    () async {
      final map = FakeMapSource();
      final stopTimes = FakeStopTimeSource();
      final result = await GtfsTripProgressRepository(
        mapDataSource: map,
        stopTimeDataSource: stopTimes,
      ).loadTrip('exact-trip');

      expect(map.requestedTrips, ['exact-trip']);
      expect(stopTimes.requestedTrip, 'exact-trip');
      expect(map.requestedShapes, ['shape-1']);
      expect(map.requestedStops, containsAll(['a', 'b']));
      expect(result.tripId, 'exact-trip');
      expect(result.stops.map((stop) => stop.stopSequence), [10, 20]);
      expect(result.stops.first.stopName, 'Stop A');
      expect(result.stops.last.coordinate, isNull);
      expect(result.shapePoints, hasLength(2));
      expect(result.shapePoints.first, const MapCoordinate(1, 103));
    },
  );
}
