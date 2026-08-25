import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_models.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/gtfs_realtime_decoder.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_position.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_repository.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_route_metadata_repository.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/static_trip_matcher.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/trip_progress_models.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/trip_progress_repository.dart';
import 'package:government_transit_collector/features/realtime_vehicle/presentation/realtime_journey_tracker_page.dart';
import 'package:government_transit_collector/features/realtime_vehicle/presentation/realtime_vehicle_marker_data.dart';

const firstVehicle = RealtimeVehiclePosition(
  vehicleId: 'JWG6029',
  tripId: 'trip-1',
  routeId: 'J15CWLMYJB',
  latitude: 1.492345,
  longitude: 103.741234,
  timestampSeconds: 1787332800,
);

const secondVehicle = RealtimeVehiclePosition(
  vehicleId: 'JVT1002',
  tripId: 'unknown-trip',
  routeId: 'J10',
  latitude: 1.500001,
  longitude: 103.750001,
  timestampSeconds: 1787332860,
);

const trackerSnapshot = RealtimeFeedSnapshot(
  vehicles: [firstVehicle, secondVehicle],
  feedTimestampSeconds: 1787332900,
);

class TrackerRepository implements RealtimeVehicleRepository {
  TrackerRepository(this.responses);
  final List<Future<RealtimeFeedSnapshot> Function()> responses;
  int calls = 0;

  @override
  Future<RealtimeFeedSnapshot> fetchVehiclePositions() {
    final index = calls.clamp(0, responses.length - 1);
    calls++;
    return responses[index]();
  }
}

class TrackerMatcher implements StaticTripMatcher {
  TrackerMatcher({this.fail = false});
  final bool fail;

  @override
  Future<Set<String>> findKnownTripIds(Iterable<String> ids) async {
    if (fail) throw Exception('matching unavailable');
    return {'trip-1'};
  }
}

class RouteMetadataRepository implements RealtimeRouteMetadataRepository {
  RouteMetadataRepository({this.fail = false});
  final bool fail;
  int calls = 0;
  final List<Set<String>> requested = [];

  @override
  Future<Map<String, RealtimeRouteMetadata>> loadRoutes(
    Iterable<String> routeIds,
  ) async {
    calls++;
    requested.add(routeIds.toSet());
    if (fail) throw Exception('static routes unavailable');
    return {
      'J15CWLMYJB': const RealtimeRouteMetadata(
        routeId: 'J15CWLMYJB',
        shortName: 'J15',
        longName: 'City Centre ↔ Permas Jaya',
      ),
      'J10': const RealtimeRouteMetadata(
        routeId: 'J10',
        shortName: 'J10',
        longName: 'JB Sentral ↔ Kota Masai',
      ),
    };
  }
}

class TrackerProgressRepository implements TripProgressRepository {
  TrackerProgressRepository(this.responses);

  final Map<String, Future<TripProgressData> Function()> responses;
  final List<String> requestedTripIds = [];

  @override
  Future<TripProgressData> loadTrip(String exactTripId) {
    requestedTripIds.add(exactTripId);
    final response = responses[exactTripId];
    if (response == null) {
      return Future.error(StateError('Unknown exact trip: $exactTripId'));
    }
    return response();
  }
}

TripProgressData progressData({
  String tripId = 'trip-1',
  String namePrefix = '',
}) => TripProgressData(
  tripId: tripId,
  shapePoints: const [
    MapCoordinate(1.490000, 103.740000),
    MapCoordinate(1.500000, 103.750000),
    MapCoordinate(1.510000, 103.760000),
  ],
  stops: [
    TrackedTripStop(
      stopId: '${namePrefix}first',
      stopName: '${namePrefix}First Stop',
      stopSequence: 1,
      coordinate: const MapCoordinate(1.490000, 103.740000),
      scheduledArrivalSeconds: 100,
      scheduledDepartureSeconds: 100,
    ),
    TrackedTripStop(
      stopId: '${namePrefix}middle',
      stopName: '${namePrefix}Middle Stop',
      stopSequence: 2,
      coordinate: const MapCoordinate(1.500000, 103.750000),
      scheduledArrivalSeconds: 200,
      scheduledDepartureSeconds: 200,
    ),
    TrackedTripStop(
      stopId: '${namePrefix}final',
      stopName: '${namePrefix}Final Stop',
      stopSequence: 3,
      coordinate: const MapCoordinate(1.510000, 103.760000),
      scheduledArrivalSeconds: 300,
      scheduledDepartureSeconds: 300,
    ),
  ],
);

