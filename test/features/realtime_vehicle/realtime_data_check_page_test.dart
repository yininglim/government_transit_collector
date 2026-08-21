import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/gtfs_realtime_decoder.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_position.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_repository.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/static_trip_matcher.dart';
import 'package:government_transit_collector/features/realtime_vehicle/presentation/realtime_data_check_page.dart';

const vehicles = [
  RealtimeVehiclePosition(
    vehicleId: 'JWG6029',
    tripId: 'trip-1',
    routeId: 'J15',
    latitude: 1.492345,
    longitude: 103.741234,
    timestampSeconds: 1787332800,
  ),
  RealtimeVehiclePosition(
    vehicleId: 'JVT1002',
    tripId: 'unknown-trip',
    routeId: 'J10',
    latitude: 1.500001,
    longitude: 103.750001,
    timestampSeconds: 1787332860,
  ),
];

const snapshot = RealtimeFeedSnapshot(
  vehicles: vehicles,
  feedTimestampSeconds: 1787332900,
);

class FakeRealtimeRepository implements RealtimeVehicleRepository {
  FakeRealtimeRepository(this.responses);
  final List<Future<RealtimeFeedSnapshot> Function()> responses;
  int calls = 0;

  @override
  Future<RealtimeFeedSnapshot> fetchVehiclePositions() {
    final index = calls.clamp(0, responses.length - 1);
    calls++;
    return responses[index]();
  }
}

class FakeTripMatcher implements StaticTripMatcher {
  FakeTripMatcher({this.knownIds = const {'trip-1'}, this.fail = false});
  final Set<String> knownIds;
  final bool fail;
  List<String>? receivedIds;

  @override
  Future<Set<String>> findKnownTripIds(Iterable<String> realtimeTripIds) async {
    receivedIds = realtimeTripIds.toList();
    if (fail) throw Exception('Supabase unavailable');
    return knownIds;
  }
}

Widget app(
  RealtimeVehicleRepository repository, {
  StaticTripMatcher? matcher,
}) => MaterialApp(
  theme: ThemeData(useMaterial3: true),
  home: RealtimeDataCheckPage(
    repository: repository,
    tripMatcher: matcher ?? FakeTripMatcher(),
  ),
);

void main() {
  testWidgets('shows initial loading state', (tester) async {
    final completer = Completer<RealtimeFeedSnapshot>();
    await tester.pumpWidget(
      app(FakeRealtimeRepository([() => completer.future])),
    );

    expect(find.byKey(const Key('realtime-loading')), findsOneWidget);
  });

  testWidgets('renders dynamic count, vehicle details, and match states', (
    tester,
  ) async {
    final matcher = FakeTripMatcher();
    await tester.pumpWidget(
      app(FakeRealtimeRepository([() async => snapshot]), matcher: matcher),
    );
    await tester.pumpAndSettle();

    expect(find.text('Vehicles received: 2'), findsOneWidget);
    expect(find.text('J15'), findsOneWidget);
    expect(find.text('Vehicle: JWG6029'), findsOneWidget);
    expect(find.text('Trip matched: Yes'), findsOneWidget);
    expect(find.text('Trip matched: No'), findsOneWidget);
    expect(find.text('Latitude: 1.492345'), findsOneWidget);
    expect(find.text('Longitude: 103.741234'), findsOneWidget);
    expect(matcher.receivedIds, ['trip-1', 'unknown-trip']);
  });

  testWidgets('shows empty feed state', (tester) async {
    await tester.pumpWidget(
      app(
        FakeRealtimeRepository([
          () async => const RealtimeFeedSnapshot(
            vehicles: [],
            feedTimestampSeconds: null,
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Vehicles received: 0'), findsOneWidget);
    expect(find.byKey(const Key('realtime-empty')), findsOneWidget);
  });

  testWidgets('API error exposes Retry and retry loads data', (tester) async {
    final repository = FakeRealtimeRepository([
      () => Future.error(
        const RealtimeVehicleReadException('Network unavailable.'),
      ),
      () async => snapshot,
    ]);
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();

    expect(find.text('Network unavailable.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('retry-realtime')));
    await tester.pumpAndSettle();
    expect(repository.calls, 2);
    expect(find.text('Vehicles received: 2'), findsOneWidget);
  });

  testWidgets('Refresh requests a new feed', (tester) async {
    final repository = FakeRealtimeRepository([
      () async => snapshot,
      () async => const RealtimeFeedSnapshot(
        vehicles: [
          RealtimeVehiclePosition(
            vehicleId: 'JWG6029',
            tripId: 'trip-1',
            routeId: 'J15',
            latitude: 1.492345,
            longitude: 103.741234,
            timestampSeconds: 1787332800,
          ),
        ],
        feedTimestampSeconds: 1787333000,
      ),
    ]);
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('refresh-realtime')));
    await tester.pumpAndSettle();
    expect(repository.calls, 2);
    expect(find.text('Vehicles received: 1'), findsOneWidget);
  });

  testWidgets('matching failure preserves realtime vehicles with warning', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        FakeRealtimeRepository([() async => snapshot]),
        matcher: FakeTripMatcher(fail: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Vehicle: JWG6029'), findsOneWidget);
    expect(find.text('Trip matched: Not checked'), findsNWidgets(2));
    expect(find.byKey(const Key('trip-matching-warning')), findsOneWidget);
  });

  testWidgets('portrait and landscape retain the same information', (
    tester,
  ) async {
    for (final size in [const Size(400, 800), const Size(800, 400)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        app(FakeRealtimeRepository([() async => snapshot])),
      );
      await tester.pumpAndSettle();

      expect(find.text('Vehicles received: 2'), findsOneWidget);
      expect(find.text('Vehicle: JWG6029'), findsOneWidget);
      expect(find.byKey(const Key('refresh-realtime')), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.binding.setSurfaceSize(null);
  });
}
