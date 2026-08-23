import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_models.dart';
import 'package:government_transit_collector/features/journey_map/presentation/route_map_page.dart';
import 'package:government_transit_collector/features/passenger_location/data/passenger_location.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_position.dart';
import 'package:government_transit_collector/features/realtime_vehicle/presentation/realtime_vehicle_marker_data.dart';

const data = JourneyMapData(
  stops: [
    JourneyMapStop(
      stopId: 'origin',
      name: 'Origin',
      coordinate: MapCoordinate(1.49, 103.74),
      role: JourneyStopRole.origin,
    ),
    JourneyMapStop(
      stopId: 'destination',
      name: 'Destination',
      coordinate: MapCoordinate(1.50, 103.75),
      role: JourneyStopRole.destination,
    ),
  ],
  legs: [
    JourneyMapLeg(
      tripId: 'trip',
      routeLabel: 'J15',
      points: [MapCoordinate(1.49, 103.74), MapCoordinate(1.50, 103.75)],
      usedFullShapeFallback: false,
    ),
  ],
);

const bus = RealtimeVehicleMarkerData(
  identity: 'bus',
  vehicle: RealtimeVehiclePosition(
    vehicleId: 'bus',
    tripId: 'trip',
    routeId: 'J15',
    latitude: 1.495,
    longitude: 103.745,
    timestampSeconds: 100,
  ),
  latitude: 1.495,
  longitude: 103.745,
);

PassengerLocation passenger(double latitude) => PassengerLocation(
  latitude: latitude,
  longitude: 103.742,
  accuracyMeters: 10,
  timestamp: DateTime.utc(2026),
);

Widget app(PassengerLocation? location) => MaterialApp(
  home: SizedBox(
    width: 400,
    height: 800,
    child: JourneyRouteMap(
      data: data,
      realtimeMarkers: const [bus],
      passengerLocation: location,
    ),
  ),
);

void main() {
  testWidgets(
    'passenger marker is distinct while route, stops, and bus remain',
    (tester) async {
      await tester.pumpWidget(app(passenger(1.492)));
      await tester.pump();

      expect(find.byKey(const Key('journey-map')), findsOneWidget);
      expect(find.byType(PolylineLayer), findsOneWidget);
      expect(
        find.byKey(const Key('passenger-location-marker')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('selected-bus')), findsOneWidget);
      expect(find.bySemanticsLabel('Your current location'), findsOneWidget);
      expect(find.byIcon(Icons.person_pin_circle), findsOneWidget);
      expect(find.byIcon(Icons.directions_bus), findsOneWidget);
    },
  );

  testWidgets(
    'missing location has no marker and refresh does not duplicate markers',
    (tester) async {
      await tester.pumpWidget(app(null));
      await tester.pump();
      expect(find.byKey(const Key('passenger-location-marker')), findsNothing);
      expect(find.byKey(const ValueKey('selected-bus')), findsOneWidget);

      await tester.pumpWidget(app(passenger(1.492)));
      await tester.pump();
      await tester.pumpWidget(app(passenger(1.493)));
      await tester.pump();
      expect(
        find.byKey(const Key('passenger-location-marker')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('selected-bus')), findsOneWidget);
    },
  );
}
