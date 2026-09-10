enum ActivityLevel { high, moderate, low }

class PeakOperationRoute {
  const PeakOperationRoute({
    required this.routeId,
    this.shortName,
    this.longName,
  });
  final String routeId;
  final String? shortName;
  final String? longName;

  String get displayName {
    final short = shortName?.trim() ?? '';
    final long = longName?.trim() ?? '';
    if (short.isNotEmpty && long.isNotEmpty) return '$short — $long';
    return short.isNotEmpty
        ? short
        : long.isNotEmpty
        ? long
        : routeId;
  }
}

class PeakOperationObservation {
  const PeakOperationObservation({
    required this.routeId,
    required this.tripId,
    required this.vehicleId,
    required this.recordedAt,
  });
  final String routeId;
  final String tripId;
  final String vehicleId;
  final DateTime recordedAt;
}

class OperationTimeBucket {
  const OperationTimeBucket({
    required this.startMinute,
    required this.averageActiveTrips,
    required this.level,
  });
  final int startMinute;
  final double averageActiveTrips;
  final ActivityLevel level;
  int get endMinute => (startMinute + 30) % (24 * 60);
}

class DailyOperationActivity {
  const DailyOperationActivity({
    required this.date,
    required this.tripOccurrences,
  });
  final DateTime date;
  final int tripOccurrences;
}

class RouteActivitySummary {
  const RouteActivitySummary({
    required this.routeId,
    required this.tripOccurrences,
  });
  final String routeId;
  final int tripOccurrences;
}

class PeakOperationSummary {
  const PeakOperationSummary({
    required this.routeId,
    required this.periodStart,
    required this.periodEnd,
    required this.observationCount,
    required this.distinctTripOccurrences,
    required this.observedDayCount,
    required this.routesRepresented,
    required this.bucketBreakdown,
    required this.peakBuckets,
    required this.averageActivity,
    required this.activityDifferencePercent,
    required this.dailyActivity,
    required this.routeActivity,
    required this.observedWindowStart,
    required this.observedWindowEnd,
    required this.hasReliablePeak,
    required this.hasLimitedCoverage,
  });
  final String? routeId;
  final DateTime periodStart;
  final DateTime periodEnd;
  final int observationCount;
  final int distinctTripOccurrences;
  final int observedDayCount;
  final int routesRepresented;
  final List<OperationTimeBucket> bucketBreakdown;
  final List<OperationTimeBucket> peakBuckets;
  final double averageActivity;
  final double activityDifferencePercent;
  final List<DailyOperationActivity> dailyActivity;
  final List<RouteActivitySummary> routeActivity;
  final DateTime? observedWindowStart;
  final DateTime? observedWindowEnd;
  final bool hasReliablePeak;
  final bool hasLimitedCoverage;

  bool get hasData => observationCount > 0;
  OperationTimeBucket? get peakBucket => peakBuckets.firstOrNull;
  RouteActivitySummary? get busiestRoute => routeActivity.firstOrNull;
}
