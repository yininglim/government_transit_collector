import 'package:government_transit_collector/features/journey_map/data/journey_map_models.dart';
import 'package:government_transit_collector/features/passenger_location/data/passenger_location.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/route_geometry.dart';

const poorPassengerLocationAccuracyMeters = 100.0;

double passengerDistanceToStopMeters(
  PassengerLocation passenger,
  MapCoordinate stop,
) => geographicDistanceMeters(
  MapCoordinate(passenger.latitude, passenger.longitude),
  stop,
);

String formatApproximateDistance(double meters) {
  if (meters >= 1000) {
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }
  final rounded = meters < 10 ? meters.round() : (meters / 10).round() * 10;
  return '$rounded m';
}

bool hasPoorPassengerLocationAccuracy(PassengerLocation location) =>
    location.accuracyMeters > poorPassengerLocationAccuracyMeters;
