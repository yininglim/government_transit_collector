import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/departure_stop_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/recent_journey_search.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/saved_journey_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/presentation/departure_recommendation_page.dart';
import 'package:government_transit_collector/features/departure_recommendation/presentation/stop_selection_page.dart';
import 'departure_recommendation_test.dart' as existing;
import 'personalized_departure_test.dart' as personalized;

RecentJourneySearch history({
  String origin = 'larkin',
  String destination = 'jb',
}) => RecentJourneySearch(
  originStopId: origin,
  destinationStopId: destination,
  originStopName: 'Outdated origin name',
  destinationStopName: 'Outdated destination name',
  searchedAt: DateTime.utc(2020),
);

class LookupStops extends existing.FakeDepartureStopRepository {
  final ids = <String>[];
  bool fail = false;
  Completer<void>? pending;
  @override
  Future<DepartureStop?> getStopById(String id) async {
    ids.add(id);
    if (pending != null) await pending!.future;
    if (fail) throw StateError('offline');
    return super.getStopById(id);
  }
}

class History extends existing.FakeRecentSearchRepository {
  History(super.searches);
  int writes = 0;
  @override
  Future<void> saveRecentSearch(RecentJourneySearch search) async {
    writes++;
    await super.saveRecentSearch(search);
  }
}

class PlanningFixture {
  final direct = personalized.RecordingDirect();
  final timetable = existing.FakeTimetableRecommendationRepository(
    results: const [existing.directRecommendation],
  );
  final realtime = existing.FakeRecommendationRealtimeRepository();
  final stops = LookupStops();
  final recent = History([history()]);
  DateTime now = DateTime.utc(2026, 9, 8, 18, 42);
  Widget page({
    DepartureStop? origin,
    DepartureStop? destination,
    RecentJourneySearch? initialRecent,
  }) => DepartureRecommendationPage(
    stopRepository: stops,
    tripRepository: direct,
    transferRepository: existing.FakeTransferJourneyRepository(),
    timetableRepository: timetable,
    recentSearchRepository: recent,
    realtimeRepository: realtime,
    initialJourney: SavedJourney(
      id: 'pair',
      name: 'Pair',
      origin: origin,
      destination: destination,
    ),
    initialRecentSearch: initialRecent,
    initialDateTime: DateTime(2024, 1, 2, 10, 15),
    now: () => now,
  );
}

