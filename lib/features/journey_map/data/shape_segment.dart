import 'package:government_transit_collector/features/journey_map/data/journey_map_models.dart';
import 'package:latlong2/latlong.dart';

class ShapePoint {
  const ShapePoint({required this.sequence, required this.coordinate});

  final int sequence;
  final MapCoordinate coordinate;
}

class ShapeSegment {
  const ShapeSegment({
    required this.points,
    required this.usedFullShapeFallback,
  });

  final List<MapCoordinate> points;
  final bool usedFullShapeFallback;
}

ShapeSegment segmentShape({
  required List<ShapePoint> shapePoints,
  required MapCoordinate boarding,
  required MapCoordinate alighting,
  double maximumStopDistanceMeters = 1000,
}) {
  final ordered = [...shapePoints]
    ..sort((left, right) => left.sequence.compareTo(right.sequence));
  final fullShape = ordered.map((point) => point.coordinate).toList();
  if (ordered.length < 2) {
    return ShapeSegment(
      points: fullShape,
      usedFullShapeFallback: fullShape.isNotEmpty,
    );
  }

  final start = _nearestPoint(ordered, boarding);
  final end = _nearestPoint(ordered, alighting);
  final reliable =
      start.distanceMeters <= maximumStopDistanceMeters &&
      end.distanceMeters <= maximumStopDistanceMeters &&
      start.index < end.index;
  if (!reliable) {
    return ShapeSegment(points: fullShape, usedFullShapeFallback: true);
  }
  return ShapeSegment(
    points: ordered
        .sublist(start.index, end.index + 1)
        .map((point) => point.coordinate)
        .toList(),
    usedFullShapeFallback: false,
  );
}

({int index, double distanceMeters}) _nearestPoint(
  List<ShapePoint> points,
  MapCoordinate target,
) {
  const distance = Distance();
  var nearestIndex = 0;
  var nearestDistance = double.infinity;
  for (var index = 0; index < points.length; index++) {
    final candidate = distance.as(
      LengthUnit.Meter,
      LatLng(target.latitude, target.longitude),
      LatLng(
        points[index].coordinate.latitude,
        points[index].coordinate.longitude,
      ),
    );
    if (candidate < nearestDistance) {
      nearestDistance = candidate;
      nearestIndex = index;
    }
  }
  return (index: nearestIndex, distanceMeters: nearestDistance);
}
