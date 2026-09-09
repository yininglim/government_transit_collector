import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/timetable_recommendation_repository.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_models.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_repository.dart';
import 'package:government_transit_collector/features/passenger_location/data/passenger_location.dart';
import 'package:government_transit_collector/features/passenger_location/data/passenger_location_service.dart';
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

class FakePassengerLocationService implements PassengerLocationService {
  FakePassengerLocationService(this.responses);

  final List<PassengerLocationResult> responses;
  int calls = 0;
  int appSettingsCalls = 0;
  int locationSettingsCalls = 0;

  @override
  Future<PassengerLocationResult> getCurrentLocation() async {
    final index = calls.clamp(0, responses.length - 1);
    calls++;
    return responses[index];
  }

  @override
  Future<bool> openAppSettings() async {
    appSettingsCalls++;
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    locationSettingsCalls++;
    return true;
  }
}

class DeferredPassengerLocationService implements PassengerLocationService {
  DeferredPassengerLocationService(this.result);
  final Future<PassengerLocationResult> result;

  @override
  Future<PassengerLocationResult> getCurrentLocation() => result;

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;
}

class QueuedPassengerLocationService implements PassengerLocationService {
  QueuedPassengerLocationService(this.responses);
  final List<Future<PassengerLocationResult>> responses;
  int calls = 0;
  int activeCalls = 0;
  int maximumActiveCalls = 0;

  @override
  Future<PassengerLocationResult> getCurrentLocation() async {
    final index = calls.clamp(0, responses.length - 1);
    calls++;
    activeCalls++;
    maximumActiveCalls = maximumActiveCalls < activeCalls
        ? activeCalls
        : maximumActiveCalls;
    try {
      return await responses[index];
    } finally {
      activeCalls--;
    }
  }

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;
}

