import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/departure_stop_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/direct_trip_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/recent_journey_search.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/recent_search_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/timetable_recommendation_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/transfer_journey_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/presentation/departure_recommendation_page.dart';
import 'package:government_transit_collector/features/departure_recommendation/presentation/departure_validation.dart';

const larkin = DepartureStop(id: 'larkin', name: 'Larkin Sentral');
const jbSentral = DepartureStop(id: 'jb', name: 'JB Sentral');

const directResult = DirectRouteResult(
  routeId: 'J15',
  routeShortName: 'J15',
  routeLongName: 'JB Sentral - Mid Valley Southkey',
  tripHeadsign: 'Mid Valley Southkey',
  matchingTripIds: ['direct-trip'],
);

const transferResult = OneTransferJourneyResult(
  firstLeg: TransferJourneyLeg(
    routeId: 'J15',
    routeShortName: 'J15',
    routeLongName: 'First route',
    tripId: 'first-trip',
    tripHeadsign: 'JB Sentral',
    fromStopId: 'larkin',
    toStopId: 'transfer',
    fromStopSequence: 1,
    toStopSequence: 5,
  ),
  transferStopId: 'transfer',
  transferStopName: 'City Square',
  secondLeg: TransferJourneyLeg(
    routeId: 'J10',
    routeShortName: 'J10',
    routeLongName: 'Second route',
    tripId: 'second-trip',
    tripHeadsign: 'JB Sentral',
    fromStopId: 'transfer',
    toStopId: 'jb',
    fromStopSequence: 2,
    toStopSequence: 8,
  ),
  matchingTripPairs: [
    TransferTripPair(firstTripId: 'first-trip', secondTripId: 'second-trip'),
  ],
);

const directRecommendation = DirectJourneyRecommendation(
  tripId: 'direct-trip',
  routeId: 'J15',
  routeShortName: 'J15',
  originStopId: 'larkin',
  destinationStopId: 'jb',
  serviceId: 'weekday',
  originStopSequence: 1,
  destinationStopSequence: 5,
  departureSeconds: 15 * 3600 + 55 * 60,
  arrivalSeconds: 16 * 3600 + 25 * 60,
);

const transferRecommendation = TransferJourneyRecommendation(
  firstTripId: 'first-trip',
  secondTripId: 'second-trip',
  firstRouteId: 'J15',
  firstRouteShortName: 'J15',
  secondRouteId: 'J10',
  secondRouteShortName: 'J10',
  originStopId: 'larkin',
  transferStopId: 'transfer',
  transferStopName: 'City Square',
  destinationStopId: 'jb',
  firstServiceId: 'weekday',
  secondServiceId: 'weekday',
  originStopSequence: 1,
  firstTransferStopSequence: 5,
  secondTransferStopSequence: 2,
  destinationStopSequence: 8,
  departureSeconds: 15 * 3600 + 45 * 60,
  transferArrivalSeconds: 16 * 3600,
  secondDepartureSeconds: 16 * 3600 + 8 * 60,
  arrivalSeconds: 16 * 3600 + 42 * 60,
);

class FakeDepartureStopRepository implements DepartureStopRepository {
  @override
  Future<List<DepartureStop>> searchStops(String query) async {
    final normalized = query.toLowerCase();
    return [
      larkin,
      jbSentral,
    ].where((stop) => stop.name.toLowerCase().contains(normalized)).toList();
  }
}

class FakeDirectTripRepository implements DirectTripRepository {
  FakeDirectTripRepository({this.results = const []});

  final List<DirectRouteResult> results;

  @override
  Future<List<DirectRouteResult>> findDirectRoutes({
    required String originStopId,
    required String destinationStopId,
  }) async => results;
}

class FakeTransferJourneyRepository implements TransferJourneyRepository {
  FakeTransferJourneyRepository({this.results = const []});

  final List<OneTransferJourneyResult> results;

  @override
  Future<List<OneTransferJourneyResult>> findOneTransferJourneys({
    required String originStopId,
    required String destinationStopId,
  }) async => results;
}

