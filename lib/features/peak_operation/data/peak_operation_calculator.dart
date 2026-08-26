import 'package:government_transit_collector/core/time/transit_service_time.dart';
import 'package:government_transit_collector/features/peak_operation/data/peak_operation_models.dart';

const operationBucketMinutes = 30;

class PeakOperationCalculator {
  const PeakOperationCalculator();

  PeakOperationSummary calculate({
    required List<PeakOperationObservation> observations,
    required DateTime periodStart,
    required DateTime periodEnd,
    String? routeId,
  }) {
    final filtered =
        observations
            .where((row) => routeId == null || row.routeId == routeId)
            .toList()
          ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
    final dates = <String, DateTime>{};
    final bucketOccurrences = <int, Set<String>>{};
    final dailyOccurrences = <String, Set<String>>{};
    final routeOccurrences = <String, Set<String>>{};
    DateTime? windowStart;
    DateTime? windowEnd;

    for (final row in filtered) {
      final local = transitServiceDateTime(row.recordedAt);
      final dateKey = '${local.year}-${local.month}-${local.day}';
      dates[dateKey] = DateTime(local.year, local.month, local.day);
      final occurrence = '$dateKey\u0000${row.tripId}\u0000${row.vehicleId}';
      final minute = local.hour * 60 + local.minute;
      final bucket = minute ~/ operationBucketMinutes * operationBucketMinutes;
      bucketOccurrences.putIfAbsent(bucket, () => {}).add(occurrence);
      dailyOccurrences.putIfAbsent(dateKey, () => {}).add(occurrence);
      routeOccurrences.putIfAbsent(row.routeId, () => {}).add(occurrence);
      if (windowStart == null || local.isBefore(windowStart)) {
        windowStart = local;
      }
      if (windowEnd == null || local.isAfter(windowEnd)) windowEnd = local;
    }

    final days = dates.length;
    final rawBuckets =
        bucketOccurrences.entries
            .map(
              (entry) => (start: entry.key, average: entry.value.length / days),
            )
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    final maximum = rawBuckets.fold<double>(
      0,
      (value, bucket) => bucket.average > value ? bucket.average : value,
    );
    final buckets = rawBuckets
        .map((bucket) {
          final ratio = maximum == 0 ? 0 : bucket.average / maximum;
          return OperationTimeBucket(
            startMinute: bucket.start,
            averageActiveTrips: bucket.average,
            level: ratio >= .8
                ? ActivityLevel.high
                : ratio >= .5
                ? ActivityLevel.moderate
                : ActivityLevel.low,
          );
        })
        .toList(growable: false);
    final occurrenceIds = dailyOccurrences.values.expand((set) => set).toSet();
    final reliable = occurrenceIds.length >= 2 && buckets.length >= 2;
    final peaks = reliable
        ? buckets
              .where((bucket) => bucket.averageActiveTrips == maximum)
              .toList()
        : <OperationTimeBucket>[];
    final average = buckets.isEmpty
        ? 0.0
        : buckets.fold<double>(
                0,
                (sum, item) => sum + item.averageActiveTrips,
              ) /
              buckets.length;
    final difference = average == 0 || peaks.isEmpty
        ? 0.0
        : (maximum - average) / average * 100;
    final daily =
        dailyOccurrences.entries
            .map(
              (entry) => DailyOperationActivity(
                date: dates[entry.key]!,
                tripOccurrences: entry.value.length,
              ),
            )
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    final routeActivity =
        routeOccurrences.entries
            .map(
              (entry) => RouteActivitySummary(
                routeId: entry.key,
                tripOccurrences: entry.value.length,
              ),
            )
            .toList()
          ..sort((a, b) {
            final byCount = b.tripOccurrences.compareTo(a.tripOccurrences);
            return byCount != 0 ? byCount : a.routeId.compareTo(b.routeId);
          });

    return PeakOperationSummary(
      routeId: routeId,
      periodStart: periodStart,
      periodEnd: periodEnd,
      observationCount: filtered.length,
      distinctTripOccurrences: occurrenceIds.length,
      observedDayCount: days,
      routesRepresented: routeOccurrences.length,
      bucketBreakdown: buckets,
      peakBuckets: peaks,
      averageActivity: average,
      activityDifferencePercent: difference,
      dailyActivity: daily,
      routeActivity: routeActivity,
      observedWindowStart: windowStart,
      observedWindowEnd: windowEnd,
      hasReliablePeak: reliable,
      hasLimitedCoverage: days < 2 || buckets.length < 4,
    );
  }
}