Future<void> press(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder fieldText(String field, String text) =>
    find.descendant(of: find.byKey(Key(field)), matching: find.text(text));
Future<void> expectPicker(
  WidgetTester tester,
  String field, {
  DateTime? date,
  TimeOfDay? time,
}) async {
  await press(tester, find.byKey(Key(field)));
  if (date != null) {
    expect(
      tester
          .widget<DatePickerDialog>(find.byType(DatePickerDialog))
          .initialDate,
      date,
    );
  }
  if (time != null) {
    expect(
      tester
          .widget<TimePickerDialog>(find.byType(TimePickerDialog))
          .initialTime,
      time,
    );
  }
  await press(tester, find.text('Cancel'));
}

void main() {
  testWidgets(
    'reverse swaps full stop IDs, preserves planning time, clears results and waits for Search',
    (tester) async {
      final f = PlanningFixture();
      await tester.pumpWidget(
        MaterialApp(
          home: f.page(
            origin: existing.larkin,
            destination: existing.jbSentral,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await press(tester, find.byKey(const Key('journey-search-button')));
      expect(find.byKey(const Key('journey-results')), findsOneWidget);
      expect(f.recent.writes, 1);
      await press(tester, find.byTooltip('Reverse journey'));
      expect(fieldText('origin-field', 'JB Sentral'), findsOneWidget);
      expect(fieldText('destination-field', 'Larkin Sentral'), findsOneWidget);
      expect(find.byKey(const Key('journey-results')), findsNothing);
      expect(f.direct.origin, 'larkin');
      expect(f.recent.writes, 1);
      await expectPicker(
        tester,
        'travel-date-field',
        date: DateTime(2024, 1, 2),
      );
      await expectPicker(
        tester,
        'travel-time-field',
        time: const TimeOfDay(hour: 10, minute: 15),
      );
      await press(tester, find.byKey(const Key('origin-field')));
      expect(
        tester
            .widget<StopSelectionPage>(find.byType(StopSelectionPage))
            .excludedStopId,
        isNull,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      await press(tester, find.byKey(const Key('journey-search-button')));
      expect(f.direct.origin, 'jb');
      expect(f.direct.destination, 'larkin');
      expect(f.timetable.receivedTravelDate, DateTime(2024, 1, 2));
      expect(f.timetable.receivedTravelTimeSeconds, 36900);
    },
  );

  for (final side in ['origin', 'destination', 'empty', 'same']) {
    testWidgets('reverse safely handles $side inputs', (tester) async {
      final f = PlanningFixture();
      await tester.pumpWidget(
        MaterialApp(
          home: f.page(
            origin: side == 'origin' || side == 'same' ? existing.larkin : null,
            destination: side == 'destination' || side == 'same'
                ? existing.larkin
                : null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await press(tester, find.byTooltip('Reverse journey'));
      expect(
        fieldText('origin-field', 'Larkin Sentral'),
        side == 'destination' ? findsOneWidget : findsNothing,
      );
      expect(fieldText('destination-field', 'Larkin Sentral'), findsNothing);
      expect(f.direct.origin, isNull);
      expect(f.recent.writes, 0);
      await press(tester, find.byKey(const Key('journey-search-button')));
      expect(find.byKey(const Key('validation-message')), findsOneWidget);
      expect(f.direct.origin, isNull);
    });
  }

  for (final initial in [false, true]) {
    testWidgets(
      'Search Again ${initial ? 'navigation' : 'in-page'} resolves IDs and fresh transit time without search',
      (tester) async {
        final f = PlanningFixture();
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(home: f.page(initialRecent: initial ? history() : null)),
        );
        await tester.pumpAndSettle();
        if (!initial) await press(tester, find.text('Search Again'));
        expect(f.stops.ids, ['larkin', 'jb']);
        expect(fieldText('origin-field', 'Larkin Sentral'), findsOneWidget);
        expect(fieldText('destination-field', 'JB Sentral'), findsOneWidget);
        expect(f.direct.origin, isNull);
        expect(f.timetable.receivedTravelDate, isNull);
        expect(f.realtime.calls, 0);
        expect(f.recent.writes, 0);
        expect(f.recent.searches.single.searchedAt, DateTime.utc(2020));
        expect(find.byKey(const Key('journey-results')), findsNothing);
        await expectPicker(
          tester,
          'travel-date-field',
          date: DateTime(2026, 9, 9),
        );
        await expectPicker(
          tester,
          'travel-time-field',
          time: const TimeOfDay(hour: 2, minute: 42),
        );
        await press(tester, find.byTooltip('Reverse journey'));
        expect(tester.takeException(), isNull);
        await press(tester, find.byTooltip('Reverse journey'));
        await press(tester, find.byKey(const Key('journey-search-button')));
        expect(f.direct.origin, 'larkin');
        expect(f.direct.destination, 'jb');
        expect(f.timetable.receivedTravelDate, DateTime(2026, 9, 9));
        expect(f.timetable.receivedTravelTimeSeconds, 9720);
        expect(f.recent.writes, 1);
      },
    );
  }

  testWidgets(
    'Search Again clears previous results and refreshes an existing form time',
    (tester) async {
      final f = PlanningFixture();
      await tester.pumpWidget(
        MaterialApp(
          home: f.page(
            origin: existing.larkin,
            destination: existing.jbSentral,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await press(tester, find.byKey(const Key('journey-search-button')));
      expect(find.byKey(const Key('journey-results')), findsOneWidget);
      await press(tester, find.text('Search Again'));
      expect(find.byKey(const Key('journey-results')), findsNothing);
      expect(f.recent.writes, 1);
      expect(f.realtime.calls, 1);
      await expectPicker(
        tester,
        'travel-date-field',
        date: DateTime(2026, 9, 9),
      );
    },
  );

  for (final missing in ['', 'deleted']) {
    testWidgets(
      'historical unavailable ID "$missing" cannot fall back to a name',
      (tester) async {
        final f = PlanningFixture();
        await tester.pumpWidget(
          MaterialApp(
            home: f.page(initialRecent: history(origin: missing)),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            'A previous stop is no longer available. Please select your stops again.',
          ),
          findsOneWidget,
        );
        expect(fieldText('origin-field', 'Larkin Sentral'), findsNothing);
        expect(f.direct.origin, isNull);
        expect(f.recent.writes, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'lookup failure is recoverable and loading disables conflicting input actions',
    (tester) async {
      final f = PlanningFixture();
      f.stops.pending = Completer<void>();
      f.stops.fail = true;
      await tester.pumpWidget(
        MaterialApp(home: f.page(initialRecent: history())),
      );
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Reverse journey',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('journey-search-button')),
            )
            .onPressed,
        isNull,
      );
      f.stops.pending!.complete();
      await tester.pumpAndSettle();
      expect(
        find.text('Unable to load the previous stops. Please try again.'),
        findsOneWidget,
      );
      f.stops.fail = false;
      await press(tester, find.text('Search Again'));
      expect(fieldText('origin-field', 'Larkin Sentral'), findsOneWidget);
      expect(f.recent.writes, 0);
    },
  );
}
