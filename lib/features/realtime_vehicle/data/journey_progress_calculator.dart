import 'dart:math' as math;

import 'package:government_transit_collector/features/journey_map/data/journey_map_models.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/route_geometry.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/trip_progress_models.dart';

const defaultMaximumProjectionDistanceMeters = 150.0;
const defaultCompletionToleranceMeters = 15.0;
const defaultBackwardJitterToleranceMeters = 30.0;
const defaultUpcomingStopLimit = 5;

class JourneyProgressCalculator {
  JourneyProgressCalculator(
    this.data, {
    this.maximumProjectionDistanceMeters =
        defaultMaximumProjectionDistanceMeters,
    this.completionToleranceMeters = defaultCompletionToleranceMeters,
    this.backwardJitterToleranceMeters = defaultBackwardJitterToleranceMeters,
    this.upcomingStopLimit = defaultUpcomingStopLimit,
  }) : cumulativeDistances = cumulativeShapeDistances(data.shapePoints) {
    _stopProgress = _mapStopsToShape();
  }

  final TripProgressData data;
  final double maximumProjectionDistanceMeters;
  final double completionToleranceMeters;
  final double backwardJitterToleranceMeters;
  final int upcomingStopLimit;
  final List<double> cumulativeDistances;
  late final List<StopRouteProgress> _stopProgress;

  List<StopRouteProgress> get stopProgress => List.unmodifiable(_stopProgress);

  JourneyProgressState calculate({
    required MapCoordinate vehicleCoordinate,
    required DateTime? timestamp,
    JourneyProgressState? previous,
  }) {
    if (data.shapePoints.length < 2 || cumulativeDistances.isEmpty) {
      return JourneyProgressState(
        activeTripId: data.tripId,
        availability: JourneyProgressAvailability.shapeUnavailable,
        completedStops: const [],
        nearestStop: null,
        nextStop: null,
        upcomingStops: const [],
        timestamp: timestamp,
      );
    }
    final nearestProjection = projectCoordinateOntoShape(
      coordinate: vehicleCoordinate,
      shape: data.shapePoints,
      cumulativeDistances: cumulativeDistances,
    );
    var raw = nearestProjection;
    final previousProgress = previous?.busProgressMeters;
    if (nearestProjection != null && previousProgress != null) {
      final contextualProjection = projectCoordinateOntoShape(
        coordinate: vehicleCoordinate,
        shape: data.shapePoints,
        cumulativeDistances: cumulativeDistances,
        minimumProgressMeters: _minimumContextProgress(previous),
      );
      final largeBackwardJump =
          nearestProjection.progressMeters <
          previousProgress - backwardJitterToleranceMeters;
      if (largeBackwardJump &&
          contextualProjection != null &&
          contextualProjection.distanceFromShapeMeters <=
              nearestProjection.distanceFromShapeMeters + 25) {
        raw = contextualProjection;
      }
    }
    if (raw == null ||
        raw.distanceFromShapeMeters > maximumProjectionDistanceMeters) {
      return JourneyProgressState(
        activeTripId: data.tripId,
        availability: JourneyProgressAvailability.offRoute,
        completedStops: previous?.completedStops ?? const [],
        nearestStop: previous?.nearestStop,
        nextStop: previous?.nextStop,
        upcomingStops: previous?.upcomingStops ?? const [],
        projectionDistanceMeters: raw?.distanceFromShapeMeters,
        timestamp: timestamp,
      );
    }

    var progress = raw.progressMeters;
    var stabilized = false;
    if (previousProgress != null && progress < previousProgress) {
      final backwards = previousProgress - progress;
      if (backwards <= backwardJitterToleranceMeters) {
        progress = previousProgress;
        stabilized = true;
      }
    }

    final completed = _stopProgress
        .where(
          (stop) => progress >= stop.progressMeters + completionToleranceMeters,
        )
        .map((stop) => stop.stop)
        .toList(growable: false);
    final remaining = _stopProgress
        .where(
          (stop) => progress < stop.progressMeters + completionToleranceMeters,
        )
        .toList(growable: false);
    final nearest = _stopProgress.isEmpty
        ? null
        : _stopProgress.reduce(
            (a, b) =>
                (a.progressMeters - progress).abs() <=
                    (b.progressMeters - progress).abs()
                ? a
                : b,
          );
    final total = cumulativeDistances.last;
    return JourneyProgressState(
      activeTripId: data.tripId,
      availability: JourneyProgressAvailability.available,
      busProgressMeters: progress,
      totalShapeMeters: total,
      progressFraction: total <= 0 ? 0 : (progress / total).clamp(0, 1),
      completedStops: completed,
      nearestStop: nearest?.stop,
      nextStop: remaining.firstOrNull?.stop,
      upcomingStops: remaining
          .take(upcomingStopLimit)
          .map((stop) => stop.stop)
          .toList(growable: false),
      projectionDistanceMeters: raw.distanceFromShapeMeters,
      timestamp: timestamp,
      wasJitterStabilized: stabilized,
    );
  }

  double _minimumContextProgress(JourneyProgressState? previous) {
    final progress = previous?.busProgressMeters;
    if (progress == null) return 0;
    return math.max(0, progress - backwardJitterToleranceMeters);
  }

  List<StopRouteProgress> _mapStopsToShape() {
    final mapped = <StopRouteProgress>[];
    var minimumProgress = 0.0;
    final orderedStops = [...data.stops]
      ..sort((a, b) => a.stopSequence.compareTo(b.stopSequence));
    for (final stop in orderedStops) {
      final coordinate = stop.coordinate;
      if (coordinate == null) continue;
      final projection = projectCoordinateOntoShape(
        coordinate: coordinate,
        shape: data.shapePoints,
        cumulativeDistances: cumulativeDistances,
        minimumProgressMeters: minimumProgress,
      );
      if (projection == null) continue;
      minimumProgress = projection.progressMeters;
      mapped.add(
        StopRouteProgress(
          stop: stop,
          progressMeters: projection.progressMeters,
          distanceFromShapeMeters: projection.distanceFromShapeMeters,
        ),
      );
    }
    return mapped;
  }
}
