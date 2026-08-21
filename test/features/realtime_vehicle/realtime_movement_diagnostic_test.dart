import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_position.dart';
import 'package:government_transit_collector/features/realtime_vehicle/presentation/realtime_movement_diagnostic.dart';
import 'package:government_transit_collector/features/realtime_vehicle/presentation/realtime_vehicle_marker_data.dart';

RealtimeVehicleMarkerData marker({
  required double latitude,
  required double longitude,
  required int timestamp,
}) => RealtimeVehicleMarkerData(
  identity: 'vehicle:bus-1',
  vehicle: RealtimeVehiclePosition(
    vehicleId: 'bus-1',
    tripId: 'trip-1',
    routeId: 'J10',
    latitude: latitude,
    longitude: longitude,
    timestampSeconds: timestamp,
  ),
  latitude: latitude,
  longitude: longitude,
);

void main() {
  test('first genuine observation has no fabricated previous position', () {
    final tracker = RealtimeMovementDiagnosticTracker();
    tracker.observe([
      marker(latitude: 1.464433, longitude: 103.887863, timestamp: 100),
    ]);

    final diagnostic = tracker.forIdentity('vehicle:bus-1')!;
    expect(diagnostic.previous, isNull);
    expect(diagnostic.positionChanged, isNull);
    expect(diagnostic.distanceMetres, isNull);
  });

  test('changed genuine observations use geographic distance', () {
    final tracker = RealtimeMovementDiagnosticTracker();
    tracker.observe([
      marker(latitude: 1.464433, longitude: 103.887863, timestamp: 100),
    ]);
    tracker.observe([
      marker(latitude: 1.464487, longitude: 103.887920, timestamp: 115),
    ]);

    final diagnostic = tracker.forIdentity('vehicle:bus-1')!;
    expect(diagnostic.positionChanged, isTrue);
    expect(diagnostic.distanceMetres, closeTo(8.7, 0.2));
    expect(diagnostic.feedIntervalSeconds, 15);
    expect(diagnostic.previous!.latitude, 1.464433);
    expect(diagnostic.latest.latitude, 1.464487);
  });

  test('identical genuine observations report zero movement', () {
    final tracker = RealtimeMovementDiagnosticTracker();
    final position = marker(
      latitude: 1.464433,
      longitude: 103.887863,
      timestamp: 100,
    );
    tracker.observe([position]);
    tracker.observe([
      marker(latitude: 1.464433, longitude: 103.887863, timestamp: 115),
    ]);

    final diagnostic = tracker.forIdentity('vehicle:bus-1')!;
    expect(diagnostic.positionChanged, isFalse);
    expect(diagnostic.distanceMetres, 0);
  });
}
