import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/peak_operation/data/peak_operation_calculator.dart';
import 'package:government_transit_collector/features/peak_operation/data/peak_operation_models.dart';

void main() {
  const calculator = PeakOperationCalculator();
  PeakOperationSummary run(
    List<PeakOperationObservation> rows, {
    String? route,
  }) => calculator.calculate(
    observations: rows,
    periodStart: DateTime.utc(2026, 8, 25, 16),
    periodEnd: DateTime.utc(2026, 8, 28, 16),
    routeId: route,
  );

  test('multiple samples from one occurrence count once in a bucket', () {
    final summary = run([row(0, 1), row(0, 3), row(0, 20)]);
    expect(summary.bucketBreakdown.single.averageActiveTrips, 1);
    expect(summary.distinctTripOccurrences, 1);
    expect(summary.observationCount, 3);
  });

  test('same occurrence counts once in each different bucket', () {
    final summary = run([row(0, 1), row(0, 31)]);
    expect(summary.bucketBreakdown, hasLength(2));
    expect(summary.bucketBreakdown.map((b) => b.averageActiveTrips), [1, 1]);
  });

  test(
    'same trip on different local dates remains separate and normalized',
    () {
      final summary = run([row(0, 1), row(24, 1)]);
      expect(summary.observedDayCount, 2);
      expect(summary.distinctTripOccurrences, 2);
      expect(summary.bucketBreakdown.single.averageActiveTrips, 1);
    },
  );

  test('multiple vehicles and trips are distinct', () {
    final summary = run([
      row(0, 1),
      row(0, 2, trip: 'two'),
      row(0, 3, vehicle: 'two'),
    ]);
    expect(summary.distinctTripOccurrences, 3);
    expect(summary.bucketBreakdown.single.averageActiveTrips, 3);
  });

  test('assigns Asia Singapore times to 30 minute buckets', () {
    final summary = run([
      rowUtc(DateTime.utc(2026, 8, 26, 0, 29)),
      rowUtc(DateTime.utc(2026, 8, 26, 0, 30), trip: 'two'),
    ]);
    expect(summary.bucketBreakdown.map((bucket) => bucket.startMinute), [
      480,
      510,
    ]);
  });

  test('after-midnight local observations use their local date', () {
    final summary = run([
      rowUtc(DateTime.utc(2026, 8, 26, 16, 5)),
      rowUtc(DateTime.utc(2026, 8, 27, 16, 5)),
    ]);
    expect(summary.observedDayCount, 2);
  });

  test('identifies tied peaks and classifications', () {
    final summary = run([
      row(0, 1),
      row(0, 2, trip: 'b'),
      row(0, 31),
      row(0, 32, trip: 'b'),
      row(0, 61, trip: 'c'),
    ]);
    expect(summary.peakBuckets, hasLength(2));
    expect(
      summary.peakBuckets.every((bucket) => bucket.level == ActivityLevel.high),
      isTrue,
    );
    expect(summary.bucketBreakdown.last.level, ActivityLevel.moderate);
  });

  test('classifies low below half of maximum', () {
    final rows = [
      for (var i = 0; i < 5; i++) row(0, i, trip: 't$i'),
      row(0, 61, trip: 'last'),
    ];
    expect(run(rows).bucketBreakdown.last.level, ActivityLevel.low);
  });

  test('network counts, route filtering, and busiest route are distinct', () {
    final rows = [
      row(0, 1, route: 'A'),
      row(0, 2, route: 'A', trip: '2'),
      row(0, 1, route: 'B', trip: '3'),
      row(0, 3, route: 'A'),
    ];
    final network = run(rows);
    expect(network.routesRepresented, 2);
    expect(network.busiestRoute!.routeId, 'A');
    expect(network.busiestRoute!.tripOccurrences, 2);
    expect(run(rows, route: 'B').observationCount, 1);
  });

  test('derives observed service window from timestamps', () {
    final summary = run([row(0, 1), row(0, 165, trip: 'two')]);
    expect(summary.observedWindowStart!.hour, 8);
    expect(summary.observedWindowEnd!.hour, 10);
    expect(summary.observedWindowEnd!.minute, 45);
  });

  test('no data and limited data states are explicit', () {
    expect(run([]).hasData, isFalse);
    final limited = run([row(0, 1)]);
    expect(limited.hasReliablePeak, isFalse);
    expect(limited.hasLimitedCoverage, isTrue);
  });
}

PeakOperationObservation row(
  int dayOffset,
  int minute, {
  String route = 'A',
  String trip = 'trip',
  String vehicle = 'bus',
}) => rowUtc(
  DateTime.utc(2026, 8, 26 + dayOffset, 0, minute),
  route: route,
  trip: trip,
  vehicle: vehicle,
);

PeakOperationObservation rowUtc(
  DateTime time, {
  String route = 'A',
  String trip = 'trip',
  String vehicle = 'bus',
}) => PeakOperationObservation(
  routeId: route,
  tripId: trip,
  vehicleId: vehicle,
  recordedAt: time,
);
