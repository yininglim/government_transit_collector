import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_position.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/selected_journey_tracking.dart';

class SelectedJourneyRealtimeMatch {
  const SelectedJourneyRealtimeMatch({required this.byLeg});

  final List<RealtimeVehiclePosition?> byLeg;
}

SelectedJourneyRealtimeMatch matchSelectedJourneyVehicles({
  required SelectedJourneyTracking journey,
  required Iterable<RealtimeVehiclePosition> vehicles,
}) {
  final feedVehicles = vehicles.toList(growable: false);
  final candidatesByTrip = <String, List<RealtimeVehiclePosition>>{};
  for (final vehicle in feedVehicles) {
    final tripId = vehicle.tripId?.trim();
    if (tripId == null || tripId.isEmpty) continue;
    if (!journey.legs.any((leg) => leg.tripId == tripId)) continue;
    if (!_hasValidCoordinate(vehicle)) continue;
    candidatesByTrip.putIfAbsent(tripId, () => []).add(vehicle);
  }
  final matches = <RealtimeVehiclePosition?>[];
  for (final leg in journey.legs) {
    final candidates = candidatesByTrip[leg.tripId];
    if (candidates == null || candidates.isEmpty) {
      matches.add(null);
    } else {
      candidates.sort(_compareCandidates);
      matches.add(candidates.first);
    }
  }
  return SelectedJourneyRealtimeMatch(byLeg: matches);
}

int _compareCandidates(
  RealtimeVehiclePosition left,
  RealtimeVehiclePosition right,
) {
  final newest = (right.timestampSeconds ?? -1).compareTo(
    left.timestampSeconds ?? -1,
  );
  if (newest != 0) return newest;
  final byVehicle = (left.vehicleId ?? '').compareTo(right.vehicleId ?? '');
  if (byVehicle != 0) return byVehicle;
  final byLatitude = left.latitude!.compareTo(right.latitude!);
  if (byLatitude != 0) return byLatitude;
  return left.longitude!.compareTo(right.longitude!);
}

bool _hasValidCoordinate(RealtimeVehiclePosition vehicle) {
  final latitude = vehicle.latitude;
  final longitude = vehicle.longitude;
  return latitude != null &&
      longitude != null &&
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;
}
