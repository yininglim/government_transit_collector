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
    expect(end.nextStop, isNull);
    expect(end.completedStops.last.stopName, 'End');
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

  group('selected passenger leg regression', () {
    final longData = data(
      stops: [
        stop('Before', 1, 0),
        stop('Origin', 2, 0.001),
        stop('Middle', 3, 0.002),
        stop('Destination', 4, 0.003),
        stop('After', 5, 0.004),
      ],
    );

    JourneyProgressCalculator selectedCalculator({
      String origin = 'Origin',
      String destination = 'Destination',
    }) => JourneyProgressCalculator(
      TripProgressData(
        tripId: longData.tripId,
        shapePoints: const [MapCoordinate(0, 0), MapCoordinate(0, 0.004)],
        stops: longData.stops,
      ),
      selectedOriginStopId: origin,
      selectedDestinationStopId: destination,
    );

    test('normalizes 0, 50, and 100 percent to selected boundaries', () {
      final calculator = selectedCalculator();
      expect(calculate(calculator, 0.001).progressFraction, closeTo(0, 0.01));
      expect(calculate(calculator, 0.002).progressFraction, closeTo(0.5, 0.01));
      expect(calculate(calculator, 0.003).progressFraction, closeTo(1, 0.01));
    });

    test('clamps before origin and after destination', () {
      final calculator = selectedCalculator();
      expect(calculate(calculator, 0.0005).progressFraction, 0);
      expect(calculate(calculator, 0.0035).progressFraction, 1);
    });

    test('passed origin advances next stop and passenger upcoming list', () {
      final result = calculate(selectedCalculator(), 0.0013);
      expect(result.completedStops.map((item) => item.stopName), ['Origin']);
      expect(result.nextStop?.stopName, 'Middle');
      expect(result.upcomingStops.map((item) => item.stopName), [
        'Middle',
        'Destination',
      ]);
      expect(result.nearestStop?.stopName, 'Origin');
    });

    test('before boarding keeps origin as next but excludes earlier stops', () {
      final result = calculate(selectedCalculator(), 0.0005);
      expect(result.nextStop?.stopName, 'Origin');
      expect(result.upcomingStops.map((item) => item.stopName), [
        'Origin',
        'Middle',
        'Destination',
      ]);
      expect(
        result.upcomingStops.map((item) => item.stopName),
        isNot(contains('Before')),
      );
    });

    test('destination completion has no future passenger stop', () {
      final result = calculate(selectedCalculator(), 0.003);
      expect(result.nextStop, isNull);
      expect(result.upcomingStops, isEmpty);
      expect(result.completedStops.last.stopName, 'Destination');
    });

    test('small jitter does not regress selected stop state', () {
      final calculator = selectedCalculator();
      final previous = calculate(calculator, 0.0022);
      final jittered = calculate(calculator, 0.0021, previous: previous);
      expect(jittered.busProgressMeters, previous.busProgressMeters);
      expect(jittered.completedStops, previous.completedStops);
      expect(jittered.nextStop?.stopName, previous.nextStop?.stopName);
    });

    test('independent transfer leg boundaries select their own stops', () {
      final first = selectedCalculator(origin: 'Before', destination: 'Middle');
      final second = selectedCalculator(origin: 'Middle', destination: 'After');
      expect(calculate(first, 0.001).progressFraction, closeTo(0.5, 0.01));
      expect(calculate(second, 0.003).progressFraction, closeTo(0.5, 0.01));
      expect(first.stopProgress.map((item) => item.stop.stopName), [
        'Before',
        'Origin',
        'Middle',
      ]);
      expect(second.stopProgress.map((item) => item.stop.stopName), [
        'Middle',
        'Destination',
        'After',
      ]);
    });

    test('has no special treatment for a route beginning at JB Sentral', () {
      final calculator = JourneyProgressCalculator(
        TripProgressData(
          tripId: 'from-jb',
          shapePoints: const [MapCoordinate(0, 0), MapCoordinate(0, 0.003)],
          stops: [
            stop('JB Sentral', 1, 0),
            stop('Wisma Peladang', 2, 0.0015),
            stop('Other Destination', 3, 0.003),
          ],
        ),
        selectedOriginStopId: 'JB Sentral',
        selectedDestinationStopId: 'Other Destination',
      );
      final result = calculate(calculator, 0.0018);
      expect(result.completedStops.map((item) => item.stopName), [
        'JB Sentral',
        'Wisma Peladang',
      ]);
      expect(result.nextStop?.stopName, 'Other Destination');
    });

    test('has no special treatment for a route ending at JB Sentral', () {
      final calculator = JourneyProgressCalculator(
        TripProgressData(
          tripId: 'to-jb',
          shapePoints: const [MapCoordinate(0, 0), MapCoordinate(0, 0.003)],
          stops: [
            stop('Other Origin', 1, 0),
            stop('Middle Elsewhere', 2, 0.0015),
            stop('JB Sentral', 3, 0.003),
          ],
        ),
        selectedOriginStopId: 'Other Origin',
        selectedDestinationStopId: 'JB Sentral',
      );
      expect(calculate(calculator, 0.002).nextStop?.stopName, 'JB Sentral');
    });

    test('GTFS sequence disambiguates a repeated self-crossing coordinate', () {
      final calculator = JourneyProgressCalculator(
        TripProgressData(
          tripId: 'loop',
          shapePoints: const [
            MapCoordinate(0, 0),
            MapCoordinate(0, 0.002),
            MapCoordinate(0.001, 0.001),
            MapCoordinate(0, 0),
            MapCoordinate(0, 0.003),
          ],
          stops: [
            stop('First crossing', 1, 0),
            stop('Loop apex', 2, 0.001),
            stop('Second crossing', 3, 0),
            stop('End', 4, 0.003),
          ],
        ),
      );
      final progresses = calculator.stopProgress
          .map((item) => item.progressMeters)
          .toList();
      expect(progresses[2], greaterThan(progresses[1]));
      expect(progresses[3], greaterThan(progresses[2]));
    });
  });
}
