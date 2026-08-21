import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_position.dart';

void main() {
  const vehicle = RealtimeVehiclePosition(
    vehicleId: 'JWG6029',
    tripId: 'trip-15',
    routeId: 'J15',
    latitude: 1.492345,
    longitude: 103.741234,
    timestampSeconds: 1787332800,
  );

  test('toJson serializes every supported realtime field', () {
    expect(vehicle.toJson(), {
      'vehicle_id': 'JWG6029',
      'trip_id': 'trip-15',
      'route_id': 'J15',
      'latitude': 1.492345,
      'longitude': 103.741234,
      'timestamp': 1787332800,
    });
  });

  test('toJson and fromJson round trip preserves model data', () {
    final restored = RealtimeVehiclePosition.fromJson(vehicle.toJson());

    expect(restored.vehicleId, vehicle.vehicleId);
    expect(restored.tripId, vehicle.tripId);
    expect(restored.routeId, vehicle.routeId);
    expect(restored.latitude, vehicle.latitude);
    expect(restored.longitude, vehicle.longitude);
    expect(restored.timestampSeconds, vehicle.timestampSeconds);
  });

  test('fromJson accepts genuinely optional null fields', () {
    final vehicle = RealtimeVehiclePosition.fromJson(const {
      'vehicle_id': null,
      'trip_id': null,
      'route_id': null,
      'latitude': null,
      'longitude': null,
      'timestamp': null,
    });

    expect(vehicle.vehicleId, isNull);
    expect(vehicle.tripId, isNull);
    expect(vehicle.routeId, isNull);
    expect(vehicle.latitude, isNull);
    expect(vehicle.longitude, isNull);
    expect(vehicle.timestampSeconds, isNull);
  });
}