Widget fakeMap(
  List<RealtimeVehicleMarkerData> markers,
  ValueChanged<RealtimeVehicleMarkerData> onTap,
) => ColoredBox(
  key: const Key('fake-live-map'),
  color: Colors.blueGrey,
  child: ListView(
    children: markers
        .map(
          (marker) => TextButton(
            key: ValueKey('fake-${marker.identity}'),
            onPressed: () => onTap(marker),
            child: Text(marker.identity),
          ),
        )
        .toList(),
  ),
);

Widget app(
  RealtimeVehicleRepository repository, {
  StaticTripMatcher? matcher,
  RealtimeRouteMetadataRepository? routeMetadata,
  TripProgressRepository? tripProgress,
}) => MaterialApp(
  theme: ThemeData(useMaterial3: true),
  home: RealtimeJourneyTrackerPage(
    repository: repository,
    tripMatcher: matcher ?? TrackerMatcher(),
    pollingInterval: const Duration(hours: 1),
    mapBuilder: fakeMap,
    routeMetadataRepository: routeMetadata ?? RouteMetadataRepository(),
    tripProgressRepository: tripProgress,
  ),
);

Future<void> disposePage(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox());

void main() {
  testWidgets('shows initial loading state', (tester) async {
    final pending = Completer<RealtimeFeedSnapshot>();
    await tester.pumpWidget(app(TrackerRepository([() => pending.future])));

    expect(find.byKey(const Key('tracker-loading')), findsOneWidget);
    await disposePage(tester);
  });

  testWidgets('initial success shows count, update, filter, and markers', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(TrackerRepository([() async => trackerSnapshot])),
    );
    await tester.pumpAndSettle();

    expect(find.text('Live buses: 2'), findsOneWidget);
    expect(find.textContaining('Updated:'), findsWidgets);
    expect(find.text('Auto refresh: 3600 sec'), findsOneWidget);
    expect(find.byKey(const Key('route-filter')), findsOneWidget);
    expect(find.byKey(const Key('fake-vehicle:JWG6029')), findsOneWidget);
    expect(find.byKey(const Key('fake-vehicle:JVT1002')), findsOneWidget);
    await disposePage(tester);
  });

  testWidgets('marker tap opens passenger-friendly details', (tester) async {
    final progressRepository = TrackerProgressRepository({
      'trip-1': () async => progressData(),
    });
    await tester.pumpWidget(
      app(
        TrackerRepository([() async => trackerSnapshot]),
        tripProgress: progressRepository,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('fake-vehicle:JWG6029')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('vehicle-details')), findsOneWidget);
    expect(find.text('J15'), findsOneWidget);
    expect(find.text('City Centre ↔ Permas Jaya'), findsOneWidget);
    expect(find.text('Vehicle: JWG6029'), findsOneWidget);
    expect(find.text('Near First Stop'), findsOneWidget);
    expect(find.text('Middle Stop'), findsOneWidget);
    expect(find.textContaining('Updated:'), findsWidgets);
    expect(find.text('Updated: 1:20:00 AM'), findsOneWidget);
    expect(find.text('Development movement diagnostic'), findsNothing);
    expect(find.textContaining('Position changed'), findsNothing);
    expect(find.textContaining('Trip matched'), findsNothing);
    expect(find.textContaining('trip-1'), findsNothing);
    expect(find.textContaining('1.492345'), findsNothing);
    expect(find.textContaining('103.741234'), findsNothing);
    expect(progressRepository.requestedTripIds, ['trip-1']);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await disposePage(tester);
  });

  testWidgets('marker details show progress loading immediately', (
    tester,
  ) async {
    final pending = Completer<TripProgressData>();
    final progressRepository = TrackerProgressRepository({
      'trip-1': () => pending.future,
    });
    await tester.pumpWidget(
      app(
        TrackerRepository([() async => trackerSnapshot]),
        tripProgress: progressRepository,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('fake-vehicle:JWG6029')));
    await tester.pump();
    expect(find.text('Loading route position...'), findsOneWidget);
    expect(find.text('Loading...'), findsOneWidget);

    pending.complete(progressData());
    await tester.pumpAndSettle();
    expect(find.text('Near First Stop'), findsOneWidget);
    expect(find.text('Middle Stop'), findsOneWidget);
  });

  testWidgets('missing exact trip and load failure stay passenger friendly', (
    tester,
  ) async {
    const missingTripVehicle = RealtimeVehiclePosition(
      vehicleId: 'missing-trip-bus',
      tripId: null,
      routeId: 'J10',
      latitude: 1.5,
      longitude: 103.75,
      timestampSeconds: 1787332860,
    );
    final progressRepository = TrackerProgressRepository({
      'unknown-trip': () => Future.error(StateError('not in static GTFS')),
    });
    await tester.pumpWidget(
      app(
        TrackerRepository([
          () async => const RealtimeFeedSnapshot(
            vehicles: [missingTripVehicle, secondVehicle],
            feedTimestampSeconds: 1787332900,
          ),
        ]),
        tripProgress: progressRepository,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('fake-vehicle:missing-trip-bus')));
    await tester.pumpAndSettle();
    expect(find.text('Route position unavailable'), findsOneWidget);
    expect(find.text('Unavailable'), findsOneWidget);
    expect(progressRepository.requestedTripIds, isEmpty);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('fake-vehicle:JVT1002')));
    await tester.pumpAndSettle();
    expect(find.text('Route position unavailable'), findsOneWidget);
    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.textContaining('not in static GTFS'), findsNothing);
  });

  testWidgets('off-route vehicle reports unavailable progress', (tester) async {
    const offRoute = RealtimeVehiclePosition(
      vehicleId: 'off-route',
      tripId: 'trip-1',
      routeId: 'J15CWLMYJB',
      latitude: 2,
      longitude: 104,
      timestampSeconds: 1787332860,
    );
    await tester.pumpWidget(
      app(
        TrackerRepository([
          () async => const RealtimeFeedSnapshot(
            vehicles: [offRoute],
            feedTimestampSeconds: 1787332900,
          ),
        ]),
        tripProgress: TrackerProgressRepository({
          'trip-1': () async => progressData(),
        }),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fake-vehicle:off-route')));
    await tester.pumpAndSettle();

    expect(find.text('Route position unavailable'), findsOneWidget);
    expect(find.text('Unavailable'), findsOneWidget);
  });

  testWidgets('final stop reports route trip completed', (tester) async {
    const completedVehicle = RealtimeVehiclePosition(
      vehicleId: 'completed-bus',
      tripId: 'trip-1',
      routeId: 'J15CWLMYJB',
      latitude: 1.51,
      longitude: 103.76,
      timestampSeconds: 1787332860,
    );
    await tester.pumpWidget(
      app(
        TrackerRepository([
          () async => const RealtimeFeedSnapshot(
            vehicles: [completedVehicle],
            feedTimestampSeconds: 1787332900,
          ),
        ]),
        tripProgress: TrackerProgressRepository({
          'trip-1': () async => progressData(),
        }),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fake-vehicle:completed-bus')));
    await tester.pumpAndSettle();

    expect(find.text('Near Final Stop'), findsOneWidget);
    expect(find.text('Route trip completed'), findsOneWidget);
    expect(find.byKey(const Key('vehicle-next-stop')), findsNothing);
  });

  testWidgets('movement advances next stop without reloading static trip', (
    tester,
  ) async {
    const movedVehicle = RealtimeVehiclePosition(
      vehicleId: 'JWG6029',
      tripId: 'trip-1',
      routeId: 'J15CWLMYJB',
      latitude: 1.505,
      longitude: 103.755,
      timestampSeconds: 1787333000,
    );
    final realtimeRepository = TrackerRepository([
      () async => const RealtimeFeedSnapshot(
        vehicles: [firstVehicle],
        feedTimestampSeconds: 1787332900,
      ),
      () async => const RealtimeFeedSnapshot(
        vehicles: [movedVehicle],
        feedTimestampSeconds: 1787333000,
      ),
    ]);
    final progressRepository = TrackerProgressRepository({
      'trip-1': () async => progressData(),
    });
    await tester.pumpWidget(
      app(realtimeRepository, tripProgress: progressRepository),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('fake-vehicle:JWG6029')));
    await tester.pumpAndSettle();
    expect(find.text('Middle Stop'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('refresh-tracker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fake-vehicle:JWG6029')));
    await tester.pumpAndSettle();

    expect(find.text('Near Middle Stop'), findsOneWidget);
    expect(find.text('Final Stop'), findsOneWidget);
    expect(progressRepository.requestedTripIds, ['trip-1']);
  });

  testWidgets('multiple vehicles resolve independent exact trips', (
    tester,
  ) async {
    final progressRepository = TrackerProgressRepository({
      'trip-1': () async => progressData(namePrefix: 'A '),
      'unknown-trip': () async =>
          progressData(tripId: 'unknown-trip', namePrefix: 'B '),
    });
    await tester.pumpWidget(
      app(
        TrackerRepository([() async => trackerSnapshot]),
        tripProgress: progressRepository,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('fake-vehicle:JWG6029')));
    await tester.pumpAndSettle();
    expect(find.text('Near A First Stop'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fake-vehicle:JVT1002')));
    await tester.pumpAndSettle();
    expect(find.text('Near B Middle Stop'), findsOneWidget);
    expect(progressRepository.requestedTripIds, ['trip-1', 'unknown-trip']);
  });

  testWidgets('initial error exposes Retry and can recover', (tester) async {
    final repository = TrackerRepository([
      () => Future.error(
        const RealtimeVehicleReadException('Network unavailable.'),
      ),
      () async => trackerSnapshot,
    ]);
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();

    expect(find.text('Network unavailable.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('retry-tracker')));
    await tester.pumpAndSettle();
    expect(repository.calls, 2);
    expect(find.text('Live buses: 2'), findsOneWidget);
    await disposePage(tester);
  });

  testWidgets('manual refresh replaces marker coordinates without duplicates', (
    tester,
  ) async {
    final movedSnapshot = RealtimeFeedSnapshot(
      vehicles: [
        const RealtimeVehiclePosition(
          vehicleId: 'JWG6029',
          tripId: 'trip-1',
          routeId: 'J15',
          latitude: 1.55,
          longitude: 103.80,
          timestampSeconds: 1787333000,
        ),
      ],
      feedTimestampSeconds: 1787333000,
    );
    final repository = TrackerRepository([
      () async => trackerSnapshot,
      () async => movedSnapshot,
    ]);
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('refresh-tracker')));
    await tester.pumpAndSettle();
    expect(repository.calls, 2);
    expect(find.text('Live buses: 1'), findsOneWidget);
    expect(find.byKey(const Key('fake-vehicle:JWG6029')), findsOneWidget);
    expect(find.byKey(const Key('fake-vehicle:JVT1002')), findsNothing);
    await disposePage(tester);
  });

  testWidgets('refresh failure retains markers and shows warning', (
    tester,
  ) async {
    final repository = TrackerRepository([
      () async => trackerSnapshot,
      () => Future.error(
        const RealtimeVehicleReadException('Network unavailable.'),
      ),
    ]);
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('refresh-tracker')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fake-vehicle:JWG6029')), findsOneWidget);
    expect(find.byKey(const Key('tracker-warning')), findsOneWidget);
    expect(find.textContaining('last known'), findsOneWidget);
    await disposePage(tester);
  });

  testWidgets('route filter shows only selected dynamic route', (tester) async {
    await tester.pumpWidget(
      app(TrackerRepository([() async => trackerSnapshot])),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('route-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('J10 —').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fake-vehicle:JVT1002')), findsOneWidget);
    expect(find.byKey(const Key('fake-vehicle:JWG6029')), findsNothing);
    expect(find.text('J10'), findsOneWidget);
    expect(find.text('JB Sentral ↔ Kota Masai'), findsOneWidget);
    expect(find.text('Live buses: 1'), findsOneWidget);
    await disposePage(tester);
  });

  testWidgets('selected route counts multiple buses using route_id filter', (
    tester,
  ) async {
    const anotherJ15 = RealtimeVehiclePosition(
      vehicleId: 'second-j15',
      tripId: 'trip-2',
      routeId: 'J15CWLMYJB',
      latitude: 1.51,
      longitude: 103.76,
      timestampSeconds: 1787332860,
    );
    const snapshot = RealtimeFeedSnapshot(
      vehicles: [firstVehicle, anotherJ15, secondVehicle],
      feedTimestampSeconds: 1787332900,
    );
    await tester.pumpWidget(app(TrackerRepository([() async => snapshot])));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('route-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('J15 —').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('fake-vehicle:JWG6029')), findsOneWidget);
    expect(find.byKey(const Key('fake-vehicle:second-j15')), findsOneWidget);
    expect(find.byKey(const Key('fake-vehicle:JVT1002')), findsNothing);
    expect(find.text('Live buses: 2'), findsWidgets);
  });

  testWidgets('selected route remains selected when its vehicles disappear', (
    tester,
  ) async {
    final repository = TrackerRepository([
      () async => trackerSnapshot,
      () async => const RealtimeFeedSnapshot(
        vehicles: [firstVehicle],
        feedTimestampSeconds: 1787333000,
      ),
    ]);
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('route-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('J10 —').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('refresh-tracker')));
    await tester.pumpAndSettle();

    expect(
      find.text('No realtime buses are currently available for J10.'),
      findsOneWidget,
    );
    expect(find.text('Live buses: 0'), findsOneWidget);
  });

  testWidgets('static route metadata failure falls back without losing map', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        TrackerRepository([() async => trackerSnapshot]),
        routeMetadata: RouteMetadataRepository(fail: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Passenger route names are temporarily unavailable.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('fake-live-map')), findsOneWidget);
    expect(find.text('All Routes'), findsOneWidget);
  });

  testWidgets('zero valid coordinates displays empty state', (tester) async {
    const noCoordinates = RealtimeFeedSnapshot(
      vehicles: [
        RealtimeVehiclePosition(
          vehicleId: 'bus',
          tripId: 'trip',
          routeId: 'J10',
          latitude: null,
          longitude: null,
          timestampSeconds: 100,
        ),
      ],
      feedTimestampSeconds: 101,
    );
    await tester.pumpWidget(
      app(TrackerRepository([() async => noCoordinates])),
    );
    await tester.pumpAndSettle();

    expect(find.text('Live buses: 0'), findsOneWidget);
    expect(find.byKey(const Key('tracker-empty')), findsOneWidget);
    await disposePage(tester);
  });

  testWidgets('portrait and landscape retain map and controls', (tester) async {
    for (final size in [const Size(400, 800), const Size(800, 400)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        app(
          TrackerRepository([() async => trackerSnapshot]),
          tripProgress: TrackerProgressRepository({
            'trip-1': () async => progressData(),
          }),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('fake-live-map')), findsOneWidget);
      expect(find.text('Live buses: 2'), findsOneWidget);
      expect(find.byKey(const Key('refresh-tracker')), findsOneWidget);
      expect(find.byKey(const Key('route-filter')), findsOneWidget);
      await tester.tap(find.byKey(const Key('fake-vehicle:JWG6029')));
      await tester.pumpAndSettle();
      expect(find.text('Near First Stop'), findsOneWidget);
      expect(find.text('Middle Stop'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await disposePage(tester);
    }
    await tester.binding.setSurfaceSize(null);
  });
}
