import 'dart:math' as math;

import 'package:government_transit_collector/features/journey_map/data/journey_map_models.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/trip_progress_models.dart';

const earthRadiusMeters = 6371008.8;

double geographicDistanceMeters(MapCoordinate a, MapCoordinate b) {
  final lat1 = _radians(a.latitude);
  final lat2 = _radians(b.latitude);
  final deltaLat = lat2 - lat1;
  final deltaLon = _radians(b.longitude - a.longitude);
  final h =
      math.pow(math.sin(deltaLat / 2), 2) +
      math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(deltaLon / 2), 2);
  return 2 * earthRadiusMeters * math.asin(math.sqrt(h.clamp(0, 1)));
}

List<double> cumulativeShapeDistances(List<MapCoordinate> shape) {
  if (shape.isEmpty) return const [];
  final distances = <double>[0];
  for (var index = 1; index < shape.length; index++) {
    distances.add(
      distances.last + geographicDistanceMeters(shape[index - 1], shape[index]),
    );
  }
  return distances;
}

VehicleRouteProjection? projectCoordinateOntoShape({
  required MapCoordinate coordinate,
  required List<MapCoordinate> shape,
  List<double>? cumulativeDistances,
  double minimumProgressMeters = 0,
}) {
  if (shape.length < 2) return null;
  final cumulative = cumulativeDistances ?? cumulativeShapeDistances(shape);
  VehicleRouteProjection? best;
  for (var index = 0; index < shape.length - 1; index++) {
    final segmentStartProgress = cumulative[index];
    final segmentEndProgress = cumulative[index + 1];
    if (segmentEndProgress + 0.01 < minimumProgressMeters) continue;
    final candidate = _projectToSegment(
      coordinate,
      shape[index],
      shape[index + 1],
      index,
      segmentStartProgress,
      segmentEndProgress,
      minimumProgressMeters,
    );
    if (best == null ||
        candidate.distanceFromShapeMeters < best.distanceFromShapeMeters) {
      best = candidate;
    }
  }
  return best;
}

VehicleRouteProjection _projectToSegment(
  MapCoordinate point,
  MapCoordinate start,
  MapCoordinate end,
  int segmentIndex,
  double startProgress,
  double endProgress,
  double minimumProgress,
) {
  final referenceLat = _radians((start.latitude + end.latitude) / 2);
  ({double x, double y}) xy(MapCoordinate value) => (
    x: earthRadiusMeters * _radians(value.longitude) * math.cos(referenceLat),
    y: earthRadiusMeters * _radians(value.latitude),
  );
  final p = xy(point);
  final a = xy(start);
  final b = xy(end);
  final dx = b.x - a.x;
  final dy = b.y - a.y;
  final lengthSquared = dx * dx + dy * dy;
  var fraction = lengthSquared == 0
      ? 0.0
      : ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared;
  fraction = fraction.clamp(0.0, 1.0);
  final segmentLength = endProgress - startProgress;
  if (segmentLength > 0 && minimumProgress > startProgress) {
    fraction = math.max(
      fraction,
      ((minimumProgress - startProgress) / segmentLength).clamp(0.0, 1.0),
    );
  }
  final projected = MapCoordinate(
    start.latitude + (end.latitude - start.latitude) * fraction,
    start.longitude + (end.longitude - start.longitude) * fraction,
  );
  return VehicleRouteProjection(
    coordinate: projected,
    segmentIndex: segmentIndex,
    segmentFraction: fraction,
    progressMeters: startProgress + segmentLength * fraction,
    distanceFromShapeMeters: geographicDistanceMeters(point, projected),
  );
}

double _radians(double degrees) => degrees * math.pi / 180;
