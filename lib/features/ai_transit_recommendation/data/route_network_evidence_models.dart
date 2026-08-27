import 'package:government_transit_collector/features/journey_map/data/journey_map_models.dart';
import 'package:government_transit_collector/features/journey_map/data/shape_segment.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';

class AiRouteNetworkEvidence {
  const AiRouteNetworkEvidence({required this.route, required this.trips});

  final RoutePerformanceRoute route;
  final List<AiRouteTripEvidence> trips;
}

class AiRouteTripEvidence {
  const AiRouteTripEvidence({
    required this.tripId,
    required this.shapeId,
    required this.stops,
    required this.shapePoints,
    required this.routeDistanceMeters,
  });

  final String tripId;
  final String? shapeId;
  final List<AiRouteStopEvidence> stops;
  final List<ShapePoint> shapePoints;
  final double? routeDistanceMeters;
}

class AiRouteStopEvidence {
  const AiRouteStopEvidence({
    required this.stopId,
    required this.stopName,
    required this.stopSequence,
    required this.coordinate,
    required this.scheduledArrivalSeconds,
    required this.scheduledDepartureSeconds,
  });

  final String stopId;
  final String? stopName;
  final int stopSequence;
  final MapCoordinate? coordinate;
  final int? scheduledArrivalSeconds;
  final int? scheduledDepartureSeconds;
}
