import 'dart:math' as math;

import 'package:government_transit_collector/features/realtime_vehicle/data/trip_progress_models.dart';

/// Urban buses reporting faster than 90 km/h are treated as GPS/projection
/// outliers rather than useful ETA evidence.
const defaultMaximumUrbanBusSpeedMetersPerSecond = 25.0;
const defaultMinimumMovementMeters = 2.0;
const defaultMaximumEtaChangePerObservation = Duration(minutes: 2);

enum ArrivalEstimateSource { realtimeAdjusted, scheduledFallback, unavailable }

class RealtimeMovementSample {
  const RealtimeMovementSample({
    required this.tripId,
    required this.vehicleId,
    required this.routeProgressMeters,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
  });

  final String tripId;
  final String? vehicleId;
  final double routeProgressMeters;
  final DateTime timestamp;
  final double latitude;
  final double longitude;
}

class ArrivalEstimate {
  const ArrivalEstimate({
    required this.nextStop,
    required this.source,
    required this.scheduledArrival,
    this.estimatedArrivalDuration,
    this.generatedFromVehicleTimestamp,
  });

  final TrackedTripStop? nextStop;
  final ArrivalEstimateSource source;
  final Duration? estimatedArrivalDuration;
  final DateTime? scheduledArrival;
  final DateTime? generatedFromVehicleTimestamp;

  bool get isRealtimeAdjusted =>
      source == ArrivalEstimateSource.realtimeAdjusted;
}

/// Keeps only genuine feed observations for one exact vehicle/trip identity.
/// Animated marker frames never pass through this class.
class RealtimeMovementHistory {
  RealtimeMovementHistory({this.maximumSamples = 5});

  final int maximumSamples;
  final List<RealtimeMovementSample> _samples = [];

  List<RealtimeMovementSample> get samples => List.unmodifiable(_samples);

  bool add(RealtimeMovementSample sample) {
    final latest = _samples.lastOrNull;
    if (latest != null &&
        (latest.tripId != sample.tripId ||
            latest.vehicleId != sample.vehicleId)) {
      _samples.clear();
    }
    final current = _samples.lastOrNull;
    if (current != null && !sample.timestamp.isAfter(current.timestamp)) {
      return false;
    }
    _samples.add(sample);
    if (_samples.length > maximumSamples) _samples.removeAt(0);
    return true;
  }

  void clear() => _samples.clear();
}

/// Local, approximate ETA calculation. data.gov.my supplies vehicle positions,
/// not an authoritative arrival prediction.
class ArrivalEstimator {
  const ArrivalEstimator({
    this.maximumSpeedMetersPerSecond =
        defaultMaximumUrbanBusSpeedMetersPerSecond,
    this.minimumMovementMeters = defaultMinimumMovementMeters,
    this.maximumEtaChangePerObservation = defaultMaximumEtaChangePerObservation,
  });

  final double maximumSpeedMetersPerSecond;
  final double minimumMovementMeters;
  final Duration maximumEtaChangePerObservation;

  ArrivalEstimate estimate({
    required TrackedTripStop? nextStop,
    required double? currentProgressMeters,
    required double? nextStopProgressMeters,
    required List<RealtimeMovementSample> samples,
    required DateTime currentTransitTime,
    required DateTime? scheduledArrival,
    required bool realtimeVehicleAvailable,
    required bool routeProjectionReliable,
    ArrivalEstimate? previous,
  }) {
    if (nextStop == null || scheduledArrival == null) {
      return ArrivalEstimate(
        nextStop: nextStop,
        source: ArrivalEstimateSource.unavailable,
        scheduledArrival: scheduledArrival,
      );
    }
    final scheduledRemaining = _nonNegativeDifference(
      scheduledArrival,
      currentTransitTime,
    );
    final progressReady =
        currentProgressMeters != null && nextStopProgressMeters != null;
    if (!realtimeVehicleAvailable ||
        !routeProjectionReliable ||
        !progressReady) {
      return ArrivalEstimate(
        nextStop: nextStop,
        source: ArrivalEstimateSource.scheduledFallback,
        scheduledArrival: scheduledArrival,
        estimatedArrivalDuration: scheduledRemaining,
      );
    }

    final speed = stabilizedSpeedMetersPerSecond(samples);
    if (speed == null) {
      return ArrivalEstimate(
        nextStop: nextStop,
        source: ArrivalEstimateSource.scheduledFallback,
        scheduledArrival: scheduledArrival,
        estimatedArrivalDuration: scheduledRemaining,
        generatedFromVehicleTimestamp: samples.lastOrNull?.timestamp,
      );
    }

    final remainingMeters = math.max(
      0,
      nextStopProgressMeters - currentProgressMeters,
    );
    final realtimeSeconds = remainingMeters / speed;
    final scheduleSeconds = scheduledRemaining.inSeconds.toDouble();
    // Keep useful realtime movement dominant, but bound it against the GTFS
    // baseline so one short observation cannot create false precision.
    final hybridSeconds = scheduleSeconds > 0
        ? (0.6 *
                  realtimeSeconds.clamp(
                    scheduleSeconds * 0.5,
                    scheduleSeconds * 2,
                  ) +
              0.4 * scheduleSeconds)
        : realtimeSeconds;
    var duration = Duration(seconds: hybridSeconds.round());
    if (previous?.isRealtimeAdjusted == true &&
        previous!.nextStop?.stopId == nextStop.stopId &&
        previous.estimatedArrivalDuration != null) {
      duration = _stabilize(duration, previous.estimatedArrivalDuration!);
    }
    return ArrivalEstimate(
      nextStop: nextStop,
      source: ArrivalEstimateSource.realtimeAdjusted,
      scheduledArrival: scheduledArrival,
      estimatedArrivalDuration: duration,
      generatedFromVehicleTimestamp: samples.lastOrNull?.timestamp,
    );
  }

  double? stabilizedSpeedMetersPerSecond(List<RealtimeMovementSample> samples) {
    final speeds = <double>[];
    for (var index = 1; index < samples.length; index++) {
      final previous = samples[index - 1];
      final current = samples[index];
      if (previous.tripId != current.tripId ||
          previous.vehicleId != current.vehicleId) {
        continue;
      }
      final seconds =
          current.timestamp.difference(previous.timestamp).inMilliseconds /
          1000;
      final movement =
          current.routeProgressMeters - previous.routeProgressMeters;
      if (seconds <= 0 || movement < minimumMovementMeters) continue;
      final speed = movement / seconds;
      if (speed <= 0 || speed > maximumSpeedMetersPerSecond) continue;
      speeds.add(speed);
    }
    if (speeds.isEmpty) return null;
    speeds.sort();
    final middle = speeds.length ~/ 2;
    return speeds.length.isOdd
        ? speeds[middle]
        : (speeds[middle - 1] + speeds[middle]) / 2;
  }

  Duration _nonNegativeDifference(DateTime later, DateTime earlier) {
    final difference = later.difference(earlier);
    return difference.isNegative ? Duration.zero : difference;
  }

  Duration _stabilize(Duration candidate, Duration previous) {
    final delta = candidate - previous;
    if (delta > maximumEtaChangePerObservation) {
      return previous + maximumEtaChangePerObservation;
    }
    if (delta < -maximumEtaChangePerObservation) {
      return previous - maximumEtaChangePerObservation;
    }
    return candidate;
  }
}

String formatApproximateArrivalDuration(Duration duration) {
  if (duration < const Duration(minutes: 1)) return '< 1 min';
  final minutes = (duration.inSeconds / 60).round().clamp(1, 999);
  return '~$minutes min';
}
