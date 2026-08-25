import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/gtfs_realtime_decoder.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_position.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_repository.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_route_metadata_repository.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/static_trip_matcher.dart';
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
}) => MaterialApp(
  theme: ThemeData(useMaterial3: true),
  home: RealtimeJourneyTrackerPage(
    repository: repository,
    tripMatcher: matcher ?? TrackerMatcher(),
    pollingInterval: const Duration(hours: 1),
    mapBuilder: fakeMap,
    routeMetadataRepository: routeMetadata ?? RouteMetadataRepository(),
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
    await tester.pumpWidget(
      app(TrackerRepository([() async => trackerSnapshot])),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('fake-vehicle:JWG6029')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('vehicle-details')), findsOneWidget);
    expect(find.text('J15'), findsOneWidget);
    expect(find.text('City Centre ↔ Permas Jaya'), findsOneWidget);
    expect(find.text('Vehicle: JWG6029'), findsOneWidget);
    expect(find.textContaining('Updated:'), findsWidgets);
    expect(find.text('Updated: 1:20:00 AM'), findsOneWidget);
    expect(find.text('Development movement diagnostic'), findsNothing);
    expect(find.textContaining('Position changed'), findsNothing);
    expect(find.textContaining('Trip matched'), findsNothing);
    expect(find.textContaining('trip-1'), findsNothing);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await disposePage(tester);
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
        app(TrackerRepository([() async => trackerSnapshot])),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('fake-live-map')), findsOneWidget);
      expect(find.text('Live buses: 2'), findsOneWidget);
      expect(find.byKey(const Key('refresh-tracker')), findsOneWidget);
      expect(find.byKey(const Key('route-filter')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await disposePage(tester);
    }
    await tester.binding.setSurfaceSize(null);
  });
}
