import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_position.dart';
import 'package:government_transit_collector/features/realtime_vehicle/presentation/realtime_vehicle_marker_data.dart';

RealtimeVehiclePosition vehicle({
  String? vehicleId = 'bus-1',
  String? tripId = 'trip-1',
  String? routeId = 'J10',
  double? latitude = 1.49,
  double? longitude = 103.74,
  int? timestamp = 100,
}) => RealtimeVehiclePosition(
  vehicleId: vehicleId,
  tripId: tripId,
  routeId: routeId,
  latitude: latitude,
  longitude: longitude,
  timestampSeconds: timestamp,
);

void main() {
  test('valid realtime coordinates create a marker', () {
    final markers = buildRealtimeVehicleMarkers([vehicle()]);

    expect(markers, hasLength(1));
    expect(markers.single.latitude, 1.49);
    expect(markers.single.longitude, 103.74);
  });

  test('missing or invalid coordinate does not create a marker', () {
    final markers = buildRealtimeVehicleMarkers([
      vehicle(latitude: null),
      vehicle(longitude: null),
      vehicle(latitude: 91),
      vehicle(longitude: 181),
    ]);

    expect(markers, isEmpty);
  });

  test('multiple vehicles create multiple markers', () {
    final markers = buildRealtimeVehicleMarkers([
      vehicle(vehicleId: 'bus-1'),
      vehicle(vehicleId: 'bus-2'),
    ]);

    expect(markers, hasLength(2));
  });

  test('vehicle identity stays stable when coordinates update', () {
    final before = buildRealtimeVehicleMarkers([vehicle(latitude: 1.49)]);
    final after = buildRealtimeVehicleMarkers([vehicle(latitude: 1.50)]);

    expect(before.single.identity, 'vehicle:bus-1');
    expect(after.single.identity, before.single.identity);
    expect(after.single.latitude, 1.50);
  });

  test('trip and route form identity when vehicle ID is missing', () {
    final marker = buildRealtimeVehicleMarkers([
      vehicle(vehicleId: null),
    ]).single;

    expect(marker.identity, 'trip:trip-1|route:J10');
  });

  test('duplicate stable identity retains only newest feed position', () {
    final markers = buildRealtimeVehicleMarkers([
      vehicle(latitude: 1.49, timestamp: 100),
      vehicle(latitude: 1.50, timestamp: 101),
    ]);

    expect(markers, hasLength(1));
    expect(markers.single.latitude, 1.50);
  });

  test('one-vehicle camera plan centers without fitting bounds', () {
    final plan = buildRealtimeMapCameraPlan(
      buildRealtimeVehicleMarkers([vehicle()]),
    )!;

    expect(plan.fitBounds, isFalse);
    expect(plan.centerLatitude, 1.49);
  });

  test('multiple-vehicle camera plan requests bounds fitting', () {
    final plan = buildRealtimeMapCameraPlan(
      buildRealtimeVehicleMarkers([
        vehicle(vehicleId: '1', latitude: 1.48),
        vehicle(vehicleId: '2', latitude: 1.50),
      ]),
    )!;

    expect(plan.fitBounds, isTrue);
    expect(plan.centerLatitude, closeTo(1.49, 0.000001));
  });

  test('empty marker list has no camera plan', () {
    expect(buildRealtimeMapCameraPlan(const []), isNull);
  });
}
