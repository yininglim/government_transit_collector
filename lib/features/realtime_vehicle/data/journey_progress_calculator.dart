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
    this.selectedOriginStopId,
    this.selectedDestinationStopId,
  }) : cumulativeDistances = cumulativeShapeDistances(data.shapePoints) {
    _allStopProgress = _mapStopsToShape();
    _stopProgress = _selectedStops(_allStopProgress);
  }

  final TripProgressData data;
  final double maximumProjectionDistanceMeters;
  final double completionToleranceMeters;
  final double backwardJitterToleranceMeters;
  final int upcomingStopLimit;
  final String? selectedOriginStopId;
  final String? selectedDestinationStopId;
  final List<double> cumulativeDistances;
  late final List<StopRouteProgress> _allStopProgress;
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

    final completed = <TrackedTripStop>[];
    final remaining = <StopRouteProgress>[];
    for (var index = 0; index < _stopProgress.length; index++) {
      final stop = _stopProgress[index];
      final isFinalSelectedStop = index == _stopProgress.length - 1;
      final isCompleted = isFinalSelectedStop
          ? progress >= stop.progressMeters - 0.01
          : progress >= stop.progressMeters + completionToleranceMeters;
      if (isCompleted) {
        completed.add(stop.stop);
      } else {
        remaining.add(stop);
      }
    }
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
    final selectedOrigin = _stopProgress.firstOrNull?.progressMeters;
    final selectedDestination = _stopProgress.lastOrNull?.progressMeters;
    final selectedLength = selectedOrigin == null || selectedDestination == null
        ? null
        : selectedDestination - selectedOrigin;
    final passengerFraction = selectedLength == null || selectedLength <= 0
        ? (total <= 0 ? 0.0 : (progress / total).clamp(0.0, 1.0))
        : ((progress - selectedOrigin!) / selectedLength).clamp(0.0, 1.0);
    return JourneyProgressState(
      activeTripId: data.tripId,
      availability: JourneyProgressAvailability.available,
      busProgressMeters: progress,
      totalShapeMeters: total,
      progressFraction: passengerFraction,
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
      selectedOriginProgressMeters: selectedOrigin,
      selectedDestinationProgressMeters: selectedDestination,
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
      // GTFS stop_sequence is authoritative at loops/self-crossings. Moving
      // the lower bound slightly forward prevents a later repeated coordinate
      // from snapping back to the same earlier shape occurrence.
      minimumProgress = projection.progressMeters + 0.01;
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

  List<StopRouteProgress> _selectedStops(List<StopRouteProgress> stops) {
    if (selectedOriginStopId == null || selectedDestinationStopId == null) {
      return stops;
    }
    final originIndex = stops.indexWhere(
      (item) => item.stop.stopId == selectedOriginStopId,
    );
    final destinationIndex = stops.indexWhere(
      (item) => item.stop.stopId == selectedDestinationStopId,
    );
    if (originIndex < 0 || destinationIndex < originIndex) return stops;
    return stops.sublist(originIndex, destinationIndex + 1);
  }
}
