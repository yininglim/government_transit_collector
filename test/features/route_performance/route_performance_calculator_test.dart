import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_calculator.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';

void main() {
  const calculator = RoutePerformanceCalculator();
  const schedule = ScheduledTripReference(
    tripId: 'trip',
    startSeconds: 8 * 3600,
    endSeconds: 8 * 3600 + 1800,
    startLatitude: 1.0,
    startLongitude: 103.0,
    endLatitude: 1.1,
    endLongitude: 103.1,
  );

  RoutePerformanceSummary calculate(
    List<HistoricalVehicleObservation> rows, {
    ScheduledTripReference reference = schedule,
  }) => calculator.calculate(
    RoutePerformanceData(
      observations: rows,
      schedulesByTripId: {'trip': reference},
    ),
  );

  List<HistoricalVehicleObservation> complete({
    DateTime? start,
    Duration duration = const Duration(minutes: 30),
    String vehicle = 'bus',
  }) {
    final first = start ?? DateTime.utc(2026, 8, 26, 0);
    return [
      observation(first, 1, 103, vehicle: vehicle),
      observation(
        first.add(const Duration(minutes: 10)),
        1.05,
        103.05,
        vehicle: vehicle,
      ),
      observation(first.add(duration), 1.1, 103.1, vehicle: vehicle),
    ];
  }

  test('sorts observations and classifies a sufficiently covered trip', () {
    final rows = complete().reversed.toList();
    final trip = calculate(rows).completeTrips.single;
    expect(trip.observedDuration, const Duration(minutes: 30));
    expect(trip.observationCount, 3);
  });

  test(
    'same exact trip and vehicle on different service dates stay separate',
    () {
      final summary = calculate([
        ...complete(),
        ...complete(start: DateTime.utc(2026, 8, 27)),
      ]);
      expect(summary.trips, hasLength(2));
    },
  );

  test('vehicle IDs form separate trip occurrences', () {
    expect(
      calculate([...complete(), ...complete(vehicle: 'bus-2')]).trips,
      hasLength(2),
    );
  });

  test('too few samples are insufficient', () {
    final result = calculate(complete().take(2).toList()).trips.single;
    expect(result.coverageStatus, TripCoverageStatus.insufficient);
    expect(result.coverageReason, 'Too few samples');
  });

  test('missing endpoint is partial and excluded', () {
    final rows = complete();
    rows[2] = observation(rows[2].recordedAt, 1.05, 103.05);
    final summary = calculate(rows);
    expect(summary.trips.single.coverageStatus, TripCoverageStatus.partial);
    expect(summary.averageTravelTime, isNull);
  });

  test('scheduled and observed durations are derived independently', () {
    final trip = calculate(
      complete(duration: const Duration(minutes: 36)),
    ).trips.single;
    expect(trip.scheduledDuration, const Duration(minutes: 30));
    expect(trip.observedDuration, const Duration(minutes: 36));
  });

  test('GTFS service times beyond 24:00 use the preceding service date', () {
    const afterMidnight = ScheduledTripReference(
      tripId: 'trip',
      startSeconds: 25 * 3600,
      endSeconds: 26 * 3600,
      startLatitude: 1,
      startLongitude: 103,
      endLatitude: 1.1,
      endLongitude: 103.1,
    );
    final trip = calculate(
      complete(
        start: DateTime.utc(2026, 8, 26, 17),
        duration: const Duration(hours: 1),
      ),
      reference: afterMidnight,
    ).trips.single;
    expect(trip.serviceDate, DateTime(2026, 8, 26));
    expect(trip.scheduledDuration, const Duration(hours: 1));
  });

  test('exactly five minutes late is within threshold', () {
    final summary = calculate(complete(duration: const Duration(minutes: 35)));
    expect(summary.delayedTripCount, 0);
  });

  test('more than five minutes late is delayed', () {
    final summary = calculate(complete(duration: const Duration(minutes: 36)));
    expect(summary.delayedTripCount, 1);
    expect(summary.delayFrequencyPercent, 100);
  });

  test('on-time trip is not delayed', () {
    expect(calculate(complete()).delayedTripCount, 0);
  });

  test('matching observed and scheduled duration has 100% adherence', () {
    expect(
      calculate(complete()).completeTrips.single.scheduleAdherencePercent,
      100,
    );
  });

  test('equally faster and slower trips have equal adherence', () {
    final faster = calculate(
      complete(duration: const Duration(minutes: 27)),
    ).completeTrips.single.scheduleAdherencePercent!;
    final slower = calculate(
      complete(duration: const Duration(minutes: 33)),
    ).completeTrips.single.scheduleAdherencePercent!;
    expect(faster, closeTo(90, 0.001));
    expect(slower, closeTo(90, 0.001));
  });

  test('extreme differences are bounded between zero and 100%', () {
    final zero = calculate(
      complete(duration: const Duration(minutes: 60)),
    ).completeTrips.single.scheduleAdherencePercent!;
    final fast = calculate(
      complete(duration: const Duration(minutes: 1)),
    ).completeTrips.single.scheduleAdherencePercent!;
    expect(zero, 0);
    expect(fast, inInclusiveRange(0, 100));
  });

  test('aggregates average, delay frequency, and schedule adherence', () {
    final summary = calculate([
      ...complete(duration: const Duration(minutes: 30)),
      ...complete(vehicle: 'bus-2', duration: const Duration(minutes: 60)),
    ]);
    expect(summary.averageTravelTime, const Duration(minutes: 45));
    expect(summary.delayFrequencyPercent, 50);
    expect(summary.scheduleAdherencePercent, closeTo(50, 0.001));
  });

  test('no complete trips returns unavailable metrics', () {
    final summary = calculate(complete().take(2).toList());
    expect(summary.averageTravelTime, isNull);
    expect(summary.delayFrequencyPercent, isNull);
    expect(summary.scheduleAdherencePercent, isNull);
  });

  test('mixed complete and partial trips only aggregate complete data', () {
    final partial = complete(vehicle: 'partial');
    partial[2] = observation(
      partial[2].recordedAt,
      1.05,
      103.05,
      vehicle: 'partial',
    );
    final summary = calculate([...complete(), ...partial]);
    expect(summary.completeTrips, hasLength(1));
    expect(summary.partialTripCount, 1);
    expect(summary.averageTravelTime, const Duration(minutes: 30));
    expect(summary.scheduleAdherencePercent, 100);
  });
}

HistoricalVehicleObservation observation(
  DateTime at,
  double latitude,
  double longitude, {
  String vehicle = 'bus',
}) => HistoricalVehicleObservation(
  routeId: 'route',
  tripId: 'trip',
  vehicleId: vehicle,
  recordedAt: at,
  latitude: latitude,
  longitude: longitude,
);
