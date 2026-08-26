enum TripCoverageStatus { sufficientlyCovered, partial, insufficient }

class RoutePerformanceRoute {
  const RoutePerformanceRoute({
    required this.routeId,
    required this.shortName,
    required this.longName,
  });

  final String routeId;
  final String? shortName;
  final String? longName;

  String get displayName {
    final short = shortName?.trim() ?? '';
    final long = longName?.trim() ?? '';
    if (short.isNotEmpty && long.isNotEmpty) return '$short — $long';
    if (short.isNotEmpty) return short;
    if (long.isNotEmpty) return long;
    return routeId;
  }
}

class HistoricalVehicleObservation {
  const HistoricalVehicleObservation({
    required this.routeId,
    required this.tripId,
    required this.vehicleId,
    required this.recordedAt,
    required this.latitude,
    required this.longitude,
  });

  final String routeId;
  final String tripId;
  final String vehicleId;
  final DateTime recordedAt;
  final double latitude;
  final double longitude;
}

class ScheduledTripReference {
  const ScheduledTripReference({
    required this.tripId,
    required this.startSeconds,
    required this.endSeconds,
    required this.startLatitude,
    required this.startLongitude,
    required this.endLatitude,
    required this.endLongitude,
  });

  final String tripId;
  final int startSeconds;
  final int endSeconds;
  final double startLatitude;
  final double startLongitude;
  final double endLatitude;
  final double endLongitude;

  Duration get scheduledDuration =>
      Duration(seconds: endSeconds - startSeconds);
}

class RoutePerformanceData {
  const RoutePerformanceData({
    required this.observations,
    required this.schedulesByTripId,
  });

  final List<HistoricalVehicleObservation> observations;
  final Map<String, ScheduledTripReference> schedulesByTripId;
}

class ObservedTripPerformance {
  const ObservedTripPerformance({
    required this.routeId,
    required this.tripId,
    required this.vehicleId,
    required this.serviceDate,
    required this.scheduledDuration,
    required this.firstObservedAt,
    required this.lastObservedAt,
    required this.observationCount,
    required this.coverageStatus,
    required this.coverageReason,
    this.observedDuration,
  });

  final String routeId;
  final String tripId;
  final String vehicleId;
  final DateTime serviceDate;
  final Duration scheduledDuration;
  final DateTime firstObservedAt;
  final DateTime lastObservedAt;
  final int observationCount;
  final TripCoverageStatus coverageStatus;
  final String coverageReason;
  final Duration? observedDuration;

  bool get isSufficientlyCovered =>
      coverageStatus == TripCoverageStatus.sufficientlyCovered;

  Duration? get delay =>
      observedDuration == null ? null : observedDuration! - scheduledDuration;

  double? get scheduleAdherencePercent {
    final observed = observedDuration;
    final scheduledSeconds = scheduledDuration.inSeconds;
    if (observed == null || scheduledSeconds <= 0) return null;
    final difference = (observed.inSeconds - scheduledSeconds).abs();
    return ((1 - difference / scheduledSeconds).clamp(0, 1) * 100);
  }
}

class RoutePerformanceSummary {
  const RoutePerformanceSummary({
    required this.trips,
    required this.totalObservations,
    required this.averageTravelTime,
    required this.delayedTripCount,
    required this.delayFrequencyPercent,
    required this.scheduleAdherencePercent,
  });

  final List<ObservedTripPerformance> trips;
  final int totalObservations;
  final Duration? averageTravelTime;
  final int delayedTripCount;
  final double? delayFrequencyPercent;
  final double? scheduleAdherencePercent;

  List<ObservedTripPerformance> get completeTrips =>
      trips.where((trip) => trip.isSufficientlyCovered).toList(growable: false);
  int get partialTripCount => trips.length - completeTrips.length;
}
