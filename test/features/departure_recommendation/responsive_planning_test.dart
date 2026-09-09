import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/departure_stop_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/timetable_recommendation_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/presentation/departure_recommendation_page.dart';
import 'package:government_transit_collector/features/departure_recommendation/presentation/stop_selection_page.dart';
import 'departure_recommendation_test.dart' as f;
import 'planning_actions_test.dart' show press;

class Reachable extends f.FakeTransferJourneyRepository {
  final origins = <String>[];
  @override
  Future<List<DepartureStop>> reachableDestinations(String originStopId) async {
    origins.add(originStopId);
    return originStopId == f.larkin.id ? [f.jbSentral] : [];
  }
}

class Timetable extends f.FakeTimetableRecommendationRepository {
  TravelTimeMode? requestedMode;
  Timetable() : super(results: [f.directRecommendation]);
  @override
  Future<List<JourneyRecommendation>> findRecommendations({
    required String originStopId,
    required String destinationStopId,
    required DateTime travelDate,
    required int travelTimeSeconds,
    TravelTimeMode mode = TravelTimeMode.departAt,
    required directRoutes,
    required transferJourneys,
  }) async {
    requestedMode = mode;
    return results;
  }
}

void main() {
  testWidgets(
    'rotation retains planner controls, results, actions and dependent selection',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final reachable = Reachable();
      final timetable = Timetable();
      await tester.pumpWidget(
        MaterialApp(
          home: DepartureRecommendationPage(
            stopRepository: f.FakeDepartureStopRepository(),
            tripRepository: f.FakeDirectTripRepository(
              results: [f.directResult],
            ),
            transferRepository: reachable,
            timetableRepository: timetable,
            recentSearchRepository: f.FakeRecentSearchRepository(),
            realtimeRepository: f.FakeRecommendationRealtimeRepository(),
            initialDateTime: DateTime(2030, 9, 7, 17),
            now: () => DateTime(2026),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Select an origin first'), findsOneWidget);
      await press(tester, find.byKey(const Key('destination-field')));
      expect(find.byType(StopSelectionPage), findsNothing);
      await press(tester, find.byKey(const Key('origin-field')));
      await tester.enterText(
        find.byKey(const Key('stop-search-field')),
        'Larkin',
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      await press(tester, find.byKey(const Key('stop-larkin')));
      expect(reachable.origins, ['larkin']);
      await press(tester, find.byKey(const Key('destination-field')));
      expect(find.byKey(const Key('stop-larkin')), findsNothing);
      await press(tester, find.byKey(const Key('stop-jb')));

      for (final size in [const Size(844, 390), const Size(390, 844)]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        for (final key in [
          'origin-field',
          'destination-field',
          'travel-date-field',
          'travel-time-field',
          'journey-search-button',
        ]) {
          await tester.ensureVisible(find.byKey(Key(key)));
          await tester.pumpAndSettle();
          expect(find.byKey(Key(key)).hitTestable(), findsOneWidget);
        }
        for (final label in [
          'Use My Current Location',
          'Depart At',
          'Arrive By',
        ]) {
          await tester.ensureVisible(find.text(label));
          await tester.pumpAndSettle();
          expect(find.text(label).hitTestable(), findsOneWidget);
        }
        await press(tester, find.text('Arrive By'));
        await press(tester, find.byKey(const Key('journey-search-button')));
        expect(timetable.requestedMode, TravelTimeMode.arriveBy);
        expect(find.text('BEST CHOICE'), findsOneWidget);
        for (final label in ['View Route', 'Remind Me', 'Track Journey']) {
          await tester.ensureVisible(find.text(label));
          await tester.pumpAndSettle();
          expect(find.text(label).hitTestable(), findsOneWidget);
        }
        expect(
          tester
              .widget<SingleChildScrollView>(
                find.byKey(const Key('departure-page-scroll')),
              )
              .physics,
          isA<ClampingScrollPhysics>(),
        );
        expect(find.byType(Scrollable), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await press(tester, find.byTooltip('Reverse journey'));
      expect(reachable.origins.last, 'jb');
      expect(find.text('No reachable destinations'), findsOneWidget);
      expect(find.text('BEST CHOICE'), findsNothing);
    },
  );
}
