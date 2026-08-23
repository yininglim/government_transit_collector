import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/timetable_recommendation_repository.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_models.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_repository.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/gtfs_realtime_decoder.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_position.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_repository.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/selected_journey_tracking.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/trip_progress_models.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/trip_progress_repository.dart';
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

class ProgressRepository implements TripProgressRepository {
  ProgressRepository({this.dataByTrip = const {}});

  final Map<String, TripProgressData> dataByTrip;
  int calls = 0;
  final List<String> loadedTripIds = [];

  @override
  Future<TripProgressData> loadTrip(String exactTripId) async {
    calls++;
    loadedTripIds.add(exactTripId);
    final custom = dataByTrip[exactTripId];
    if (custom != null) return custom;
    return TripProgressData(
      tripId: exactTripId,
      shapePoints: const [
        MapCoordinate(1.49, 103.74),
        MapCoordinate(1.50, 103.75),
        MapCoordinate(1.51, 103.76),
      ],
      stops: const [
        TrackedTripStop(
          stopId: 'origin',
          stopName: 'Origin',
          stopSequence: 1,
          coordinate: MapCoordinate(1.49, 103.74),
          scheduledArrivalSeconds: 36000,
          scheduledDepartureSeconds: 36000,
        ),
        TrackedTripStop(
          stopId: 'middle',
          stopName: 'Middle Stop',
          stopSequence: 2,
          coordinate: MapCoordinate(1.50, 103.75),
          scheduledArrivalSeconds: 36600,
          scheduledDepartureSeconds: 36600,
        ),
        TrackedTripStop(
          stopId: 'destination',
          stopName: 'Destination',
          stopSequence: 3,
          coordinate: MapCoordinate(1.51, 103.76),
          scheduledArrivalSeconds: 37200,
          scheduledDepartureSeconds: 37200,
        ),
      ],
    );
  }
}

class DeferredProgressRepository implements TripProgressRepository {
  DeferredProgressRepository(this.future);
  final Future<TripProgressData> future;

  @override
  Future<TripProgressData> loadTrip(String exactTripId) => future;
}

class FailingProgressRepository implements TripProgressRepository {
  @override
  Future<TripProgressData> loadTrip(String exactTripId) =>
      Future.error(Exception('static unavailable'));
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
  longitude: 103.74 + (latitude - 1.49),
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
  TripProgressRepository? progress,
}) => MaterialApp(
  theme: ThemeData(useMaterial3: true),
  home: SelectedJourneyTrackerPage(
    journey: selected,
    realtimeRepository: realtime,
    journeyMapRepository: MapRepository(),
    tripProgressRepository: progress ?? ProgressRepository(),
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
    expect(find.byKey(const Key('route-progress-summary')), findsOneWidget);
    expect(find.text('Next stop: Middle Stop'), findsOneWidget);
    expect(find.text('Upcoming Stops'), findsOneWidget);
    expect(find.text('✓ Origin'), findsOneWidget);
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
    expect(find.byKey(const Key('route-progress-waiting')), findsOneWidget);
    expect(find.byKey(const Key('map-unrelated')), findsNothing);
  });

  testWidgets('shows static progress loading and failure distinctly', (
    tester,
  ) async {
    final pending = Completer<TripProgressData>();
    await tester.pumpWidget(
      app(
        selected: journey(fixtures.directRecommendation),
        realtime: SequenceRepository([() async => snapshot([])]),
        progress: DeferredProgressRepository(pending.future),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('route-progress-loading')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      app(
        selected: journey(fixtures.directRecommendation),
        realtime: SequenceRepository([() async => snapshot([])]),
        progress: FailingProgressRepository(),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Unable to load route progress information.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('retry-route-progress')), findsOneWidget);
  });

  testWidgets('shows missing-shape and off-route progress states', (
    tester,
  ) async {
    final noShape = TripProgressData(
      tripId: 'direct-trip',
      shapePoints: const [],
      stops: const [],
    );
    await tester.pumpWidget(
      app(
        selected: journey(fixtures.directRecommendation),
        realtime: SequenceRepository([
          () async => snapshot([vehicle('direct-trip')]),
        ]),
        progress: ProgressRepository(dataByTrip: {'direct-trip': noShape}),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('route-progress-shape-unavailable')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      app(
        selected: journey(fixtures.directRecommendation),
        realtime: SequenceRepository([
          () async => snapshot([vehicle('direct-trip', latitude: 2)]),
        ]),
        progress: ProgressRepository(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('route-progress-off-route')), findsOneWidget);
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
    expect(find.text('Last known route progress'), findsOneWidget);
    expect(find.text('direct-trip:1.49'), findsOneWidget);

    await refresh(tester);
    expect(find.text('Live tracking active'), findsOneWidget);
    expect(find.text('direct-trip:1.51'), findsOneWidget);
  });

  testWidgets(
    'static trip progress data loads once across realtime refreshes',
    (tester) async {
      final progress = ProgressRepository();
      final realtime = SequenceRepository([
        () async => snapshot([vehicle('direct-trip', latitude: 1.495)]),
        () async =>
            snapshot([vehicle('direct-trip', latitude: 1.50, timestamp: 115)]),
      ]);
      await tester.pumpWidget(
        app(
          selected: journey(fixtures.directRecommendation),
          realtime: realtime,
          progress: progress,
        ),
      );
      await tester.pumpAndSettle();
      await refresh(tester);

      expect(progress.calls, 1);
      expect(progress.loadedTripIds, ['direct-trip']);
      expect(find.byKey(const Key('route-progress-summary')), findsOneWidget);
    },
  );

  testWidgets('transfer leg selector displays each exact leg vehicle', (
    tester,
  ) async {
    TripProgressData legData(String tripId, String stopName) =>
        TripProgressData(
          tripId: tripId,
          shapePoints: const [
            MapCoordinate(1.49, 103.74),
            MapCoordinate(1.51, 103.76),
          ],
          stops: [
            TrackedTripStop(
              stopId: '$tripId-stop',
              stopName: stopName,
              stopSequence: 1,
              coordinate: const MapCoordinate(1.50, 103.75),
              scheduledArrivalSeconds: 36000,
              scheduledDepartureSeconds: 36000,
            ),
          ],
        );
    final progress = ProgressRepository(
      dataByTrip: {
        'first-trip': legData('first-trip', 'First Leg Stop'),
        'second-trip': legData('second-trip', 'Second Leg Stop'),
      },
    );
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
        progress: progress,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('J13 → J10'), findsOneWidget);
    expect(find.text('Transfer at JB Sentral'), findsOneWidget);
    expect(find.text('Selected leg: J13'), findsOneWidget);
    expect(find.text('Near: First Leg Stop'), findsOneWidget);
    expect(find.byKey(const Key('map-first-bus')), findsOneWidget);
    expect(find.byKey(const Key('map-other-bus')), findsNothing);
    expect(find.text('planned-legs:2'), findsOneWidget);

    await tester.tap(find.text('Leg 2: J10'));
    await tester.pumpAndSettle();
    expect(find.text('Selected leg: J10'), findsOneWidget);
    expect(find.text('Near: Second Leg Stop'), findsOneWidget);
    expect(find.textContaining('First Leg Stop'), findsNothing);
    expect(find.byKey(const Key('map-second-bus')), findsOneWidget);
    expect(find.byKey(const Key('map-first-bus')), findsNothing);
    expect(progress.calls, 2);
    expect(progress.loadedTripIds, containsAll(['first-trip', 'second-trip']));
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
