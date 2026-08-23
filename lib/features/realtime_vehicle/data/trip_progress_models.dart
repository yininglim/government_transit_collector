import 'package:government_transit_collector/features/journey_map/data/journey_map_models.dart';

class TrackedTripStop {
  const TrackedTripStop({
    required this.stopId,
    required this.stopName,
    required this.stopSequence,
    required this.coordinate,
    required this.scheduledArrivalSeconds,
    required this.scheduledDepartureSeconds,
  });

  final String stopId;
  final String stopName;
  final int stopSequence;
  final MapCoordinate? coordinate;
  final int? scheduledArrivalSeconds;
  final int? scheduledDepartureSeconds;
}

class TripProgressData {
  const TripProgressData({
    required this.tripId,
    required this.shapePoints,
    required this.stops,
  });

  final String tripId;
  final List<MapCoordinate> shapePoints;
  final List<TrackedTripStop> stops;
}

class StopRouteProgress {
  const StopRouteProgress({
    required this.stop,
    required this.progressMeters,
    required this.distanceFromShapeMeters,
  });

  final TrackedTripStop stop;
  final double progressMeters;
  final double distanceFromShapeMeters;
}

class VehicleRouteProjection {
  const VehicleRouteProjection({
    required this.coordinate,
    required this.segmentIndex,
    required this.segmentFraction,
    required this.progressMeters,
    required this.distanceFromShapeMeters,
  });

  final MapCoordinate coordinate;
  final int segmentIndex;
  final double segmentFraction;
  final double progressMeters;
  final double distanceFromShapeMeters;
}

enum JourneyProgressAvailability { available, offRoute, shapeUnavailable }

class JourneyProgressState {
  const JourneyProgressState({
    required this.activeTripId,
    required this.availability,
    required this.completedStops,
    required this.nearestStop,
    required this.nextStop,
    required this.upcomingStops,
    required this.timestamp,
    this.busProgressMeters,
    this.totalShapeMeters,
    this.progressFraction,
    this.projectionDistanceMeters,
    this.wasJitterStabilized = false,
  });

  final String activeTripId;
  final JourneyProgressAvailability availability;
  final double? busProgressMeters;
  final double? totalShapeMeters;
  final double? progressFraction;
  final List<TrackedTripStop> completedStops;
  final TrackedTripStop? nearestStop;
  final TrackedTripStop? nextStop;
  final List<TrackedTripStop> upcomingStops;
  final double? projectionDistanceMeters;
  final DateTime? timestamp;
  final bool wasJitterStabilized;
}
