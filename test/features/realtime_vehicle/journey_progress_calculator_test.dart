import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_models.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/journey_progress_calculator.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/trip_progress_models.dart';

TrackedTripStop stop(String name, int sequence, double? longitude) =>
    TrackedTripStop(
      stopId: name,
      stopName: name,
      stopSequence: sequence,
      coordinate: longitude == null ? null : MapCoordinate(0, longitude),
      scheduledArrivalSeconds: sequence * 60,
      scheduledDepartureSeconds: sequence * 60,
    );

TripProgressData data({List<TrackedTripStop>? stops}) => TripProgressData(
  tripId: 'exact-trip',
  shapePoints: const [MapCoordinate(0, 0), MapCoordinate(0, 0.003)],
  stops:
      stops ??
      [stop('Start', 1, 0), stop('Middle', 2, 0.0015), stop('End', 3, 0.003)],
);

JourneyProgressState calculate(
  JourneyProgressCalculator calculator,
  double longitude, {
  JourneyProgressState? previous,
  double latitude = 0,
}) => calculator.calculate(
  vehicleCoordinate: MapCoordinate(latitude, longitude),
  timestamp: DateTime.utc(2026),
  previous: previous,
);

void main() {
  test('maps stops in GTFS sequence and skips missing coordinates', () {
    final calculator = JourneyProgressCalculator(
      data(
        stops: [
          stop('Third', 3, 0.003),
          stop('Missing', 2, null),
          stop('First', 1, 0),
        ],
      ),
    );
    expect(calculator.stopProgress.map((item) => item.stop.stopSequence), [
      1,
      3,
    ]);
  });

  test('start, middle, and end produce conservative ordered stop states', () {
    final calculator = JourneyProgressCalculator(data());
    final start = calculate(calculator, 0);
    expect(start.completedStops, isEmpty);
    expect(start.nextStop?.stopName, 'Start');

    final beforeMiddle = calculate(calculator, 0.00145);
    expect(beforeMiddle.completedStops.map((stop) => stop.stopName), ['Start']);
    expect(beforeMiddle.nextStop?.stopName, 'Middle');

    final afterMiddle = calculate(calculator, 0.0017);
    expect(afterMiddle.completedStops.map((stop) => stop.stopName), [
      'Start',
      'Middle',
    ]);
    expect(afterMiddle.upcomingStops.map((stop) => stop.stopName), ['End']);

    final end = calculate(calculator, 0.003);
    expect(end.nearestStop?.stopName, 'End');
    expect(end.nextStop?.stopName, 'End');
  });

  test('vehicle far from route is unreliable and does not claim progress', () {
    final result = calculate(
      JourneyProgressCalculator(data()),
      0.001,
      latitude: 1,
    );
    expect(result.availability, JourneyProgressAvailability.offRoute);
    expect(result.busProgressMeters, isNull);
  });

  test(
    'small backward GPS jitter is stabilized without forward extrapolation',
    () {
      final calculator = JourneyProgressCalculator(data());
      final previous = calculate(calculator, 0.0015);
      final jittered = calculate(calculator, 0.0014, previous: previous);
      expect(jittered.busProgressMeters, previous.busProgressMeters);
      expect(jittered.wasJitterStabilized, isTrue);

      final unchanged = calculate(calculator, 0.0015, previous: previous);
      expect(
        unchanged.busProgressMeters,
        closeTo(previous.busProgressMeters!, 0.01),
      );
      expect(unchanged.wasJitterStabilized, isFalse);
    },
  );

  test('genuine large backward projection is retained', () {
    final calculator = JourneyProgressCalculator(data());
    final previous = calculate(calculator, 0.0025);
    final backwards = calculate(calculator, 0.0005, previous: previous);
    expect(backwards.busProgressMeters, lessThan(previous.busProgressMeters!));
    expect(backwards.wasJitterStabilized, isFalse);
  });

  test('missing shape reports progress unavailable', () {
    final calculator = JourneyProgressCalculator(
      TripProgressData(
        tripId: 'exact-trip',
        shapePoints: const [],
        stops: [stop('A', 1, 0)],
      ),
    );
    expect(
      calculate(calculator, 0).availability,
      JourneyProgressAvailability.shapeUnavailable,
    );
  });
}
