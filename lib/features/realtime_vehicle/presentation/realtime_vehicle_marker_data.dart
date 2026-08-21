import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_position.dart';

class RealtimeVehicleMarkerData {
  const RealtimeVehicleMarkerData({
    required this.identity,
    required this.vehicle,
    required this.latitude,
    required this.longitude,
  });

  final String identity;
  final RealtimeVehiclePosition vehicle;
  final double latitude;
  final double longitude;
}

class RealtimeMapCameraPlan {
  const RealtimeMapCameraPlan.single({
    required this.centerLatitude,
    required this.centerLongitude,
  }) : fitBounds = false;

  const RealtimeMapCameraPlan.bounds({
    required this.centerLatitude,
    required this.centerLongitude,
  }) : fitBounds = true;

  final double centerLatitude;
  final double centerLongitude;
  final bool fitBounds;
}

RealtimeMapCameraPlan? buildRealtimeMapCameraPlan(
  List<RealtimeVehicleMarkerData> markers,
) {
  if (markers.isEmpty) return null;
  if (markers.length == 1) {
    return RealtimeMapCameraPlan.single(
      centerLatitude: markers.single.latitude,
      centerLongitude: markers.single.longitude,
    );
  }
  final latitude =
      markers.fold<double>(0, (sum, marker) => sum + marker.latitude) /
      markers.length;
  final longitude =
      markers.fold<double>(0, (sum, marker) => sum + marker.longitude) /
      markers.length;
  return RealtimeMapCameraPlan.bounds(
    centerLatitude: latitude,
    centerLongitude: longitude,
  );
}

List<RealtimeVehicleMarkerData> buildRealtimeVehicleMarkers(
  Iterable<RealtimeVehiclePosition> vehicles,
) {
  final markers = <String, RealtimeVehicleMarkerData>{};
  var unidentifiedIndex = 0;
  for (final vehicle in vehicles) {
    final latitude = vehicle.latitude;
    final longitude = vehicle.longitude;
    if (!_validCoordinates(latitude, longitude)) continue;
    final identity = _vehicleIdentity(vehicle, unidentifiedIndex++);
    final candidate = RealtimeVehicleMarkerData(
      identity: identity,
      vehicle: vehicle,
      latitude: latitude!,
      longitude: longitude!,
    );
    final existing = markers[identity];
    if (existing == null ||
        (candidate.vehicle.timestampSeconds ?? -1) >=
            (existing.vehicle.timestampSeconds ?? -1)) {
      markers[identity] = candidate;
    }
  }
  return markers.values.toList(growable: false);
}

bool _validCoordinates(double? latitude, double? longitude) =>
    latitude != null &&
    longitude != null &&
    latitude.isFinite &&
    longitude.isFinite &&
    latitude >= -90 &&
    latitude <= 90 &&
    longitude >= -180 &&
    longitude <= 180;

String _vehicleIdentity(RealtimeVehiclePosition vehicle, int fallbackIndex) {
  final vehicleId = vehicle.vehicleId?.trim();
  if (vehicleId?.isNotEmpty == true) return 'vehicle:$vehicleId';
  final tripId = vehicle.tripId?.trim();
  final routeId = vehicle.routeId?.trim();
  if (tripId?.isNotEmpty == true || routeId?.isNotEmpty == true) {
    return 'trip:${tripId ?? ''}|route:${routeId ?? ''}';
  }
  return 'unidentified:$fallbackIndex';
}
