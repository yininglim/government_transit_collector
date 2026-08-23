import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/timetable_recommendation_repository.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_models.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_repository.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/gtfs_realtime_decoder.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_position.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_repository.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/selected_journey_tracking.dart';
import 'package:government_transit_collector/features/realtime_vehicle/presentation/selected_journey_tracker_page.dart';

import 'selected_journey_tracking_test.dart' as fixtures;

class SequenceRepository implements RealtimeVehicleRepository {
  SequenceRepository(this.responses);
  final List<Future<RealtimeFeedSnapshot> Function()> responses;
  int calls = 0;

  @override
  Future<RealtimeFeedSnapshot> fetchVehiclePositions() {
    final index = calls.clamp(0, responses.length - 1);
    calls++;
    return responses[index]();
  }
}

class MapRepository implements JourneyMapRepository {
  int calls = 0;

  @override
  Future<JourneyMapData> loadJourney(
    JourneyRecommendation recommendation,
  ) async {
    calls++;
    final tripIds = switch (recommendation) {
      DirectJourneyRecommendation direct => [direct.tripId],
      TransferJourneyRecommendation transfer => [
        transfer.firstTripId,
        transfer.secondTripId,
      ],
    };
    return JourneyMapData(
      stops: const [
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
        for (final tripId in tripIds)
          JourneyMapLeg(
            tripId: tripId,
            routeLabel: 'route',
            points: const [MapCoordinate(1.49, 103.74)],
            usedFullShapeFallback: false,
          ),
      ],
    );
  }
}

RealtimeVehiclePosition vehicle(
  String tripId, {
  String id = 'bus-1',
  String routeId = 'route-15',
  double latitude = 1.495,
  int timestamp = 100,
}) => RealtimeVehiclePosition(
  vehicleId: id,
  tripId: tripId,
  routeId: routeId,
  latitude: latitude,
  longitude: 103.745,
  timestampSeconds: timestamp,
);

RealtimeFeedSnapshot snapshot(List<RealtimeVehiclePosition> vehicles) =>
    RealtimeFeedSnapshot(vehicles: vehicles, feedTimestampSeconds: 100);

SelectedJourneyTracking journey(JourneyRecommendation recommendation) =>
    SelectedJourneyTracking.fromRecommendation(
      recommendation: recommendation,
      originStopName: 'Origin Stop',
      destinationStopName: 'Destination Stop',
      travelDate: DateTime(2026, 8, 23),
    );

Widget app({
  required SelectedJourneyTracking selected,
  required SequenceRepository realtime,
}) => MaterialApp(
  theme: ThemeData(useMaterial3: true),
  home: SelectedJourneyTrackerPage(
    journey: selected,
    realtimeRepository: realtime,
    journeyMapRepository: MapRepository(),
    pollingInterval: const Duration(hours: 1),
    mapBuilder: (data, markers) => ColoredBox(
      key: const Key('fake-selected-map'),
      color: Colors.blueGrey,
      child: Column(
        children: [
          Text('planned-stops:${data.stops.length}'),
          Text('planned-legs:${data.legs.length}'),
          for (final marker in markers)
            Text(
              '${marker.vehicle.tripId}:${marker.latitude}',
              key: Key('map-${marker.vehicle.vehicleId}'),
            ),
        ],
      ),
    ),
  ),
);

