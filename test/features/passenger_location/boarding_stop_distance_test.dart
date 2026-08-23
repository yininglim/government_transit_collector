import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_models.dart';
import 'package:government_transit_collector/features/passenger_location/data/boarding_stop_distance.dart';
import 'package:government_transit_collector/features/passenger_location/data/passenger_location.dart';

PassengerLocation passenger({
  double latitude = 0,
  double longitude = 0,
  double accuracy = 10,
}) => PassengerLocation(
  latitude: latitude,
  longitude: longitude,
  accuracyMeters: accuracy,
  timestamp: DateTime.utc(2026),
);

void main() {
  test('Haversine distance is zero at the boarding stop', () {
    expect(
      passengerDistanceToStopMeters(passenger(), const MapCoordinate(0, 0)),
      0,
    );
  });

  test('Haversine distance handles near, hundreds, and kilometres', () {
    expect(
      passengerDistanceToStopMeters(
        passenger(),
        const MapCoordinate(0, 0.0001),
      ),
      closeTo(11.1, 0.5),
    );
    expect(
      passengerDistanceToStopMeters(
        passenger(),
        const MapCoordinate(0, 0.0045),
      ),
      closeTo(500, 2),
    );
    expect(
      passengerDistanceToStopMeters(passenger(), const MapCoordinate(0, 0.018)),
      closeTo(2000, 5),
    );
  });

  test('formats metres and kilometres without false precision', () {
    expect(formatApproximateDistance(0), '0 m');
    expect(formatApproximateDistance(11.1), '10 m');
    expect(formatApproximateDistance(184), '180 m');
    expect(formatApproximateDistance(1420), '1.4 km');
  });

  test('retains and classifies poor location accuracy', () {
    expect(hasPoorPassengerLocationAccuracy(passenger(accuracy: 100)), isFalse);
    expect(hasPoorPassengerLocationAccuracy(passenger(accuracy: 101)), isTrue);
  });
}
