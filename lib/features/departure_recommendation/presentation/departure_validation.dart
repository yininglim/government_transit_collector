import 'package:government_transit_collector/features/departure_recommendation/data/departure_stop_repository.dart';

String? validateDepartureStops({
  required DepartureStop? origin,
  required DepartureStop? destination,
}) {
  if (origin == null) return 'Please select an origin stop.';
  if (destination == null) return 'Please select a destination stop.';
  if (origin.id == destination.id) {
    return 'Origin and destination must be different stops.';
  }
  return null;
}
