import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/gtfs_realtime_decoder.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_position.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_repository.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/static_trip_matcher.dart';
import 'package:government_transit_collector/features/realtime_vehicle/presentation/realtime_journey_tracker_page.dart';
import 'package:government_transit_collector/features/realtime_vehicle/presentation/realtime_vehicle_marker_data.dart';

const firstVehicle = RealtimeVehiclePosition(
  vehicleId: 'JWG6029',
  tripId: 'trip-1',
  routeId: 'J15',
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
}) => MaterialApp(
  theme: ThemeData(useMaterial3: true),
  home: RealtimeJourneyTrackerPage(
    repository: repository,
    tripMatcher: matcher ?? TrackerMatcher(),
    pollingInterval: const Duration(hours: 1),
    mapBuilder: fakeMap,
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

    expect(find.text('Live Vehicles: 2'), findsOneWidget);
    expect(find.textContaining('Last updated:'), findsOneWidget);
    expect(find.text('Auto refresh: Every 3600 sec'), findsOneWidget);
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
    expect(find.text('Route J15'), findsOneWidget);
    expect(find.text('Vehicle: JWG6029'), findsOneWidget);
    expect(find.text('Trip matched: Yes'), findsOneWidget);
    expect(find.textContaining('Updated:'), findsOneWidget);
    expect(find.text('Development movement diagnostic'), findsOneWidget);
    expect(
      find.text('Position changed: Not available (first observation)'),
      findsOneWidget,
    );
    expect(find.text('Previous: Not available'), findsOneWidget);
    expect(find.text('Latest: 1.492345, 103.741234'), findsOneWidget);
    expect(find.textContaining('trip-1'), findsNothing);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await disposePage(tester);
  });

  testWidgets('vehicle details compare consecutive genuine feed positions', (
    tester,
  ) async {
    const movedVehicle = RealtimeVehiclePosition(
      vehicleId: 'JWG6029',
      tripId: 'trip-1',
      routeId: 'J15',
      latitude: 1.492399,
      longitude: 103.741291,
      timestampSeconds: 1787332815,
    );
    final repository = TrackerRepository([
      () async => trackerSnapshot,
      () async => const RealtimeFeedSnapshot(
        vehicles: [movedVehicle],
        feedTimestampSeconds: 1787332815,
      ),
    ]);
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('refresh-tracker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fake-vehicle:JWG6029')));
    await tester.pumpAndSettle();

    expect(find.text('Position changed: Yes'), findsOneWidget);
    expect(find.text('Previous: 1.492345, 103.741234'), findsOneWidget);
    expect(find.text('Latest: 1.492399, 103.741291'), findsOneWidget);
    expect(find.textContaining('Moved: '), findsOneWidget);
    expect(find.text('Feed interval: 15 sec'), findsOneWidget);
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
    expect(find.text('Live Vehicles: 2'), findsOneWidget);
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
    expect(find.text('Live Vehicles: 1'), findsOneWidget);
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
    await tester.tap(find.text('J10').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fake-vehicle:JVT1002')), findsOneWidget);
    expect(find.byKey(const Key('fake-vehicle:JWG6029')), findsNothing);
    await disposePage(tester);
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

    expect(find.text('Live Vehicles: 0'), findsOneWidget);
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
      expect(find.text('Live Vehicles: 2'), findsOneWidget);
      expect(find.byKey(const Key('refresh-tracker')), findsOneWidget);
      expect(find.byKey(const Key('route-filter')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await disposePage(tester);
    }
    await tester.binding.setSurfaceSize(null);
  });
}
