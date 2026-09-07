import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/nearby_stop_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/departure_stop_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/presentation/stop_selection_page.dart';
import 'package:government_transit_collector/features/passenger_location/data/passenger_location.dart';
import 'package:government_transit_collector/features/passenger_location/data/passenger_location_service.dart';

class TestLocation implements PassengerLocationService {
  TestLocation(this.result);
  PassengerLocationResult result;
  @override
  Future<PassengerLocationResult> getCurrentLocation() async => result;
  @override
  Future<bool> openAppSettings() async => true;
  @override
  Future<bool> openLocationSettings() async => true;
}

class TestStops implements DepartureStopRepository {
  @override
  Future<DepartureStop?> getStopById(String id) async => null;
  @override
  Future<List<DepartureStop>> searchStops(String query) async => const [
    DepartureStop(id: 'manual', name: 'Manual stop'),
  ];
}

PassengerLocation position() => PassengerLocation(
  latitude: 1.5,
  longitude: 103.7,
  accuracyMeters: 10,
  timestamp: DateTime.now(),
);
Map<String, dynamic> row(String id, double lat, {double lon = 103.7}) => {
  'stop_id': id,
  'stop_name': 'Stop $id',
  'stop_lat': lat,
  'stop_lon': lon,
};
void main() {
  for (final failure in [
    (
      const PassengerLocationResult.permissionDeniedForever(),
      'Location permission is disabled.',
      'Open Settings',
    ),
    (
      const PassengerLocationResult.servicesDisabled(),
      'Location services are turned off.',
      'Open Location Settings',
    ),
    (
      const PassengerLocationResult.positionTimeout(),
      'Unable to get your location. Please try again.',
      'Try Again',
    ),
  ]) {
    testWidgets('recoverable location state ${failure.$1.status}', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: StopSelectionPage(
            title: 'Origin',
            repository: TestStops(),
            excludedStopId: null,
            allowNearby: true,
            startNearby: true,
            locationService: TestLocation(failure.$1),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(failure.$2), findsOneWidget);
      expect(find.text(failure.$3), findsOneWidget);
      expect(find.text('Search Manually'), findsOneWidget);
    });
  }
  testWidgets('outdated location is rejected before querying stops', (
    tester,
  ) async {
    var queried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: StopSelectionPage(
          title: 'Origin',
          repository: TestStops(),
          excludedStopId: null,
          allowNearby: true,
          startNearby: true,
          locationService: TestLocation(
            PassengerLocationResult.available(
              PassengerLocation(
                latitude: 1.5,
                longitude: 103.7,
                accuracyMeters: 10,
                timestamp: DateTime.now().subtract(const Duration(hours: 1)),
              ),
              isLastKnown: true,
            ),
          ),
          nearbyRepository: SupabaseNearbyStopRepository(
            query: (_, _, _, _) async {
              queried = true;
              return [];
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(queried, false);
    expect(
      find.text('Your location is invalid or outdated. Please try again.'),
      findsOneWidget,
    );
  });
  test(
    'orders distances, filters radius and invalid coordinates, breaks ties by ID',
    () async {
      final repository = SupabaseNearbyStopRepository(
        query: (_, _, _, _) async => [
          row('far', 1.508),
          row('b', 1.5),
          row('a', 1.5),
          row('invalid', double.nan),
          row('outside', 2),
        ],
      );
      expect(
        (await repository.findNearby(position(), 500)).map((r) => r.stop.id),
        ['a', 'b'],
      );
      expect(
        (await repository.findNearby(position(), 1000)).map((r) => r.stop.id),
        ['a', 'b', 'far'],
      );
    },
  );
  test('pages past first response before finding nearest stop', () async {
    final offsets = <int>[];
    final repository = SupabaseNearbyStopRepository(
      query: (_, _, offset, limit) async {
        offsets.add(offset);
        return offset == 0
            ? List.generate(limit, (i) => row('far$i', 1.508))
            : [row('nearest', 1.5)];
      },
    );
    expect(
      (await repository.findNearby(position(), 1000)).first.stop.id,
      'nearest',
    );
    expect(offsets, [0, 500]);
  });
  test('empty and network failure remain distinct', () async {
    expect(
      await SupabaseNearbyStopRepository(
        query: (_, _, _, _) async => [],
      ).findNearby(position(), 1000),
      isEmpty,
    );
    await expectLater(
      SupabaseNearbyStopRepository(
        query: (_, _, _, _) async => throw Exception(),
      ).findNearby(position(), 1000),
      throwsA(isA<DepartureStopReadException>()),
    );
  });
  testWidgets(
    'location success requires selection and offers temporary radius',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: StopSelectionPage(
            title: 'Origin',
            repository: TestStops(),
            excludedStopId: null,
            allowNearby: true,
            startNearby: true,
            locationService: TestLocation(
              PassengerLocationResult.available(position()),
            ),
            nearbyRepository: SupabaseNearbyStopRepository(
              query: (_, _, _, _) async => [row('near', 1.5)],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('nearby-near')), findsOneWidget);
      expect(find.textContaining('Approx.'), findsOneWidget);
      expect(find.text('500 m'), findsOneWidget);
      expect(find.text('Nearby Bus Stops'), findsOneWidget);
    },
  );
  testWidgets('denied location allows manual search', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StopSelectionPage(
          title: 'Origin',
          repository: TestStops(),
          excludedStopId: null,
          allowNearby: true,
          startNearby: true,
          locationService: TestLocation(
            const PassengerLocationResult.permissionDenied(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Location permission is required to find nearby bus stops.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Search Manually'));
    await tester.enterText(
      find.byKey(const Key('stop-search-field')),
      'Manual',
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(find.text('Manual stop'), findsOneWidget);
  });
  testWidgets('no nearby stops offers expansion', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StopSelectionPage(
          title: 'Origin',
          repository: TestStops(),
          excludedStopId: null,
          allowNearby: true,
          startNearby: true,
          locationService: TestLocation(
            PassengerLocationResult.available(position()),
          ),
          nearbyRepository: SupabaseNearbyStopRepository(
            query: (_, _, _, _) async => [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No bus stops found within 1 km.'), findsOneWidget);
    expect(find.text('Search within 2 km'), findsOneWidget);
  });
}
