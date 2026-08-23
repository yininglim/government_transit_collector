import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_position.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/selected_journey_realtime_matcher.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/selected_journey_tracking.dart';

import 'selected_journey_tracking_test.dart' as fixtures;

RealtimeVehiclePosition vehicle({
  required String? tripId,
  String vehicleId = 'bus',
  String routeId = 'route-15',
  int timestamp = 100,
  double latitude = 1.49,
}) => RealtimeVehiclePosition(
  vehicleId: vehicleId,
  tripId: tripId,
  routeId: routeId,
  latitude: latitude,
  longitude: 103.74,
  timestampSeconds: timestamp,
);

SelectedJourneyTracking directJourney() =>
    SelectedJourneyTracking.fromRecommendation(
      recommendation: fixtures.directRecommendation,
      originStopName: 'Origin',
      destinationStopName: 'Destination',
      travelDate: DateTime(2026, 8, 23),
    );

SelectedJourneyTracking transferJourney() =>
    SelectedJourneyTracking.fromRecommendation(
      recommendation: fixtures.transferRecommendation,
      originStopName: 'Origin',
      destinationStopName: 'Destination',
      travelDate: DateTime(2026, 8, 23),
    );

void main() {
  test('direct matching accepts only the exact trip ID', () {
    final result = matchSelectedJourneyVehicles(
      journey: directJourney(),
      vehicles: [
        vehicle(tripId: 'wrong-trip', vehicleId: 'same-route'),
        vehicle(tripId: null, vehicleId: 'missing-trip'),
        vehicle(tripId: 'direct-trip', vehicleId: 'exact'),
      ],
    );
    expect(result.byLeg.single?.vehicleId, 'exact');
  });

  test('same route with a different trip ID is rejected', () {
    final result = matchSelectedJourneyVehicles(
      journey: directJourney(),
      vehicles: [vehicle(tripId: 'other-trip', routeId: 'route-15')],
    );
    expect(result.byLeg.single, isNull);
  });

  test('same route with the same trip ID is accepted', () {
    final result = matchSelectedJourneyVehicles(
      journey: directJourney(),
      vehicles: [vehicle(tripId: 'direct-trip', routeId: 'route-15')],
    );
    expect(result.byLeg.single, isNotNull);
  });

  test('duplicate exact trip entities choose newest then deterministic ID', () {
    final result = matchSelectedJourneyVehicles(
      journey: directJourney(),
      vehicles: [
        vehicle(tripId: 'direct-trip', vehicleId: 'old', timestamp: 100),
        vehicle(tripId: 'direct-trip', vehicleId: 'z-bus', timestamp: 200),
        vehicle(tripId: 'direct-trip', vehicleId: 'a-bus', timestamp: 200),
      ],
    );
    expect(result.byLeg.single?.vehicleId, 'a-bus');
  });

  test('transfer matching handles both, one, and neither leg', () {
    final both = matchSelectedJourneyVehicles(
      journey: transferJourney(),
      vehicles: [
        vehicle(tripId: 'first-trip', vehicleId: 'first'),
        vehicle(tripId: 'second-trip', vehicleId: 'second'),
        vehicle(tripId: 'unrelated', vehicleId: 'other'),
      ],
    );
    expect(both.byLeg.map((item) => item?.vehicleId), ['first', 'second']);

    final firstOnly = matchSelectedJourneyVehicles(
      journey: transferJourney(),
      vehicles: [vehicle(tripId: 'first-trip', vehicleId: 'first')],
    );
    expect(firstOnly.byLeg.first?.vehicleId, 'first');
    expect(firstOnly.byLeg.last, isNull);

    final secondOnly = matchSelectedJourneyVehicles(
      journey: transferJourney(),
      vehicles: [vehicle(tripId: 'second-trip', vehicleId: 'second')],
    );
    expect(secondOnly.byLeg.first, isNull);
    expect(secondOnly.byLeg.last?.vehicleId, 'second');

    final neither = matchSelectedJourneyVehicles(
      journey: transferJourney(),
      vehicles: [vehicle(tripId: 'unrelated')],
    );
    expect(neither.byLeg, everyElement(isNull));
  });
}
