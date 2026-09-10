import 'dart:async';
import 'package:government_transit_collector/features/departure_recommendation/data/transfer_journey_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/departure_stop_repository.dart';
import 'package:government_transit_collector/features/passenger_location/data/passenger_location.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/direct_trip_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/nearby_stop_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/saved_journey_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/presentation/departure_recommendation_page.dart';
import 'package:government_transit_collector/features/departure_recommendation/presentation/stop_selection_page.dart';
import 'departure_recommendation_test.dart' as existing;
import 'nearby_stop_test.dart' as nearby;

class RecordingDirect extends existing.FakeDirectTripRepository {
  RecordingDirect() : super(results: const [existing.directResult]);
  String? origin, destination;
  @override
  Future<List<DirectRouteResult>> findDirectRoutes({
    required String originStopId,
    required String destinationStopId,
  }) async {
    origin = originStopId;
    destination = destinationStopId;
    return super.findDirectRoutes(
      originStopId: originStopId,
      destinationStopId: destinationStopId,
    );
  }
}

class RecordingSaved implements SavedJourneyRepository {
  String? savedName;
  DepartureStop? origin, destination;
  @override
  Future<void> save(String name, DepartureStop from, DepartureStop to) async {
    savedName = name;
    origin = from;
    destination = to;
  }

  @override
  Future<List<SavedJourney>> load() async => [];
  @override
  Future<void> delete(String id) async {}
}

class PendingDirect extends existing.FakeDirectTripRepository {
  final pending = Completer<List<DirectRouteResult>>();
  @override
  Future<List<DirectRouteResult>> findDirectRoutes({
    required String originStopId,
    required String destinationStopId,
  }) => pending.future;
}

class FailingTransfer extends existing.FakeTransferJourneyRepository {
  @override
  Future<List<OneTransferJourneyResult>> findOneTransferJourneys({
    required String originStopId,
    required String destinationStopId,
  }) async {
    throw const TransferJourneyReadException('Transfer query failed');
  }
}

void main() {
  testWidgets(
    'review: transfer error is handled while direct query is pending',
    (tester) async {
      final direct = PendingDirect();
      await tester.pumpWidget(
        MaterialApp(
          home: DepartureRecommendationPage(
            stopRepository: existing.FakeDepartureStopRepository(),
            tripRepository: direct,
            transferRepository: FailingTransfer(),
            timetableRepository:
                existing.FakeTimetableRecommendationRepository(),
            recentSearchRepository: existing.FakeRecentSearchRepository(),
            savedJourneyRepository: RecordingSaved(),
            initialJourney: const SavedJourney(
              id: 'saved',
              name: 'Test',
              origin: existing.larkin,
              destination: existing.jbSentral,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final search = find.byKey(const Key('journey-search-button'));
      await tester.ensureVisible(search);
      await tester.tap(search);
      await tester.pump();
      expect(tester.takeException(), isNull);
      direct.pending.complete([]);
      await tester.pumpAndSettle();
      expect(find.textContaining('Transfer query failed'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Save Journey dialog submits the selected pair and name', (
    tester,
  ) async {
    final saved = RecordingSaved();
    await tester.pumpWidget(
      MaterialApp(
        home: DepartureRecommendationPage(
          stopRepository: existing.FakeDepartureStopRepository(),
          tripRepository: RecordingDirect(),
          transferRepository: existing.FakeTransferJourneyRepository(),
          timetableRepository: existing.FakeTimetableRecommendationRepository(),
          recentSearchRepository: existing.FakeRecentSearchRepository(),
          savedJourneyRepository: saved,
          initialJourney: const SavedJourney(
            id: 'saved',
            name: 'Old',
            origin: existing.larkin,
            destination: existing.jbSentral,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Journey'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'College');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved.savedName, 'College');
    expect(saved.origin?.id, 'larkin');
    expect(saved.destination?.id, 'jb');
  });
  testWidgets(
    'saved pair keeps current date/time and uses existing engine IDs',
    (tester) async {
      final direct = RecordingDirect();
      final timetable = existing.FakeTimetableRecommendationRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: DepartureRecommendationPage(
            stopRepository: existing.FakeDepartureStopRepository(),
            tripRepository: direct,
            transferRepository: existing.FakeTransferJourneyRepository(),
            timetableRepository: timetable,
            recentSearchRepository: existing.FakeRecentSearchRepository(),
            initialDateTime: DateTime(2026, 9, 7, 14, 30),
            initialJourney: const SavedJourney(
              id: 'saved',
              name: 'College',
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
      expect(direct.origin, 'larkin');
      expect(direct.destination, 'jb');
      expect(timetable.receivedTravelDate, DateTime(2026, 9, 7));
      expect(timetable.receivedTravelTimeSeconds, 14 * 3600 + 30 * 60);
    },
  );
  testWidgets(
    'nearby origin becomes normal stop and destination stays manual',
    (tester) async {
      final direct = RecordingDirect();
      await tester.pumpWidget(
        MaterialApp(
          home: DepartureRecommendationPage(
            stopRepository: existing.FakeDepartureStopRepository(),
            tripRepository: direct,
            transferRepository: existing.FakeTransferJourneyRepository(),
            timetableRepository:
                existing.FakeTimetableRecommendationRepository(),
            recentSearchRepository: existing.FakeRecentSearchRepository(),
            passengerLocationService: nearby.TestLocation(
              PassengerLocationResult.available(nearby.position()),
            ),
            nearbyStopRepository: SupabaseNearbyStopRepository(
              query: (_, _, _, _) async => [nearby.row('larkin', 1.5)],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use My Current Location'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nearby-larkin')));
      await tester.pumpAndSettle();
      expect(find.text('Stop larkin'), findsOneWidget);
      await tester.tap(find.byKey(const Key('destination-field')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<StopSelectionPage>(find.byType(StopSelectionPage))
            .allowNearby,
        false,
      );
      expect(find.text('Use My Current Location'), findsNothing);
      await tester.enterText(find.byKey(const Key('stop-search-field')), 'JB');
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('stop-jb')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Reverse journey'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('journey-search-button')),
      );
      await tester.tap(find.byKey(const Key('journey-search-button')));
      await tester.pumpAndSettle();
      expect(direct.origin, 'jb');
      expect(direct.destination, 'larkin');
    },
  );
}
