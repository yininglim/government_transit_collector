import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/departure_stop_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/direct_trip_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/recent_journey_search.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/recent_search_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/presentation/departure_recommendation_page.dart';
import 'package:government_transit_collector/features/departure_recommendation/presentation/departure_validation.dart';

const larkin = DepartureStop(id: 'larkin', name: 'Larkin Sentral');
const jbSentral = DepartureStop(id: 'jb', name: 'JB Sentral');

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
    Future<void> pumpPage(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DepartureRecommendationPage(
            stopRepository: FakeDepartureStopRepository(),
            tripRepository: FakeDirectTripRepository(),
            recentSearchRepository: FakeRecentSearchRepository(),
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
        find.text('No direct bus route was found between these stops.'),
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
      expect(find.byKey(const Key('direct-route-results')), findsNothing);
    });

    for (final size in <Size>[const Size(400, 800), const Size(800, 400)]) {
      testWidgets('renders without overflow at ${size.width}x${size.height}', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await pumpPage(tester);
        await tester.pumpAndSettle();

        expect(find.text('Departure Recommendation'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