class FakeTimetableRecommendationRepository
    implements TimetableRecommendationRepository {
  FakeTimetableRecommendationRepository({this.results = const []});

  final List<JourneyRecommendation> results;

  @override
  Future<List<JourneyRecommendation>> findRecommendations({
    required String originStopId,
    required String destinationStopId,
    required DateTime travelDate,
    required int travelTimeSeconds,
    required List<DirectRouteResult> directRoutes,
    required List<OneTransferJourneyResult> transferJourneys,
  }) async => results;
}

class FakeRecentSearchRepository implements RecentSearchRepository {
  FakeRecentSearchRepository([List<RecentJourneySearch> searches = const []])
    : searches = List.of(searches);

  final List<RecentJourneySearch> searches;

  @override
  Future<void> clearRecentSearches() async => searches.clear();

  @override
  Future<List<RecentJourneySearch>> getRecentSearches() async =>
      List.of(searches);

  @override
  Future<void> saveRecentSearch(RecentJourneySearch search) async {
    searches
      ..removeWhere(
        (item) =>
            item.originStopId == search.originStopId &&
            item.destinationStopId == search.destinationStopId,
      )
      ..insert(0, search);
  }
}

void main() {
  group('departure stop validation', () {
    test('rejects missing origin', () {
      expect(
        validateDepartureStops(origin: null, destination: jbSentral),
        'Please select an origin stop.',
      );
    });

    test('rejects missing destination', () {
      expect(
        validateDepartureStops(origin: larkin, destination: null),
        'Please select a destination stop.',
      );
    });

    test('rejects the same origin and destination', () {
      expect(
        validateDepartureStops(origin: larkin, destination: larkin),
        'Origin and destination must be different stops.',
      );
    });

    test('accepts a valid origin and destination', () {
      expect(
        validateDepartureStops(origin: larkin, destination: jbSentral),
        isNull,
      );
    });
  });

  group('departure recommendation page', () {
    Future<void> pumpPage(
      WidgetTester tester, {
      List<DirectRouteResult> directResults = const [],
      List<OneTransferJourneyResult> transferResults = const [],
      List<JourneyRecommendation> recommendations = const [],
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DepartureRecommendationPage(
            stopRepository: FakeDepartureStopRepository(),
            tripRepository: FakeDirectTripRepository(results: directResults),
            transferRepository: FakeTransferJourneyRepository(
              results: transferResults,
            ),
            timetableRepository: FakeTimetableRecommendationRepository(
              results: recommendations,
            ),
            recentSearchRepository: FakeRecentSearchRepository(),
            initialDateTime: DateTime(2026, 8, 21, 15, 30),
          ),
        ),
      );
    }

    Future<void> selectStop(
      WidgetTester tester, {
      required Key fieldKey,
      required DepartureStop stop,
    }) async {
      await tester.tap(find.byKey(fieldKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('stop-${stop.id}')));
      await tester.pumpAndSettle();
    }

    testWidgets('selects an origin stop', (tester) async {
      await pumpPage(tester);

      await selectStop(
        tester,
        fieldKey: const Key('origin-field'),
        stop: larkin,
      );

      expect(find.text('Larkin Sentral'), findsOneWidget);
    });

    testWidgets('selects a destination stop', (tester) async {
      await pumpPage(tester);

      await selectStop(
        tester,
        fieldKey: const Key('destination-field'),
        stop: jbSentral,
      );

      expect(find.text('JB Sentral'), findsOneWidget);
    });

    testWidgets('shows validation when origin is missing', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.byKey(const Key('journey-search-button')));
      await tester.pump();

      expect(find.text('Please select an origin stop.'), findsOneWidget);
    });

    testWidgets('opens travel date and time selectors', (tester) async {
      await pumpPage(tester);

      await tester.tap(find.byKey(const Key('travel-date-field')));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('travel-time-field')));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('shows validation when destination is missing', (tester) async {
      await pumpPage(tester);
      await selectStop(
        tester,
        fieldKey: const Key('origin-field'),
        stop: larkin,
      );

      await tester.tap(find.byKey(const Key('journey-search-button')));
      await tester.pump();

      expect(find.text('Please select a destination stop.'), findsOneWidget);
    });

    testWidgets('searches with a valid origin and destination', (tester) async {
      await pumpPage(tester);
      await selectStop(
        tester,
        fieldKey: const Key('origin-field'),
        stop: larkin,
      );
      await selectStop(
        tester,
        fieldKey: const Key('destination-field'),
        stop: jbSentral,
      );

      await tester.tap(find.byKey(const Key('journey-search-button')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'No direct or one-transfer journey was found between these stops.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('renders direct and transfer result sections', (tester) async {
      await pumpPage(
        tester,
        directResults: const [directResult],
        transferResults: const [transferResult],
        recommendations: const [directRecommendation, transferRecommendation],
      );
      await selectStop(
        tester,
        fieldKey: const Key('origin-field'),
        stop: larkin,
      );
      await selectStop(
        tester,
        fieldKey: const Key('destination-field'),
        stop: jbSentral,
      );
      await tester.tap(find.byKey(const Key('journey-search-button')));
      await tester.pumpAndSettle();

      expect(find.text('Recommended Departures'), findsOneWidget);
      expect(find.text('J15 → J10'), findsOneWidget);
      expect(find.text('Transfer at City Square'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('journey-results')),
          matching: find.text('Larkin Sentral → JB Sentral'),
        ),
        findsNWidgets(2),
      );
      expect(find.text('30 min • Direct'), findsOneWidget);
      expect(find.text('57 min • 1 transfer'), findsOneWidget);
      expect(find.text('8 min transfer'), findsOneWidget);
      expect(find.text('View Route'), findsNWidgets(2));
      expect(find.textContaining('matching trip'), findsNothing);
      expect(find.textContaining('Leg 1:'), findsNothing);
      expect(find.textContaining('Leg 2:'), findsNothing);
    });

    testWidgets('shows no upcoming departure for structural routes', (
      tester,
    ) async {
      await pumpPage(tester, directResults: const [directResult]);
      await selectStop(
        tester,
        fieldKey: const Key('origin-field'),
        stop: larkin,
      );
      await selectStop(
        tester,
        fieldKey: const Key('destination-field'),
        stop: jbSentral,
      );
      await tester.tap(find.byKey(const Key('journey-search-button')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'No upcoming departure was found for the selected date and time.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('tapping recent search restores origin and destination', (
      tester,
    ) async {
      final history = RecentJourneySearch(
        originStopId: larkin.id,
        originStopName: larkin.name,
        destinationStopId: jbSentral.id,
        destinationStopName: jbSentral.name,
        searchedAt: DateTime.utc(2026, 8, 21),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: DepartureRecommendationPage(
            stopRepository: FakeDepartureStopRepository(),
            tripRepository: FakeDirectTripRepository(),
            transferRepository: FakeTransferJourneyRepository(),
            timetableRepository: FakeTimetableRecommendationRepository(),
            recentSearchRepository: FakeRecentSearchRepository([history]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('recent-larkin-jb')));
      await tester.pump();

      expect(
        find.descendant(
          of: find.byKey(const Key('origin-field')),
          matching: find.text('Larkin Sentral'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('destination-field')),
          matching: find.text('JB Sentral'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('journey-results')), findsNothing);
    });

    for (final size in <Size>[const Size(400, 800), const Size(800, 400)]) {
      testWidgets('renders without overflow at ${size.width}x${size.height}', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await pumpPage(
          tester,
          directResults: const [directResult],
          transferResults: const [transferResult],
          recommendations: const [directRecommendation, transferRecommendation],
        );
        await tester.pumpAndSettle();
        await selectStop(
          tester,
          fieldKey: const Key('origin-field'),
          stop: larkin,
        );
        await selectStop(
          tester,
          fieldKey: const Key('destination-field'),
          stop: jbSentral,
        );
        await tester.ensureVisible(
          find.byKey(const Key('journey-search-button')),
        );
        await tester.tap(find.byKey(const Key('journey-search-button')));
        await tester.pumpAndSettle();

        expect(find.text('Departure Recommendation'), findsOneWidget);
        expect(find.byKey(const Key('origin-field')), findsOneWidget);
        expect(find.byKey(const Key('destination-field')), findsOneWidget);
        expect(find.byKey(const Key('travel-date-field')), findsOneWidget);
        expect(find.byKey(const Key('travel-time-field')), findsOneWidget);
        expect(find.byKey(const Key('journey-search-button')), findsOneWidget);
        expect(find.text('Recommended Departures'), findsOneWidget);
        expect(
          find.byKey(const Key('recent-searches-section')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
