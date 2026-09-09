import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_position.dart';
import 'package:government_transit_collector/features/realtime_vehicle/presentation/animated_realtime_vehicle_layer.dart';
import 'package:government_transit_collector/features/realtime_vehicle/presentation/realtime_vehicle_marker_data.dart';

RealtimeVehicleMarkerData marker(double latitude, {String id = 'bus-1'}) =>
    RealtimeVehicleMarkerData(
      identity: 'vehicle:$id',
      vehicle: RealtimeVehiclePosition(
        vehicleId: id,
        tripId: 'trip-1',
        routeId: 'J10',
        latitude: latitude,
        longitude: 103.74,
        timestampSeconds: 100,
      ),
      latitude: latitude,
      longitude: 103.74,
    );

Widget app(List<RealtimeVehicleMarkerData> markers) => MaterialApp(
  home: AnimatedRealtimeVehicleLayer(
    markers: markers,
    builder: (context, displayed, moving) {
      final vehicle = displayed.single;
      return Column(
        children: [
          Text(vehicle.identity, key: const Key('identity')),
          Text('${vehicle.latitude}', key: const Key('latitude')),
          Text('${vehicle.longitude}', key: const Key('longitude')),
          Text(
            '${moving.contains(vehicle.identity)}',
            key: const Key('moving'),
          ),
        ],
      );
    },
  ),
);

String value(WidgetTester tester, Key key) =>
    (tester.widget<Text>(find.byKey(key))).data!;

void main() {
  testWidgets('first coordinate appears immediately without animation', (
    tester,
  ) async {
    await tester.pumpWidget(app([marker(1.49)]));

    expect(value(tester, const Key('latitude')), '1.49');
    expect(value(tester, const Key('moving')), 'false');
  });

  testWidgets('changed coordinate animates from previous real coordinate', (
    tester,
  ) async {
    await tester.pumpWidget(app([marker(1.49)]));
    await tester.pumpWidget(app([marker(1.51)]));

    expect(value(tester, const Key('latitude')), '1.49');
    expect(value(tester, const Key('moving')), 'true');

    await tester.pump(const Duration(milliseconds: 750));
    final midpoint = double.parse(value(tester, const Key('latitude')));
    expect(midpoint, greaterThan(1.49));
    expect(midpoint, lessThan(1.51));
  });

  testWidgets('unchanged coordinate does not animate', (tester) async {
    await tester.pumpWidget(app([marker(1.49)]));
    await tester.pumpWidget(app([marker(1.49)]));

    expect(value(tester, const Key('latitude')), '1.49');
    expect(value(tester, const Key('moving')), 'false');
  });

  testWidgets('animation finishes exactly at latest realtime coordinate', (
    tester,
  ) async {
    await tester.pumpWidget(app([marker(1.49)]));
    await tester.pumpWidget(app([marker(1.51)]));
    await tester.pump(realtimeMarkerMovementDuration);
    await tester.pump(const Duration(milliseconds: 1));

    expect(double.parse(value(tester, const Key('latitude'))), 1.51);
    expect(double.parse(value(tester, const Key('longitude'))), 103.74);
    expect(value(tester, const Key('moving')), 'false');
  });

  testWidgets('new update continues from displayed position without overlap', (
    tester,
  ) async {
    await tester.pumpWidget(app([marker(1.49)]));
    await tester.pumpWidget(app([marker(1.51)]));
    await tester.pump(const Duration(milliseconds: 500));
    final displayedBeforeUpdate = double.parse(
      value(tester, const Key('latitude')),
    );

    await tester.pumpWidget(app([marker(1.53)]));

    expect(
      double.parse(value(tester, const Key('latitude'))),
      displayedBeforeUpdate,
    );
    expect(value(tester, const Key('moving')), 'true');

    await tester.pump(realtimeMarkerMovementDuration);
    await tester.pump(const Duration(milliseconds: 1));
    expect(double.parse(value(tester, const Key('latitude'))), 1.53);
    expect(value(tester, const Key('moving')), 'false');
  });

  testWidgets('vehicle identity remains stable throughout movement', (
    tester,
  ) async {
    await tester.pumpWidget(app([marker(1.49)]));
    expect(value(tester, const Key('identity')), 'vehicle:bus-1');

    await tester.pumpWidget(app([marker(1.51)]));
    await tester.pump(const Duration(milliseconds: 750));
    expect(value(tester, const Key('identity')), 'vehicle:bus-1');
  });

  testWidgets('disposing during movement cancels animation safely', (
    tester,
  ) async {
    await tester.pumpWidget(app([marker(1.49)]));
    await tester.pumpWidget(app([marker(1.51)]));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(realtimeMarkerMovementDuration);
    expect(tester.takeException(), isNull);
  });
}
