import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/timetable_recommendation_repository.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_models.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_repository.dart';
import 'package:government_transit_collector/features/journey_map/presentation/route_map_page.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_position.dart';
import 'package:government_transit_collector/features/realtime_vehicle/presentation/realtime_vehicle_marker_data.dart';

const recommendation = DirectJourneyRecommendation(
  tripId: 'trip',
  routeId: 'route',
  routeShortName: 'J10',
  originStopId: 'origin',
  destinationStopId: 'destination',
  serviceId: 'weekday',
  originStopSequence: 1,
  destinationStopSequence: 2,
  departureSeconds: 3600,
  arrivalSeconds: 5400,
);

class FakeRepository implements JourneyMapRepository {
  FakeRepository(this.result, {this.error});
  final JourneyMapData result;
  final Object? error;
  int calls = 0;

  @override
  Future<JourneyMapData> loadJourney(JourneyRecommendation _) async {
    calls++;
    if (error != null) throw error!;
    return result;
  }
}

const emptyMapData = JourneyMapData(stops: [], legs: []);

Widget app(FakeRepository repository) => MaterialApp(
  theme: ThemeData(useMaterial3: true),
  home: RouteMapPage(
    recommendation: recommendation,
    originStopName: 'Larkin Sentral',
    destinationStopName: 'JB Sentral',
    repository: repository,
    mapBuilder: (_) =>
        const ColoredBox(key: Key('fake-map'), color: Colors.blue),
  ),
);

void main() {
  testWidgets('selected journey map exposes compact camera controls', (
    tester,
  ) async {
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
          routeLabel: 'J10',
          points: [MapCoordinate(1.49, 103.74), MapCoordinate(1.50, 103.75)],
          usedFullShapeFallback: false,
        ),
      ],
    );
    const vehicle = RealtimeVehiclePosition(
      vehicleId: 'bus',
      tripId: 'trip',
      routeId: 'route',
      latitude: 1.495,
      longitude: 103.745,
      timestampSeconds: 1,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: JourneyRouteMap(
            data: data,
            realtimeMarkers: buildRealtimeVehicleMarkers([vehicle]),
            activeLegIndex: 0,
            showCameraControls: true,
            busLabel: 'J10',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('fit-journey-map')), findsOneWidget);
    expect(find.byKey(const Key('fit-active-leg-map')), findsOneWidget);
    expect(find.byKey(const Key('follow-live-bus')), findsOneWidget);
    await tester.tap(find.byKey(const Key('fit-journey-map')));
    await tester.tap(find.byKey(const Key('fit-active-leg-map')));
    await tester.tap(find.byKey(const Key('follow-live-bus')));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing shape keeps summary and displays fallback message', (
    tester,
  ) async {
    await tester.pumpWidget(app(FakeRepository(emptyMapData)));
    await tester.pump();

    expect(find.text('J10'), findsOneWidget);
    expect(find.text('Larkin Sentral → JB Sentral'), findsOneWidget);
    expect(find.byKey(const Key('missing-route-shape')), findsOneWidget);
    expect(find.byKey(const Key('fake-map')), findsOneWidget);
  });

  testWidgets('error state retries the read', (tester) async {
    final repository = FakeRepository(
      emptyMapData,
      error: Exception('offline'),
    );
    await tester.pumpWidget(app(repository));
    await tester.pump();

    expect(find.text('Unable to load this journey route.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('retry-route-map')));
    await tester.pump();
    expect(repository.calls, 2);
  });

  testWidgets('portrait and landscape show the same journey information', (
    tester,
  ) async {
    final repository = FakeRepository(emptyMapData);
    for (final size in [const Size(400, 800), const Size(800, 400)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(app(repository));
      await tester.pump();
      expect(find.text('J10'), findsOneWidget);
      expect(find.text('Larkin Sentral → JB Sentral'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.binding.setSurfaceSize(null);
  });
}
