import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_models.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/route_geometry.dart';

void main() {
  const shape = [
    MapCoordinate(0, 0),
    MapCoordinate(0, 0.001),
    MapCoordinate(0, 0.002),
  ];

  test('cumulative distances increase along each ordered shape segment', () {
    final distances = cumulativeShapeDistances(shape);
    expect(distances.first, 0);
    expect(distances[1], closeTo(111.2, 0.5));
    expect(distances[2], closeTo(222.4, 1));
  });

  test('projects between shape points with segment and fraction', () {
    final projection = projectCoordinateOntoShape(
      coordinate: const MapCoordinate(0.0001, 0.0005),
      shape: shape,
    )!;
    expect(projection.segmentIndex, 0);
    expect(projection.segmentFraction, closeTo(0.5, 0.01));
    expect(projection.progressMeters, closeTo(55.6, 1));
    expect(projection.distanceFromShapeMeters, closeTo(11.1, 1));
  });

  test('chooses the closest shape segment near the end', () {
    final projection = projectCoordinateOntoShape(
      coordinate: const MapCoordinate(0, 0.0018),
      shape: shape,
    )!;
    expect(projection.segmentIndex, 1);
    expect(projection.progressMeters, closeTo(200.2, 1));
  });

  test('minimum progress disambiguates a self-crossing shape', () {
    const loop = [
      MapCoordinate(0, 0),
      MapCoordinate(0.001, 0.001),
      MapCoordinate(0, 0.001),
      MapCoordinate(0.001, 0),
    ];
    final cumulative = cumulativeShapeDistances(loop);
    final early = projectCoordinateOntoShape(
      coordinate: const MapCoordinate(0.0005, 0.0005),
      shape: loop,
      cumulativeDistances: cumulative,
    )!;
    final later = projectCoordinateOntoShape(
      coordinate: const MapCoordinate(0.0005, 0.0005),
      shape: loop,
      cumulativeDistances: cumulative,
      minimumProgressMeters: cumulative[2],
    )!;
    expect(early.segmentIndex, 0);
    expect(later.segmentIndex, 2);
    expect(later.progressMeters, greaterThan(early.progressMeters));
  });
}
