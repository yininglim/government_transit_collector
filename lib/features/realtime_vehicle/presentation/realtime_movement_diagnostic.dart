import 'dart:math' as math;

import 'package:government_transit_collector/features/realtime_vehicle/presentation/realtime_vehicle_marker_data.dart';

class RealtimeMovementDiagnostic {
  const RealtimeMovementDiagnostic({
    required this.previous,
    required this.latest,
  });

  final RealtimeVehicleMarkerData? previous;
  final RealtimeVehicleMarkerData latest;

  bool? get positionChanged {
    final old = previous;
    if (old == null) return null;
    return old.latitude != latest.latitude || old.longitude != latest.longitude;
  }

  double? get distanceMetres {
    final old = previous;
    if (old == null) return null;
    return geographicDistanceMetres(
      old.latitude,
      old.longitude,
      latest.latitude,
      latest.longitude,
    );
  }

  int? get feedIntervalSeconds {
    final previousTimestamp = previous?.vehicle.timestampSeconds;
    final latestTimestamp = latest.vehicle.timestampSeconds;
    if (previousTimestamp == null || latestTimestamp == null) return null;
    return latestTimestamp - previousTimestamp;
  }
}

class RealtimeMovementDiagnosticTracker {
  final Map<String, RealtimeMovementDiagnostic> _diagnostics = {};

  void observe(Iterable<RealtimeVehicleMarkerData> latestMarkers) {
    for (final latest in latestMarkers) {
      final priorDiagnostic = _diagnostics[latest.identity];
      _diagnostics[latest.identity] = RealtimeMovementDiagnostic(
        previous: priorDiagnostic?.latest,
        latest: latest,
      );
    }
  }

  RealtimeMovementDiagnostic? forIdentity(String identity) =>
      _diagnostics[identity];
}

double geographicDistanceMetres(
  double fromLatitude,
  double fromLongitude,
  double toLatitude,
  double toLongitude,
) {
  const earthRadiusMetres = 6371000.0;
  final latitudeDelta = _radians(toLatitude - fromLatitude);
  final longitudeDelta = _radians(toLongitude - fromLongitude);
  final fromLatitudeRadians = _radians(fromLatitude);
  final toLatitudeRadians = _radians(toLatitude);
  final haversine =
      math.sin(latitudeDelta / 2) * math.sin(latitudeDelta / 2) +
      math.cos(fromLatitudeRadians) *
          math.cos(toLatitudeRadians) *
          math.sin(longitudeDelta / 2) *
          math.sin(longitudeDelta / 2);
  final angularDistance =
      2 * math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine));
  return earthRadiusMetres * angularDistance;
}

double _radians(double degrees) => degrees * math.pi / 180;