final johorPassengerLocation = PassengerLocation(
  latitude: 1.49,
  longitude: 103.74,
  accuracyMeters: 12,
  timestamp: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
);

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
  PassengerLocationService? location,
  DateTime Function()? now,
}) => MaterialApp(
  theme: ThemeData(useMaterial3: true),
  home: SelectedJourneyTrackerPage(
    journey: selected,
    realtimeRepository: realtime,
    journeyMapRepository: MapRepository(),
    tripProgressRepository: progress ?? ProgressRepository(),
    passengerLocationService:
        location ??
        FakePassengerLocationService(const [
          PassengerLocationResult.permissionDenied(),
        ]),
    pollingInterval: const Duration(hours: 1),
    now: now,
    mapBuilder: (data, markers, passenger) => ColoredBox(
      key: const Key('fake-selected-map'),
      color: Colors.blueGrey,
      child: Column(
        children: [
          Text('planned-stops:${data.stops.length}'),
          Text('planned-legs:${data.legs.length}'),
          if (passenger != null)
            Text(
              'passenger:${passenger.latitude},${passenger.longitude}',
              key: const Key('fake-passenger-marker'),
            ),
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

TripProgressData stagedLegData({required bool firstLeg}) => TripProgressData(
  tripId: firstLeg ? 'first-trip' : 'second-trip',
  shapePoints: const [MapCoordinate(1.49, 103.74), MapCoordinate(1.51, 103.76)],
  stops: firstLeg
      ? const [
          TrackedTripStop(
            stopId: 'origin',
            stopName: 'Origin Stop',
            stopSequence: 1,
            coordinate: MapCoordinate(1.49, 103.74),
            scheduledArrivalSeconds: 36000,
            scheduledDepartureSeconds: 36000,
          ),
          TrackedTripStop(
            stopId: 'transfer',
            stopName: 'JB Sentral',
            stopSequence: 2,
            coordinate: MapCoordinate(1.50, 103.75),
            scheduledArrivalSeconds: 36600,
            scheduledDepartureSeconds: 36600,
          ),
        ]
      : const [
          TrackedTripStop(
            stopId: 'transfer',
            stopName: 'JB Sentral',
            stopSequence: 1,
            coordinate: MapCoordinate(1.50, 103.75),
            scheduledArrivalSeconds: 37000,
            scheduledDepartureSeconds: 37000,
          ),
          TrackedTripStop(
            stopId: 'middle',
            stopName: 'Second Leg Stop',
            stopSequence: 2,
            coordinate: MapCoordinate(1.507, 103.757),
            scheduledArrivalSeconds: 37500,
            scheduledDepartureSeconds: 37500,
          ),
          TrackedTripStop(
            stopId: 'destination',
            stopName: 'Destination Stop',
            stopSequence: 3,
            coordinate: MapCoordinate(1.51, 103.76),
            scheduledArrivalSeconds: 38000,
            scheduledDepartureSeconds: 38000,
          ),
        ],
);

TripProgressData manyStopsData() => TripProgressData(
  tripId: 'direct-trip',
  shapePoints: const [MapCoordinate(1.49, 103.74), MapCoordinate(1.50, 103.75)],
  stops: [
    for (var index = 0; index < 7; index++)
      TrackedTripStop(
        stopId: index == 0
            ? 'origin'
            : index == 6
            ? 'destination'
            : 'stop-$index',
        stopName: index == 0 ? 'Origin' : 'Upcoming $index',
        stopSequence: index + 1,
        coordinate: MapCoordinate(
          1.49 + index * 0.0015,
          103.74 + index * 0.0015,
        ),
        scheduledArrivalSeconds: 36000 + index * 60,
        scheduledDepartureSeconds: 36000 + index * 60,
      ),
  ],
);

void main() {
  testWidgets(
    'shows scheduled fallback before enough genuine movement samples',
    (tester) async {
      await tester.pumpWidget(
        app(
          selected: journey(fixtures.directRecommendation),
          realtime: SequenceRepository([
            () async => snapshot([vehicle('direct-trip', latitude: 1.495)]),
          ]),
          now: () => DateTime.utc(2026, 8, 23, 2, 32),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('arrival-estimate-summary')), findsOneWidget);
      expect(find.text('Next Stop'), findsOneWidget);
      expect(find.text('Middle Stop'), findsWidgets);
      expect(find.byKey(const Key('live-arrival-unavailable')), findsOneWidget);
      expect(
        find.byKey(const Key('scheduled-next-stop-arrival')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'shows realtime-adjusted ETA after genuine progress observations',
    (tester) async {
      final realtime = SequenceRepository([
        () async => snapshot([
          vehicle('direct-trip', latitude: 1.4950, timestamp: 100),
        ]),
        () async => snapshot([
          vehicle('direct-trip', latitude: 1.4951, timestamp: 115),
        ]),
      ]);
      await tester.pumpWidget(
        app(
          selected: journey(fixtures.directRecommendation),
          realtime: realtime,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('live-arrival-unavailable')), findsOneWidget);

      await refresh(tester);
      expect(
        find.byKey(const Key('realtime-arrival-estimate')),
        findsOneWidget,
      );
      expect(find.textContaining('Estimated arrival ~'), findsOneWidget);
      expect(
        find.byKey(const Key('scheduled-next-stop-arrival')),
        findsOneWidget,
      );
      expect(find.textContaining('Updated'), findsWidgets);
    },
  );

  testWidgets('missing realtime shows schedule without fabricating live ETA', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        selected: journey(fixtures.directRecommendation),
        realtime: SequenceRepository([() async => snapshot([])]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('realtime-arrival-estimate')), findsNothing);
    expect(find.byKey(const Key('live-arrival-unavailable')), findsOneWidget);
    expect(
      find.byKey(const Key('scheduled-next-stop-arrival')),
      findsOneWidget,
    );
  });

  testWidgets(
    'destination is the ETA target and completion removes countdown',
    (tester) async {
      final realtime = SequenceRepository([
        () async =>
            snapshot([vehicle('direct-trip', latitude: 1.505, timestamp: 100)]),
        () async =>
            snapshot([vehicle('direct-trip', latitude: 1.51, timestamp: 115)]),
      ]);
      await tester.pumpWidget(
        app(
          selected: journey(fixtures.directRecommendation),
          realtime: realtime,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Destination'), findsWidgets);
      expect(find.byKey(const Key('arrival-estimate-summary')), findsOneWidget);

      await refresh(tester);
      expect(
        find.byKey(const Key('arrival-estimate-completed')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('realtime-arrival-estimate')), findsNothing);
    },
  );

  testWidgets('upcoming stops are compact and can be expanded', (tester) async {
    await tester.pumpWidget(
      app(
        selected: journey(fixtures.directRecommendation),
        realtime: SequenceRepository([
          () async => snapshot([vehicle('direct-trip', latitude: 1.4902)]),
        ]),
        progress: ProgressRepository(
          dataByTrip: {'direct-trip': manyStopsData()},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Upcoming 5'), findsNothing);
    expect(find.textContaining(RegExp(r'^\d+\. Upcoming')), findsNWidgets(3));
    final toggle = find.byKey(const Key('toggle-upcoming-stops'));
    expect(toggle, findsOneWidget);
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.textContaining(RegExp(r'^\d+\. Upcoming')), findsNWidgets(5));
    expect(find.text('Show fewer upcoming stops'), findsOneWidget);
  });

  testWidgets(
    'automatic transfer progression preserves manual viewing and location',
    (tester) async {
      final realtime = SequenceRepository([
        () async => snapshot([
          vehicle(
            'first-trip',
            id: 'first-bus',
            routeId: 'route-13',
            latitude: 1.4995,
          ),
          vehicle(
            'second-trip',
            id: 'second-bus-early',
            routeId: 'route-10',
            latitude: 1.503,
          ),
        ]),
        () async => snapshot([
          vehicle(
            'first-trip',
            id: 'first-bus',
            routeId: 'route-13',
            latitude: 1.5003,
          ),
        ]),
        () async => snapshot([
          vehicle(
            'second-trip',
            id: 'second-bus',
            routeId: 'route-10',
            latitude: 1.503,
          ),
        ]),
      ]);
      final progress = ProgressRepository(
        dataByTrip: {
          'first-trip': stagedLegData(firstLeg: true),
          'second-trip': stagedLegData(firstLeg: false),
        },
      );
      await tester.pumpWidget(
        app(
          selected: journey(fixtures.transferRecommendation),
          realtime: realtime,
          progress: progress,
          location: FakePassengerLocationService([
            PassengerLocationResult.available(johorPassengerLocation),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Approaching transfer at JB Sentral'), findsOneWidget);
      expect(find.text('Viewing J13 · Current leg'), findsOneWidget);
      expect(find.text('JB Sentral'), findsWidgets);
      expect(find.byKey(const Key('arrival-estimate-summary')), findsOneWidget);
      expect(find.byKey(const Key('map-first-bus')), findsOneWidget);
      expect(find.byKey(const Key('map-second-bus-early')), findsNothing);

      await refresh(tester);
      expect(find.text('Waiting for J10'), findsOneWidget);
      expect(find.text('Viewing J10 · Current leg'), findsOneWidget);
      expect(find.text('Second Leg Stop'), findsWidgets);
      expect(find.text('Boarding stop: JB Sentral'), findsOneWidget);
      expect(
        find.textContaining('approximately 1.6 km from boarding stop'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('fake-passenger-marker')), findsOneWidget);

      await tester.tap(find.textContaining('Leg 1 · J13'));
      await tester.pumpAndSettle();
      expect(find.text('Viewing J13'), findsOneWidget);
      expect(find.text('Waiting for J10'), findsOneWidget);
      expect(find.byKey(const Key('follow-current-stage')), findsOneWidget);

      await tester.tap(find.byKey(const Key('follow-current-stage')));
      await tester.pumpAndSettle();
      expect(find.text('Viewing J10 · Current leg'), findsOneWidget);

      await refresh(tester);
      expect(find.text('Tracking J10'), findsOneWidget);
      expect(find.byKey(const Key('map-second-bus')), findsOneWidget);
      expect(progress.calls, 2);
    },
  );

  testWidgets('shows location loading independently from realtime', (
    tester,
  ) async {
    final pending = Completer<PassengerLocationResult>();
    await tester.pumpWidget(
      app(
        selected: journey(fixtures.directRecommendation),
        realtime: SequenceRepository([() async => snapshot([])]),
        location: DeferredPassengerLocationService(pending.future),
      ),
    );
    await tester.pump();
    expect(find.text('Getting your location...'), findsOneWidget);
    expect(
      find.text('Waiting for realtime vehicle data for this trip.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'successful location shows boarding distance without a live bus',
    (tester) async {
      final location = FakePassengerLocationService([
        PassengerLocationResult.available(johorPassengerLocation),
      ]);
      await tester.pumpWidget(
        app(
          selected: journey(fixtures.directRecommendation),
          realtime: SequenceRepository([() async => snapshot([])]),
          location: location,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Boarding stop: Origin Stop'), findsOneWidget);
      expect(
        find.text(
          'Straight-line distance: approximately 0 m from boarding stop',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('fake-passenger-marker')), findsOneWidget);
      expect(find.byKey(const Key('map-bus-1')), findsNothing);
    },
  );

  testWidgets('location failures do not hide realtime bus and progress', (
    tester,
  ) async {
    final cases = <PassengerLocationResult, String>{
      const PassengerLocationResult.notRequested():
          'Location permission is required.',
      const PassengerLocationResult.permissionDenied():
          'Location permission was denied.',
      const PassengerLocationResult.permissionDeniedForever():
          'Location permission is permanently denied.',
      const PassengerLocationResult.servicesDisabled():
          'Location services are disabled.',
      const PassengerLocationResult.unknownError():
          'An unexpected location error occurred.',
    };
    for (final entry in cases.entries) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(
        app(
          selected: journey(fixtures.directRecommendation),
          realtime: SequenceRepository([
            () async => snapshot([vehicle('direct-trip')]),
          ]),
          location: FakePassengerLocationService([entry.key]),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      expect(find.byKey(const Key('map-bus-1')), findsOneWidget);
      expect(find.byKey(const Key('route-progress-summary')), findsOneWidget);
      expect(find.byKey(const Key('fake-passenger-marker')), findsNothing);
    }
  });

  testWidgets('missing boarding coordinate and poor accuracy are explained', (
    tester,
  ) async {
    final poorLocation = PassengerLocation(
      latitude: 1.49,
      longitude: 103.74,
      accuracyMeters: 150,
      timestamp: DateTime.utc(2026),
    );
    await tester.pumpWidget(
      app(
        selected: journey(fixtures.directRecommendation),
        realtime: SequenceRepository([() async => snapshot([])]),
        progress: ProgressRepository(
          dataByTrip: {
            'direct-trip': const TripProgressData(
              tripId: 'direct-trip',
              shapePoints: [],
              stops: [],
            ),
          },
        ),
        location: FakePassengerLocationService([
          PassengerLocationResult.available(poorLocation),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Boarding-stop coordinates are unavailable.'),
      findsOneWidget,
    );
    expect(
      find.text('Approximate location (limited GPS accuracy)'),
      findsOneWidget,
    );
  });

  testWidgets('settings actions and Refresh Location use injected service', (
    tester,
  ) async {
    final service = FakePassengerLocationService([
      PassengerLocationResult.permissionDeniedForever(),
      PassengerLocationResult.available(johorPassengerLocation),
    ]);
    await tester.pumpWidget(
      app(
        selected: journey(fixtures.directRecommendation),
        realtime: SequenceRepository([
          () async => snapshot([vehicle('direct-trip')]),
        ]),
        location: service,
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('open-location-app-settings')),
    );
    await tester.tap(find.byKey(const Key('open-location-app-settings')));
    await tester.pump();
    expect(service.appSettingsCalls, 1);

    await tester.ensureVisible(
      find.byKey(const Key('refresh-passenger-location')),
    );
    await tester.tap(find.byKey(const Key('refresh-passenger-location')));
    await tester.pumpAndSettle();
    expect(service.calls, 2);
    expect(find.byKey(const Key('fake-passenger-marker')), findsOneWidget);
    expect(find.byKey(const Key('map-bus-1')), findsOneWidget);
  });

  testWidgets('repeated Refresh Location taps never overlap requests', (
    tester,
  ) async {
    final refreshResult = Completer<PassengerLocationResult>();
    final service = QueuedPassengerLocationService([
      Future.value(PassengerLocationResult.available(johorPassengerLocation)),
      refreshResult.future,
    ]);
    await tester.pumpWidget(
      app(
        selected: journey(fixtures.directRecommendation),
        realtime: SequenceRepository([() async => snapshot([])]),
        location: service,
      ),
    );
    await tester.pumpAndSettle();
    final refreshButton = find.byKey(const Key('refresh-passenger-location'));
    await tester.ensureVisible(refreshButton);
    await tester.tap(refreshButton);
    await tester.pump();
    await tester.tap(refreshButton);
    await tester.pump();

    expect(service.calls, 2);
    expect(service.maximumActiveCalls, 1);
    expect(find.text('Getting your location...'), findsOneWidget);
    expect(tester.widget<TextButton>(refreshButton).onPressed, isNull);

    refreshResult.complete(const PassengerLocationResult.unknownError());
    await tester.pumpAndSettle();
    expect(find.text('An unexpected location error occurred.'), findsOneWidget);
    expect(tester.widget<TextButton>(refreshButton).onPressed, isNotNull);
  });

  testWidgets('last-known fallback is labelled and loading clears', (
    tester,
  ) async {
    final service = FakePassengerLocationService([
      PassengerLocationResult.available(
        johorPassengerLocation,
        isLastKnown: true,
      ),
    ]);
    await tester.pumpWidget(
      app(
        selected: journey(fixtures.directRecommendation),
        realtime: SequenceRepository([() async => snapshot([])]),
        location: service,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('last-known-passenger-location')),
      findsOneWidget,
    );
    expect(find.text('Getting your location...'), findsNothing);
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const Key('refresh-passenger-location')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('disposed tracker ignores a late location result safely', (
    tester,
  ) async {
    final pending = Completer<PassengerLocationResult>();
    await tester.pumpWidget(
      app(
        selected: journey(fixtures.directRecommendation),
        realtime: SequenceRepository([() async => snapshot([])]),
        location: DeferredPassengerLocationService(pending.future),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(PassengerLocationResult.available(johorPassengerLocation));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

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
    expect(find.textContaining('10:30 AM → 11:05 AM'), findsOneWidget);
    expect(find.text('Tracking J15'), findsOneWidget);
    expect(find.text('Next: Middle Stop'), findsOneWidget);
    expect(find.text('Live tracking active'), findsOneWidget);
    expect(find.textContaining('selected · Updated'), findsOneWidget);
    expect(find.byKey(const Key('route-progress-summary')), findsOneWidget);
    expect(find.text('Next stop: Middle Stop'), findsOneWidget);
    expect(find.text('Middle Stop'), findsWidgets);
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
    expect(find.text('Waiting to board J15'), findsOneWidget);
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
    expect(find.textContaining('· Last known'), findsOneWidget);
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
    TripProgressData legData(
      String tripId,
      String stopId,
      String stopName,
      MapCoordinate coordinate,
    ) => TripProgressData(
      tripId: tripId,
      shapePoints: const [
        MapCoordinate(1.49, 103.74),
        MapCoordinate(1.51, 103.76),
      ],
      stops: [
        TrackedTripStop(
          stopId: stopId,
          stopName: stopName,
          stopSequence: 1,
          coordinate: coordinate,
          scheduledArrivalSeconds: 36000,
          scheduledDepartureSeconds: 36000,
        ),
      ],
    );
    final progress = ProgressRepository(
      dataByTrip: {
        'first-trip': legData(
          'first-trip',
          'origin',
          'First Leg Stop',
          const MapCoordinate(1.49, 103.74),
        ),
        'second-trip': legData(
          'second-trip',
          'transfer',
          'Second Leg Stop',
          const MapCoordinate(1.50, 103.75),
        ),
      },
    );
    final location = FakePassengerLocationService([
      PassengerLocationResult.available(johorPassengerLocation),
    ]);
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
        location: location,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('J13 → J10'), findsOneWidget);
    expect(find.text('Transfer · JB Sentral'), findsOneWidget);
    expect(find.text('Viewing J13 · Current leg'), findsOneWidget);
    expect(find.text('Boarding stop: Origin Stop'), findsOneWidget);
    expect(
      find.textContaining('approximately 0 m from boarding stop'),
      findsOneWidget,
    );
    expect(find.text('Near: First Leg Stop'), findsOneWidget);
    expect(find.byKey(const Key('map-first-bus')), findsOneWidget);
    expect(find.byKey(const Key('map-other-bus')), findsNothing);
    expect(find.text('planned-legs:2'), findsOneWidget);

    await tester.tap(find.textContaining('Leg 2 · J10'));
    await tester.pumpAndSettle();
    expect(find.text('Viewing J10'), findsOneWidget);
    expect(find.text('Boarding stop: JB Sentral'), findsOneWidget);
    expect(
      find.textContaining('approximately 1.6 km from boarding stop'),
      findsOneWidget,
    );
    expect(find.text('Near: Second Leg Stop'), findsOneWidget);
    expect(find.textContaining('First Leg Stop'), findsNothing);
    expect(find.byKey(const Key('map-second-bus')), findsOneWidget);
    expect(find.byKey(const Key('map-first-bus')), findsNothing);
    expect(progress.calls, 2);
    expect(progress.loadedTripIds, containsAll(['first-trip', 'second-trip']));
    expect(location.calls, 1);
    expect(find.byKey(const Key('fake-passenger-marker')), findsOneWidget);
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
      find.text('Live update temporarily unavailable. Retrying automatically…'),
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
    final realtime = SequenceRepository([() async => snapshot([])]);
    await tester.binding.setSurfaceSize(const Size(400, 800));
    await tester.pumpWidget(
      app(
        selected: journey(fixtures.transferRecommendation),
        realtime: realtime,
        location: FakePassengerLocationService([
          PassengerLocationResult.available(johorPassengerLocation),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Leg 2'));
    await tester.pump();

    for (final size in [const Size(800, 400), const Size(400, 800)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpAndSettle();
      expect(find.text('J13 → J10'), findsOneWidget);
      expect(find.byKey(const Key('selected-leg-selector')), findsOneWidget);
      expect(
        tester
            .widget<SegmentedButton<int>>(
              find.byKey(const Key('selected-leg-selector')),
            )
            .selected,
        {1},
      );
      expect(find.byKey(const Key('current-journey-stage')), findsOneWidget);
      expect(find.byKey(const Key('refresh-selected-journey')), findsOneWidget);
      expect(find.text('Your Location'), findsOneWidget);
      expect(find.text('Boarding stop: JB Sentral'), findsOneWidget);
      expect(
        find.byKey(const Key('refresh-passenger-location')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('fake-passenger-marker')), findsOneWidget);
      expect(find.byKey(const Key('fake-selected-map')), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    expect(realtime.calls, 1);
    await tester.binding.setSurfaceSize(null);
  });
}