Future<void> refresh(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('refresh-selected-journey')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('direct UI shows planned journey and only exact-trip vehicle', (
    tester,
  ) async {
    final realtime = SequenceRepository([
      () async => snapshot([
        vehicle('wrong-trip', id: 'unrelated'),
        vehicle('direct-trip', id: 'selected'),
      ]),
    ]);
    await tester.pumpWidget(
      app(selected: journey(fixtures.directRecommendation), realtime: realtime),
    );
    await tester.pumpAndSettle();

    expect(find.text('J15'), findsOneWidget);
    expect(find.text('Origin Stop → Destination Stop'), findsOneWidget);
    expect(find.text('10:30 AM → 11:05 AM'), findsOneWidget);
    expect(find.text('Live tracking active'), findsOneWidget);
    expect(find.text('Vehicle: selected'), findsOneWidget);
    expect(find.byKey(const Key('map-selected')), findsOneWidget);
    expect(find.byKey(const Key('map-unrelated')), findsNothing);
    expect(find.text('planned-stops:2'), findsOneWidget);
    expect(find.text('planned-legs:1'), findsOneWidget);
  });

  testWidgets('valid feed without selected trip waits and shows no marker', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        selected: journey(fixtures.directRecommendation),
        realtime: SequenceRepository([
          () async => snapshot([
            vehicle('wrong-trip', id: 'unrelated', routeId: 'route-15'),
          ]),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Waiting for realtime vehicle data for this trip.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('map-unrelated')), findsNothing);
  });

  testWidgets('selected vehicle appearing later is shown automatically', (
    tester,
  ) async {
    final realtime = SequenceRepository([
      () async => snapshot([]),
      () async => snapshot([vehicle('direct-trip', id: 'later-bus')]),
    ]);
    await tester.pumpWidget(
      app(selected: journey(fixtures.directRecommendation), realtime: realtime),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Waiting for realtime vehicle data for this trip.'),
      findsOneWidget,
    );

    await refresh(tester);
    expect(find.text('Live tracking active'), findsOneWidget);
    expect(find.byKey(const Key('map-later-bus')), findsOneWidget);
  });

  testWidgets('vehicle updates, disappears, and later reappears', (
    tester,
  ) async {
    final realtime = SequenceRepository([
      () async => snapshot([vehicle('direct-trip', latitude: 1.49)]),
      () async => snapshot([vehicle('wrong-trip')]),
      () async =>
          snapshot([vehicle('direct-trip', latitude: 1.51, timestamp: 130)]),
    ]);
    await tester.pumpWidget(
      app(selected: journey(fixtures.directRecommendation), realtime: realtime),
    );
    await tester.pumpAndSettle();
    expect(find.text('direct-trip:1.49'), findsOneWidget);

    await refresh(tester);
    expect(find.textContaining('temporarily unavailable'), findsOneWidget);
    expect(find.text('Last known position'), findsOneWidget);
    expect(find.text('direct-trip:1.49'), findsOneWidget);

    await refresh(tester);
    expect(find.text('Live tracking active'), findsOneWidget);
    expect(find.text('direct-trip:1.51'), findsOneWidget);
  });

  testWidgets('transfer leg selector displays each exact leg vehicle', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        selected: journey(fixtures.transferRecommendation),
        realtime: SequenceRepository([
          () async => snapshot([
            vehicle('first-trip', id: 'first-bus', routeId: 'route-13'),
            vehicle('second-trip', id: 'second-bus', routeId: 'route-10'),
            vehicle('unrelated', id: 'other-bus'),
          ]),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('J13 → J10'), findsOneWidget);
    expect(find.text('Transfer at JB Sentral'), findsOneWidget);
    expect(find.text('Selected leg: J13'), findsOneWidget);
    expect(find.byKey(const Key('map-first-bus')), findsOneWidget);
    expect(find.byKey(const Key('map-other-bus')), findsNothing);
    expect(find.text('planned-legs:2'), findsOneWidget);

    await tester.tap(find.text('Leg 2: J10'));
    await tester.pumpAndSettle();
    expect(find.text('Selected leg: J10'), findsOneWidget);
    expect(find.byKey(const Key('map-second-bus')), findsOneWidget);
    expect(find.byKey(const Key('map-first-bus')), findsNothing);
  });

  testWidgets('refresh failure retains selected last-known position', (
    tester,
  ) async {
    final realtime = SequenceRepository([
      () async => snapshot([vehicle('direct-trip')]),
      () => Future.error(const RealtimeVehicleReadException('network failed')),
    ]);
    await tester.pumpWidget(
      app(selected: journey(fixtures.directRecommendation), realtime: realtime),
    );
    await tester.pumpAndSettle();
    await refresh(tester);

    expect(
      find.text('Unable to refresh — showing last known position'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('map-bus-1')), findsOneWidget);
  });

  testWidgets('initial API failure is distinct from a valid waiting feed', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        selected: journey(fixtures.directRecommendation),
        realtime: SequenceRepository([
          () => Future.error(
            const RealtimeVehicleReadException('network failed'),
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Unable to refresh realtime vehicle data.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('fake-selected-map')), findsOneWidget);
  });

  testWidgets('portrait and landscape retain summary, refresh, and map', (
    tester,
  ) async {
    for (final size in [const Size(400, 800), const Size(800, 400)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        app(
          selected: journey(fixtures.transferRecommendation),
          realtime: SequenceRepository([() async => snapshot([])]),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('J13 → J10'), findsOneWidget);
      expect(find.byKey(const Key('selected-leg-selector')), findsOneWidget);
      expect(find.byKey(const Key('refresh-selected-journey')), findsOneWidget);
      expect(find.byKey(const Key('fake-selected-map')), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.binding.setSurfaceSize(null);
  });
}
