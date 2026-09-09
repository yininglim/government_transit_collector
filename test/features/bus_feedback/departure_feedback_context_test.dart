import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/bus_feedback/presentation/bus_feedback_page.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/saved_journey_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/presentation/departure_recommendation_page.dart';
import '../departure_recommendation/departure_recommendation_test.dart'
    as existing;
import 'report_form_test.dart' show ReportsFake, ReferenceFake, choose;

void main() {
  for (final transfer in [false, true]) {
    testWidgets(
      '${transfer ? 'transfer' : 'direct'} recommendation passes exact boarding event to report',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final recommendation = transfer
            ? existing.transferRecommendation
            : existing.directRecommendation;
        await tester.pumpWidget(
          MaterialApp(
            home: DepartureRecommendationPage(
              stopRepository: existing.FakeDepartureStopRepository(),
              tripRepository: existing.FakeDirectTripRepository(
                results: const [existing.directResult],
              ),
              transferRepository: existing.FakeTransferJourneyRepository(
                results: const [existing.transferResult],
              ),
              timetableRepository:
                  existing.FakeTimetableRecommendationRepository(
                    results: [recommendation],
                  ),
              recentSearchRepository: existing.FakeRecentSearchRepository(),
              realtimeRepository:
                  existing.FakeRecommendationRealtimeRepository(),
              feedbackRepository: ReportsFake(),
              feedbackReferenceRepository: ReferenceFake(),
              initialDateTime: DateTime(2026, 9, 7, 14),
              initialJourney: const SavedJourney(
                id: 'saved',
                name: 'Journey',
                origin: existing.larkin,
                destination: existing.jbSentral,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const Key('journey-search-button')),
        );
        await tester.tap(find.byKey(const Key('journey-search-button')));
        await tester.pumpAndSettle();
        expect(find.text('Report a Transit Issue'), findsNothing);
        expect(find.text('BEST CHOICE'), findsOneWidget);
        expect(find.text('Why this journey:'), findsOneWidget);
        if (transfer) {
          expect(find.text('LEG 1'), findsOneWidget);
          expect(find.text('TRANSFER'), findsOneWidget);
          expect(find.text('LEG 2'), findsOneWidget);
          expect(
            find.text('Larkin Sentral \u2192 City Square'),
            findsOneWidget,
          );
          expect(find.text('City Square \u2192 JB Sentral'), findsOneWidget);
          expect(find.text('3:45 PM \u2192 4:00 PM'), findsOneWidget);
          expect(find.text('4:08 PM \u2192 4:42 PM'), findsOneWidget);
          expect(find.text('Waiting time: 8 min'), findsOneWidget);
        }
        for (final size in [const Size(390, 844), const Size(844, 390)]) {
          tester.view.physicalSize = size;
          await tester.pumpAndSettle();
          for (final label in [
            'Report Problem',
            'View Route',
            'Track Journey',
          ]) {
            await tester.ensureVisible(find.text(label));
            await tester.pumpAndSettle();
            expect(find.text(label).hitTestable(), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        }
        final reportButton = find.byKey(
          Key('report-bus-${recommendation.departureSeconds}'),
        );
        await tester.ensureVisible(reportButton);
        await tester.tap(reportButton);
        await tester.pumpAndSettle();
        final page = tester.widget<BusFeedbackPage>(
          find.byType(BusFeedbackPage),
        );
        expect(page.travelDate, DateTime(2026, 9, 7));
        expect(page.hasJourneyContext, isTrue);
        expect(page.journeyOptions.first.boardingStop?.id, 'larkin');
        expect(
          page.journeyOptions.first.departureSeconds,
          recommendation.departureSeconds,
        );
        if (transfer) {
          expect(page.journeyOptions.last.boardingStop?.id, 'transfer');
          expect(page.journeyOptions.last.tripId, 'second-trip');
          expect(
            page.journeyOptions.last.departureSeconds,
            existing.transferRecommendation.secondDepartureSeconds,
          );
          await choose(
            tester,
            find.byType(DropdownButtonFormField<FeedbackJourneyOption>),
            'Leg 2 - J10',
          );
          expect(
            find.textContaining('Scheduled departure: 4:08 PM'),
            findsWidgets,
          );
          expect(find.text('City Square (transfer)'), findsOneWidget);
          expect(find.byKey(const Key('report-service-date')), findsNothing);
          expect(find.byType(DropdownButtonFormField<int>), findsNothing);
        } else {
          expect(page.journeyOptions.single.tripId, 'direct-trip');
        }
      },
    );
  }
}
